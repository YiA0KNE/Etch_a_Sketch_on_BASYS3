// moving_square_gen.sv — Bouncing square demo generator.
//
// A coloured square bounces horizontally and vertically inside the active
// display area. Horizontal and vertical state are kept in separate always_ff
// blocks so each contains only two registered signals.

module moving_square_gen #(
    parameter int H_ACTIVE = 640,   // horizontal resolution
    parameter int V_ACTIVE = 480,   // vertical resolution
    parameter int COLOURW  = 4,     // bits per colour channel
    parameter int SQ_SIZE  = 60,    // square edge length in pixels
    parameter int STEP     = 4      // pixels moved per frame
) (
    input  wire                        pix_clk,    // pixel clock
    input  wire                        rst_ni,     // active-low reset
    input  wire                        frame_tick, // one pulse per full frame
    input  wire [$clog2(H_ACTIVE)-1:0] x_i,        // current pixel X
    input  wire [$clog2(V_ACTIVE)-1:0] y_i,        // current pixel Y
    output logic [3*COLOURW-1:0]       colour_o    // RGB output
);

    // Maximum top-left coordinates so the square never leaves the screen.
    localparam int SQ_X_MAX = H_ACTIVE - SQ_SIZE;
    localparam int SQ_Y_MAX = V_ACTIVE - SQ_SIZE;

    // Horizontal motion state.
    logic [$clog2(H_ACTIVE)-1:0] sq_x;   // square left edge
    logic                        dir_x;  // 1 = right, 0 = left
    logic                        next_dir_x;

    always_ff @(posedge pix_clk) begin
        if (!rst_ni) begin
            sq_x  <= '0;
            dir_x <= 1'b1;
        end else if (frame_tick) begin
            // Decide direction for the next step before moving.
            next_dir_x = dir_x;
            if (dir_x && (sq_x + STEP > SQ_X_MAX)) next_dir_x = 1'b0;
            else if (!dir_x && (sq_x < STEP))      next_dir_x = 1'b1;
            dir_x <= next_dir_x;
            sq_x  <= next_dir_x ? (sq_x + STEP) : (sq_x - STEP);
        end
    end

    // Vertical motion state.
    logic [$clog2(V_ACTIVE)-1:0] sq_y;   // square top edge
    logic                        dir_y;  // 1 = down, 0 = up
    logic                        next_dir_y;

    always_ff @(posedge pix_clk) begin
        if (!rst_ni) begin
            sq_y  <= '0;
            dir_y <= 1'b1;
        end else if (frame_tick) begin
            next_dir_y = dir_y;
            if (dir_y && (sq_y + STEP > SQ_Y_MAX)) next_dir_y = 1'b0;
            else if (!dir_y && (sq_y < STEP))      next_dir_y = 1'b1;
            dir_y <= next_dir_y;
            sq_y  <= next_dir_y ? (sq_y + STEP) : (sq_y - STEP);
        end
    end

    // Pixel-in-square test and colour mux.
    wire inside_square = (x_i >= sq_x) && (x_i < sq_x + SQ_SIZE) &&
                         (y_i >= sq_y) && (y_i < sq_y + SQ_SIZE);

    assign colour_o = inside_square ? {4'hF, 4'h0, 4'h0} : {4'hF, 4'h0, 4'hF};

endmodule