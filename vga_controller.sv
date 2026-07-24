// vga_controller.sv — 640x480 VGA timing generator.
//
// Produces horizontal and vertical sync signals, blanks colour outside the
// active area, and exposes the current pixel coordinates. Horizontal and
// vertical counters are kept in separate always_ff blocks so each contains
// exactly one registered signal.

module vga_controller #(
    // Horizontal timing parameters (measured in pixel clocks).
    parameter int H_ACTIVE = 640,   // visible pixels per line
    parameter int H_FRONT  = 16,    // horizontal front porch
    parameter int H_PULSE  = 96,    // horizontal sync pulse width
    parameter int H_BACK   = 48,    // horizontal back porch

    // Vertical timing parameters (measured in lines).
    parameter int V_ACTIVE = 480,   // visible lines per frame
    parameter int V_FRONT  = 10,    // vertical front porch
    parameter int V_PULSE  = 2,     // vertical sync pulse width
    parameter int V_BACK   = 33,    // vertical back porch

    parameter int COLOURW  = 4      // bits per RGB channel
) (
    input  logic                               pix_clk,  // 25.175 MHz for 640x480@60
    input  logic                               rst_ni,   // active-low reset
    input  logic [3*COLOURW-1:0]               colour_i, // RRRRGGGGBBBB pixel data

    output logic                               hsynct_o, // horizontal sync
    output logic                               vsynct_o, // vertical sync

    output logic [COLOURW-1:0]                 red_o,    // red channel
    output logic [COLOURW-1:0]                 green_o,  // green channel
    output logic [COLOURW-1:0]                 blue_o,   // blue channel

    output logic [$clog2(H_ACTIVE+H_FRONT+H_PULSE+H_BACK)-1:0] next_x_o, // current X
    output logic [$clog2(V_ACTIVE+V_FRONT+V_PULSE+V_BACK)-1:0] next_y_o  // current Y
);

    // Total line and frame lengths.
    localparam int H_TOTAL = H_ACTIVE + H_FRONT + H_PULSE + H_BACK;
    localparam int V_TOTAL = V_ACTIVE + V_FRONT + V_PULSE + V_BACK;

    // Counter widths.
    localparam int H_CW = $clog2(H_TOTAL);
    localparam int V_CW = $clog2(V_TOTAL);

    // Horizontal pixel counter.
    logic [H_CW-1:0] h_counter;

    always_ff @(posedge pix_clk or negedge rst_ni) begin
        if (!rst_ni)
            h_counter <= '0;
        else
            h_counter <= (h_counter == H_TOTAL - 1) ? '0 : h_counter + 1'b1;
    end

    // Vertical line counter, incremented at the end of each full line.
    logic [V_CW-1:0] v_counter;

    always_ff @(posedge pix_clk or negedge rst_ni) begin
        if (!rst_ni)
            v_counter <= '0;
        else if (h_counter == H_TOTAL - 1)
            v_counter <= (v_counter == V_TOTAL - 1) ? '0 : v_counter + 1'b1;
    end

    // Sync and active-region flags.
    wire h_sync_area = (h_counter >= (H_ACTIVE + H_FRONT)) &&
                       (h_counter <  (H_ACTIVE + H_FRONT + H_PULSE));
    wire v_sync_area = (v_counter >= (V_ACTIVE + V_FRONT)) &&
                       (v_counter <  (V_ACTIVE + V_FRONT + V_PULSE));
    wire active_area = (h_counter < H_ACTIVE) && (v_counter < V_ACTIVE);

    // Sync outputs are active-low; drive high during reset.
    assign hsynct_o = h_sync_area ? 1'b0 : 1'b1;
    assign vsynct_o = v_sync_area ? 1'b0 : 1'b1;

    // Colour outputs are forced to black outside the active area or during reset.
    assign red_o   = (!active_area) ? {COLOURW{1'b0}} : colour_i[3*COLOURW-1 -: COLOURW];
    assign green_o = (!active_area) ? {COLOURW{1'b0}} : colour_i[2*COLOURW-1 -: COLOURW];
    assign blue_o  = (!active_area) ? {COLOURW{1'b0}} : colour_i[COLOURW-1:0];

    // Expose current position.
    assign next_x_o = h_counter;
    assign next_y_o = v_counter;

endmodule