# FIR và IIR có tham số — Lab 2

Bốn lõi độc lập, synthesizable SystemVerilog:

| File | Kiến trúc | Phép nhân trong RTL | Output sau cạnh nhận input | Khoảng nhận mẫu tối thiểu |
|---|---|---:|---:|---:|
| `fir_baseline.sv` | Direct form, tích song song, tổng tổ hợp | N_TAPS | Ngay sau cạnh nhận | 1 clock |
| `fir_folded.sv` | Một bộ nhân và accumulator | 1 | N_TAPS clock | N_TAPS + 1 clock |
| `iir_baseline.sv` | Cascade biquad DF-I, tổ hợp qua các section | 5 × N_SECTIONS | Ngay sau cạnh nhận | 1 clock |
| `iir_folded.sv` | Một bộ nhân, lần lượt 5 tích/section | 1 | 5 × N_SECTIONS clock | 5 × N_SECTIONS + 1 clock |

Đây là số phép nhân mô tả trong RTL, không phải số DSP block vật lý. Baseline
chưa pipeline; đặc biệt đường tổ hợp qua nhiều biquad có thể dài. Phải kiểm tra
Fmax/timing và mapping DSP bằng Quartus. Chưa tích hợp với I2S hoặc top Lab 1.

## Cách đọc bốn bản theo công thức

Các file được chia thành các khối đánh số: hệ số, delay/state, phép tính và
điều khiển. Đọc phép tính chính trước; các hàm `finish_sample` / `finish_section`
ở cuối file chỉ thực hiện dịch fixed-point, làm tròn và bão hòa. Không có bộ lọc
khác ẩn trong các hàm đó.

Giữ các parameter và cổng của bản trước để dùng lại hệ số Python. Khi bắt đầu,
chỉ cần quan tâm `N_TAPS` hoặc `N_SECTIONS` và bộ hệ số; có thể dùng nguyên
các độ rộng mặc định. Phần `COEFFS[...]` đầu file chỉ chuyển dữ liệu hệ số đã
xuất thành các tên dễ đọc `h[k]`, `b0[s]`, `b1[s]`, `b2[s]`, `a1[s]`, `a2[s]`.

### 1. FIR baseline — viết trực tiếp tổng tích

Ví dụ FIR ba taps:

```text
y[n] = h[0]*x[n] + h[1]*x[n-1] + h[2]*x[n-2]

x[n] ──────────────── ×h[0] ──┐
  └── z^-1 ────────── ×h[1] ──┼── Σ ── làm tròn/bão hòa ── y[n]
        └── z^-1 ──── ×h[2] ──┘
```

`z^-1` là trễ **một mẫu được nhận**, không phải một clock xử lý.
Trước cạnh nhận `x[n]`, `x_delay[0]` giữ `x[n-1]`, `x_delay[1]` giữ `x[n-2]`.
Vì vậy đoạn tính chính trong `fir_baseline.sv` là:

```systemverilog
sum = h[0] * x;
for (integer k = 1; k < N_TAPS; k = k + 1)
  sum = sum + h[k] * x_delay[k-1];
```

Đây là vòng lặp trong khối tổ hợp: synthesis tạo các phép nhân/cộng phần cứng,
không chạy vòng lặp qua nhiều clock như Python. Các tích dùng cùng một snapshot
mẫu trước khi delay line dịch tại cạnh nhận. Register `y` chốt kết quả tại cạnh đó.

### 2. FIR folded — một tích mỗi clock

```text
x[n] ── bộ đệm mẫu ── chọn x_delay[tap] ──┐
                                        × ── + ── acc
h[] ──────────────── chọn h[tap] ─────────┘    ↑     │
                                             └─────┘
                 tích cuối ── làm tròn/bão hòa ── y[n]
```

Sau cạnh nhận mẫu, buffer đã chứa `x_delay[0]=x[n]`, `x_delay[1]=x[n-1]`, ... .
Các clock tiếp theo thực hiện:

```text
tap=0: acc_next = 0   + h[0]*x[n]
tap=1: acc_next = acc + h[1]*x[n-1]
tap=2: acc_next = acc + h[2]*x[n-2]  → xuất kết quả nếu N_TAPS=3
```

`acc_next` bao gồm tích đang tính; `acc` chỉ chứa các tích của clock trước.
Ở tap cuối phải xuất `finish_sample(acc_next)` để không bỏ mất tích cuối.
`busy=1` trong lúc tính, nên buffer không nhận mẫu mới giữa chừng.

### 3. IIR baseline — một công thức cho mỗi biquad

Với input `u`, output `v` của một section:

```text
v[n] = b0*u[n] + b1*u[n-1] + b2*u[n-2] - a1*v[n-1] - a2*v[n-2]

u[n] ──────────────── ×b0 ──── (+) ──┐
  └── z^-1 ── x1 ─── ×b1 ──── (+) ──┤
        └── z^-1 ─x2─ ×b2 ──── (+) ──┤
                                     Σ ── lượng tử/bão hòa ── v[n]
v[n] ── z^-1 ─ y1 ── ×a1 ──── (-) ──┤
          └── z^-1 ─y2─ ×a2 ── (-) ──┘
```

Các thanh ghi có tên trùng với sơ đồ:

| Tên | Giá trị trước khi nhận mẫu |
|---|---|
| `x1[s]` | Input trước một mẫu của section s |
| `x2[s]` | Input trước hai mẫu của section s |
| `y1[s]` | Output trước một mẫu của section s |
| `y2[s]` | Output trước hai mẫu của section s |

Trong code, năm tích được viết riêng, sau đó cộng đúng dấu của công thức:

```systemverilog
assign sum = b0_u + b1_x1 + b2_x2 - a1_y1 - a2_y2;
assign stage[s+1] = finish_section(sum);
```

`stage[0]` là input đã scale; `stage[s+1]` là output của section s.
Ba section nối tiếp tương ứng IIR bậc 6:

```text
x ── scale input ── biquad 0 ── biquad 1 ── biquad 2 ── scale output ── y
```

Các section dùng hệ số `a1`, `a2` đúng dấu Python xuất, rồi **trừ** hai tích
feedback như công thức. Không đổi dấu hệ số thêm lần nữa khi nạp.
State chỉ cập nhật khi nhận mẫu mới. `y1` lưu output đã bão hòa của section,
không lưu tổng accumulator chưa lượng tử.

### 4. IIR folded — đi qua năm tích theo thứ tự công thức

```text
u / x1 / x2 / y1 / y2 ── mux ──┐
                               × ── cộng/trừ ── acc
b0 / b1 / b2 / a1 / a2 ─ mux ──┘        ↑        │
                                        └────────┘
                   tích cuối ── lượng tử/bão hòa ── section_output
```

FSM dùng tên cho từng bước, không dùng mã số phải tự nhớ:

| Bước `step` | Phép tính |
|---|---|
| `B0_U` | acc ← acc + b0*u |
| `B1_X1` | acc ← acc + b1*x1 |
| `B2_X2` | acc ← acc + b2*x2 |
| `A1_Y1` | acc ← acc - a1*y1 |
| `A2_Y2` | Tính tích cuối, lượng tử và cập nhật state |

Tại `A2_Y2`, section hiện tại hoàn tất. Nếu còn section tiếp theo thì chuyển
`section_output` sang `u`, xóa acc rồi bắt đầu lại ở `B0_U`. Nếu đã là section
cuối thì xuất `y`, bật `out_valid` và về trạng thái sẵn sàng.

Tại cạnh nhận gọi là clock 0, ba section chạy theo lịch:

```text
clock 0     : nhận x[n]
clock 1..5  : section 0
clock 6..10 : section 1
clock 11..15: section 2; xuất y[n] tại clock 15
clock 16    : có thể nhận mẫu tiếp theo
```

`x1/x2/y1/y2` chỉ được cập nhật sau tích thứ năm. Nếu cập nhật sớm, các tích
phía sau sẽ dùng state của mẫu mới và công thức hồi tiếp sẽ sai.

## Giao tiếp

- Nhận mẫu ở cạnh lên khi `in_valid && in_ready`.
- Chỉ những mẫu được nhận mới làm tiến delay line/state.
- `out_valid` dài một clock, `y` giữ kết quả cuối khi không có output mới.
- Không có `out_ready`: phía nhận phải nhận được mọi output hợp lệ.
- Khi folded bận, `in_ready=0`. Nguồn phải giữ mẫu/valid tới khi được nhận,
  hoặc chỉ phát strobe khi đã kiểm tra ready; không có FIFO đệm input.
- `rst_n` assert bất đồng bộ; nhả reset phải đồng bộ với `clk` từ phía top.
  Reset xóa toàn bộ lịch sử/state và hủy mẫu đang tính.
- Không có CDC bên trong các lõi.

Với clock 12.288 MHz và Fs=48 kHz, phát một input mỗi 256 clock. Cấu hình
21 taps / 3 biquad dùng lần lượt 22 / 16 clock giữa các lần nhận của folded,
đủ ngân sách. Có thể đổi tham số nhưng phải tự kiểm tra lại ngân sách này.

## Hệ số và ví dụ sử dụng

`COEFFS` là packed parameter lúc elaboration; không có cổng nạp hệ số runtime.
Mặc định các hệ số bằng 0, tức output bằng 0. Các lõi không tự thiết kế đáp ứng.

- FIR: tap 0 nằm ở `COEFFS[0 +: W_COEF]`.
- IIR: thứ tự tăng dần từ bit thấp là section 0: b0,b1,b2,a1,a2,
  tiếp theo section 1... . a0 phải được chuẩn hóa bằng 1.

`coeffs/` đã chứa hệ số xuất từ pipeline Python hiện tại:

- FIR remez 21 taps, signed 18 bit / 17 fractional bits.
- IIR Butterworth bậc 6, 3 SOS, signed 18 bit / 16 fractional bits.
- Spec: Fs=48 kHz, fp=2 kHz, fsb=8 kHz, Rp≤0.5 dB, As≥60 dB.
- `coeffs.json` ghi đáp ứng đã đo sau lượng tử và độ rộng accumulator.

`filter_example.sv` chọn một trong bốn cấu hình đã có hệ số:

```systemverilog
filter_example #(
  .USE_IIR(1'b0), // 0: FIR, 1: IIR
  .FOLDED (1'b1)  // 0: baseline, 1: folded
) u_filter (
  .clk(clk_12M), .rst_n(rst12_n),
  .in_valid(sample_valid), .in_ready(sample_ready), .x(sample_in),
  .out_valid(filtered_valid), .y(filtered_sample)
);
```

Compile các `.sv` trong thư mục này, thêm include directory `filter/coeffs`.
Wrapper ví dụ cố định cổng 24 bit theo cấu hình hiện tại; lõi có thể dùng riêng
với các độ rộng khác. Nếu thay đổi spec/width, xuất lại hệ số và sửa wrapper.
File list `files.f` dùng đường dẫn tính từ project root.

Xuất lại hệ số từ project root:

```sh
python3 - <<'PY'
import sys
from pathlib import Path
sys.path.insert(0, 'LAB2_Python/LAB2/python')
from export_coeffs import export
export(out_dir=Path('filter/coeffs'))
PY
```

## Quy tắc fixed-point

FIR cộng đầy đủ các tích, sau đó mới làm tròn và bão hòa:

```text
acc = Σ h_int[k] × x[n-k]
y   = sat_W_OUT((acc + 2^(F_COEF-1)) >>> F_COEF)
```

Nếu F_COEF=0 thì không cộng bias. Quy tắc tie hướng về dương, khớp golden hiện có.

IIR DF-I dùng state riêng cho từng section:

```text
u0  = sign_extend(x) <<< INPUT_SHIFT       // chỉ tại input section đầu
acc = b0*u0 + b1*x1 + b2*x2 - a1*y1 - a2*y2
v0  = sat_W_STATE(trunc_toward_zero(acc / 2^F_COEF))
x2 <- x1; x1 <- u0; y2 <- y1; y1 <- v0
```

Bão hòa mỗi section trước khi lưu feedback và trước khi đưa qua section sau.
Output cuối làm tròn bằng bias rồi dịch phải INPUT_SHIFT và bão hòa W_OUT.
Hai bit dịch input mặc định tăng độ phân giải nội bộ, không tự tăng headroom biên độ.

Accumulator mặc định có độ rộng bảo thủ để chứa tổng các tích với hệ số bất kỳ
trong miền signed đã khai báo. Nếu override W_ACC nhỏ hơn mặc định, người dùng
phải chứng minh tổng và các tổng trung gian không tràn; không có saturation bên
trong accumulator. Sự tràn accumulator sẽ khiến output sai dù đầu ra có saturate.
Rounding bias dùng thêm một bit. Khi đổi hệ số IIR, kiểm tra lại cực sau lượng tử,
headroom và limit cycle; tham số hóa phần cứng không bảo đảm mọi bộ hệ số ổn định.

## Kiểm tra

```sh
python3 filter/tests/check_filters.py
```

Cần NumPy/SciPy của pipeline Lab 2, Yosys có CXXRTL headers và g++.
Script compile trực tiếp bốn RTL, thực thi bằng CXXRTL, so từng mẫu với
`golden_fir.py` / `golden_iir.py`. Không cần Icarus/Xcelium.

Các cấu hình gồm hệ số Lab 2 thực tế; một tap/một section với fractional shift=0;
tap chẵn, hệ số âm, nhiều section và bão hòa. Vector gồm impulse, cực trị signed,
random, DC và zero tail; kiểm tra valid/ready đúng lịch, reset khi folded đang bận và baseline nhận mẫu
liên tiếp mỗi clock.
Đây là kiểm tra chức năng RTL; chưa phải timing closure, synthesis comparison
hay demo FPGA. Các vector audio dài do pipeline sinh có thể bổ sung ở bước sau.
