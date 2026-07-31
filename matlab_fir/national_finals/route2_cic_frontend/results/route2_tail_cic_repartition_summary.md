# Route 2B tail-CIC repartition screen

- Overall MATLAB decision: **PASS**
- Structure: FIR2 x3 -> sparse HB2 x2 -> CIC4 N=2
- Estimated DSP: 6 (1 + 1 + 1 + 3)
- Taps: Stage1=97, Stage2=17, Stage3=11, HB4=7, HB5=7
- Stage1 MAC pairs/history: 24/48
- CIC: R=4, N=2
- Limits: pass <= +/-0.050 dB, stop >= 70.0 dB
- Source decision under old private 72-dB gate: NO-GO

| Fs in | Node | Pass abs/dB | Ripple p-p/dB | Stop/dB | Symmetry | Delay | Pass |
|---:|:---:|---:|---:|---:|---:|---:|:---:|
| 44100 | 4x | 0.005984828 | 0.007584394 | 73.418311613 | 0 | 104.0 | 1 |
| 44100 | 8x | 0.013176605 | 0.013175833 | 73.427740206 | 0 | 213.0 | 1 |
| 44100 | 128x | 0.005841131 | 0.008182771 | 71.585225372 | 2.22e-16 | 3447.0 | 1 |
| 48000 | 4x | 0.005984828 | 0.006860989 | 73.418311613 | 0 | 104.0 | 1 |
| 48000 | 8x | 0.011775966 | 0.011775318 | 73.427740206 | 0 | 213.0 | 1 |
| 48000 | 128x | 0.005841131 | 0.006959610 | 71.585225372 | 2.22e-16 | 3447.0 | 1 |
