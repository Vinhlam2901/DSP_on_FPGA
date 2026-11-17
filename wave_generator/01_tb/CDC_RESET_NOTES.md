CDC/reset verification
======================

Run bounded logical checks from the project root:

    python3 01_tb/check_cdc_reset.py

Requires Yosys. Five checks cover initial configuration, lock loss during a
transfer, changes while transferring, retention of frequency across lock loss,
and a bouncing/held button producing one tick. The control harness is extracted
from production RTL and debounce is shortened to three cycles. SAT advances
both clocks together: these checks do not prove metastability containment,
arbitrary clock phase behavior, reset recovery/removal timing, or physical timing.
RTL elaboration/check was also run with the vendor PLL treated as a black box.

PLL
---

Synthesis uses the restored altera_pll IP by default. Behavioral simulation must
define LAB_SIM_PLL (added to 02_sim/flist and its makefile generator):

    +define+LAB_SIM_PLL

Do not define LAB_SIM_PLL for Quartus synthesis. The behavioral oscillator is an
approximation; it does not model reference-clock failure. To inject lock loss in
a simulation, force/release dut.pll_locked. Xcelium could not start in the current
environment, so the full waveform testbench has not been simulated here.

Controls
--------

SW[7:5] selects waveform; SW[8] enables noise; SW[1:0] selects duty:
00 = 25%, 01 = 50%, 10 = 75%, 11 = near 100% (generator-specific).
This vector must remain stable for approximately 10 ms before it is sent.
KEY0 resets all user settings. PLL lock loss resets audio and both handshake
endpoints while retaining frequency/amplitude settings in the 50 MHz domain.

Timing and codec
----------------

wg.sdc retains related PLL clocks, cuts the first request/ack synchronizer stage,
and bounds cfg_hold-to-par_12 routing to 60 ns. It constrains DAC serial outputs
against BCLK. Validate clock/endpoint matches and timing with the actual Quartus
project and board timing; TimeQuest has not been run here.
The waveform TB still has no codec ACK model, so cfg_error is expected once
configuration encounters a NACK. This is independent of the CDC/reset checks.
