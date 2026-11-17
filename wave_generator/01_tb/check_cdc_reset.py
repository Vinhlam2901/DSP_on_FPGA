"""Bounded RTL checks using Yosys SAT. Run: python3 01_tb/check_cdc_reset.py.

The control-only harness is extracted from production RTL. Debounce intervals
are shortened to three cycles. SAT treats both clocks as advancing together;
these checks cover logical recovery, not metastability or physical CDC timing.
"""
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
TOP = (ROOT / '00_src/DE10_Standard_golden_top.sv').read_text()


def run_check(work, name, source, top, constraints):
    path = work / (name + '.sv')
    path.write_text(source)
    script = (
        f'read_verilog -sv {ROOT}/00_src/button_debouncer.sv {path}; '
        f'hierarchy -check -top {top}; proc; flatten; async2sync; opt; '
        f'sat {constraints} -verify'
    )
    result = subprocess.run(['yosys', '-Q', '-T', '-p', script],
                            text=True, capture_output=True)
    if result.returncode or 'SUCCESS!' not in result.stdout:
        raise RuntimeError(name + '\n' + result.stdout + result.stderr)
    print('PASS:', name)


with tempfile.TemporaryDirectory(prefix='lab-cdc-') as directory:
    work = Path(directory)
    declarations = TOP[TOP.index('  localparam logic [15:0] MAX_FREQ'):
                       TOP.index('  // =======================================================')]
    declarations = declarations.replace('  logic        clk_12M, pll_locked;', '')
    controls = TOP[TOP.index('  //------------50Mhz Reset'):
                   TOP.index('  //================7 SEGMENT DISPLAY')]
    transfer = TOP[TOP.index('  // Synchronize physical switches'):
                   TOP.index('  // Tính tuning word')]
    harness = (
        'module cdc_check(input CLOCK_50, clk_12M, pll_locked, '
        'input [3:0] KEY, input [9:0] SW, output [23:0] observed);\n'
        'localparam DATA_WIDTH = 24;\n' + declarations + controls + transfer +
        'assign observed = par_12;\nendmodule\n'
    ).replace('500_000', '3').replace(
        'button_debouncer db_', 'button_debouncer #(.WAIT_CYCLES(3)) db_')
    common = '-seq 40 -set KEY 15 -set-at 1 KEY 0 -set-at 2 KEY 0 '
    final = '-prove-skip 39 -prove observed 256230'
    run_check(work, 'configuration_after_reset', harness, 'cdc_check',
              common + '-set pll_locked 1 -set SW 386 ' + final)
    run_check(work, 'lock_loss_during_transfer', harness, 'cdc_check',
              common + '-set pll_locked 1 -set-at 8 pll_locked 0 '
              '-set-at 9 pll_locked 1 -set SW 386 ' + final)
    run_check(work, 'latest_switch_configuration', harness, 'cdc_check',
              common + '-set pll_locked 1 -set SW 386 ' +
              ' '.join(f'-set-at {i} SW 1' for i in range(1, 7)) + ' ' + final)
    run_check(work, 'frequency_survives_lock_loss', harness, 'cdc_check',
              '-seq 45 -set KEY 11 -set-at 1 KEY 0 -set-at 2 KEY 0 '
              '-set pll_locked 1 -set-at 20 pll_locked 0 -set SW 402 '
              '-prove-skip 44 -prove observed 256486')
    debounce = '''module debounce_check(input clk, rst_n, btn,
        output [7:0] ticks);
      wire tick;
      reg [7:0] count;
      button_debouncer #(.WAIT_CYCLES(3)) dut(clk, rst_n, btn, tick);
      always @(posedge clk or negedge rst_n)
        if (!rst_n) count <= 0;
        else if (tick) count <= count + 1;
      assign ticks = count;
    endmodule
    '''
    run_check(work, 'bounce_then_held_button', debounce, 'debounce_check',
              '-seq 25 -set rst_n 1 -set-at 1 rst_n 0 '
              '-set btn 0 ' +
              ' '.join(f'-set-at {i} btn 1' for i in [1, 2, 3, 5, 6, 7]) +
              ' -prove-skip 24 -prove ticks 1')
