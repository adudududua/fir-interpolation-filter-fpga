# P3-J 9-tap Stage 3 candidate — implementation result

- Source branch: `national-finals-p3j-stage3-fwl-search`
- Source commit: `cfd10053c3a5ccc2d2e1303c9d19bf1908f96e8f`
- Source worktree dirty at build start: `false`
- Architecture: 9-tap compensated Stage 3, 5/4 MAC tasks, 4-DSP/2-BRAM baseline configuration
- RTL Smoke regression: 17/17 PASS (`20260803_000818`)
- Full-chain comparison: impulse + one fixed random seed, 4x/8x/128x all 0 LSB
- Reset recovery: 8/8 scenarios PASS
- Dynamic mode switching: 10/10 transitions PASS
- Bitstream: PASS
- LUT: 441
- FF: 431
- DSP48E1: 4
- RAMB18E1: 4 (2 Block RAM Tiles)
- MMCM: 2
- Routed setup slack: +46.190 ns
- Routed hold slack: +0.121 ns
- Vectorless power: 0.271 W total / 0.199 W dynamic / 0.072 W static

Decision: **No-Go**. The signed-off 11-tap baseline uses 430 LUT and 431 FF under the same 4-DSP/2-BRAM configuration. The 9-tap candidate adds 11 LUT and saves no FF, so it fails the predeclared resource gate despite passing functional, timing, and bitstream checks.
