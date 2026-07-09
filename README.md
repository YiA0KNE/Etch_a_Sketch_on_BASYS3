# Etch_a_Sketch_on_BASYS3

A digital Etch-A-Sketch built in Verilog/SystemVerilog for the Basys 3 board, rendered live over VGA.

## Overview

This project drives a VGA display through the Basys 3's VGA port to create an interactive drawing canvas. A cursor is moved around the screen using the board's buttons (and/or switches), leaving a trail of pixels behind it, with the drawing color selectable on the fly.

## Stages

- [ ] 1. **VGA simulation** — Simulate a VGA signal at 640x480. 
- [ ] 2. **VGA output** — Outputting colours on a monitor.
- [ ] 3. **Color switching** — Change the active drawing color on the fly.
- [ ] 4. **Increasing Resolution** — Increasing resolution to 1024x768 at 60Hz.
- [ ] 5. **Cursor movement** — Move a cursor around the screen using onboard buttons (may switch to a Pmod).
- [ ] 6. **Adding a reset to the canvas** — A button that will reset everything on the screen at once.
- [ ] 7. **Color selection** — Three buttons/switches that select from the Red, Green, Blue colors.
- [ ] 8. **Color indicator UI** — A UI element that shows the current color inluding color combinations.

## Hardware

- Digilent **Basys 3** (Artix-7 FPGA)
- VGA-compatible monitor
- VGA cable

