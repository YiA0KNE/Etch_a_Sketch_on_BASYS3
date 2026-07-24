////////////////////////////////////////////////////////////////////////////////
// cursor_track.sv
// Scales a 12-bit absolute mouse position onto the canvas and tracks the
// current cursor location. On every valid mouse event the previous registered
// location is copied to old_cursor_x/old_cursor_y before the new position is
// captured.
////////////////////////////////////////////////////////////////////////////////

module cursor_track #(
    parameter int H_MAX = 446,      // Canvas width in pixels
    parameter int V_MAX = 480       // Canvas height in pixels
) (
    input  logic        clk,                // System clock
    input  logic        rst_n,              // Active-low reset
    input  logic        enable,             // 1 = UI mode (pause updates)

    input  logic [11:0] mouse_xpos,         // 0..4095 absolute X from ps2_mouse
    input  logic [11:0] mouse_ypos,         // 0..4095 absolute Y from ps2_mouse
    input  logic        mouse_new_event,    // Pulse when mouse position changes

    input  logic [11:0] cursor_width,       // Current cursor bounding-box size

    output logic [10:0] cursor_x,           // Registered cursor X
    output logic [10:0] cursor_y,           // Registered cursor Y
    output logic [10:0] old_cursor_x,       // Cursor X before last mouse event
    output logic [10:0] old_cursor_y        // Cursor Y before last mouse event
);

    // -------------------------------------------------------------------------
    // Internal declarations
    // -------------------------------------------------------------------------

    // Full 24-bit product of 12-bit mouse coordinate and canvas dimension
    logic [23:0] prod_x;
    logic [23:0] prod_y;

    // Scaled canvas coordinate = upper 12 bits of fixed-point product
    // mouse_pos * H_MAX / 4096
    logic [10:0] scaled_x;
    logic [10:0] scaled_y;

    // Next cursor values computed combinationally
    logic [10:0] next_cx;
    logic [10:0] next_cy;

    // -------------------------------------------------------------------------
    // Mouse position scaling
    // Multiply the 12-bit absolute mouse coordinate by the canvas dimension,
    // then take the top 12 bits to obtain a canvas-relative position.
    // -------------------------------------------------------------------------
    assign prod_x   = mouse_xpos * H_MAX;
    assign prod_y   = mouse_ypos * V_MAX;
    assign scaled_x = prod_x[23:12];
    assign scaled_y = prod_y[23:12];

    // -------------------------------------------------------------------------
    // Next cursor combinational logic
    // Retain the current cursor position by default. When a new mouse event
    // arrives and tracking is enabled, clamp the scaled coordinate so the
    // cursor bounding box stays fully inside the canvas.
    // -------------------------------------------------------------------------
    always_comb begin
        next_cx = cursor_x;
        next_cy = cursor_y;

        if (mouse_new_event && !enable) begin
            // Clamp X so cursor_width does not exceed right/bottom edge
            if (scaled_x + cursor_width >= H_MAX)
                next_cx = H_MAX - cursor_width;
            else
                next_cx = scaled_x;

            if (scaled_y + cursor_width >= V_MAX)
                next_cy = V_MAX - cursor_width;
            else
                next_cy = scaled_y;
        end
    end

    // -------------------------------------------------------------------------
    // Cursor position registers
    // Reset to the center of the canvas; otherwise load the next value.
    // -------------------------------------------------------------------------
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cursor_x <= H_MAX / 2;
            cursor_y <= V_MAX / 2;
        end else begin
            cursor_x <= next_cx;
            cursor_y <= next_cy;
        end
    end

    // -------------------------------------------------------------------------
    // Old cursor position registers
    // Latch the current cursor position whenever a new mouse event is accepted.
    // This gives the Bresenham line generator its starting point.
    // -------------------------------------------------------------------------
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            old_cursor_x <= H_MAX / 2;
            old_cursor_y <= V_MAX / 2;
        end else if (mouse_new_event && !enable) begin
            old_cursor_x <= cursor_x;
            old_cursor_y <= cursor_y;
        end
    end

endmodule