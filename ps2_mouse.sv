////////////////////////////////////////////////////////////////////////////////
// ps2_mouse.sv
// Self-contained PS/2 mouse controller for BASYS 3.
//
// FIXES applied:
//  1. Sign-extension: {rx_byte[7], rx_byte} instead of {1'b0, rx_byte}
//  2. Y delta matches VHDL: negate rx_byte FIRST, then sign-extend with y_sign
//  3. Y accumulator uses + (VHDL adds inc, not subtracts)
//  4. Watchdog (wd_tick) added to M_READ_BYTE_2/3/4 so a stuck packet
//     doesn't lock the FSM.
////////////////////////////////////////////////////////////////////////////////

module ps2_mouse #(
    parameter int SYSCLK_HZ         = 25_175_000,   // System clock frequency (Hz)
    parameter int CHECK_PERIOD_MS   = 2000,         // Watchdog period (ms)
    parameter int TIMEOUT_PERIOD_MS = 100           // ID-check timeout period (ms)
) (
    input  logic        clk,        // System clock
    input  logic        rst_n,      // Active-low asynchronous reset

    inout  wire         ps2_clk,    // PS/2 clock line (bidirectional, open-drain)
    inout  wire         ps2_data,   // PS/2 data line (bidirectional, open-drain)

    input  logic [11:0] setmax_val, // Value loaded into x_max / y_max
    input  logic        setmax_x,   // Load setmax_val into x_max
    input  logic        setmax_y,   // Load setmax_val into y_max
    input  logic        setx,       // Force xpos to setmax_val
    input  logic        sety,       // Force ypos to setmax_val

    output logic [11:0] xpos,       // Current X position
    output logic [11:0] ypos,       // Current Y position
    output logic        left_btn,   // Left button state
    output logic        right_btn,  // Right button state
    output logic        middle_btn, // Middle button state
    output logic        new_event   // Pulse when a new packet is processed
);

    // -------------------------------------------------------------------------
    // Local parameters
    // -------------------------------------------------------------------------

    // Timing constants derived from SYSCLK_HZ.
    localparam int CLK_PERIOD_NS = 1_000_000_000 / SYSCLK_HZ;   // Clock period (ns)
    localparam int DELAY_100US   = (100_000 / CLK_PERIOD_NS);   // Clocks in 100 us
    localparam int W100          = $clog2(DELAY_100US + 1);     // Bit width of 100 us counter
    localparam int DELAY_20US    = (20_000 / CLK_PERIOD_NS);    // Clocks in 20 us
    localparam int W20           = $clog2(DELAY_20US + 1);      // Bit width of 20 us counter
    localparam int W63           = 7;                           // Bit width of 63-clock counter
    localparam int DEBOUNCE      = 4;                           // Stable samples for debounce
    localparam int CHECK_TICK    = (CHECK_PERIOD_MS * 1_000_000) / CLK_PERIOD_NS;  // Watchdog ticks
    localparam int TIMEOUT_TOP   = (TIMEOUT_PERIOD_MS * 1_000_000) / CLK_PERIOD_NS; // Timeout ticks

    // PS/2 command bytes.
    localparam logic [7:0] CMD_RESET           = 8'hFF;   // Reset mouse
    localparam logic [7:0] CMD_ENABLE_REPORT   = 8'hF4;   // Enable data reporting
    localparam logic [7:0] CMD_SET_RESOLUTION  = 8'hE8;   // Set resolution
    localparam logic [7:0] CMD_SET_SAMPLE_RATE = 8'hF3;   // Set sample rate
    localparam logic [7:0] CMD_READ_ID         = 8'hF2;   // Read device ID

    // PS/2 response bytes.
    localparam logic [7:0] ACK                 = 8'hFA;   // Command acknowledge
    localparam logic [7:0] BAT_OK              = 8'hAA;   // Basic Assurance Test passed
    localparam logic [7:0] MOUSE_ID_STD        = 8'h00;   // Standard PS/2 mouse ID
    localparam logic [7:0] MOUSE_ID_WHEEL      = 8'h03;   // PS/2 wheel mouse ID

    // Sample-rate values sent during init.
    localparam logic [7:0] SAMPLE_200          = 8'hC8;   // 200 samples/sec
    localparam logic [7:0] SAMPLE_100          = 8'h64;   // 100 samples/sec
    localparam logic [7:0] SAMPLE_80           = 8'h50;   // 80 samples/sec
    localparam logic [7:0] SAMPLE_40           = 8'h28;   // 40 samples/sec
    localparam logic [7:0] RESOLUTION          = 8'h03;   // 8 counts/mm

    // Default position limits.
    localparam logic [11:0] DEFAULT_MAX_X = 12'hFFF;      // Default X maximum
    localparam logic [11:0] DEFAULT_MAX_Y = 12'hFFF;      // Default Y maximum

    // -------------------------------------------------------------------------
    // Internal declarations
    // -------------------------------------------------------------------------

    // PS/2 physical interface
    logic ps2_clk_in;       // Buffered PS/2 clock input (from tristate pin)
    logic ps2_data_in;      // Buffered PS/2 data input (from tristate pin)
    logic ps2_clk_h;        // PS/2 clock tristate control (1 = high-Z, 0 = drive low)
    logic ps2_data_h;       // PS/2 data tristate control (1 = high-Z, 0 = drive low)
    logic tx_bit;           // Current TX bit held stable across clock edges

    // PS/2 input synchronisers and debouncers
    logic [1:0] clk_sync;                  // Two-stage synchroniser for PS/2 clock
    logic [1:0] data_sync;                 // Two-stage synchroniser for PS/2 data
    logic [DEBOUNCE-1:0] clk_db_cnt;       // Debounce counter for PS/2 clock
    logic [DEBOUNCE-1:0] data_db_cnt;      // Debounce counter for PS/2 data
    logic ps2_clk_clean;                   // Debounced PS/2 clock
    logic ps2_data_clean;                  // Debounced PS/2 data
    logic ps2_clk_s;                       // Alias for cleaned PS/2 clock
    logic ps2_data_s;                      // Alias for cleaned PS/2 data
    logic ps2_clk_prev;                    // Previous-cycle PS/2 clock for edge detection

    // Bit-level delay timers
    logic [W100-1:0] cnt_100us;            // 100 us delay counter
    logic            done_100us;           // 100 us timer reached target
    logic            en_100us;             // Enable 100 us delay timer
    logic [W20-1:0]  cnt_20us;             // 20 us delay counter
    logic            done_20us;            // 20 us timer reached target
    logic            en_20us;              // Enable 20 us delay timer
    logic [W63-1:0]  cnt_63clk;            // 63-clock delay counter
    logic            done_63clk;           // 63-clock timer reached target
    logic            en_63clk;             // Enable 63-clock delay timer

    // PS/2 serial interface FSM
    typedef enum logic [4:0] {
        PS2_IDLE,
        PS2_RX_CLK_H,  PS2_RX_CLK_L,  PS2_RX_DOWN_EDGE,
        PS2_RX_ERR_PAR, PS2_RX_READY,
        PS2_TX_FORCE_CLK_L,  PS2_TX_BRING_DATA_DOWN, PS2_TX_RELEASE_CLK,
        PS2_TX_FIRST_WAIT_DOWN, PS2_TX_CLK_L,
        PS2_TX_WAIT_UP_EDGE, PS2_TX_CLK_H,
        PS2_TX_WAIT_UP_BEFORE_ACK, PS2_TX_WAIT_ACK,
        PS2_TX_RECV_ACK, PS2_TX_ERR_NO_ACK
    } ps2_state_t;

    ps2_state_t ps2_if_state;              // Current state of PS/2 bit-level FSM
    logic [10:0] frame;                    // 11-bit shift register for RX/TX frame
    logic [3:0]  bit_cnt;                  // Bit counter for RX/TX frame
    logic        reset_bit_cnt;            // Clear bit counter when returning to idle
    logic        shift_frame;              // Shift frame by one bit
    logic        load_tx_data;             // Load tx_byte into TX frame
    logic        load_rx_data;             // Capture RX byte from frame
    logic [7:0]  tx_byte;                  // Byte to transmit
    logic        tx_start;                 // Start transmission request
    logic [7:0]  rx_byte;                  // Byte received from mouse
    logic        rx_ready;                 // RX byte ready pulse
    logic        rx_err;                   // RX parity / TX no-ack error pulse
    logic        busy;                     // PS/2 interface busy flag

    // Mouse protocol FSM
    typedef enum logic [5:0] {
        M_RESET,
        M_RESET_WAIT_ACK,
        M_RESET_WAIT_BAT,
        M_RESET_WAIT_ID,
        M_SET_SR_200,  M_SET_SR_200_WAIT_ACK,  M_SEND_SR_200,  M_SEND_SR_200_WAIT_ACK,
        M_SET_SR_100,  M_SET_SR_100_WAIT_ACK,  M_SEND_SR_100,  M_SEND_SR_100_WAIT_ACK,
        M_SET_SR_80,   M_SET_SR_80_WAIT_ACK,   M_SEND_SR_80,   M_SEND_SR_80_WAIT_ACK,
        M_READ_ID,     M_READ_ID_WAIT_ACK,     M_READ_ID_WAIT_ID,
        M_SET_RES,     M_SET_RES_WAIT_ACK,     M_SEND_RES,     M_SEND_RES_WAIT_ACK,
        M_SET_SR_40,   M_SET_SR_40_WAIT_ACK,   M_SEND_SR_40,   M_SEND_SR_40_WAIT_ACK,
        M_ENABLE_REPORT, M_ENABLE_REPORT_WAIT_ACK,
        M_READ_BYTE_1, M_READ_BYTE_2, M_READ_BYTE_3, M_READ_BYTE_4,
        M_CHK_READ_ID, M_CHK_READ_ID_WAIT_ACK, M_CHK_READ_ID_WAIT_ID,
        M_MARK_NEW
    } mouse_state_t;

    mouse_state_t m_state;                 // Current state of mouse protocol FSM
    logic         m_tx_req;                // Request PS/2 interface transmission
    logic [7:0]   m_tx_data;               // Command/data byte to send to mouse
    logic         has_wheel;               // 1 if wheel mouse ID was detected
    logic         x_ovf;                   // X movement overflow flag from packet
    logic         y_ovf;                   // Y movement overflow flag from packet
    logic         x_sign;                  // X movement sign bit from packet
    logic         y_sign;                  // Y movement sign bit (inverted from packet)
    logic signed [8:0] x_delta;            // Signed 9-bit X displacement
    logic signed [8:0] y_delta;            // Signed 9-bit Y displacement
    logic              x_new;              // Update X accumulator this cycle
    logic              y_new;              // Update Y accumulator this cycle

    // Position limits and accumulators
    logic [11:0] x_pos;                    // Current X position output register
    logic [11:0] y_pos;                    // Current Y position output register
    logic [11:0] x_max;                    // Maximum allowed X position
    logic [11:0] y_max;                    // Maximum allowed Y position
    logic signed [13:0] tmp_x;             // Temporary signed X accumulator result
    logic signed [13:0] tmp_y;             // Temporary signed Y accumulator result

    // Watchdog and timeout
    logic [$clog2(CHECK_TICK)-1:0]  wd_cnt;  // Watchdog counter
    logic                           wd_tick; // Watchdog expired pulse
    logic [$clog2(TIMEOUT_TOP)-1:0] to_cnt;  // Timeout counter
    logic                           timeout; // Timeout expired flag
    logic                           en_wd;   // Enable watchdog counter
    logic                           en_to;   // Enable timeout counter
    logic                           rst_wd;  // Reset watchdog counter
    logic                           rst_to;  // Reset timeout counter

    // -------------------------------------------------------------------------
    // Helper functions
    // -------------------------------------------------------------------------

    function automatic logic odd_parity(input logic [7:0] d);
        odd_parity = ^d ^ 1'b1;
    endfunction

    // -------------------------------------------------------------------------
    // PS/2 line tristate drivers
    // -------------------------------------------------------------------------
    assign ps2_clk  = ps2_clk_h  ? 1'bz : 1'b0;
    assign ps2_data = ps2_data_h ? 1'bz : 1'b0;
    assign ps2_clk_in  = ps2_clk;
    assign ps2_data_in = ps2_data;

    // -------------------------------------------------------------------------
    // PS/2 input synchronisers
    // -------------------------------------------------------------------------
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            clk_sync  <= 2'b11;
            data_sync <= 2'b11;
        end else begin
            clk_sync  <= {clk_sync[0],  ps2_clk_in};
            data_sync <= {data_sync[0], ps2_data_in};
        end
    end

    // -------------------------------------------------------------------------
    // PS/2 input debouncers
    // -------------------------------------------------------------------------
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            clk_db_cnt     <= '0;
            ps2_clk_clean  <= 1'b1;
            data_db_cnt    <= '0;
            ps2_data_clean <= 1'b1;
        end else begin
            if (clk_sync[0] !== clk_sync[1]) begin
                clk_db_cnt <= '0;
            end else if (clk_db_cnt != {DEBOUNCE{1'b1}}) begin
                clk_db_cnt <= clk_db_cnt + 1'b1;
            end else begin
                ps2_clk_clean <= clk_sync[1];
            end

            if (data_sync[0] !== data_sync[1]) begin
                data_db_cnt <= '0;
            end else if (data_db_cnt != {DEBOUNCE{1'b1}}) begin
                data_db_cnt <= data_db_cnt + 1'b1;
            end else begin
                ps2_data_clean <= data_sync[1];
            end
        end
    end

    // -------------------------------------------------------------------------
    // Cleaned PS/2 line aliases and edge detector
    // -------------------------------------------------------------------------
    assign ps2_clk_s  = ps2_clk_clean;
    assign ps2_data_s = ps2_data_clean;

    always_ff @(posedge clk) begin
        ps2_clk_prev <= ps2_clk_s;
    end

    // -------------------------------------------------------------------------
    // 100 us delay timer
    // -------------------------------------------------------------------------
    always_ff @(posedge clk) begin
        if (!en_100us) begin
            cnt_100us  <= '0;
            done_100us <= 1'b0;
        end else if (done_100us) begin
        end else if (cnt_100us == DELAY_100US) begin
            done_100us <= 1'b1;
        end else begin
            cnt_100us <= cnt_100us + 1'b1;
        end
    end

    // -------------------------------------------------------------------------
    // 20 us delay timer
    // -------------------------------------------------------------------------
    always_ff @(posedge clk) begin
        if (!en_20us) begin
            cnt_20us  <= '0;
            done_20us <= 1'b0;
        end else if (done_20us) begin
        end else if (cnt_20us == DELAY_20US) begin
            done_20us <= 1'b1;
        end else begin
            cnt_20us <= cnt_20us + 1'b1;
        end
    end

    // -------------------------------------------------------------------------
    // 63-clock delay timer
    // -------------------------------------------------------------------------
    always_ff @(posedge clk) begin
        if (!en_63clk) begin
            cnt_63clk  <= '0;
            done_63clk <= 1'b0;
        end else if (done_63clk) begin
        end else if (cnt_63clk == 63) begin
            done_63clk <= 1'b1;
        end else begin
            cnt_63clk <= cnt_63clk + 1'b1;
        end
    end

    // -------------------------------------------------------------------------
    // Mouse FSM to PS/2 interface control assignments
    // -------------------------------------------------------------------------
    assign tx_start = m_tx_req;
    assign tx_byte  = m_tx_data;

    // -------------------------------------------------------------------------
    // PS/2 serial interface FSM
    // -------------------------------------------------------------------------
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ps2_if_state  <= PS2_IDLE;
            ps2_clk_h     <= 1'b1;
            ps2_data_h    <= 1'b1;
            tx_bit        <= 1'b1;
            load_tx_data  <= 1'b0;
            load_rx_data  <= 1'b0;
            rx_ready      <= 1'b0;
            rx_err        <= 1'b0;
            en_100us      <= 1'b0;
            en_20us       <= 1'b0;
            en_63clk      <= 1'b0;
        end else begin
            ps2_clk_h    <= 1'b1;
            ps2_data_h   <= 1'b1;
            load_tx_data <= 1'b0;
            load_rx_data <= 1'b0;
            rx_ready     <= 1'b0;
            rx_err       <= 1'b0;
            en_100us     <= 1'b0;
            en_20us      <= 1'b0;
            en_63clk     <= 1'b0;

            unique case (ps2_if_state)
                PS2_IDLE: begin
                    if (ps2_clk_s == 1'b0)
                        ps2_if_state <= PS2_RX_DOWN_EDGE;
                    else if (tx_start) begin
                        load_tx_data <= 1'b1;
                        en_100us     <= 1'b1;
                        ps2_if_state <= PS2_TX_FORCE_CLK_L;
                    end
                end

                PS2_RX_CLK_H: begin
                    if (bit_cnt == 4'd11) begin
                        if (frame[9] != odd_parity(frame[8:1])) begin
                            rx_err       <= 1'b1;
                            ps2_if_state <= PS2_RX_ERR_PAR;
                        end else begin
                            load_rx_data <= 1'b1;
                            ps2_if_state <= PS2_RX_READY;
                        end
                    end else if (ps2_clk_s == 1'b0)
                        ps2_if_state <= PS2_RX_DOWN_EDGE;
                end

                PS2_RX_CLK_L: begin
                    if (ps2_clk_s == 1'b1)
                        ps2_if_state <= PS2_RX_CLK_H;
                end

                PS2_RX_DOWN_EDGE: begin
                    ps2_if_state <= PS2_RX_CLK_L;
                end

                PS2_RX_ERR_PAR: begin
                    ps2_if_state <= PS2_IDLE;
                end

                PS2_RX_READY: begin
                    rx_ready     <= 1'b1;
                    ps2_if_state <= PS2_IDLE;
                end

                PS2_TX_FORCE_CLK_L: begin
                    ps2_clk_h <= 1'b0;
                    en_100us  <= 1'b1;
                    if (done_100us)
                        ps2_if_state <= PS2_TX_BRING_DATA_DOWN;
                end

                PS2_TX_BRING_DATA_DOWN: begin
                    ps2_clk_h  <= 1'b0;
                    ps2_data_h <= 1'b0;
                    en_20us    <= 1'b1;
                    if (done_20us)
                        ps2_if_state <= PS2_TX_RELEASE_CLK;
                end

                PS2_TX_RELEASE_CLK: begin
                    ps2_clk_h    <= 1'b1;
                    ps2_data_h   <= 1'b0;
                    en_63clk     <= 1'b1;
                    ps2_if_state <= PS2_TX_FIRST_WAIT_DOWN;
                end

                PS2_TX_FIRST_WAIT_DOWN: begin
                    ps2_data_h <= 1'b0;
                    en_63clk   <= 1'b1;
                    if (done_63clk && ps2_clk_s == 1'b0)
                        ps2_if_state <= PS2_TX_CLK_L;
                end

                PS2_TX_CLK_L: begin
                    tx_bit     <= frame[0];
                    ps2_data_h <= frame[0];
                    ps2_if_state <= PS2_TX_WAIT_UP_EDGE;
                end

                PS2_TX_WAIT_UP_EDGE: begin
                    ps2_data_h <= tx_bit;
                    if (bit_cnt == 4'd10) begin
                        ps2_data_h   <= 1'b1;
                        ps2_if_state <= PS2_TX_WAIT_UP_BEFORE_ACK;
                    end else if (ps2_clk_s == 1'b1)
                        ps2_if_state <= PS2_TX_CLK_H;
                end

                PS2_TX_CLK_H: begin
                    ps2_data_h <= tx_bit;
                    if (ps2_clk_s == 1'b0)
                        ps2_if_state <= PS2_TX_CLK_L;
                end

                PS2_TX_WAIT_UP_BEFORE_ACK: begin
                    ps2_data_h <= 1'b1;
                    if (ps2_clk_s == 1'b1)
                        ps2_if_state <= PS2_TX_WAIT_ACK;
                end

                PS2_TX_WAIT_ACK: begin
                    if (ps2_clk_s == 1'b0) begin
                        if (ps2_data_s == 1'b0)
                            ps2_if_state <= PS2_TX_RECV_ACK;
                        else
                            ps2_if_state <= PS2_TX_ERR_NO_ACK;
                    end
                end

                PS2_TX_RECV_ACK: begin
                    if (ps2_clk_s == 1'b1 && ps2_data_s == 1'b1)
                        ps2_if_state <= PS2_IDLE;
                end

                PS2_TX_ERR_NO_ACK: begin
                    if (ps2_clk_s == 1'b1 && ps2_data_s == 1'b1) begin
                        rx_err       <= 1'b1;
                        ps2_if_state <= PS2_IDLE;
                    end
                end

                default: ps2_if_state <= PS2_IDLE;
            endcase
        end
    end

    // -------------------------------------------------------------------------
    // PS/2 bit counter and frame shift control
    // -------------------------------------------------------------------------
    assign reset_bit_cnt = (ps2_if_state == PS2_IDLE);
    assign shift_frame   = (ps2_if_state == PS2_RX_DOWN_EDGE) ||
                           (ps2_if_state == PS2_TX_CLK_L);
    assign busy          = (ps2_if_state != PS2_IDLE);

    always_ff @(posedge clk) begin
        if (reset_bit_cnt)
            bit_cnt <= '0;
        else if (shift_frame)
            bit_cnt <= bit_cnt + 1'b1;
    end

    always_ff @(posedge clk) begin
        if (load_tx_data) begin
            frame[0]   <= tx_byte[0];
            frame[7:1] <= tx_byte[7:1];
            frame[8]   <= odd_parity(tx_byte);
            frame[9]   <= 1'b1;
            frame[10]  <= 1'b1;
        end else if (shift_frame) begin
            if (ps2_if_state == PS2_RX_DOWN_EDGE) begin
                frame <= {ps2_data_s, frame[10:1]};
            end else begin
                frame <= {1'b1, frame[10:1]};
            end
        end
    end

    always_ff @(posedge clk) begin
        if (load_rx_data)
            rx_byte <= frame[8:1];
    end

    // -------------------------------------------------------------------------
    // Packet watchdog timer
    // -------------------------------------------------------------------------
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wd_cnt  <= '0;
            wd_tick <= 1'b0;
        end else if (rst_wd) begin
            wd_cnt  <= '0;
            wd_tick <= 1'b0;
        end else if (en_wd) begin
            if (wd_cnt == CHECK_TICK - 1) begin
                wd_cnt  <= '0;
                wd_tick <= 1'b1;
            end else begin
                wd_cnt  <= wd_cnt + 1'b1;
                wd_tick <= 1'b0;
            end
        end else begin
            wd_tick <= 1'b0;
        end
    end

    // -------------------------------------------------------------------------
    // ID-check timeout timer
    // -------------------------------------------------------------------------
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            to_cnt  <= '0;
            timeout <= 1'b0;
        end else if (rst_to) begin
            to_cnt  <= '0;
            timeout <= 1'b0;
        end else if (en_to) begin
            if (to_cnt == TIMEOUT_TOP - 1) begin
                timeout <= 1'b1;
            end else begin
                to_cnt <= to_cnt + 1'b1;
            end
        end else begin
            timeout <= 1'b0;
        end
    end

    // -------------------------------------------------------------------------
    // Position limit registers
    // -------------------------------------------------------------------------
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            x_max <= DEFAULT_MAX_X;
            y_max <= DEFAULT_MAX_Y;
        end else begin
            if (setmax_x) x_max <= setmax_val;
            if (setmax_y) y_max <= setmax_val;
        end
    end

    // -------------------------------------------------------------------------
    // Position accumulators
    // X: x_delta is already properly signed -> just ADD
    // Y: y_delta is already properly signed (negated + sign-extended) -> ADD
    //    (matches VHDL: y_inter := y_pos + inc)
    // -------------------------------------------------------------------------
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            x_pos <= '0;
            y_pos <= '0;
        end else begin
            if (setx) begin
                x_pos <= setmax_val;
            end else if (x_new) begin
                tmp_x = $signed({2'b00, x_pos}) + $signed(x_delta);
                if (tmp_x < 0) x_pos <= 0;
                else if (tmp_x > $signed({2'b00, x_max})) x_pos <= x_max;
                else x_pos <= tmp_x[11:0];
            end

            if (sety) begin
                y_pos <= setmax_val;
            end else if (y_new) begin
                // FIXED: + instead of - (VHDL uses +)
                tmp_y = $signed({2'b00, y_pos}) + $signed(y_delta);
                if (tmp_y < 0) y_pos <= 0;
                else if (tmp_y > $signed({2'b00, y_max})) y_pos <= y_max;
                else y_pos <= tmp_y[11:0];
            end
        end
    end

    // -------------------------------------------------------------------------
    // Mouse protocol FSM
    // -------------------------------------------------------------------------
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            m_state    <= M_RESET;
            has_wheel  <= 1'b0;
            m_tx_req   <= 1'b0;
            m_tx_data  <= 8'd0;
            x_ovf      <= 1'b0;
            y_ovf      <= 1'b0;
            x_sign     <= 1'b0;
            y_sign     <= 1'b0;
            x_delta    <= 9'd0;
            y_delta    <= 9'd0;
            x_new      <= 1'b0;
            y_new      <= 1'b0;
            new_event  <= 1'b0;
            left_btn   <= 1'b0;
            right_btn  <= 1'b0;
            middle_btn <= 1'b0;
            en_wd      <= 1'b0;
            en_to      <= 1'b0;
            rst_wd     <= 1'b1;
            rst_to     <= 1'b1;
        end else begin
            m_tx_req  <= 1'b0;
            x_new     <= 1'b0;
            y_new     <= 1'b0;
            new_event <= 1'b0;
            en_wd     <= 1'b0;
            en_to     <= 1'b0;
            rst_wd    <= 1'b0;
            rst_to    <= 1'b0;

            unique case (m_state)

                // ----- Initialisation ----------------------------------------
                M_RESET: begin
                    has_wheel  <= 1'b0;
                    left_btn   <= 1'b0;
                    right_btn  <= 1'b0;
                    middle_btn <= 1'b0;
                    m_tx_req   <= 1'b1;
                    m_tx_data  <= CMD_RESET;
                    rst_wd     <= 1'b1;
                    rst_to     <= 1'b1;
                    m_state    <= M_RESET_WAIT_ACK;
                end

                M_RESET_WAIT_ACK: begin
                    if (rx_ready && rx_byte == ACK)
                        m_state <= M_RESET_WAIT_BAT;
                    else if (rx_err || (rx_ready && rx_byte != ACK))
                        m_state <= M_RESET;
                end

                M_RESET_WAIT_BAT: begin
                    if (rx_ready && rx_byte == BAT_OK)
                        m_state <= M_RESET_WAIT_ID;
                    else if (rx_err || (rx_ready && rx_byte != BAT_OK))
                        m_state <= M_RESET;
                end

                M_RESET_WAIT_ID: begin
                    if (rx_ready)
                        m_state <= M_SET_SR_200;
                    else if (rx_err)
                        m_state <= M_RESET;
                end

                M_SET_SR_200: begin
                    m_tx_req  <= 1'b1;
                    m_tx_data <= CMD_SET_SAMPLE_RATE;
                    m_state   <= M_SET_SR_200_WAIT_ACK;
                end
                M_SET_SR_200_WAIT_ACK: begin
                    if (rx_ready && rx_byte == ACK) m_state <= M_SEND_SR_200;
                    else if (rx_err) m_state <= M_RESET;
                end
                M_SEND_SR_200: begin
                    m_tx_req  <= 1'b1;
                    m_tx_data <= SAMPLE_200;
                    m_state   <= M_SEND_SR_200_WAIT_ACK;
                end
                M_SEND_SR_200_WAIT_ACK: begin
                    if (rx_ready && rx_byte == ACK) m_state <= M_SET_SR_100;
                    else if (rx_err) m_state <= M_RESET;
                end

                M_SET_SR_100: begin
                    m_tx_req  <= 1'b1;
                    m_tx_data <= CMD_SET_SAMPLE_RATE;
                    m_state   <= M_SET_SR_100_WAIT_ACK;
                end
                M_SET_SR_100_WAIT_ACK: begin
                    if (rx_ready && rx_byte == ACK) m_state <= M_SEND_SR_100;
                    else if (rx_err) m_state <= M_RESET;
                end
                M_SEND_SR_100: begin
                    m_tx_req  <= 1'b1;
                    m_tx_data <= SAMPLE_100;
                    m_state   <= M_SEND_SR_100_WAIT_ACK;
                end
                M_SEND_SR_100_WAIT_ACK: begin
                    if (rx_ready && rx_byte == ACK) m_state <= M_SET_SR_80;
                    else if (rx_err) m_state <= M_RESET;
                end

                M_SET_SR_80: begin
                    m_tx_req  <= 1'b1;
                    m_tx_data <= CMD_SET_SAMPLE_RATE;
                    m_state   <= M_SET_SR_80_WAIT_ACK;
                end
                M_SET_SR_80_WAIT_ACK: begin
                    if (rx_ready && rx_byte == ACK) m_state <= M_SEND_SR_80;
                    else if (rx_err) m_state <= M_RESET;
                end
                M_SEND_SR_80: begin
                    m_tx_req  <= 1'b1;
                    m_tx_data <= SAMPLE_80;
                    m_state   <= M_SEND_SR_80_WAIT_ACK;
                end
                M_SEND_SR_80_WAIT_ACK: begin
                    if (rx_ready && rx_byte == ACK) m_state <= M_READ_ID;
                    else if (rx_err) m_state <= M_RESET;
                end

                M_READ_ID: begin
                    m_tx_req  <= 1'b1;
                    m_tx_data <= CMD_READ_ID;
                    m_state   <= M_READ_ID_WAIT_ACK;
                end
                M_READ_ID_WAIT_ACK: begin
                    if (rx_ready && rx_byte == ACK) m_state <= M_READ_ID_WAIT_ID;
                    else if (rx_err) m_state <= M_RESET;
                end
                M_READ_ID_WAIT_ID: begin
                    if (rx_ready) begin
                        has_wheel <= (rx_byte == MOUSE_ID_WHEEL);
                        m_state   <= M_SET_RES;
                    end else if (rx_err) m_state <= M_RESET;
                end

                M_SET_RES: begin
                    m_tx_req  <= 1'b1;
                    m_tx_data <= CMD_SET_RESOLUTION;
                    m_state   <= M_SET_RES_WAIT_ACK;
                end
                M_SET_RES_WAIT_ACK: begin
                    if (rx_ready && rx_byte == ACK) m_state <= M_SEND_RES;
                    else if (rx_err) m_state <= M_RESET;
                end
                M_SEND_RES: begin
                    m_tx_req  <= 1'b1;
                    m_tx_data <= RESOLUTION;
                    m_state   <= M_SEND_RES_WAIT_ACK;
                end
                M_SEND_RES_WAIT_ACK: begin
                    if (rx_ready && rx_byte == ACK) m_state <= M_SET_SR_40;
                    else if (rx_err) m_state <= M_RESET;
                end

                M_SET_SR_40: begin
                    m_tx_req  <= 1'b1;
                    m_tx_data <= CMD_SET_SAMPLE_RATE;
                    m_state   <= M_SET_SR_40_WAIT_ACK;
                end
                M_SET_SR_40_WAIT_ACK: begin
                    if (rx_ready && rx_byte == ACK) m_state <= M_SEND_SR_40;
                    else if (rx_err) m_state <= M_RESET;
                end
                M_SEND_SR_40: begin
                    m_tx_req  <= 1'b1;
                    m_tx_data <= SAMPLE_40;
                    m_state   <= M_SEND_SR_40_WAIT_ACK;
                end
                M_SEND_SR_40_WAIT_ACK: begin
                    if (rx_ready && rx_byte == ACK) m_state <= M_ENABLE_REPORT;
                    else if (rx_err) m_state <= M_RESET;
                end

                M_ENABLE_REPORT: begin
                    m_tx_req  <= 1'b1;
                    m_tx_data <= CMD_ENABLE_REPORT;
                    m_state   <= M_ENABLE_REPORT_WAIT_ACK;
                end
                M_ENABLE_REPORT_WAIT_ACK: begin
                    if (rx_ready && rx_byte == ACK) m_state <= M_READ_BYTE_1;
                    else if (rx_err) m_state <= M_RESET;
                end

                // ----- Data reception (fixed sign-extension + watchdog) ------
                M_READ_BYTE_1: begin
                    en_wd     <= 1'b1;
                    new_event <= 1'b0;
                    if (rx_ready) begin
                        if (rx_byte[3]) begin
                            left_btn   <= rx_byte[0];
                            right_btn  <= rx_byte[1];
                            middle_btn <= rx_byte[2];
                            x_sign     <= rx_byte[4];
                            y_sign     <= ~rx_byte[5];   // invert (VHDL does this)
                            x_ovf      <= rx_byte[6];
                            y_ovf      <= rx_byte[7];
                            m_state    <= M_READ_BYTE_2;
                        end
                    end else if (wd_tick) begin
                        m_state <= M_CHK_READ_ID;
                    end else if (rx_err) begin
                        m_state <= M_READ_BYTE_1;
                    end
                end

                M_READ_BYTE_2: begin
                    if (rx_ready) begin
                        // FIXED sign-extension: {x_sign, rx_byte} preserves
                        // the 2's-complement sign.
                        if (x_ovf)
                            x_delta <= x_sign ? $signed(9'h100) : $signed(9'h0FF);
                        else
                            x_delta <= $signed({x_sign, rx_byte});
                        x_new   <= 1'b1;
                        m_state <= M_READ_BYTE_3;
                    end else if (wd_tick) begin          // watchdog
                        m_state <= M_CHK_READ_ID;
                    end else if (rx_err) begin
                        m_state <= M_READ_BYTE_1;
                    end
                end

                M_READ_BYTE_3: begin
                    if (rx_ready) begin
                        if (rx_byte != 8'd0) begin
                            if (y_ovf) begin
                                // FIXED: +/-256 (VHDL uses +/-256, not +/-255)
                                y_delta <= y_sign ? $signed(9'h100) : $signed(9'h0FF);
                            end else begin
                                // FIXED: match VHDL exactly -
                                //   1) negate rx_byte (2's complement)
                                //   2) sign-extend with y_sign (not rx_byte[7]!)
                                y_delta <= $signed({y_sign, (~rx_byte + 1'b1)});
                            end
                            y_new <= 1'b1;
                        end
                        m_state <= has_wheel ? M_READ_BYTE_4 : M_MARK_NEW;
                    end else if (wd_tick) begin          // watchdog
                        m_state <= M_CHK_READ_ID;
                    end else if (rx_err) begin
                        m_state <= M_READ_BYTE_1;
                    end
                end

                M_READ_BYTE_4: begin
                    if (rx_ready)
                        m_state <= M_MARK_NEW;
                    else if (wd_tick) begin              // watchdog
                        m_state <= M_CHK_READ_ID;
                    end else if (rx_err) begin
                        m_state <= M_READ_BYTE_1;
                    end
                end

                M_CHK_READ_ID: begin
                    en_to     <= 1'b1;
                    m_tx_req  <= 1'b1;
                    m_tx_data <= CMD_READ_ID;
                    m_state   <= M_CHK_READ_ID_WAIT_ACK;
                end
                M_CHK_READ_ID_WAIT_ACK: begin
                    en_to <= 1'b1;
                    if (rx_ready && rx_byte == ACK) m_state <= M_CHK_READ_ID_WAIT_ID;
                    else if (rx_err || timeout) m_state <= M_RESET;
                end
                M_CHK_READ_ID_WAIT_ID: begin
                    if (rx_ready) begin
                        rst_to  <= 1'b1;
                        m_state <= M_READ_BYTE_1;
                    end else if (rx_err || timeout) begin
                        m_state <= M_RESET;
                    end
                end

                M_MARK_NEW: begin
                    new_event <= 1'b1;
                    m_state   <= M_READ_BYTE_1;
                end

                default: m_state <= M_RESET;
            endcase
        end
    end

    // -------------------------------------------------------------------------
    // Output assignments
    // -------------------------------------------------------------------------
    assign xpos = x_pos;
    assign ypos = y_pos;

endmodule