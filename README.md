# Stereo 1st-Order IIR Filter (AXI-Stream) on FPGA

This repository provides a **reference design** of a stereo 16-bit first-order IIR filter
implemented in **Verilog**, integrated with **AXI-Stream**, **AXI-Lite control**, and
**AXI DMA**, and validated using **RTL simulation** and a **bare-metal Vitis application**.

Target platform: **AMD Kria KV260**  
Focus: **clean architecture, reproducible design, and hardware–software co-design**

This design operates in a fully real-time, sample-by-sample streaming architecture with deterministic latency.

---

## Features

- Stereo **1st-order IIR filter** (Q1.15 fixed-point)
- AXI-Stream data interface (32-bit interleaved stereo)
- AXI-Lite control & coefficient registers
- Deterministic **1-cycle processing latency**
- Bare-metal C reference application using AXI DMA
- Independent testbenches for DSP core and AXI wrapper

---

## Architecture Overview
```
    +--------------------+
    | ARM (Bare-metal)   |
    |  - AXI DMA         |
    |  - AXI-Lite Ctrl   |
    +----------+---------+
               |
    +----------v---------+
    | Stereo IIR AXI IP  |
    |  - AXI-Stream IN   |
    |  - IIR Core (L/R)  |
    |  - AXI-Stream OUT  |
    +--------------------+
```
- Left and Right channels are processed **in lockstep**
- Coefficients are **shared** between channels
- No multiband or dynamic reconfiguration (intentional, reference scope)

---

## Data Format

- AXI-Stream width: **32-bit**
- Channel mapping:
  - `[31:16]` → Left channel (signed Q1.15)
  - `[15:0]`  → Right channel (signed Q1.15)

---

## Latency

- **Processing latency:** 1 clock cycle  
- Latency is fixed and deterministic (no buffering, no variable pipeline)

---

## Register Map (AXI-Lite)

| Offset | Register | Description |
|------:|---------|-------------|
| 0x00 | CTRL | bit0 = enable, bit1 = clear_state |
| 0x04 | A0 | Feedforward coefficient (Q1.15) |
| 0x08 | A1 | Feedforward coefficient (Q1.15) |
| 0x0C | B1 | Feedback coefficient (Q1.15) |

---

## Verification

Two Verilog testbenches are provided:

- `tb_iir_orde1_core.sv`  
  Verifies DSP behavior (step response, sine response)

- `tb_iir_axis.sv`  
  Verifies AXI-Stream handshake, AXI-Lite control, and stereo data packing

Simulation results (impulse and step responses) are generated from RTL testbenches.

---

## Software Reference (Bare-Metal)

A bare-metal Vitis application is included to demonstrate:

- AXI-Lite register control
- AXI DMA data transfer
- Cache flush / invalidate handling
- Stereo impulse response test

Linux / PetaLinux integration is intentionally **out of scope** for this repository.

---

## Build Flow (High-Level)

1. Package RTL as custom AXI IP in Vivado
2. Integrate IP with AXI DMA in block design
3. Generate bitstream and export XSA
4. Build bare-metal application in Vitis
5. Run DMA-based test application

See `docs/build_overview.md` for details.

---

## Scope & Intent

This repository is intended as a **clean, minimal reference design**.
Advanced architectures (multiband, mid-side, adaptive DSP) are intentionally excluded.

---

## Design Notes

- Filter coefficients are configured via **AXI-Lite registers** instead of being
  hardcoded, allowing runtime reconfiguration without resynthesis and making the
  IP reusable for different first-order filter responses.

- No coefficient generator is included by design. Users are free to generate
  coefficients using any tool or method, as long as values are provided in
  **Q1.15 fixed-point format**.

- The provided bare-metal application serves only as a minimal reference for
  AXI-Lite and AXI DMA integration. The primary focus of this repository is the
  **RTL architecture and deterministic DSP behavior**.

---

## Project Status

This repository is provided as a **reference implementation**.

- The design is considered **feature-complete and frozen**
- No active development or roadmap is planned
- Issues and pull requests are currently not expected

The repository may be updated in the future if a new major revision is released.

---

## License

Licensed under MIT. Provided as-is, without warranty.






