# Shared FIR MAC v1: No-Go checkpoint

## Objective

Replace the two verified Route1 FIR DSP lanes with one DSP48E1 shared by
Stage1, Stage2 and Stage3, while keeping the 48 MHz master clock and all
4x/8x/128x bit-true interfaces unchanged.

## Result

The prototype is a deliberate **No-Go** and is not a board candidate.
Vivado 2018.3 compiled and elaborated the RTL, but XSim caught the real
Stage1 deadline failure.  An earlier Stage2 bridge overwrite exposed the
9/8- and 6/5-cycle short-job completion jitter; padding the odd phases with
a zero-coefficient MAC removed that jitter but cannot repair the tighter
Stage1 deadline.

## Correct local deadline proof

The original 117/128 estimate considered only the complete input
supercycle.  Stage1 is created on its filtered phase and must be ready at the
next 2x event, which is only 64 master clocks later.  That same window has:

| Work in one 64-clock Stage1 window | Clocks |
|---|---:|
| Stage1: 26 MAC + exact rounding | 27 |
| Stage2: one 9-MAC and one 8-MAC phase + rounding | 19 |
| Stage3: two 6-MAC and two 5-MAC phases + rounding | 26 |
| Total | **72** |

Thus the unchanged sequential algorithms need at least 72 operations before
the 64-clock deadline.  The deficit is eight clocks, independent of FIFO
depth or scheduler priority.  Fixed-length 9/9 and 6/6 jobs would require 75
clocks and are also impossible.

## Evidence

- `xvlog`: PASS for the shared core and full-chain wrapper.
- `xelab`: PASS with the DSP48E1 UNISIM model.
- XSim: correctly raised `Shared FIR Stage1 result not ready` in the
  national-finals full-chain bit-true test.
- The prototype must not be merged into the verified Route1 board path.

## Next route

Return to Route1 and keep its two FIR DSP lanes.  Attempt to move the single
time-shared low-rate CIC comb subtractor from DSP48E1 to the LUT carry chain,
while explicitly retaining the three high-rate integrators in DSP48E1.  This
targets 5 DSP with a much smaller and timing-safe LUT trade.
