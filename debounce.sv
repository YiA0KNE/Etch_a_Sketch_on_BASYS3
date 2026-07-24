////////////////////////////////////////////////////////////////////////////////
// debounce.sv
// Mechanical button debouncer with 2-FF synchroniser.
//
// The raw button is first synchronised to the clock, then a saturation counter
// decides when the input has been stable long enough to commit a new value.
// COUNTER_BITS=18 gives ~10.4 ms at 25.175 MHz.
////////////////////////////////////////////////////////////////////////////////

module debounce #(
    parameter int COUNTER_BITS = 18   // 2^N cycles of stability required
) (
    input  logic clk,       // System clock
    input  logic reset_n,   // Active-low asynchronous reset
    input  logic noisy,     // Raw, possibly bouncing button input
    output logic clean      // Debounced, synchronous output
);

    // -------------------------------------------------------------------------
    // Internal declarations
    // -------------------------------------------------------------------------

    // 2-FF synchroniser registers: prevents metastability from the asynchronous
    // button input.
    logic [1:0] sync_ff;

    // Stability counter and committed output register.
    logic [COUNTER_BITS-1:0] cnt;
    logic                    stable;

    // -------------------------------------------------------------------------
    // 2-FF synchroniser
    // Shift the raw asynchronous input through two flip-flops to reduce the
    // chance of metastability and produce a synchronous version of the signal.
    // -------------------------------------------------------------------------
    always_ff @(posedge clk or negedge reset_n) begin
        if (!reset_n)
            sync_ff <= 2'b00;
        else
            sync_ff <= {sync_ff[0], noisy};
    end

    // -------------------------------------------------------------------------
    // Stability counter
    // The counter increments while the synchronised input disagrees with the
    // stable value. When it saturates, the stable value is updated. While the
    // input agrees, the counter resets to zero.
    // -------------------------------------------------------------------------
    always_ff @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            cnt    <= '0;
            stable <= 1'b0;
        end else if (sync_ff[1] != stable) begin
            if (&cnt) begin
                // Input has been stable long enough -> commit new value
                stable <= sync_ff[1];
            end else begin
                // Still observing a possible bounce -> keep counting
                cnt <= cnt + 1'b1;
            end
        end else begin
            // Synchronised input matches stable value -> reset counter
            cnt <= '0;
        end
    end

    // -------------------------------------------------------------------------
    // Output assignment
    // -------------------------------------------------------------------------
    assign clean = stable;

endmodule