////////////////////////////////////////////////////////////////////////////////
// colour_lut.sv
// Hue/saturation to RGB lookup table.
//
// The palette is fully pre-computed at elaboration. Base hues are generated
// algorithmically around the HSV colour wheel, then each base hue is mixed
// toward white as saturation decreases. The resulting ROM contains one entry
// for every (hue, saturation) pair, so NUM_HUES can be changed freely.
////////////////////////////////////////////////////////////////////////////////

module colour_lut #(
    parameter int NUM_HUES = 16,   // Number of discrete hues around the wheel (>= 2)
    parameter int NUM_SATS = 16,   // Number of saturation steps (>= 2)
    parameter int CHANW    = 4     // Bits per RGB channel
) (
    input  logic [$clog2(NUM_HUES)-1:0] hue,  // Hue index
    input  logic [$clog2(NUM_SATS)-1:0] sat,  // Saturation index
    output logic [CHANW-1:0]            r,    // Red channel
    output logic [CHANW-1:0]            g,    // Green channel
    output logic [CHANW-1:0]            b     // Blue channel
);

    // -------------------------------------------------------------------------
    // Local parameters and compile-time checks
    // -------------------------------------------------------------------------
    localparam int MAXV = (1 << CHANW) - 1;   // Peak channel value

    generate
        if (NUM_HUES < 2)
            $fatal(1, "colour_lut: NUM_HUES must be >= 2");
        if (NUM_SATS < 2)
            $fatal(1, "colour_lut: NUM_SATS must be >= 2");
    endgenerate

    // -------------------------------------------------------------------------
    // Internal declarations
    // -------------------------------------------------------------------------

    // Flattened palette arrays: one entry per (hue, saturation).
    logic [CHANW-1:0] pal_r [0:NUM_HUES*NUM_SATS-1];
    logic [CHANW-1:0] pal_g [0:NUM_HUES*NUM_SATS-1];
    logic [CHANW-1:0] pal_b [0:NUM_HUES*NUM_SATS-1];

    // Flattened index into the palette arrays.
    logic [$clog2(NUM_HUES*NUM_SATS)-1:0] idx;

    // -------------------------------------------------------------------------
    // Base-hue generation function
    // -------------------------------------------------------------------------

    // Compute one channel of the fully-saturated base hue at index h.
    // ch selects the channel: 0 = R, 1 = G, 2 = B.
    // The hue is evenly spaced around the HSV wheel (0 .. 360 degrees).
    function automatic logic [CHANW-1:0] base_channel(input int h, input int ch);
        int angle, sector, f, t, q;

        begin
            angle  = (h * 360) / NUM_HUES;   // 0 .. 359
            sector = (angle / 60) % 6;       // 0 .. 5
            f      = angle - (sector * 60);  // fraction within sector, 0 .. 59
            t      = (MAXV * f) / 60;        // rising edge value
            q      = MAXV - t;               // falling edge value

            unique case (sector)
                0: base_channel = (ch == 0) ? MAXV     : (ch == 1) ? t        : CHANW'(0); // red -> yellow
                1: base_channel = (ch == 0) ? q        : (ch == 1) ? MAXV     : CHANW'(0); // yellow -> green
                2: base_channel = (ch == 0) ? CHANW'(0) : (ch == 1) ? MAXV    : t;         // green -> cyan
                3: base_channel = (ch == 0) ? CHANW'(0) : (ch == 1) ? q      : MAXV;       // cyan -> blue
                4: base_channel = (ch == 0) ? t        : (ch == 1) ? CHANW'(0) : MAXV;     // blue -> magenta
                5: base_channel = (ch == 0) ? MAXV     : (ch == 1) ? CHANW'(0) : q;        // magenta -> red
                default: base_channel = CHANW'(0);
            endcase
        end
    endfunction

    // -------------------------------------------------------------------------
    // Palette generation
    // -------------------------------------------------------------------------
    genvar gi;
    generate
        for (gi = 0; gi < NUM_HUES * NUM_SATS; gi++) begin : gen_pal
            localparam int H_I = gi / NUM_SATS;   // hue index
            localparam int S_I = gi % NUM_SATS;   // saturation index

            // Fully-saturated base colour for this hue.
            localparam logic [CHANW-1:0] BR = base_channel(H_I, 0);
            localparam logic [CHANW-1:0] BG = base_channel(H_I, 1);
            localparam logic [CHANW-1:0] BB = base_channel(H_I, 2);

            // Move the base hue toward white as saturation drops.
            // At sat = NUM_SATS-1 the base hue is used unchanged; at sat = 0
            // the colour becomes white.
            localparam logic [CHANW-1:0] PR =
                BR + (((MAXV - BR) * (NUM_SATS-1-S_I)) / (NUM_SATS-1));
            localparam logic [CHANW-1:0] PG =
                BG + (((MAXV - BG) * (NUM_SATS-1-S_I)) / (NUM_SATS-1));
            localparam logic [CHANW-1:0] PB =
                BB + (((MAXV - BB) * (NUM_SATS-1-S_I)) / (NUM_SATS-1));

            assign pal_r[gi] = PR;
            assign pal_g[gi] = PG;
            assign pal_b[gi] = PB;
        end
    endgenerate

    // -------------------------------------------------------------------------
    // Output assignments
    // -------------------------------------------------------------------------
    assign idx = hue * NUM_SATS + sat;

    assign r = pal_r[idx];
    assign g = pal_g[idx];
    assign b = pal_b[idx];

endmodule