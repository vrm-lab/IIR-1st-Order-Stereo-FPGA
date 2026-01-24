# Simulation Results

All results are generated from RTL simulation testbenches.

## Core DSP Verification
- Step and sine responses are generated from `tb_iir_orde1_core`
- Results demonstrate correct fixed-point IIR behavior (Q1.15)

## AXI-Stream Verification
- Stereo impulse response captured from `tb_iir_axis`
- Confirms:
  - Correct AXI-Stream handshake
  - Identical Left/Right channel processing
  - Fixed 1-cycle system latency

Waveform screenshots are provided in the `docs/` directory for timing reference.
