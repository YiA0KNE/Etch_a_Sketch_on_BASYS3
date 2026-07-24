////////////////////////////////////////////////////////////////////////////////
// user_interface.sv
// Vertical tool panel with control bus for a drawing application.
//
// UI layout (top → bottom, scaled by UI_SCALE):
//   EN     [■]            enable toggle (centre button)
//   COLOUR                 label (arrow appears when selected)
//   [■■■■■■■■■■■■■■■■■]    swatch — shows current pen colour
//   SAT:hN                 saturation index hex, N = 0..NUM_SATS-1 (wraps)
//   ■ :hF                  shape (■/●) + size 1..F
//
// control = {x, y, z}  —  one-cycle pulses:
//   Up    = 3'b010   Down  = 3'b110
//   Left  = 3'b001   Right = 3'b101
//
// sel_item : 0=COLOUR(hue)  1=SAT  2=shape  3=size
////////////////////////////////////////////////////////////////////////////////

import ui_font_pkg::*;

module user_interface #(
    parameter int HORIZONTAL = 192,   // Width of the UI zone (pixels)
    parameter int VERTICAL   = 480,   // Height of the UI zone (pixels)
    parameter int UI_SCALE   = 1,     // Pixel scaling factor
    parameter int COLOURW    = 4,     // Colour channel width
    parameter int NUM_HUES   = 16,    // Number of distinct hues
    parameter int NUM_SATS   = 16     // Number of saturation levels
) (
    input  logic                        clk,              // Pixel clock
    input  logic                        rst_n,            // Active-low reset
    input  logic                        enable,           // UI enable flag
    input  logic [2:0]                  control,          // {up/down, left/right, pulse}

    input  logic [10:0]                 x,                // Current pixel X
    input  logic [10:0]                 y,                // Current pixel Y

    output logic [3*COLOURW-1:0]        pixel_colour,     // RGB pixel output

    output logic [3:0]                  size_panel,       // Current brush size
    output logic                        cursor_shape_panel, // 0=square, 1=circle
    output logic [$clog2(NUM_HUES)-1:0] hue_panel,        // Current hue index
    output logic [$clog2(NUM_SATS)-1:0] sat_panel         // Current sat index
);

    // -------------------------------------------------------------------------
    // Local parameters
    // -------------------------------------------------------------------------
    localparam int HUEW = $clog2(NUM_HUES);
    localparam int SATW = $clog2(NUM_SATS);

    // Row Y origins (7 px per row × UI_SCALE).
    localparam int Y_EN     = 0  * UI_SCALE;
    localparam int Y_COLOUR = 9  * UI_SCALE;
    localparam int Y_SWATCH = 17 * UI_SCALE;
    localparam int Y_SAT    = 26 * UI_SCALE;
    localparam int Y_SHAPE  = 34 * UI_SCALE;

    // Horizontal layout constants.
    localparam int GLYPH_ADV = 6 * UI_SCALE;   // Advance per glyph column
    localparam int X_LABEL   = 2 * UI_SCALE;   // Start of label column

    // Toggle box sits after the "EN" label (2 glyphs).
    localparam int X_TOGGLE  = X_LABEL + 2 * GLYPH_ADV;

    // Swatch is 6 glyph slots wide and 7 pixels high.
    localparam int SWATCH_X  = X_LABEL;
    localparam int SWATCH_W  = 6 * GLYPH_ADV;
    localparam int SWATCH_H  = 7 * UI_SCALE;

    // Compute the panel bounding box.
    localparam int SAT_RIGHT    = X_LABEL + 6 * GLYPH_ADV + 5 * UI_SCALE;
    localparam int TOGGLE_RIGHT = X_TOGGLE + 7 * UI_SCALE;
    localparam int UI_MAX_X     = (SAT_RIGHT > TOGGLE_RIGHT) ? SAT_RIGHT : TOGGLE_RIGHT;
    localparam int UI_MAX_Y     = Y_SHAPE + 7 * UI_SCALE;

    // Maximum selectable item index (wraps 0↔3).
    localparam int SEL_LAST = 3'd3;

    // -------------------------------------------------------------------------
    // Compile-time size check
    // -------------------------------------------------------------------------
    generate
        if (UI_MAX_X > HORIZONTAL)
            $fatal(1, "user_interface: panel width %0d > HORIZONTAL %0d — reduce UI_SCALE",
                   UI_MAX_X, HORIZONTAL);
        if (UI_MAX_Y > VERTICAL)
            $fatal(1, "user_interface: panel height %0d > VERTICAL %0d — reduce UI_SCALE",
                   UI_MAX_Y, VERTICAL);
    endgenerate

    // -------------------------------------------------------------------------
    // Internal declarations
    // -------------------------------------------------------------------------

    // Menu state and edited values
    logic [2:0]         sel_item;       // Currently selected menu item
    logic [HUEW-1:0]    edited_hue;     // Edited hue index
    logic [SATW-1:0]    edited_sat;     // Edited saturation index

    // Cursor/shape settings
    logic               cursor_shape_reg;   // 0=square, 1=circle
    logic [3:0]         size_reg;           // Brush size 1..F

    // Pen colour preview from LUT
    logic [COLOURW-1:0] pen_r, pen_g, pen_b;

    // Hex characters displayed next to SAT and size
    logic [7:0] sat_hex;
    logic [7:0] sz_hex;

    // Pixel classification flags for rendering
    logic lit;              // 1 = draw white pixel
    logic in_swatch_fill;   // 1 = fill with current pen colour

    // -------------------------------------------------------------------------
    // Text and shape helper functions
    // -------------------------------------------------------------------------

    // Convert a 4-bit nibble to its ASCII hex character.
    function automatic logic [7:0] nibble_to_hex(input logic [3:0] nib);
        unique case (nib)
            4'h0: nibble_to_hex = "0";
            4'h1: nibble_to_hex = "1";
            4'h2: nibble_to_hex = "2";
            4'h3: nibble_to_hex = "3";
            4'h4: nibble_to_hex = "4";
            4'h5: nibble_to_hex = "5";
            4'h6: nibble_to_hex = "6";
            4'h7: nibble_to_hex = "7";
            4'h8: nibble_to_hex = "8";
            4'h9: nibble_to_hex = "9";
            4'hA: nibble_to_hex = "A";
            4'hB: nibble_to_hex = "B";
            4'hC: nibble_to_hex = "C";
            4'hD: nibble_to_hex = "D";
            4'hE: nibble_to_hex = "E";
            4'hF: nibble_to_hex = "F";
            default: nibble_to_hex = "0";
        endcase
    endfunction

    // 5×5 logical shape icon (square or circle), scaled.
    function automatic logic shape_pixel(
        input logic is_circle,
        input int   px, py, gx, gy, scale
    );
        int sx, sy, dx, dy;

        shape_pixel = 1'b0;

        if (px >= gx && px < gx + 5*scale && py >= gy + scale && py < gy + 6*scale) begin
            sx = (px - gx) / scale;          // logical column 0..4
            sy = (py - gy - scale) / scale;  // logical row    0..4

            if (is_circle) begin
                dx = sx - 2;
                dy = sy - 2;
                shape_pixel = (dx*dx + dy*dy <= 4);   // filled circle radius 2
            end else begin
                shape_pixel = 1'b1;                   // filled square
            end
        end
    endfunction

    // 7×7 toggle box: border always drawn, interior filled when active.
    function automatic logic toggle_pixel(
        input logic active,
        input int   px, py, tx, ty, scale
    );
        int lx_t, ly_t;

        toggle_pixel = 1'b0;

        if (px >= tx && px < tx + 7*scale && py >= ty && py < ty + 7*scale) begin
            lx_t = (px - tx) / scale;
            ly_t = (py - ty) / scale;
            toggle_pixel = (lx_t == 0 || lx_t == 6 || ly_t == 0 || ly_t == 6) || active;
        end
    endfunction

    // Swatch border (perimeter) test.
    function automatic logic swatch_border(
        input int px, py, bx, by, w, h, scale
    );
        int lx_t, ly_t;

        swatch_border = 1'b0;

        if (px >= bx && px < bx + w && py >= by && py < by + h) begin
            lx_t = (px - bx) / scale;
            ly_t = (py - by) / scale;
            swatch_border = (lx_t == 0 || lx_t == (w/scale - 1) ||
                             ly_t == 0 || ly_t == (h/scale - 1));
        end
    endfunction

    // Swatch interior test.
    function automatic logic swatch_interior(
        input int px, py, bx, by, w, h, scale
    );
        int lx_t, ly_t;

        swatch_interior = 1'b0;

        if (px >= bx && px < bx + w && py >= by && py < by + h) begin
            lx_t = (px - bx) / scale;
            ly_t = (py - by) / scale;
            swatch_interior = (lx_t != 0 && lx_t != (w/scale - 1) &&
                               ly_t != 0 && ly_t != (h/scale - 1));
        end
    endfunction

    // -------------------------------------------------------------------------
    // Pen colour preview LUT
    // RGB values for the current edited hue/sat, used by the swatch.
    // -------------------------------------------------------------------------
    colour_lut #(
        .NUM_HUES(NUM_HUES),
        .NUM_SATS(NUM_SATS),
        .CHANW   (COLOURW)
    ) u_colour_lut (
        .hue(edited_hue),
        .sat(edited_sat),
        .r  (pen_r),
        .g  (pen_g),
        .b  (pen_b)
    );

    // -------------------------------------------------------------------------
    // Hex digit assignments for SAT and size labels
    // -------------------------------------------------------------------------
    assign sat_hex = nibble_to_hex(4'(edited_sat));
    assign sz_hex  = nibble_to_hex(size_reg);

    // -------------------------------------------------------------------------
    // Pixel rendering combinational logic
    // Determines lit/in_swatch_fill for the current (x,y) pixel.
    // -------------------------------------------------------------------------
    always_comb begin
        lit            = 1'b0;
        in_swatch_fill = 1'b0;

        if (x < UI_MAX_X && y < UI_MAX_Y) begin

            // EN  [■] — enable label + toggle box
            if (y >= Y_EN && y < Y_EN + 7*UI_SCALE) begin
                if      (glyph_pixel("E", x, y, X_LABEL + 0*GLYPH_ADV, Y_EN, UI_SCALE)) lit = 1'b1;
                else if (glyph_pixel("N", x, y, X_LABEL + 1*GLYPH_ADV, Y_EN, UI_SCALE)) lit = 1'b1;
                else if (toggle_pixel(enable, x, y, X_TOGGLE, Y_EN, UI_SCALE))           lit = 1'b1;
            end

            // COLOUR label; arrow appears when hue item (0) is selected
            else if (y >= Y_COLOUR && y < Y_COLOUR + 7*UI_SCALE) begin
                if      (glyph_pixel("C", x, y, X_LABEL + 0*GLYPH_ADV, Y_COLOUR, UI_SCALE)) lit = 1'b1;
                else if (glyph_pixel("O", x, y, X_LABEL + 1*GLYPH_ADV, Y_COLOUR, UI_SCALE)) lit = 1'b1;
                else if (glyph_pixel("L", x, y, X_LABEL + 2*GLYPH_ADV, Y_COLOUR, UI_SCALE)) lit = 1'b1;
                else if (glyph_pixel("O", x, y, X_LABEL + 3*GLYPH_ADV, Y_COLOUR, UI_SCALE)) lit = 1'b1;
                else if (glyph_pixel("U", x, y, X_LABEL + 4*GLYPH_ADV, Y_COLOUR, UI_SCALE)) lit = 1'b1;
                else if (glyph_pixel("R", x, y, X_LABEL + 5*GLYPH_ADV, Y_COLOUR, UI_SCALE)) lit = 1'b1;
                else if (sel_item == 3'd0 && glyph_pixel(">", x, y, X_LABEL + 6*GLYPH_ADV, Y_COLOUR, UI_SCALE)) lit = 1'b1;
            end

            // Swatch: white border, interior shows pen colour
            else if (y >= Y_SWATCH && y < Y_SWATCH + SWATCH_H) begin
                if      (swatch_border(x, y, SWATCH_X, Y_SWATCH, SWATCH_W, SWATCH_H, UI_SCALE)) lit = 1'b1;
                else if (swatch_interior(x, y, SWATCH_X, Y_SWATCH, SWATCH_W, SWATCH_H, UI_SCALE)) in_swatch_fill = 1'b1;
            end

            // SAT:hN — saturation label + hex value; arrow when item 1 selected
            else if (y >= Y_SAT && y < Y_SAT + 7*UI_SCALE) begin
                if      (glyph_pixel("S",     x, y, X_LABEL + 0*GLYPH_ADV, Y_SAT, UI_SCALE)) lit = 1'b1;
                else if (glyph_pixel("A",     x, y, X_LABEL + 1*GLYPH_ADV, Y_SAT, UI_SCALE)) lit = 1'b1;
                else if (glyph_pixel("T",     x, y, X_LABEL + 2*GLYPH_ADV, Y_SAT, UI_SCALE)) lit = 1'b1;
                else if (glyph_pixel(":",     x, y, X_LABEL + 3*GLYPH_ADV, Y_SAT, UI_SCALE)) lit = 1'b1;
                else if (glyph_pixel("h",     x, y, X_LABEL + 4*GLYPH_ADV, Y_SAT, UI_SCALE)) lit = 1'b1;
                else if (glyph_pixel(sat_hex, x, y, X_LABEL + 5*GLYPH_ADV, Y_SAT, UI_SCALE)) lit = 1'b1;
                else if (sel_item == 3'd1 && glyph_pixel(">", x, y, X_LABEL + 6*GLYPH_ADV, Y_SAT, UI_SCALE)) lit = 1'b1;
            end

            // ■ :hF — shape icon, colon, hex size; arrows for shape/size items
            else if (y >= Y_SHAPE && y < Y_SHAPE + 7*UI_SCALE) begin
                if      (shape_pixel(cursor_shape_reg, x, y, X_LABEL + 0*GLYPH_ADV, Y_SHAPE, UI_SCALE)) lit = 1'b1;
                else if (glyph_pixel(":",    x, y, X_LABEL + 1*GLYPH_ADV, Y_SHAPE, UI_SCALE)) lit = 1'b1;
                else if (glyph_pixel("h",    x, y, X_LABEL + 2*GLYPH_ADV, Y_SHAPE, UI_SCALE)) lit = 1'b1;
                else if (glyph_pixel(sz_hex, x, y, X_LABEL + 3*GLYPH_ADV, Y_SHAPE, UI_SCALE)) lit = 1'b1;
                else if (sel_item == 3'd2 && glyph_pixel(">", x, y, X_LABEL + 4*GLYPH_ADV, Y_SHAPE, UI_SCALE)) lit = 1'b1;
                else if (sel_item == 3'd3 &&
                         (glyph_pixel(">", x, y, X_LABEL + 4*GLYPH_ADV, Y_SHAPE, UI_SCALE) ||
                          glyph_pixel(">", x, y, X_LABEL + 5*GLYPH_ADV, Y_SHAPE, UI_SCALE))) lit = 1'b1;
            end

        end
    end

    // -------------------------------------------------------------------------
    // Final colour output mux
    // -------------------------------------------------------------------------
    always_comb begin
        if (in_swatch_fill)
            pixel_colour = {pen_r, pen_g, pen_b};          // Current pen colour
        else if (lit)
            pixel_colour = {3{ {COLOURW{1'b1}} }};         // White
        else
            pixel_colour = '0;                             // Black / off
    end

    // -------------------------------------------------------------------------
    // Registered outputs to the drawing engine
    // -------------------------------------------------------------------------
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            size_panel         <= 4'h1;
            cursor_shape_panel <= 1'b0;
        end else begin
            size_panel         <= size_reg;
            cursor_shape_panel <= cursor_shape_reg;
        end
    end

    // -------------------------------------------------------------------------
    // Hue and saturation registered outputs
    // -------------------------------------------------------------------------
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            hue_panel <= '0;
            sat_panel <= SATW'(NUM_SATS - 1);
        end else begin
            hue_panel <= edited_hue;
            sat_panel <= edited_sat;
        end
    end

    // -------------------------------------------------------------------------
    // Square/circle shape toggle
    // -------------------------------------------------------------------------
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cursor_shape_reg <= 1'b0;
        end else if (enable && control[0] && sel_item == 3'd2) begin
            cursor_shape_reg <= ~cursor_shape_reg;
        end
    end

    // -------------------------------------------------------------------------
    // Brush size register
    // Range 1..F, wraps around at both ends.
    // -------------------------------------------------------------------------
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            size_reg <= 4'h1;
        end else if (enable && control[0] && sel_item == 3'd3) begin
            size_reg <= control[2] ? ((size_reg == 4'hF) ? 4'h1 : size_reg + 4'h1)
                                   : ((size_reg == 4'h1) ? 4'hF : size_reg - 4'h1);
        end
    end

    // -------------------------------------------------------------------------
    // Menu selection register
    // Navigate with up/down pulses on control[1].
    // control[2] = 1 means down, 0 means up. Wraps 0↔3.
    // -------------------------------------------------------------------------
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            sel_item <= 3'd0;
        end else if (enable && control[1]) begin
            sel_item <= control[2] ? ((sel_item == SEL_LAST) ? 3'd0 : sel_item + 1'b1)
                                   : ((sel_item == 3'd0) ? SEL_LAST : sel_item - 1'b1);
        end
    end

    // -------------------------------------------------------------------------
    // Hue and saturation index registers
    // Edited with left/right pulses on control[0].
    // control[2] = 1 increments, 0 decrements. Wraps around.
    // -------------------------------------------------------------------------
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            edited_hue <= '0;
            edited_sat <= SATW'(NUM_SATS - 1);
        end else if (enable && control[0]) begin
            case (sel_item)
                3'd0: begin
                    edited_hue <= control[2]
                                  ? ((edited_hue == HUEW'(NUM_HUES-1)) ? '0 : edited_hue + 1'b1)
                                  : ((edited_hue == '0) ? HUEW'(NUM_HUES-1) : edited_hue - 1'b1);
                end

                3'd1: begin
                    edited_sat <= control[2]
                                  ? ((edited_sat == SATW'(NUM_SATS-1)) ? '0 : edited_sat + 1'b1)
                                  : ((edited_sat == '0) ? SATW'(NUM_SATS-1) : edited_sat - 1'b1);
                end

                default: begin
                    // No hue/sat adjustment for shape/size items
                end
            endcase
        end
    end

endmodule