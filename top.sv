////////////////////////////////////////////////////////////////////////////////
// top.sv
// Top-level for the BASYS 3 drawing interface.
//
// A PLL generates the VGA pixel clock. The screen is split into a left tool
// panel and a right drawing canvas, both fed from the same VGA controller.
////////////////////////////////////////////////////////////////////////////////

module top #(
    // Video timing parameters.
    parameter int H_ACTIVE    = 800,    // Horizontal active video width (pixels)
    parameter int H_FRONT     = 40,     // Horizontal front porch width (pixels)
    parameter int H_PULSE     = 128,     // Horizontal sync pulse width (pixels)
    parameter int H_BACK      = 88,     // Horizontal back porch width (pixels)
    
    parameter int V_ACTIVE    = 600,    // Vertical active video height (lines)
    parameter int V_FRONT     = 1,     // Vertical front porch height (lines)
    parameter int V_PULSE     = 4,      // Vertical sync pulse height (lines)
    parameter int V_BACK      = 23,     // Vertical back porch height (lines)

    // Data-path parameters.
    parameter int COLOURW     = 4,      // Bit width of each RGB channel
    parameter int START_SIZE  = 4,      // Initial brush/cursor size
    parameter int NUM_HUES    = 4,     // Number of hue settings in colour picker
    parameter int NUM_SATS    = 4,      // Number of saturation settings in colour picker

    // Split-screen geometry.
    parameter int SPLIT       = 30,     // Left zone width as % of H_ACTIVE
    parameter int LINEW       = 1,      // Separator line width (pixels)

    // UI scale.
    parameter int UI_SCALE    = 4       // Pixel scaling factor for UI glyphs
) (
    input  logic        sys_clock,      // Board 100 MHz system clock

    input  logic [15:0] sw,             // Slide switches
    output logic [15:0] led,            // LEDs for debug/mouse state

    input  logic        btnC,           // Centre button
    input  logic        btnU,           // Up button
    input  logic        btnL,           // Left button
    input  logic        btnR,           // Right button
    input  logic        btnD,           // Down button

    // PS/2 mouse pins.
    inout  logic        PS2Clk,         // PS/2 mouse clock line
    inout  logic        PS2Data,        // PS/2 mouse data line

    output logic        Hsync,          // VGA horizontal sync output
    output logic        Vsync,          // VGA vertical sync output

    output logic [3:0]  vgaRed,         // VGA red channel
    output logic [3:0]  vgaBlue,        // VGA blue channel
    output logic [3:0]  vgaGreen        // VGA green channel
);

    // -------------------------------------------------------------------------
    // Local parameters
    // -------------------------------------------------------------------------
    localparam int H_TOTAL = H_ACTIVE + H_FRONT + H_PULSE + H_BACK;   // Total horizontal scanline length
    localparam int V_TOTAL = V_ACTIVE + V_FRONT + V_PULSE + V_BACK;   // Total vertical frame length

    localparam int CANVAS_W = (H_ACTIVE * (100 - SPLIT)) / 100 - LINEW; // Drawing canvas width (pixels)
    localparam int CANVAS_H = V_ACTIVE;                                 // Drawing canvas height (pixels)

    // -------------------------------------------------------------------------
    // Internal declarations
    // -------------------------------------------------------------------------

    // Clock and reset
    logic resetn;               // Active-low reset from switch 15
    logic pix_clk;              // Pixel clock from PLL/MMCM wrapper

    // Global pixel coordinates from the VGA controller.
    logic [$clog2(H_TOTAL)-1:0] next_x_o;
    logic [$clog2(V_TOTAL)-1:0] next_y_o;

    // One-cycle pulse at the very last pixel of a frame.
    logic frame_tick;

    // Local coordinates for the left and right zones.
    logic [$clog2(H_TOTAL)-1:0] next_x_left_o;
    logic [$clog2(H_TOTAL)-1:0] next_x_right_o;
    logic [$clog2(V_TOTAL)-1:0] next_y_left_o;
    logic [$clog2(V_TOTAL)-1:0] next_y_right_o;

    // RGB streams from the two content generators.
    logic [3*COLOURW-1:0] vga_colour;
    logic [3*COLOURW-1:0] user_interface;
    logic [3*COLOURW-1:0] drawing_interface;

    // UI / drawing control.
    logic enable;
    logic [2:0] ctrl;

    // Tool-panel settings.
    logic [3:0] size;
    logic       cursor_shape;
    logic [$clog2(NUM_HUES)-1:0] hue_panel;
    logic [$clog2(NUM_SATS)-1:0] sat_panel;

    // PS/2 mouse signals.
    logic [11:0] mouse_xpos;
    logic [11:0] mouse_ypos;
    logic        mouse_left;
    logic        mouse_right;
    logic        mouse_middle;
    logic        mouse_new_event;

    // Reset edge detector for setmax pulse.
    logic resetn_d;
    logic setmax_pulse;

    // -------------------------------------------------------------------------
    // Combinational assignments
    // -------------------------------------------------------------------------

    // Active-low reset from switch 15.
    assign resetn = sw[15];

    // Frame complete pulse: last pixel of the active frame.
    assign frame_tick = (next_x_o == H_TOTAL - 1) && (next_y_o == V_TOTAL - 1);

    // One-shot pulse on the rising edge of resetn.
    assign setmax_pulse = resetn && !resetn_d;

    // LED debug: show mouse state.
    assign led = {mouse_new_event, mouse_middle, mouse_right, mouse_left, mouse_xpos};

    // -------------------------------------------------------------------------
    // Sequential logic
    // -------------------------------------------------------------------------

    // Delay reset by one cycle to detect its rising edge.
    always_ff @(posedge pix_clk) begin
        resetn_d <= resetn;
    end

    // -------------------------------------------------------------------------
    // Submodule instantiations
    // -------------------------------------------------------------------------

    // Pixel clock generator.
    clk_vga_wrapper u_clk_vga_wrapper (
        .clk_out1_0 (pix_clk),
        .reset      (resetn),
        .sys_clock  (sys_clock)
    );

    // Button encoder: debounce, edge detect, toggle enable, encode control bus.
    encoder u_encoder (
        .clk     (pix_clk),
        .reset_n (resetn),

        .btnC    (btnC),
        .btnU    (btnU),
        .btnL    (btnL),
        .btnR    (btnR),
        .btnD    (btnD),
        
        .enable  (enable),
        .ctrl    (ctrl)
    );

    // PS/2 mouse tracker.
    ps2_mouse #(
        .SYSCLK_HZ         (25_175_000),
        .CHECK_PERIOD_MS   (500),
        .TIMEOUT_PERIOD_MS (100)
    ) u_ps2_mouse (
        .clk        (pix_clk),
        .rst_n      (resetn),

        .ps2_clk    (PS2Clk),
        .ps2_data   (PS2Data),

        .setmax_val (12'hFFF),        // was: (CANVAS_W - 1)
        .setmax_x   (setmax_pulse),   // pulse once after reset
        .setmax_y   (setmax_pulse),   // pulse once after reset

        .setx       (1'b0),
        .sety       (1'b0),

        .xpos       (mouse_xpos),
        .ypos       (mouse_ypos),

        .left_btn   (mouse_left),
        .right_btn  (mouse_right),
        .middle_btn (mouse_middle),

        .new_event  (mouse_new_event)
    );

    // Left zone: tool panel.
    user_interface #(
        .HORIZONTAL (u_vga_split_screen.LEFT_W),
        .VERTICAL   (V_ACTIVE),

        .UI_SCALE   (UI_SCALE),
        .NUM_HUES   (NUM_HUES),
        .NUM_SATS   (NUM_SATS)
    ) u_user_interface (
        .clk                (pix_clk),
        .rst_n              (resetn),

        .enable             (enable),
        .control            (ctrl),

        .x                  (next_x_left_o),
        .y                  (next_y_left_o),

        .pixel_colour       (user_interface),

        .size_panel         (size),
        .cursor_shape_panel (cursor_shape),
        .hue_panel          (hue_panel),
        .sat_panel          (sat_panel)
    );

    // Right zone: drawing canvas.
    drawing_interface #(
        .HORIZONTAL (u_vga_split_screen.RIGHT_W),
        .VERTICAL   (V_ACTIVE),
        .COLOURW    (COLOURW),
        .START_SIZE (START_SIZE),
        .NUM_HUES   (NUM_HUES),
        .NUM_SATS   (NUM_SATS)
    ) u_drawing_interface (
        .clk                (pix_clk),
        .rst_n              (resetn),
        .enable             (enable),

        .hide_cursor        (sw[0]),
        .frame_tick         (frame_tick),
        .draw_enable        (mouse_left),

        .x                  (next_x_right_o),
        .y                  (next_y_right_o),

        .mouse_xpos         (mouse_xpos),
        .mouse_ypos         (mouse_ypos),
        .mouse_new_event    (mouse_new_event),

        .hue_sel            (hue_panel),
        .sat_sel            (sat_panel),

        .size_cursor        (size),
        .cursor_shape       (cursor_shape),
        .colour             (drawing_interface)
    );

    // Split the screen into left panel | separator | right canvas.
    vga_split_screen #(
        .COLOURW          (COLOURW),
        .H_ACTIVE         (H_ACTIVE),
        .H_FRONT          (H_FRONT),
        .H_PULSE          (H_PULSE),
        .H_BACK           (H_BACK),

        .V_ACTIVE         (V_ACTIVE),
        .V_FRONT          (V_FRONT),
        .V_PULSE          (V_PULSE),
        .V_BACK           (V_BACK),
        .SPLIT_PCT        (SPLIT),

        .LINE_W           (LINEW),
        .SEPARATOR_COLOUR ('hFFF)
    ) u_vga_split_screen (
        .next_x_i       (next_x_o),
        .next_y_i       (next_y_o),

        .colour_left_i  (user_interface),
        .colour_right_i (drawing_interface),

        .next_x_left_o  (next_x_left_o),
        .next_y_left_o  (next_y_left_o),

        .next_x_right_o (next_x_right_o),
        .next_y_right_o (next_y_right_o),

        .colour_o       (vga_colour)
    );

    // VGA timing and RGB output.
    vga_controller #(
        .H_ACTIVE (H_ACTIVE),
        .H_FRONT  (H_FRONT),
        .H_PULSE  (H_PULSE),
        .H_BACK   (H_BACK),

        .V_ACTIVE (V_ACTIVE),
        .V_FRONT  (V_FRONT),
        .V_PULSE  (V_PULSE),
        .V_BACK   (V_BACK),

        .COLOURW  (COLOURW)
    ) u_vga_controller (
        .pix_clk  (pix_clk),
        .rst_ni   (resetn),

        .colour_i (vga_colour),

        .next_x_o (next_x_o),
        .next_y_o (next_y_o),

        .hsynct_o (Hsync),
        .vsynct_o (Vsync),

        .red_o    (vgaRed),
        .green_o  (vgaGreen),
        .blue_o   (vgaBlue)
    );

endmodule