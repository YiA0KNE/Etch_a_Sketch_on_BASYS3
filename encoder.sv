////////////////////////////////////////////////////////////////////////////////
// encoder.sv
// Debounces five buttons and produces a one-cycle control pulse.
//
// btnC toggles the global enable flag; the four directional buttons are
// encoded as a 3-bit control bus (Up/Down/Left/Right) for the UI state machine.
////////////////////////////////////////////////////////////////////////////////

module encoder (
    input  logic clk,       // System clock
    input  logic reset_n,   // Active-low asynchronous reset

    input  logic btnC,      // Centre button (toggle enable)
    input  logic btnU,      // Up
    input  logic btnL,      // Left
    input  logic btnR,      // Right
    input  logic btnD,      // Down

    output logic enable,    // Toggled by centre button
    output logic [2:0] ctrl // One-cycle directional pulse
);

    // -------------------------------------------------------------------------
    // Internal declarations
    // -------------------------------------------------------------------------

    // Synchronised and debounced button signals.
    logic btnC_db;
    logic btnU_db;
    logic btnL_db;
    logic btnR_db;
    logic btnD_db;

    // Previous-cycle copies for edge detection.
    logic btnC_prev;
    logic btnU_prev;
    logic btnL_prev;
    logic btnR_prev;
    logic btnD_prev;

    // Single-cycle pulses on rising edges.
    logic btnC_edge;
    logic btnU_edge;
    logic btnL_edge;
    logic btnR_edge;
    logic btnD_edge;

    // -------------------------------------------------------------------------
    // Button debouncers
    // -------------------------------------------------------------------------
    debounce #(.COUNTER_BITS(18)) u_dbC (
        .clk  (clk),
        .reset_n(reset_n),
        .noisy(btnC),
        .clean(btnC_db)
    );

    debounce #(.COUNTER_BITS(18)) u_dbU (
        .clk  (clk),
        .reset_n(reset_n),
        .noisy(btnU),
        .clean(btnU_db)
    );

    debounce #(.COUNTER_BITS(18)) u_dbD (
        .clk  (clk),
        .reset_n(reset_n),
        .noisy(btnD),
        .clean(btnD_db)
    );

    debounce #(.COUNTER_BITS(18)) u_dbL (
        .clk  (clk),
        .reset_n(reset_n),
        .noisy(btnL),
        .clean(btnL_db)
    );

    debounce #(.COUNTER_BITS(18)) u_dbR (
        .clk  (clk),
        .reset_n(reset_n),
        .noisy(btnR),
        .clean(btnR_db)
    );

    // -------------------------------------------------------------------------
    // Previous-cycle registers for edge detection
    // Split into pairs (and one single) to keep each always_ff at most two
    // signals.
    // -------------------------------------------------------------------------
    always_ff @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            btnC_prev <= 1'b0;
            btnU_prev <= 1'b0;
        end else begin
            btnC_prev <= btnC_db;
            btnU_prev <= btnU_db;
        end
    end

    always_ff @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            btnL_prev <= 1'b0;
            btnR_prev <= 1'b0;
        end else begin
            btnL_prev <= btnL_db;
            btnR_prev <= btnR_db;
        end
    end

    always_ff @(posedge clk or negedge reset_n) begin
        if (!reset_n)
            btnD_prev <= 1'b0;
        else
            btnD_prev <= btnD_db;
    end

    // -------------------------------------------------------------------------
    // Rising-edge detection assignments
    // -------------------------------------------------------------------------
    assign btnC_edge = btnC_db & ~btnC_prev;
    assign btnU_edge = btnU_db & ~btnU_prev;
    assign btnD_edge = btnD_db & ~btnD_prev;
    assign btnL_edge = btnL_db & ~btnL_prev;
    assign btnR_edge = btnR_db & ~btnR_prev;

    // -------------------------------------------------------------------------
    // Enable toggle
    // Centre button toggles the global enable flag.
    // -------------------------------------------------------------------------
    always_ff @(posedge clk or negedge reset_n) begin
        if (!reset_n)
            enable <= 1'b0;
        else if (btnC_edge)
            enable <= ~enable;
    end

    // -------------------------------------------------------------------------
    // Directional control encoder
    // Convert one-cycle directional edges into the control bus.
    // Priority: Up > Down > Left > Right.
    // -------------------------------------------------------------------------
    always_comb begin
        if      (btnU_edge) ctrl = 3'b010; //UP
        else if (btnD_edge) ctrl = 3'b110; //DOwn
        else if (btnL_edge) ctrl = 3'b001; //LEFT
        else if (btnR_edge) ctrl = 3'b101; //RIGHT
        else                ctrl = 3'b000;
    end

endmodule