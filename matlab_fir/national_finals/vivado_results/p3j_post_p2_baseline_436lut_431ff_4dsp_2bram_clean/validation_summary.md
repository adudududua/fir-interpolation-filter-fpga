# Post-P2 source baseline reproduction

- Source branch: `national-finals-p3j-stage3-fwl-search`
- Source commit: `e51942029f325028fb2976efe41e3e0f2b687fae`
- Source worktree dirty at build start: `false`
- Runtime configuration: original 11-tap Stage 3, 4 DSP, 2 BRAM; all P2/P5 optional features disabled
- Release RTL regression: 17/17 PASS (`20260803_002817`)
- Full-chain cases: 14/14 PASS, 4x/8x/128x all 0 LSB
- Bitstream: PASS
- LUT: 436
- FF: 431
- DSP48E1: 4
- RAMB18E1: 4 (2 Block RAM Tiles)
- MMCM: 2
- Routed setup slack: +45.697 ns
- Routed hold slack: +0.121 ns
- Vectorless power: 0.271 W total / 0.199 W dynamic / 0.072 W static

Decision: do not replace the 430-LUT source line. Even with every optional P2/P5 feature disabled, the enlarged compatibility source changes Vivado 2018.3 optimization and reproduces at 436 LUT. The 430-LUT final version must therefore remain on its dedicated P1 branch instead of treating disabled later experiments as cost-free.
