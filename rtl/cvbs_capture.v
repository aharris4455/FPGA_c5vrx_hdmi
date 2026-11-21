// CVBS capture from the C5VRX six-bit digital video tap.
//
// C5VRX-5 "EXPERIMENTAL > Clock Pin D10" exports the PARLIO TX clock on
// D10/GPIO10 and moves DAC bit 2 from D6/GPIO11 to D3/GPIO7.  The tap must be
// taken before the resistor DAC.  Bus bit order, low to high:
//
//   bit0 = D4 (GPIO23)   bit1 = D5 (GPIO24)   bit2 = D3 (GPIO7)
//   bit3 = D7 (GPIO12)   bit4 = D8 (GPIO8)    bit5 = D9 (GPIO9)
//
// Timing measured by LAP87 on issue #256: 40.0 MHz clock, data changes on the
// falling edge, every 20 MS/s code appears as two identical samples.  This
// block samples on the rising edge and decimates by two.
//
// Levels move with the receiver's AFC: observed sync tip 13..24, blanking
// 24..32, white 48..62 (six-bit codes).  The slicer therefore tracks the sync
// tip instead of using a fixed threshold.
//
// The module also recovers sync, clamps black to the back porch, low-passes
// the composite to remove the colour subcarrier for a luma-only picture, and
// writes 1024 active samples per line into a ping-pong line buffer.

module cvbs_capture (
    input  wire       clk,        // 40 MHz sample clock from C5VRX D10
    input  wire       resetn,     // asynchronous, active low
    input  wire [5:0] cvbs,       // six composite bits, see header

    output wire       we,         // line buffer write enable
    output wire [9:0] waddr,      // 0..1023, sample within the active window
    output wire [7:0] wdata,      // luma
    output reg        wbank,      // bank currently being written
    output reg        last_bank,  // bank completed at the last line end
    output reg        line_toggle,// toggles once per captured line
    output reg        vsync_toggle,// toggles once per detected vertical sync
    output reg        locked,     // 32 good lines seen
    output reg        std_pal,    // 0 = NTSC, 1 = PAL
    output wire [5:0] dbg_min,    // tracked sync tip (debug)
    output wire       dbg_clk     // 40 MHz clock heartbeat (debug LED)
);

    // ------------------------------------------------------------------
    // Reset synchroniser for the 40 MHz domain
    // ------------------------------------------------------------------
    reg [3:0] rst_cnt;
    always @(posedge clk or negedge resetn) begin
        if (!resetn) rst_cnt <= 4'd0;
        else if (rst_cnt != 4'hF) rst_cnt <= rst_cnt + 4'd1;
    end
    wire rstn = (rst_cnt == 4'hF);

    // ------------------------------------------------------------------
    // Input register and 2:1 decimation
    //
    // ce is high every second 40 MHz cycle.  The source holds each 20 MS/s
    // code for two cycles, so this yields exactly one sample per code.
    // ------------------------------------------------------------------
    reg       phase;
    reg [5:0] sample_r;

    always @(posedge clk or negedge resetn) begin
        if (!resetn) phase <= 1'b0;
        else if (rstn) phase <= ~phase;
    end

    always @(posedge clk) sample_r <= cvbs;

    wire       ce     = phase;
    wire [5:0] sample = sample_r;

    // ------------------------------------------------------------------
    // Adaptive sync slicer
    //
    // sync_min attacks to the lowest code seen (the sync tip) and decays
    // upward by one code about every 51 us.  A small hysteresis band keeps
    // the slicer from chattering on the sloping sync edges.
    // ------------------------------------------------------------------
    reg [5:0]  sync_min;
    reg [9:0]  min_decay;
    reg        sync_lo;

    wire [6:0] enter_thr = {1'b0, sync_min} + 7'd3;
    wire [6:0] exit_thr  = {1'b0, sync_min} + 7'd6;
    wire       have_signal = (sync_min < 6'd48);

    always @(posedge clk) begin
        if (!rstn) begin
            sync_min  <= 6'd63;
            min_decay <= 10'd0;
            sync_lo   <= 1'b0;
        end else if (ce) begin
            if (sample < sync_min)
                sync_min <= sample;
            else if (min_decay == 10'd0) begin
                if (sync_min != 6'd63) sync_min <= sync_min + 6'd1;
                min_decay <= 10'd1023;
            end else
                min_decay <= min_decay - 10'd1;

            if (!have_signal)
                sync_lo <= 1'b0;
            else if ({1'b0, sample} < enter_thr)
                sync_lo <= 1'b1;
            else if ({1'b0, sample} >= exit_thr)
                sync_lo <= 1'b0;
        end
    end

    assign dbg_min = sync_min;

    // Free-running divider on the incoming 40 MHz clock.  It only toggles if
    // the C5VRX clock is actually present at pin 35.
    reg [21:0] dbg_div;
    always @(posedge clk or negedge resetn) begin
        if (!resetn) dbg_div <= 22'd0;
        else         dbg_div <= dbg_div + 22'd1;
    end
    assign dbg_clk = dbg_div[21];



    // ------------------------------------------------------------------
    // Sync pulse measurement
    //
    // Normal horizontal sync is about 4.7 us (94 samples).  Vertical
    // equalising pulses are about 2.3 us and the broad vertical sync pulses
    // about 27 us.  A broad pulse is recognised 12.5 us into the low period,
    // so one vertical event is produced per field.
    // ------------------------------------------------------------------
    reg        sync_lo_d;
    reg [11:0] low_cnt;
    reg [10:0] line_pos;
    reg        hsync_pulse;
    reg        vsync_pulse;
    reg        vsync_shot;
    reg [19:0] vsync_holdoff;

    always @(posedge clk) begin
        if (!rstn) begin
            sync_lo_d     <= 1'b0;
            low_cnt       <= 12'd0;
            line_pos      <= 11'd0;
            hsync_pulse   <= 1'b0;
            vsync_pulse   <= 1'b0;
            vsync_shot    <= 1'b0;
            vsync_holdoff <= 20'd0;
        end else if (ce) begin
            sync_lo_d   <= sync_lo;
            hsync_pulse <= 1'b0;
            vsync_pulse <= 1'b0;

            if (vsync_holdoff != 20'd0) vsync_holdoff <= vsync_holdoff - 20'd1;

            if (sync_lo) begin
                if (low_cnt != 12'hFFF) low_cnt <= low_cnt + 12'd1;
            end else begin
                low_cnt    <= 12'd0;
                vsync_shot <= 1'b0;
            end

            // line_pos is relative to the start of the sync pulse.  It is
            // reset by every pulse, including equalising pulses, and the
            // capture window below never overlaps those.
            if (!sync_lo_d && sync_lo) begin
                line_pos <= 11'd0;
                low_cnt  <= 12'd1;
            end else if (line_pos != 11'h7FF) begin
                line_pos <= line_pos + 11'd1;
            end

            // Broad pulse -> vertical sync, once per pulse.  NTSC and PAL
            // send several broad pulses in a row; the 5 ms hold-off keeps
            // one vertical event per field.
            if (sync_lo && (low_cnt == 12'd250) && !vsync_shot &&
                (vsync_holdoff == 20'd0)) begin
                vsync_pulse   <= 1'b1;
                vsync_shot    <= 1'b1;
                vsync_holdoff <= 20'd100000; // 5 ms at 20 MS/s
            end

            // falling edge of a normal horizontal sync pulse
            if (sync_lo_d && !sync_lo) begin
                if ((low_cnt >= 12'd70) && (low_cnt <= 12'd140))
                    hsync_pulse <= 1'b1;
            end
        end
    end

    // ------------------------------------------------------------------
    // Line lock, vertical-sync counter and NTSC/PAL detection
    // ------------------------------------------------------------------
    reg [7:0]  hsync_good;
    reg [14:0] hsync_gap;
    reg [19:0] field_cnt;
    reg [1:0]  pal_score;

    localparam [14:0] HSYNC_TIMEOUT = 15'd20000; // 1 ms at 20 MS/s
    localparam [19:0] PAL_FIELD_MIN = 20'd366000; // 18.3 ms at 20 MS/s

    always @(posedge clk) begin
        if (!rstn) begin
            hsync_good <= 8'd0;
            hsync_gap  <= 15'd0;
            field_cnt  <= 20'd0;
            pal_score  <= 2'd0;
            std_pal    <= 1'b0;
            locked     <= 1'b0;
        end else if (ce) begin
            if (hsync_gap != 15'h7FFF) hsync_gap <= hsync_gap + 15'd1;
            if (hsync_pulse) begin
                hsync_gap <= 15'd0;
                if (hsync_good != 8'hFF) hsync_good <= hsync_good + 8'd1;
            end
            if (hsync_gap > HSYNC_TIMEOUT) hsync_good <= 8'd0;

            if (vsync_pulse) begin
                field_cnt <= 20'd0;

                // A field that takes longer than 18.3 ms is PAL.
                if ((field_cnt > PAL_FIELD_MIN) != std_pal) begin
                    if (pal_score == 2'd3) begin
                        std_pal   <= ~std_pal;
                        pal_score <= 2'd0;
                    end else begin
                        pal_score <= pal_score + 2'd1;
                    end
                end else begin
                    pal_score <= 2'd0;
                end
            end else if (field_cnt != 20'hFFFFF) begin
                field_cnt <= field_cnt + 20'd1;
            end

            locked <= (hsync_good >= 8'd32) && (hsync_gap < HSYNC_TIMEOUT);
        end
    end

    // ------------------------------------------------------------------
    // Back-porch clamp and luma low-pass
    //
    // The 7-tap binomial filter (1 6 15 20 15 6 1)/64 suppresses the colour
    // subcarrier for the luma-only output.  It is cheap in LUTs and runs in
    // the 20 MS/s enable domain.
    // ------------------------------------------------------------------
    reg [5:0] blank_level;
    reg [5:0] f1, f2, f3, f4, f5, f6;

    always @(posedge clk) begin
        if (!rstn) begin
            blank_level <= 6'd30;
            f1 <= 6'd0; f2 <= 6'd0; f3 <= 6'd0;
            f4 <= 6'd0; f5 <= 6'd0; f6 <= 6'd0;
        end else if (ce) begin
            // 8.2 us after the start of horizontal sync: after the colour
            // burst, before active video, for both NTSC and PAL.
            if (line_pos == 11'd164) blank_level <= sample;

            f1 <= sample;
            f2 <= f1;
            f3 <= f2;
            f4 <= f3;
            f5 <= f4;
            f6 <= f5;
        end
    end

    wire [6:0] p0 = {1'b0, sample} + {1'b0, f6};
    wire [6:0] p1 = {1'b0, f1}     + {1'b0, f5};
    wire [6:0] p2 = {1'b0, f2}     + {1'b0, f4};

    wire [11:0] acc = {5'b0, p0}
                    + {3'b0, p1, 2'b0} + {4'b0, p1, 1'b0}   //  6*p1
                    + {1'b0, p2, 4'b0} - {5'b0, p2}         // 15*p2
                    + {2'b0, f3, 4'b0} + {4'b0, f3, 2'b0};  // 20*f3

    wire [5:0] filt = acc[11:6];

    wire signed [7:0] code = $signed({2'b0, filt}) - $signed({2'b0, blank_level});
    wire [7:0] luma = code[7]      ? 8'd0   :
                      (code[5:0] > 6'd31) ? 8'd255 :
                      {code[4:0], 3'b000};

    // ------------------------------------------------------------------
    // Active window and line-buffer write
    //
    // NTSC: active starts 9.4 us after sync (188 samples).  Capture from
    // 198 for 1024 samples, i.e. a 1024-sample crop of the 1052-sample
    // active line.  PAL: active starts 10.4 us (208 samples); capture from
    // 214 for 1024 of 1040 samples.  The 720-pixel output is resampled from
    // these 1024 samples (step 364/256 in video_out).
    // ------------------------------------------------------------------
    wire [10:0] cap_start = std_pal ? 11'd214 : 11'd198;
    wire [10:0] cap_end   = cap_start + 11'd1024;
    wire        in_window = (line_pos >= cap_start) && (line_pos < cap_end);
    wire [10:0] cap_addr  = line_pos - cap_start;

    wire line_window_end = in_window && (line_pos == (cap_end - 11'd1));

    assign we    = ce && in_window;
    assign waddr = cap_addr[9:0];
    assign wdata = luma;

    always @(posedge clk) begin
        if (!rstn) begin
            wbank       <= 1'b0;
            last_bank   <= 1'b0;
            line_toggle <= 1'b0;
        end else if (ce) begin
            if (line_window_end) begin
                last_bank   <= wbank;
                wbank       <= ~wbank;
                line_toggle <= ~line_toggle;
            end
        end
    end

    always @(posedge clk) begin
        if (!rstn) vsync_toggle <= 1'b0;
        else if (ce && vsync_pulse) vsync_toggle <= ~vsync_toggle;
    end

endmodule
