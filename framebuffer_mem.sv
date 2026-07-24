////////////////////////////////////////////////////////////////////////////////
// framebuffer_mem.sv
// Simple single-port read / single-port write block-RAM framebuffer.
//
// Stores PIXELS pixel values, each PIXW bits wide. The memory is inferred as
// Xilinx block RAM (ram_style = "block"). Writes are synchronous and occur
// when wr_en is asserted. Reads are registered: the data at rd_addr appears
// on rd_data on the next rising clock edge.
//
// Parameters:
//   PIXELS - Total number of addressable pixel locations.
//   PIXW   - Bit width of each pixel.
//   ADDRW  - Address width, automatically sized to cover PIXELS.
////////////////////////////////////////////////////////////////////////////////

module framebuffer_mem #(
    parameter int PIXELS = 53520,          // Total pixel storage locations
    parameter int PIXW   = 8,              // Bits per pixel
    parameter int ADDRW  = $clog2(PIXELS)  // Address bus width
) (
    input  logic             clk,          // System clock

    input  logic             wr_en,        // Write enable (active high)
    input  logic [ADDRW-1:0] wr_addr,      // Write address
    input  logic [PIXW-1:0]  wr_data,      // Write data

    input  logic [ADDRW-1:0] rd_addr,      // Read address
    output logic [PIXW-1:0]  rd_data       // Registered read data
);

    // -------------------------------------------------------------------------
    // Pixel storage array
    // -------------------------------------------------------------------------
    // Infer as block RAM. The array holds PIXELS entries, each PIXW bits wide.
    (* ram_style = "block" *)
    logic [PIXW-1:0] mem [0:PIXELS-1];

    // -------------------------------------------------------------------------
    // Synchronous write and registered read
    // -------------------------------------------------------------------------
    always_ff @(posedge clk) begin
        // Write port: update memory when enabled.
        if (wr_en)
            mem[wr_addr] <= wr_data;

        // Registered read port: output data one cycle after address is applied.
        rd_data <= mem[rd_addr];
    end

endmodule