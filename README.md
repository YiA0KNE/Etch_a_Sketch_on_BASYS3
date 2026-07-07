# Etch_a_Sketch_on_BASYS3

A digital Etch-A-Sketch built in Verilog/SystemVerilog for the Basys 3 board, rendered live over VGA.

## Overview

This project drives a VGA display through the Basys 3's VGA port to create an interactive drawing canvas. A cursor is moved around the screen using the board's buttons (and/or switches), leaving a trail of pixels behind it, with the drawing color selectable on the fly.

## Goals

- [ ] **VGA output** — Generate a stable 640x480 VGA signal (or similar resolution) from the FPGA.
- [ ] **Color switching** — Change the active drawing color on the fly, without stopping or resetting the drawing.
- [ ] **Cursor movement** — Move a cursor around the screen using onboard buttons (may switch to a Pmod, e.g. a joystick, later).
- [ ] **Color indicator UI** — Display an on-screen element showing the currently selected color.

## Hardware

- Digilent **Basys 3** (Artix-7 FPGA)
- VGA-compatible monitor
- VGA cable

## Status

Early development — VGA signal generation is the current focus.
