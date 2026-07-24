////////////////////////////////////////////////////////////////////////////////
// bresenham.sv
// Bresenham line generator with stall support.
//
// start  : latch (x0,y0)->(x1,y1) and begin emission.
// stall  : hold state when high (pause for stamping downstream).
// valid  : high for one cycle per emitted pixel.
// done   : pulses one cycle after the final pixel.
//          done is NOT masked by stall — it persists until seen.
////////////////////////////////////////////////////////////////////////////////

module bresenham (
    input  logic        clk,        // System clock
    input  logic        rst_n,      // Active-low reset
    input  logic        start,      // Begin a new line segment
    input  logic        stall,      // Pause processing while high

    input  logic [10:0] x0,         // Line start X
    input  logic [10:0] y0,         // Line start Y
    input  logic [10:0] x1,         // Line end X
    input  logic [10:0] y1,         // Line end Y

    output logic [10:0] x_out,      // Current emitted pixel X
    output logic [10:0] y_out,      // Current emitted pixel Y
    output logic        valid,      // High when x_out/y_out are valid
    output logic        done        // High for one cycle when line is complete
);

    // -------------------------------------------------------------------------
    // FSM state type
    // -------------------------------------------------------------------------
    typedef enum logic [1:0] {
        S_IDLE = 2'b00,     // Waiting for start
        S_INIT = 2'b01,     // Emit the starting pixel
        S_RUN  = 2'b10      // Walk the line until the end pixel
    } state_t;

    state_t state;          // Current FSM state
    state_t next_state;     // Next FSM state

    // -------------------------------------------------------------------------
    // Absolute deltas and zero-length detection
    // -------------------------------------------------------------------------
    logic signed [11:0] adx;        // |x1 - x0|
    logic signed [11:0] ady;        // |y1 - y0|
    logic               zero_len;   // 1 when start and end are identical

    // -------------------------------------------------------------------------
    // Captured line parameters (loaded on start)
    // -------------------------------------------------------------------------
    logic signed [11:0] dx;     // Absolute delta in X
    logic signed [11:0] dy;     // Absolute delta in Y
    logic               steep;  // 1 when |dy| > |dx|
    logic [10:0]        sx;     // X step direction (+1 or -1)
    logic [10:0]        sy;     // Y step direction (+1 or -1)
    logic [10:0]        tx;     // Target X
    logic [10:0]        ty;     // Target Y

    // -------------------------------------------------------------------------
    // Working registers
    // -------------------------------------------------------------------------
    logic signed [11:0] err;    // Bresenham error term
    logic [10:0]        cx;     // Current X
    logic [10:0]        cy;     // Current Y

    // -------------------------------------------------------------------------
    // Next-value signals (combinational)
    // -------------------------------------------------------------------------
    logic signed [11:0] next_err;
    logic [10:0]        next_cx;
    logic [10:0]        next_cy;
    logic               next_valid;
    logic               next_done;

    // -------------------------------------------------------------------------
    // Absolute delta assignments
    // Extend inputs to 12-bit signed, then take the absolute difference.
    // -------------------------------------------------------------------------
    assign adx = (x1 > x0)
                 ? ($signed({1'b0, x1}) - $signed({1'b0, x0}))
                 : ($signed({1'b0, x0}) - $signed({1'b0, x1}));

    assign ady = (y1 > y0)
                 ? ($signed({1'b0, y1}) - $signed({1'b0, y0}))
                 : ($signed({1'b0, y0}) - $signed({1'b0, y1}));

    assign zero_len = (x0 == x1) && (y0 == y1);

    // -------------------------------------------------------------------------
    // Output assignments
    // -------------------------------------------------------------------------
    assign x_out = cx;
    assign y_out = cy;

    // -------------------------------------------------------------------------
    // FSM state register
    // -------------------------------------------------------------------------
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            state <= S_IDLE;
        else
            state <= next_state;
    end

    // -------------------------------------------------------------------------
    // Captured parameter registers
    // Loaded when start is asserted and the unit is not stalled.
    // -------------------------------------------------------------------------
    always_ff @(posedge clk) begin
        if (start && !stall) begin
            dx <= adx;
            dy <= ady;
        end
    end

    always_ff @(posedge clk) begin
        if (start && !stall)
            steep <= (ady > adx);
    end

    always_ff @(posedge clk) begin
        if (start && !stall)
            sx <= (x0 < x1) ? 11'd1 : (~11'd0);   // +1 right, -1 left
    end

    always_ff @(posedge clk) begin
        if (start && !stall)
            sy <= (y0 < y1) ? 11'd1 : (~11'd0);   // +1 down, -1 up
    end

    always_ff @(posedge clk) begin
        if (start && !stall) begin
            tx <= x1;
            ty <= y1;
        end
    end

    // -------------------------------------------------------------------------
    // Working registers
    // Updated every cycle unless stalled.
    // -------------------------------------------------------------------------
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            cx <= 11'd0;
        else if (!stall)
            cx <= next_cx;
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            cy <= 11'd0;
        else if (!stall)
            cy <= next_cy;
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            err <= 12'd0;
        else if (!stall)
            err <= next_err;
    end

    // -------------------------------------------------------------------------
    // Output control registers
    // valid is masked by stall so no pixel is emitted while paused.
    // done is NOT masked by stall; it persists until the consumer sees it.
    // -------------------------------------------------------------------------
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            valid <= 1'b0;
            done  <= 1'b0;
        end else begin
            valid <= (!stall) ? next_valid : 1'b0;
            done  <= next_done;     // always update — never masked
        end
    end

    // -------------------------------------------------------------------------
    // FSM next-state and next-value combinational logic
    // -------------------------------------------------------------------------
    always_comb begin
        // Default: hold current values, no valid/done
        next_state = state;
        next_cx    = cx;
        next_cy    = cy;
        next_err   = err;
        next_valid = 1'b0;
        next_done  = 1'b0;

        if (!stall) begin
            case (state)

                S_IDLE: begin
                    if (start) begin
                        // Load start point and initial error term
                        next_cx  = x0;
                        next_cy  = y0;
                        next_err = (ady > adx)
                                   ? (2*adx - ady)
                                   : (2*ady - adx);

                        if (zero_len) begin
                            // Single-pixel line: emit and finish immediately
                            next_valid = 1'b1;
                            next_done  = 1'b1;
                            // remain in S_IDLE
                        end else begin
                            next_state = S_INIT;
                        end
                    end
                end

                S_INIT: begin
                    // Emit the starting pixel, then begin stepping
                    next_valid = 1'b1;
                    next_state = S_RUN;
                end

                S_RUN: begin
                    // Take one Bresenham step
                    if (steep) begin
                        // Y-major line
                        next_cy = cy + sy;
                        if (err >= 0) begin
                            next_cx  = cx + sx;
                            next_err = err + 2*(dx - dy);
                        end else begin
                            next_err = err + 2*dx;
                        end
                    end else begin
                        // X-major line
                        next_cx = cx + sx;
                        if (err >= 0) begin
                            next_cy  = cy + sy;
                            next_err = err + 2*(dy - dx);
                        end else begin
                            next_err = err + 2*dy;
                        end
                    end

                    // Check if the step landed on the target pixel
                    if ((next_cx == tx) && (next_cy == ty)) begin
                        next_valid = 1'b1;
                        next_done  = 1'b1;
                        next_state = S_IDLE;
                    end else begin
                        next_valid = 1'b1;
                    end
                end

                default: begin
                    next_state = S_IDLE;
                end

            endcase
        end
    end

endmodule