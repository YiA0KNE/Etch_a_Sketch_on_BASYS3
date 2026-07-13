module moving_circle_gen #(
    parameter H_ACTIVE = 640,
    parameter V_ACTIVE = 480,

    parameter COLOURW  = 4,
    parameter RADIUS   = 20,
    parameter STEP     = 2,
    parameter MOVE_DIV = 300_000
) (
    input  wire                        pix_clk,
    input  wire                        rst_ni,

    input  wire [$clog2(H_ACTIVE)-1:0] x_i,
    input  wire [$clog2(V_ACTIVE)-1:0] y_i,

    input  wire                        manual_i,
    input  wire                        btn_up_i,
    input  wire                        btn_down_i,
    input  wire                        btn_left_i,
    input  wire                        btn_right_i,

    output logic [3*COLOURW-1:0]       colour_o
);

    // Bounding box limits
    localparam CX_MAX = H_ACTIVE - RADIUS - 1;
    localparam CX_MIN = RADIUS;
    localparam CY_MAX = V_ACTIVE - RADIUS - 1;
    localparam CY_MIN = RADIUS;

    // State registers
    logic [$clog2(H_ACTIVE)-1:0] cx;
    logic [$clog2(V_ACTIVE)-1:0] cy;
    logic                        dir_x;
    logic                        dir_y;
    logic [$clog2(MOVE_DIV)-1:0] div_cnt;

    // ----------------------------------------------------------------
    // 1. Move tick: registered 1-cycle pulse
    // ----------------------------------------------------------------
    wire move_tick_raw = (div_cnt == MOVE_DIV - 1);
    logic move_tick;

    always_ff @(posedge pix_clk)
        if (!rst_ni)
            move_tick <= 1'b0;
        else
            move_tick <= move_tick_raw;

    always_ff @(posedge pix_clk)
        if (!rst_ni)
            div_cnt <= '0;
        else
            div_cnt <= move_tick_raw ? '0 : div_cnt + 1'b1;

    // ----------------------------------------------------------------
    // 2. Synchronise button inputs (2-stage flip-flops)
    // ----------------------------------------------------------------
    logic btn_up_s1,   btn_up_s2;
    logic btn_down_s1, btn_down_s2;
    logic btn_left_s1, btn_left_s2;
    logic btn_right_s1,btn_right_s2;

    always_ff @(posedge pix_clk) begin
        btn_up_s1    <= btn_up_i;
        btn_up_s2    <= btn_up_s1;

        btn_down_s1  <= btn_down_i;
        btn_down_s2  <= btn_down_s1;

        btn_left_s1  <= btn_left_i;
        btn_left_s2  <= btn_left_s1;

        btn_right_s1 <= btn_right_i;
        btn_right_s2 <= btn_right_s1;
    end

    wire btn_up    = btn_up_s2;
    wire btn_down  = btn_down_s2;
    wire btn_left  = btn_left_s2;
    wire btn_right = btn_right_s2;

    // ----------------------------------------------------------------
    // 3. Next-state logic for X axis (using registered move_tick)
    // ----------------------------------------------------------------
    logic [$clog2(H_ACTIVE)-1:0] cx_next;
    logic                        dir_x_next;

    always_comb begin
        cx_next    = cx;
        dir_x_next = dir_x;

        if (move_tick) begin
            if (manual_i) begin
                if (btn_right && cx <= CX_MAX - STEP)
                    cx_next = cx + STEP;
                else if (btn_left && cx >= CX_MIN + STEP)
                    cx_next = cx - STEP;
            end else begin
                if (dir_x == 1'b0) begin           // moving right
                    if (cx >= CX_MAX - STEP) begin
                        cx_next    = CX_MAX;
                        dir_x_next = 1'b1;
                    end else begin
                        cx_next = cx + STEP;
                    end
                end else begin                     // moving left
                    if (cx <= CX_MIN + STEP) begin
                        cx_next    = CX_MIN;
                        dir_x_next = 1'b0;
                    end else begin
                        cx_next = cx - STEP;
                    end
                end
            end
        end
    end

    // ----------------------------------------------------------------
    // 4. Next-state logic for Y axis
    // ----------------------------------------------------------------
    logic [$clog2(V_ACTIVE)-1:0] cy_next;
    logic                        dir_y_next;

    always_comb begin
        cy_next    = cy;
        dir_y_next = dir_y;

        if (move_tick) begin
            if (manual_i) begin
                if (btn_down && cy <= CY_MAX - STEP)
                    cy_next = cy + STEP;
                else if (btn_up && cy >= CY_MIN + STEP)
                    cy_next = cy - STEP;
            end else begin
                if (dir_y == 1'b0) begin           // moving down
                    if (cy >= CY_MAX - STEP) begin
                        cy_next    = CY_MAX;
                        dir_y_next = 1'b1;
                    end else begin
                        cy_next = cy + STEP;
                    end
                end else begin                     // moving up
                    if (cy <= CY_MIN + STEP) begin
                        cy_next    = CY_MIN;
                        dir_y_next = 1'b0;
                    end else begin
                        cy_next = cy - STEP;
                    end
                end
            end
        end
    end

    // ----------------------------------------------------------------
    // 5. Register updates
    // ----------------------------------------------------------------
    always_ff @(posedge pix_clk)
        if (!rst_ni)
            cx <= H_ACTIVE / 2;
        else
            cx <= cx_next;

    always_ff @(posedge pix_clk)
        if (!rst_ni)
            cy <= V_ACTIVE / 2;
        else
            cy <= cy_next;

    always_ff @(posedge pix_clk)
        if (!rst_ni)
            dir_x <= 1'b0;
        else
            dir_x <= dir_x_next;

    always_ff @(posedge pix_clk)
        if (!rst_ni)
            dir_y <= 1'b0;
        else
            dir_y <= dir_y_next;

    // ----------------------------------------------------------------
    // 6. Pipelined circle hit test
    //    Stage 1: register pixel & centre coordinates
    //    Stage 2: compute distances → in_circle → registered colour
    // ----------------------------------------------------------------
    // Stage 1 registers
    logic [$clog2(H_ACTIVE)-1:0] x_d, cx_d;
    logic [$clog2(V_ACTIVE)-1:0] y_d, cy_d;

    always_ff @(posedge pix_clk) begin
        x_d  <= x_i;
        y_d  <= y_i;
        cx_d <= cx;
        cy_d <= cy;
    end

    // Combinational hit test from registered values
    wire signed [$clog2(H_ACTIVE):0] dx = $signed({1'b0, x_d}) - $signed({1'b0, cx_d});
    wire signed [$clog2(V_ACTIVE):0] dy = $signed({1'b0, y_d}) - $signed({1'b0, cy_d});
    wire in_circle = (dx*dx + dy*dy <= RADIUS*RADIUS);

    // Stage 2 register: colour output (final registered output)
    always_ff @(posedge pix_clk) begin
        if (!rst_ni)
            colour_o <= 12'hFFE;   // background colour during reset
        else
            colour_o <= in_circle ? {cx_d[3:0], cy_d[3:0], cx_d[5:2] ^ cy_d[5:2]} : 12'hFFE;
    end

endmodule