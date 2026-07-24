////////////////////////////////////////////////////////////////////////////////
// drawing_interface.sv
// Cursor + framebuffer + Bresenham stroke canvas.
// Draws a line between the previous and current cursor position and stamps
// a configurable brush shape at each Bresenham pixel.
////////////////////////////////////////////////////////////////////////////////

module drawing_interface #(
    parameter int HORIZONTAL = 446,        // Display width in pixels
    parameter int VERTICAL   = 480,        // Display height in pixels
    parameter int COLOURW    = 4,          // Bits per RGB channel
    parameter int START_SIZE = 4,          // Minimum brush size offset
    parameter int NUM_HUES   = 16,         // Number of hue entries in LUT
    parameter int NUM_SATS   = 4           // Number of saturation entries in LUT
) (
    input  logic                        clk,            // System clock
    input  logic                        rst_n,          // Active-low reset
    input  logic                        enable,         // Cursor tracking enable
    input  logic                        hide_cursor,    // 1 = hide cursor overlay
    input  logic                        frame_tick,     // Unused in this module
    input  logic                        draw_enable,    // 1 = allow drawing strokes

    input  logic [10:0]                 x,              // Current display X pixel
    input  logic [10:0]                 y,              // Current display Y pixel

    input  logic [11:0]                 mouse_xpos,     // Mouse X from PS/2 tracker
    input  logic [11:0]                 mouse_ypos,     // Mouse Y from PS/2 tracker
    input  logic                        mouse_new_event,// Pulse when mouse moves

    input  logic [$clog2(NUM_HUES)-1:0] hue_sel,        // Selected hue index
    input  logic [$clog2(NUM_SATS)-1:0] sat_sel,        // Selected saturation index
    input  logic [3:0]                  size_cursor,    // User brush size offset
    input  logic                        cursor_shape,   // 0 = square, 1 = circle
    output logic [3*COLOURW-1:0]        colour          // Final RGB colour output
);

    // -------------------------------------------------------------------------
    // Local parameters
    // -------------------------------------------------------------------------
    localparam int HUEW   = $clog2(NUM_HUES);   // Bits for hue index
    localparam int SATW   = $clog2(NUM_SATS);   // Bits for saturation index
    localparam int PIXW   = HUEW + SATW;        // Total bits stored per pixel
    localparam int PIXELS = HORIZONTAL * VERTICAL;
    localparam int ADDRW  = $clog2(PIXELS);     // Framebuffer address width

    // -------------------------------------------------------------------------
    // Cursor size and geometry
    // -------------------------------------------------------------------------
    logic [11:0] eff_size;      // Effective brush radius / half-size
    logic [11:0] cursor_width;  // Total bounding-box width for cursor/stamp

    // -------------------------------------------------------------------------
    // Cursor tracker interface
    // -------------------------------------------------------------------------
    logic [10:0] cursor_x;      // Current cursor X (registered)
    logic [10:0] cursor_y;      // Current cursor Y (registered)
    logic [10:0] old_cx;        // Previous cursor X
    logic [10:0] old_cy;        // Previous cursor Y

    // -------------------------------------------------------------------------
    // Bresenham line generator interface
    // -------------------------------------------------------------------------
    logic        bres_start;    // Start a new line segment
    logic        bres_stall;    // Stall Bresenham while stamping a pixel
    logic [10:0] bres_x;        // Line pixel X from Bresenham
    logic [10:0] bres_y;        // Line pixel Y from Bresenham
    logic        bres_valid;    // bres_x/y are valid this cycle
    logic        bres_done;     // Line complete pulse

    // -------------------------------------------------------------------------
    // Hue/saturation output before LUT
    // -------------------------------------------------------------------------
    logic [HUEW-1:0] out_hue;        // Hue fed to colour LUT
    logic [SATW-1:0] out_sat;        // Saturation fed to colour LUT

    // -------------------------------------------------------------------------
    // Cursor overlay signals
    // -------------------------------------------------------------------------
    logic              cursor_outer; // 1 when display pixel is inside cursor
    logic [3*COLOURW-1:0] lut_colour;// LUT RGB output before cursor invert

    // -------------------------------------------------------------------------
    // Display coordinate delay for cursor overlay
    // -------------------------------------------------------------------------
    logic [10:0] x_d;           // Delayed display X
    logic [10:0] y_d;           // Delayed display Y

    // -------------------------------------------------------------------------
    // Boot clear counter
    // -------------------------------------------------------------------------
    logic [ADDRW-1:0] clear_addr;
    logic             clear_done;

    // -------------------------------------------------------------------------
    // Stamp box iterator
    // -------------------------------------------------------------------------
    logic [11:0] stamp_bx;          // X offset inside stamp bounding box
    logic [11:0] stamp_by;          // Y offset inside stamp bounding box
    logic        stamp_row_done;    // Reached end of current stamp row
    logic        stamp_done;        // Reached end of entire stamp box

    // -------------------------------------------------------------------------
    // Captured stamp parameters (latched at line start)
    // -------------------------------------------------------------------------
    logic [11:0]     stamp_sz;      // Latched effective brush size
    logic [11:2]     stamp_w;       // Latched bounding-box width
    logic            stamp_shape;   // Latched brush shape
    logic [PIXW-1:0] stamp_pixel;   // Latched {hue, saturation}

    // -------------------------------------------------------------------------
    // Pixel pipeline latches
    // -------------------------------------------------------------------------
    logic            pixel_pending;     // 1 = a Bresenham pixel is being stamped
    logic [10:0]     stamp_cx;          // X coordinate of pixel being stamped
    logic [10:0]     stamp_cy;          // Y coordinate of pixel being stamped
    logic            bres_done_latched; // Registered Bresenham done flag

    // -------------------------------------------------------------------------
    // Framebuffer write signals
    // -------------------------------------------------------------------------
    logic             wr_en;
    logic [ADDRW-1:0] wr_addr;
    logic [PIXW-1:0]  wr_data;

    // -------------------------------------------------------------------------
    // Framebuffer read pixel
    // -------------------------------------------------------------------------
    logic [PIXW-1:0] disp_pixel;

    // -------------------------------------------------------------------------
    // Main FSM
    // -------------------------------------------------------------------------
    typedef enum logic [1:0] {
        S_CLEAR = 2'b00,    // Clear framebuffer after reset
        S_IDLE  = 2'b01,    // Wait for mouse movement
        S_STAMP = 2'b10     // Stamp brush shape at Bresenham pixels
    } state_t;

    state_t state;          // Current FSM state
    state_t state_next;     // Next FSM state

    // -------------------------------------------------------------------------
    // Geometry helper functions
    // -------------------------------------------------------------------------

    // Returns 1 if (px,py) is inside the brush centered at (cx,cy).
    // For square shape: axis-aligned bounding box.
    // For circle shape: distance from center <= radius.
    function automatic logic point_in_shape(
        input logic [10:0] px, py, cx, cy,
        input logic [11:0] sz,
        input logic        shape
    );
        logic [10:0] ddx, ddy;
        logic [21:0] dsq, rsq;

        if (!shape) begin
            // Square brush: half-width sz, centered at (cx,cy)
            point_in_shape = (px >= cx) && (px < cx + sz) &&
                             (py >= cy) && (py < cy + sz);
        end else begin
            // Circular brush: radius sz, centered at (cx + sz, cy + sz)
            ddx = (px > cx + sz) ? (px - (cx + sz)) : ((cx + sz) - px);
            ddy = (py > cy + sz) ? (py - (cy + sz)) : ((cy + sz) - py);
            dsq = ddx*ddx + ddy*ddy;
            rsq = sz*sz;
            point_in_shape = (dsq <= rsq);
        end
    endfunction

    // Convert 2D pixel coordinates to 1D framebuffer address.
    function automatic logic [ADDRW-1:0] pix_addr(
        input logic [10:0] px,
        input logic [10:0] py
    );
        pix_addr = py * HORIZONTAL + px;
    endfunction

    // -------------------------------------------------------------------------
    // Cursor size combinational assignments
    // -------------------------------------------------------------------------
    assign eff_size     = size_cursor + START_SIZE;
    assign cursor_width = cursor_shape ? (eff_size*2 + 1) : eff_size;

    // -------------------------------------------------------------------------
    // Boot clear status
    // -------------------------------------------------------------------------
    assign clear_done = (clear_addr == ADDRW'(PIXELS - 1));

    // -------------------------------------------------------------------------
    // Bresenham trigger
    // Start a new stroke when idle, mouse moved, drawing enabled, and not erasing.
    // -------------------------------------------------------------------------
    assign bres_start = (state == S_IDLE) && mouse_new_event && !enable && draw_enable;

    // -------------------------------------------------------------------------
    // Bresenham stall while current pixel is being stamped
    // -------------------------------------------------------------------------
    assign bres_stall = pixel_pending && (state == S_STAMP);

    // -------------------------------------------------------------------------
    // Stamp iterator status
    // -------------------------------------------------------------------------
    assign stamp_row_done = (stamp_bx == stamp_w - 1);
    assign stamp_done     = stamp_row_done && (stamp_by == stamp_w - 1);

    // -------------------------------------------------------------------------
    // Cursor overlay hit detection
    // -------------------------------------------------------------------------
    assign cursor_outer = point_in_shape(x_d, y_d,
                                         cursor_x, cursor_y,
                                         eff_size, cursor_shape);

    // -------------------------------------------------------------------------
    // Display coordinate delay for cursor overlay timing
    // -------------------------------------------------------------------------
    always_ff @(posedge clk) begin
        x_d <= x;
        y_d <= y;
    end

    // -------------------------------------------------------------------------
    // Boot clear counter
    // Increments through every framebuffer address in S_CLEAR, then resets.
    // -------------------------------------------------------------------------
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            clear_addr <= '0;
        end else if (state == S_CLEAR) begin
            clear_addr <= clear_done ? '0 : clear_addr + 1'b1;
        end
    end

    // -------------------------------------------------------------------------
    // Capture brush parameters at the start of each line segment
    // -------------------------------------------------------------------------
    always_ff @(posedge clk) begin
        if (bres_start) begin
            stamp_sz    <= eff_size;
            stamp_w     <= cursor_width;
            stamp_shape <= cursor_shape;
            stamp_pixel <= {hue_sel, sat_sel};
        end
    end

    // -------------------------------------------------------------------------
    // Latch each Bresenham pixel and hold it until stamping finishes.
    // Also registers the Bresenham done flag.
    // -------------------------------------------------------------------------
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            stamp_cx          <= '0;
            stamp_cy          <= '0;
            pixel_pending     <= 1'b0;
            bres_done_latched <= 1'b0;
        end else begin
            // Capture Bresenham completion immediately
            if (bres_done) begin
                bres_done_latched <= 1'b1;
            end

            // Accept a new Bresenham pixel when current one is finished
            if (bres_valid && !pixel_pending) begin
                stamp_cx      <= bres_x;
                stamp_cy      <= bres_y;
                pixel_pending <= 1'b1;
            end else if (stamp_done) begin
                pixel_pending <= 1'b0;
            end

            // Clear done latch when returning to idle
            if (state == S_IDLE) begin
                bres_done_latched <= 1'b0;
            end
        end
    end

    // -------------------------------------------------------------------------
    // Stamp bounding-box iterator
    // Scans a stamp_w x stamp_w box around the latched Bresenham pixel.
    // -------------------------------------------------------------------------
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            stamp_bx <= '0;
            stamp_by <= '0;
        end else if (!pixel_pending) begin
            // Reset when waiting for next pixel
            stamp_bx <= '0;
            stamp_by <= '0;
        end else if (state == S_STAMP) begin
            // Advance X; wrap to next row when row completes
            stamp_bx <= stamp_row_done ? '0 : stamp_bx + 1'b1;

            // Advance Y only at end of row; stop when stamp is complete
            stamp_by <= stamp_row_done
                        ? (stamp_by + {11'b0, ~stamp_done})
                        : stamp_by;
        end
    end

    // -------------------------------------------------------------------------
    // FSM next-state combinational logic
    // -------------------------------------------------------------------------
    always_comb begin
        state_next = state;

        case (state)
            S_CLEAR: begin
                // Move to idle once entire framebuffer has been cleared
                if (clear_done) begin
                    state_next = S_IDLE;
                end
            end

            S_IDLE: begin
                // Start stamping when a new mouse stroke begins
                if (bres_start) begin
                    state_next = S_STAMP;
                end
            end

            S_STAMP: begin
                // Return to idle when last pixel stamped and Bresenham is done
                if (stamp_done && bres_done_latched) begin
                    state_next = S_IDLE;
                end
            end

            default: begin
                state_next = S_IDLE;
            end
        endcase
    end

    // -------------------------------------------------------------------------
    // FSM state register
    // -------------------------------------------------------------------------
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= S_CLEAR;
        end else begin
            state <= state_next;
        end
    end

    // -------------------------------------------------------------------------
    // Framebuffer write combinational logic
    // -------------------------------------------------------------------------
    always_comb begin
        // Default: no write
        wr_en   = 1'b0;
        wr_addr = '0;
        wr_data = '0;

        case (state)
            S_CLEAR: begin
                // Zero entire framebuffer during boot clear
                wr_en   = 1'b1;
                wr_addr = clear_addr;
            end

            S_STAMP: begin
                // Write only pixels inside the brush shape
                if (pixel_pending &&
                    point_in_shape(stamp_cx + stamp_bx[10:0],
                                   stamp_cy + stamp_by[10:0],
                                   stamp_cx,
                                   stamp_cy,
                                   stamp_sz,
                                   stamp_shape)) begin
                    wr_en   = 1'b1;
                    wr_addr = pix_addr(stamp_cx + stamp_bx[10:0],
                                       stamp_cy + stamp_by[10:0]);
                    wr_data = stamp_pixel;
                end
            end

            default: begin
                // S_IDLE: no framebuffer writes
            end
        endcase
    end

    // -------------------------------------------------------------------------
    // Colour output selection
    // Cursor overlay always shows the stored pixel — never the brush colour —
    // so the invert step below is the only thing that visually marks the cursor.
    // -------------------------------------------------------------------------
    always_comb begin
        {out_hue, out_sat} = disp_pixel;
    end

    // -------------------------------------------------------------------------
    // Submodule instantiations
    // -------------------------------------------------------------------------

    // Framebuffer memory
    framebuffer_mem #(
        .PIXELS(PIXELS),
        .PIXW  (PIXW),
        .ADDRW (ADDRW)
    ) u_fb (
        .clk,

        .wr_en   (wr_en),
        .wr_addr (wr_addr),
        .wr_data (wr_data),

        .rd_addr (pix_addr(x, y)),
        .rd_data (disp_pixel)
    );

    // Cursor position tracker
    cursor_track #(
        .H_MAX(HORIZONTAL),
        .V_MAX(VERTICAL)
    ) u_track (
        .clk,
        .rst_n,

        .enable,

        .mouse_xpos     (mouse_xpos),
        .mouse_ypos     (mouse_ypos),
        .mouse_new_event(mouse_new_event),

        .cursor_width   (cursor_width),
        
        .cursor_x       (cursor_x),
        .cursor_y       (cursor_y),

        .old_cursor_x   (old_cx),
        .old_cursor_y   (old_cy)
    );

    // Bresenham line generator between old and new cursor positions
    bresenham u_bres (
        .clk,
        .rst_n,

        .start (bres_start),
        .stall (bres_stall),

        .x0    (old_cx),
        .y0    (old_cy),
        .x1    (cursor_x),
        .y1    (cursor_y),

        .x_out (bres_x),
        .y_out (bres_y),

        .valid (bres_valid),
        .done  (bres_done)
    );

    // Hue/saturation to RGB lookup table
    colour_lut #(
        .NUM_HUES(NUM_HUES),
        .NUM_SATS(NUM_SATS),
        .CHANW   (COLOURW)
    ) u_colour_lut (
        .hue(out_hue),
        .sat(out_sat),

        .r  (lut_colour[3*COLOURW-1 : 2*COLOURW]),
        .g  (lut_colour[2*COLOURW-1 : 1*COLOURW]),
        .b  (lut_colour[1*COLOURW-1 : 0])
    );

    // -------------------------------------------------------------------------
    // Final colour output
    // Invert the displayed colour only under the cursor, for visibility.
    // The FSM's stamp write (stamp_pixel <= {hue_sel, sat_sel}) is completely
    // separate from this and is not affected.
    // -------------------------------------------------------------------------
    assign colour = (!hide_cursor && (state != S_CLEAR) && cursor_outer) ? ~lut_colour : lut_colour;

endmodule