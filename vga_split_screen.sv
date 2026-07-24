// vga_split_screen.sv — Splits the active area into left/right zones.
//
// The left zone shows the tool panel; the right zone shows the drawing canvas.
// A configurable separator line sits between them. Local coordinates and the
// final colour mux are purely combinational, so no extra registers are added
// between the pixel generators and the display.

module vga_split_screen #(
    parameter int COLOURW  = 4,

    // Must match the timing parameters used by vga_controller.
    parameter int H_ACTIVE = 640,
    parameter int H_FRONT  = 16,
    parameter int H_PULSE  = 96,
    parameter int H_BACK   = 48,

    parameter int V_ACTIVE = 480,
    parameter int V_FRONT  = 10,
    parameter int V_PULSE  = 2,
    parameter int V_BACK   = 33,

    parameter int SPLIT_PCT = 30,  // LEFT zone width, as % of H_ACTIVE
    parameter int LINE_W    = 3,   // separator line width in pixels

    parameter logic [3*COLOURW-1:0] SEPARATOR_COLOUR = {3*COLOURW{1'b1}}, // white

    // Geometry derived from the parameters above, declared in the parameter
    // port list so they are known before the actual port list below.
    localparam int LEFT_W     = (H_ACTIVE * SPLIT_PCT) / 100,
    localparam int RIGHT_W    = H_ACTIVE - LEFT_W - LINE_W,
    localparam int LINE_START = LEFT_W,
    localparam int LINE_END   = LEFT_W + LINE_W - 1,
    localparam int XW_L       = $clog2(LEFT_W),
    localparam int XW_R       = $clog2(RIGHT_W)
) (
    // Global pixel position, straight from vga_controller.next_x_o/next_y_o.
    input  logic [$clog2(H_ACTIVE+H_FRONT+H_PULSE+H_BACK)-1:0] next_x_i,
    input  logic [$clog2(V_ACTIVE+V_FRONT+V_PULSE+V_BACK)-1:0] next_y_i,

    // Colour from each zone's own independent content generator.
    input  logic [3*COLOURW-1:0] colour_left_i,
    input  logic [3*COLOURW-1:0] colour_right_i,

    // LEFT zone local coordinates: (0,0) .. (LEFT_W-1, V_ACTIVE-1).
    output logic [XW_L-1:0]      next_x_left_o,
    output logic [$clog2(V_ACTIVE+V_FRONT+V_PULSE+V_BACK)-1:0] next_y_left_o,

    // RIGHT zone local coordinates: (0,0) .. (RIGHT_W-1, V_ACTIVE-1).
    output logic [XW_R-1:0]      next_x_right_o,
    output logic [$clog2(V_ACTIVE+V_FRONT+V_PULSE+V_BACK)-1:0] next_y_right_o,

    // Final muxed colour, feed straight into vga_controller.colour_i.
    output logic [3*COLOURW-1:0] colour_o
);

    // Temporary full-width subtraction result. SystemVerilog does not allow a
    // part-select directly on an expression, so we compute it first and slice
    // it afterwards.
    logic [$clog2(H_ACTIVE+H_FRONT+H_PULSE+H_BACK)-1:0] x_right_diff;

    always_comb begin
        // Y is identical for both zones — each spans the full active height.
        next_y_left_o  = next_y_i;
        next_y_right_o = next_y_i;

        // LEFT zone local X (clamped to 0 outside the zone; harmless because
        // colour_left_i is simply not selected by the mux below then).
        next_x_left_o = (next_x_i < LEFT_W) ? next_x_i[XW_L-1:0] : '0;

        // RIGHT zone local X: subtract the left zone and separator width.
        x_right_diff   = next_x_i - (LEFT_W + LINE_W);
        next_x_right_o = (next_x_i >= (LEFT_W + LINE_W)) ? x_right_diff[XW_R-1:0] : '0;

        // Colour mux: left | separator | right.
        if (next_x_i >= LINE_START && next_x_i <= LINE_END)
            colour_o = SEPARATOR_COLOUR;
        else if (next_x_i < LEFT_W)
            colour_o = colour_left_i;
        else
            colour_o = colour_right_i;
    end

endmodule