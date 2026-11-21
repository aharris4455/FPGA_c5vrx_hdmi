// 27 MHz HDMI output timing, line-buffer readback and luma/test-pattern mux.
//
// The output is a standard CEA-861 720x480p60 or 720x576p50 frame at exactly
// 27.000 MHz.  Each captured CVBS line is displayed twice (line doubling), so
// the 15.734/15.625 kHz input line rate maps to the 31.47/31.25 kHz output
// line rate.
//
// The frame is genlocked to the receiver's vertical sync.  On each input
// vertical sync the vertical counter is reloaded so that the output active
// region starts 44 (NTSC) or 48 (PAL) output lines later.  Horizontal timing
// is free-running and standard; the line buffer supplies one complete line per
// output line pair and is re-read for the second line of the pair.
//
// If the receiver is absent or unlocked the block shows 75% colour bars, so
// the HDMI path can be tested without a C5VRX connected.

module video_out (
    input  wire        clk,          // 27 MHz pixel clock
    input  wire        resetn,       // synchronous-domain reset, active low

    input  wire [7:0]  pix,          // line buffer read data
    output wire [10:0] raddr,        // {bank, offset}

    input  wire        line_toggle,  // from capture domain
    input  wire        last_bank,    // bank of the line just completed
    input  wire        vsync_toggle, // from capture domain
    input  wire        std_pal,      // 0 = NTSC, 1 = PAL
    input  wire        locked,       // receiver locked

    output reg         de,
    output reg         hsync,
    output reg         vsync,
    output reg  [7:0]  r,
    output reg  [7:0]  g,
    output reg  [7:0]  b
);

    // ------------------------------------------------------------------
    // CEA-861 timing
    //
    // x counts from the start of horizontal sync:
    //   NTSC 480p60: 62 sync + 60 back porch + 720 active + 16 front = 858
    //   PAL  576p50: 63 sync + 69 back porch + 720 active + 12 front = 864
    // y counts from the start of vertical sync:
    //   NTSC: 6 sync + 30 back porch + 480 active + 9 front = 525
    //   PAL : 5 sync + 39 back porch + 576 active + 5 front = 625
    // ------------------------------------------------------------------
    localparam [10:0] H_TOTAL_N   = 11'd858;
    localparam [10:0] H_TOTAL_P   = 11'd864;
    localparam [9:0]  V_TOTAL_N   = 10'd525;
    localparam [9:0]  V_TOTAL_P   = 10'd625;
    localparam [10:0] H_ACT_N     = 11'd122;
    localparam [10:0] H_ACT_P     = 11'd132;
    localparam [9:0]  V_ACT_N     = 10'd36;
    localparam [9:0]  V_ACT_P     = 10'd44;
    localparam [9:0]  V_END_N     = 10'd516;  // 36 + 480
    localparam [9:0]  V_END_P     = 10'd620;  // 44 + 576
    localparam [9:0]  RESET_Y_N   = 10'd523;  // active starts 38 lines after vsync
    localparam [9:0]  RESET_Y_P   = 10'd624;  // active starts 45 lines after vsync

    // ------------------------------------------------------------------
    // Capture-domain synchronisers (levels and one-bit toggles)
    // ------------------------------------------------------------------
    reg [2:0] line_s, bank_s, vs_s, pal_s, lock_s;

    always @(posedge clk or negedge resetn) begin
        if (!resetn) begin
            line_s <= 3'd0;
            bank_s <= 3'd0;
            vs_s   <= 3'd0;
            pal_s  <= 3'd0;
            lock_s <= 3'd0;
        end else begin
            line_s <= {line_s[1:0], line_toggle};
            bank_s <= {bank_s[1:0], last_bank};
            vs_s   <= {vs_s[1:0],   vsync_toggle};
            pal_s  <= {pal_s[1:0],  std_pal};
            lock_s <= {lock_s[1:0], locked};
        end
    end

    // ------------------------------------------------------------------
    // Output timing counters and frame genlock
    // ------------------------------------------------------------------
    reg [10:0] x;
    reg [9:0]  y;
    reg        pal_q;
    reg        pal_next;
    reg        align_pending;
    reg        vsync_seen;

    wire vsync_edge = (vs_s[2] != vsync_seen);

    wire [10:0] h_total      = pal_q ? H_TOTAL_P : H_TOTAL_N;
    wire [9:0]  v_total      = pal_q ? V_TOTAL_P : V_TOTAL_N;
    wire [10:0] h_act_start  = pal_q ? H_ACT_P   : H_ACT_N;
    wire [9:0]  v_act_start  = pal_q ? V_ACT_P   : V_ACT_N;
    wire [9:0]  v_act_end    = pal_q ? V_END_P   : V_END_N;
    wire [9:0]  reset_y_next = pal_next ? RESET_Y_P : RESET_Y_N;
    wire [10:0] h_act_end    = h_act_start + 11'd720;

    always @(posedge clk or negedge resetn) begin
        if (!resetn) begin
            x             <= 11'd0;
            y             <= 10'd0;
            pal_q         <= 1'b0;
            pal_next      <= 1'b0;
            align_pending <= 1'b0;
            vsync_seen    <= 1'b0;
        end else begin
            if (vsync_edge) begin
                pal_next      <= pal_s[2];
                align_pending <= 1'b1;
                vsync_seen    <= vs_s[2];
            end

            if (x >= (h_total - 11'd1)) begin
                x <= 11'd0;
                if (align_pending) begin
                    y             <= reset_y_next;
                    pal_q         <= pal_next;
                    align_pending <= 1'b0;
                end else begin
                    if (y >= (v_total - 10'd1)) y <= 10'd0;
                    else                        y <= y + 10'd1;
                end
            end else begin
                x <= x + 11'd1;
            end
        end
    end

    // ------------------------------------------------------------------
    // Line-buffer consume: one completed line per output line pair
    // ------------------------------------------------------------------
    reg       seen_line;
    reg       rd_bank;
    reg       line_valid;

    wire y_pair_even = (y[0] == v_act_start[0]);
    wire line_avail = (line_s[2] != seen_line);
    wire pair_start = (x == 11'd0) &&
                      (y >= v_act_start) && (y < v_act_end) &&
                      y_pair_even;

    always @(posedge clk or negedge resetn) begin
        if (!resetn) begin
            seen_line  <= 1'b0;
            rd_bank    <= 1'b0;
            line_valid <= 1'b0;
        end else begin
            if (vsync_edge) begin
                // Drop anything left from the previous field.  The first
                // active line of the new field arrives after this point.
                seen_line  <= line_s[2];
                line_valid <= 1'b0;
            end else if (!lock_s[2]) begin
                // Do not advance the line sequence while the receiver is
                // unlocked; the output is showing the test pattern.
                line_valid <= 1'b0;
            end else if (pair_start && line_avail) begin
                seen_line  <= line_s[2];
                rd_bank    <= bank_s[2];
                line_valid <= 1'b1;
            end
        end
    end

    // ------------------------------------------------------------------
    // Horizontal resampling: 1024 captured samples -> 720 pixels
    //
    // acc advances by 364/256 = 1.4219 per output pixel, so address 1022 is
    // reached at the last pixel.  The read data is aligned with x_d1/y_d1,
    // one pixel behind the counters.
    // ------------------------------------------------------------------
    reg [17:0] acc;
    wire [9:0] pix_addr = acc[17:8];

    assign raddr = {rd_bank, pix_addr};

    wire in_active_now = (y >= v_act_start) && (y < v_act_end) &&
                         (x >= h_act_start)  && (x < h_act_end);

    always @(posedge clk or negedge resetn) begin
        if (!resetn) acc <= 18'd0;
        else if (x == (h_act_start - 11'd1)) acc <= 18'd0;
        else if (in_active_now) acc <= acc + 18'd364;
    end

    reg [10:0] x_d1;
    reg [9:0]  y_d1;

    always @(posedge clk) begin
        x_d1 <= x;
        y_d1 <= y;
    end

    // ------------------------------------------------------------------
    // Encoder-facing timing and pixel mux
    // ------------------------------------------------------------------
    wire de_enc = (x_d1 >= h_act_start) && (x_d1 < h_act_end) &&
                  (y_d1 >= v_act_start) && (y_d1 < v_act_end);
    wire hs_enc = ~(x_d1 < (pal_q ? 11'd63 : 11'd62)); // active low
    wire vs_enc = ~(y_d1 < (pal_q ? 10'd5  : 10'd6));  // active low

    // 75% colour bars for bring-up / no-signal
    wire [2:0] bar = x_d1[8:6];
    reg [7:0] tp_r, tp_g, tp_b;

    always @* begin
        if ((x_d1 < (h_act_start + 11'd2)) || (x_d1 >= (h_act_end - 11'd2)) ||
            (y_d1 < (v_act_start + 10'd2)) || (y_d1 >= (v_act_end - 10'd2))) begin
            tp_r = 8'hFF; tp_g = 8'hFF; tp_b = 8'hFF;
        end else begin
            case (bar)
                3'd0: begin tp_r = 8'hC0; tp_g = 8'hC0; tp_b = 8'hC0; end // white
                3'd1: begin tp_r = 8'hC0; tp_g = 8'hC0; tp_b = 8'h00; end // yellow
                3'd2: begin tp_r = 8'h00; tp_g = 8'hC0; tp_b = 8'hC0; end // cyan
                3'd3: begin tp_r = 8'h00; tp_g = 8'hC0; tp_b = 8'h00; end // green
                3'd4: begin tp_r = 8'hC0; tp_g = 8'h00; tp_b = 8'hC0; end // magenta
                3'd5: begin tp_r = 8'hC0; tp_g = 8'h00; tp_b = 8'h00; end // red
                3'd6: begin tp_r = 8'h00; tp_g = 8'h00; tp_b = 8'hC0; end // blue
                default: begin tp_r = 8'h00; tp_g = 8'h00; tp_b = 8'h00; end // black
            endcase
        end
    end

    always @(posedge clk or negedge resetn) begin
        if (!resetn) begin
            de    <= 1'b0;
            hsync <= 1'b0;
            vsync <= 1'b0;
            r     <= 8'd0;
            g     <= 8'd0;
            b     <= 8'd0;
        end else begin
            de    <= de_enc;
            hsync <= hs_enc;
            vsync <= vs_enc;

            if (!de_enc) begin
                r <= 8'd0;
                g <= 8'd0;
                b <= 8'd0;
            end else if (!lock_s[2]) begin
                r <= tp_r;
                g <= tp_g;
                b <= tp_b;
            end else if (!line_valid) begin
                r <= 8'd0;
                g <= 8'd0;
                b <= 8'd0;
            end else begin
                r <= pix;
                g <= pix;
                b <= pix;
            end
        end
    end

endmodule
