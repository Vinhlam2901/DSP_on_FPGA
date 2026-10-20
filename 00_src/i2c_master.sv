module i2c_master #(
    parameter integer DIV = 16
) (
    input  logic        clk,
    input  logic        reset_n,
    input  logic        start_pulse,
    input  logic [6:0]  dev_addr,
    input  logic [15:0] data_in,
    output logic        busy,
    output logic        done,
    output logic        ack_error,
    inout  tri          i2c_sda,
    output wire         i2c_scl
);
    logic scl_out;

    i2c_clk_div #(.DIV(DIV)) u_clkdiv (
        .clk      (clk),
        .reset_n  (reset_n),
        .scl_out  (scl_out)
    );

    /*
     * SCL is forced high while idle. The transaction is aligned to an
     * internal high phase before busy is asserted, so START is generated
     * while the externally visible SCL is high.
     */
    assign i2c_scl = busy ? scl_out : 1'b1;

    logic scl_q;
    always_ff @(posedge clk or negedge reset_n) begin
        if (!reset_n)
            scl_q <= 1'b1;
        else
            scl_q <= scl_out;
    end

    wire scl_rise = (~scl_q) & scl_out;
    wire scl_fall = scl_q & (~scl_out);

    /* I2C SDA must be open-drain: drive only zero, otherwise release. */
    logic sda_drive_low;
    wire  sda_in = i2c_sda;
    assign i2c_sda = sda_drive_low ? 1'b0 : 1'bz;

    typedef enum logic [3:0] {
        ST_IDLE,
        ST_ALIGN_HIGH,
        ST_START_HOLD,
        ST_SEND_BIT,
        ST_ACK_SETUP,
        ST_ACK_SAMPLE,
        ST_STOP_LOW,
        ST_STOP_HIGH,
        ST_DONE
    } state_t;

    state_t state;

    logic [7:0] tx_bytes [0:2];
    logic [7:0] shift_byte;
    logic [2:0] bit_idx;
    logic [1:0] byte_index;

    always_ff @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            state          <= ST_IDLE;
            busy           <= 1'b0;
            done           <= 1'b0;
            ack_error      <= 1'b0;
            sda_drive_low  <= 1'b0;
            shift_byte     <= 8'h00;
            bit_idx        <= 3'd7;
            byte_index     <= 2'd0;
            tx_bytes[0]    <= 8'h00;
            tx_bytes[1]    <= 8'h00;
            tx_bytes[2]    <= 8'h00;
        end else begin
            done <= 1'b0;

            case (state)
                ST_IDLE: begin
                    busy          <= 1'b0;
                    sda_drive_low <= 1'b0;

                    if (start_pulse) begin
                        tx_bytes[0] <= {dev_addr, 1'b0}; //addr+W
                        tx_bytes[1] <= data_in[15:8]; // MSB
                        tx_bytes[2] <= data_in[7:0]; // LSB
                        shift_byte  <= {dev_addr, 1'b0};
                        bit_idx     <= 3'd7;
                        byte_index  <= 2'd0;
                        ack_error   <= 1'b0;
                        state       <= ST_ALIGN_HIGH;
                    end
                end

                ST_ALIGN_HIGH: begin
                    /* Keep the external bus idle until the divider is high. */
                    busy <= 1'b0;
                    if (scl_rise) begin
                        busy          <= 1'b1;
                        sda_drive_low <= 1'b1;  // SDA high-to-low while SCL high
                        state         <= ST_START_HOLD;
                    end
                end

                ST_START_HOLD: begin
                    if (scl_fall) begin
                        sda_drive_low <= ~shift_byte[bit_idx]; 
                        state         <= ST_SEND_BIT;
                    end
                end

                ST_SEND_BIT: begin
                    /* Change data only while SCL is low. */
                    if (scl_fall)   // update gia tri bit tiep theo ra chan SDA
                        sda_drive_low <= ~shift_byte[bit_idx];

                    if (scl_rise) begin  // kiem tra da gui het 8 bit chua
                        if (bit_idx == 3'd0)  // neu chua bit_idx != 0, giam bix_idx di 1 
                            state <= ST_ACK_SETUP;  // de gui bit tiep theo
                        else                        // neu du thi chuyen sang ACK
                            bit_idx <= bit_idx - 1'b1;
                    end
                end

                ST_ACK_SETUP: begin
                    
                    if (scl_fall) begin
                        sda_drive_low <= 1'b0;
                        state         <= ST_ACK_SAMPLE;
                    end
                end

                ST_ACK_SAMPLE: begin
                    if (scl_rise) begin
                        if (sda_in !== 1'b0) begin
                            ack_error <= 1'b1;   //NACK
                            state     <= ST_STOP_LOW;
                        end else if (byte_index == 2'd2) begin
                            state <= ST_STOP_LOW;
                        end else begin
                            byte_index <= byte_index + 1'b1;
                            bit_idx    <= 3'd7;
                            if (byte_index == 2'd0)
                                shift_byte <= tx_bytes[1];
                            else
                                shift_byte <= tx_bytes[2];
                            state <= ST_SEND_BIT;
                        end
                    end
                end

                ST_STOP_LOW: begin
                    if (scl_fall) begin
                        sda_drive_low <= 1'b1;
                        state         <= ST_STOP_HIGH;
                    end
                end

                ST_STOP_HIGH: begin
                    if (scl_rise) begin
                        sda_drive_low <= 1'b0;  // SDA low-to-high while SCL high
                        state         <= ST_DONE;
                    end
                end

                ST_DONE: begin
                    busy  <= 1'b0;
                    done  <= 1'b1;
                    state <= ST_IDLE;
                end

                default: begin
                    state         <= ST_IDLE;
                    busy          <= 1'b0;
                    done          <= 1'b0;
                    ack_error     <= 1'b1;
                    sda_drive_low <= 1'b0;
                end
            endcase
        end
    end
endmodule
