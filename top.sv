// Format            Pixel Clock(MHz)    H_ACTIVE    H_FRONT    H_SYNC    H_BACK  |  V_ACTIVE    V_FRONT    V_SYNC    V_BACK
//  640x480@60Hz     25.175              640         16         96        48      |  480         11         2         31
//  800x600@60Hz     40.000              800         40         128       88      |  600         1          4         23
//  1024x768@60Hz    65.000              1024        24         136       160     |  768         3          6         29

module top #(

    //Video Timing Parameters 
    parameter H_ACTIVE = 640,
    parameter H_FRONT  = 16,
    parameter H_PULSE  = 96,
    parameter H_BACK   = 48,

    parameter V_ACTIVE = 480,
    parameter V_FRONT  = 11,      
    parameter V_PULSE  = 2,
    parameter V_BACK   = 33,
    
    parameter COLOURW  = 4,

    // Circle parameters
    parameter CIRCLE_RADIUS   = 20,
    parameter CIRCLE_STEP     = 2,
    parameter CIRCLE_MOVE_DIV = 300_000,

    // Square parameters
    parameter SQUARE_SIZE     = 80,
    parameter SQUARE_STEP     = 4
) (
    input  logic        sys_clock,

    input  logic [15:0] sw,

    input  logic        btnC,   // centre
    input  logic        btnU,   // up
    input  logic        btnL,   // left
    input  logic        btnR,   // right
    input  logic        btnD,   // down

    output logic        Hsync,
    output logic        Vsync,

    output logic [3:0]  vgaRed,
    output logic [3:0]  vgaBlue,
    output logic [3:0]  vgaGreen
);

    //reset activ low
    logic resetn;
    assign resetn = sw[15];

    //total width of the horizontal and vertical counters
    localparam H_TOTAL = H_ACTIVE + H_FRONT + H_PULSE + H_BACK;
    localparam V_TOTAL = V_ACTIVE + V_FRONT + V_PULSE + V_BACK;

    //auto scale pixel coords
    logic [$clog2(H_TOTAL)-1:0] pix_x;
    logic [$clog2(V_TOTAL)-1:0] pix_y;
    logic [3*COLOURW-1:0]       pixel_colour;

    wire [3*COLOURW-1:0]        square_colour;

    //is 1 every time the pix_x and pix_y are at the last pixel (ie end of frame)
    wire frame_tick = (pix_x == H_TOTAL - 1) && (pix_y == V_TOTAL - 1);

    //pll for ckl gen
    logic pix_clk;
    clk_vga_wrapper u_clk_vga_wrapper (
        .clk_out1_0 (pix_clk),
        .reset      (resetn),
        .sys_clock  (sys_clock)
    );

    moving_square_gen #(
        .H_ACTIVE   (H_ACTIVE),
        .V_ACTIVE   (V_ACTIVE),

        .COLOURW    (COLOURW),
        .SQ_SIZE    (SQUARE_SIZE),
        .STEP       (SQUARE_STEP)
    ) u_bouncing_square_gen (
        .pix_clk    (pix_clk),
        .rst_ni     (resetn),

        .frame_tick (frame_tick),      // square uses frame_tick for movement
        .x_i        (pix_x),
        .y_i        (pix_y),

        .colour_o   (square_colour)
    );

    // -----------------------------------------------------------------
    // VGA controller
    // -----------------------------------------------------------------
    vga_controller #(
        .H_ACTIVE   (H_ACTIVE),
        .H_FRONT    (H_FRONT),
        .H_PULSE    (H_PULSE),
        .H_BACK     (H_BACK),

        .V_ACTIVE   (V_ACTIVE),
        .V_FRONT    (V_FRONT),
        .V_PULSE    (V_PULSE),
        .V_BACK     (V_BACK),

        .COLOURW    (COLOURW)
    ) u_vga_controller (
        .pix_clk    (pix_clk),
        .rst_ni     (resetn),

        .colour_i   (square_colour),

        .next_x_o   (pix_x),
        .next_y_o   (pix_y),

        .hsynct_o   (Hsync),
        .vsynct_o   (Vsync),

        .red_o      (vgaRed),
        .green_o    (vgaGreen),
        .blue_o     (vgaBlue)
    );

endmodule