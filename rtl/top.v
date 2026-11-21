// HDMI analog FPV VRX - Tang Nano 9K side.
//
// Receives the C5VRX-5 six-bit digital video tap (D10 sample clock mode),
// recovers sync, converts composite luma to 720x480p60 / 720x576p50, and
// drives the board's HDMI connector.
//
// Wiring (see docs/PINMAP.md):
//   C5VRX D4  -> cvbs[0]  Tang Nano pin 25
//   C5VRX D5  -> cvbs[1]  pin 26
//   C5VRX D3  -> cvbs[2]  pin 27
//   C5VRX D7  -> cvbs[3]  pin 28
//   C5VRX D8  -> cvbs[4]  pin 29
//   C5VRX D9  -> cvbs[5]  pin 30
//   C5VRX D10 -> cvbs_clk pin 35
//   GND       -> GND
//
// Tap the ESP32 pins before the resistor DAC.  All signals are 3.3 V.

module top (
    input  wire       clk,        // 27 MHz board oscillator (pin 52)
    input  wire       resetn,     // S1 button, active low (pin 4)

    input  wire [5:0] cvbs,       // C5VRX composite bits (pins 25..30)
    input  wire       cvbs_clk,   // C5VRX 40 MHz sample clock (pin 35)

    output wire [5:0] led,        // LED1 lock, LED2 PAL, LED3 clock, LED4 lines

    output wire       tmds_clk_n,
    output wire       tmds_clk_p,
    output wire [2:0] tmds_d_n,
    output wire [2:0] tmds_d_p
);

    // ------------------------------------------------------------------
    // 27 MHz pixel clock and 135 MHz TMDS serial clock
    // (same Gowin rPLL configuration as the proven hdmi_block design)
    // ------------------------------------------------------------------
    wire clk_5x;
    wire pll_lock;

    Gowin_rPLL u_pll (
        .clkin (clk),
        .clkout(clk_5x),
        .lock  (pll_lock)
    );

    wire sys_resetn;

    Reset_Sync u_reset (
        .clk      (clk),
        .ext_reset(resetn & pll_lock),
        .resetn   (sys_resetn)
    );

    // ------------------------------------------------------------------
    // Receiver capture (40 MHz domain)
    // ------------------------------------------------------------------
    // Pin 35 is a GCLKT_4-capable package pin but the open-source placer does
    // not automatically promote it to a global clock.  BUFG does that
    // explicitly, which removes the clock skew seen by the 40 MHz logic and
    // the line-buffer write port.
    wire cvbs_clk_g;
    BUFG u_cvbs_bufg (
        .I(cvbs_clk),
        .O(cvbs_clk_g)
    );

    wire       we;
    wire [9:0] waddr;
    wire [7:0] wdata;
    wire       wbank;
    wire       last_bank;
    wire       line_toggle;
    wire       vsync_toggle;
    wire       locked;
    wire       std_pal;
    wire       dbg_clk;

    cvbs_capture u_capture (
        .clk         (cvbs_clk_g),
        .resetn      (resetn),
        .cvbs        (cvbs),
        .we          (we),
        .waddr       (waddr),
        .wdata       (wdata),
        .wbank       (wbank),
        .last_bank   (last_bank),
        .line_toggle (line_toggle),
        .vsync_toggle(vsync_toggle),
        .locked      (locked),
        .std_pal     (std_pal),
        .dbg_min     (),
        .dbg_clk     (dbg_clk)
    );

    wire [7:0]  pix;
    wire [10:0] raddr;

    line_buffer u_linebuf (
        .wr_clk (cvbs_clk_g),
        .we     (we),
        .wr_addr({wbank, waddr}),
        .wr_data(wdata),
        .rd_clk (clk),
        .rd_addr(raddr),
        .rd_data(pix)
    );

    // ------------------------------------------------------------------
    // 27 MHz output / HDMI encoder
    // ------------------------------------------------------------------
    wire       de;
    wire       hs;
    wire       vs;
    wire [7:0] r;
    wire [7:0] g;
    wire [7:0] b;

    video_out u_video (
        .clk         (clk),
        .resetn      (sys_resetn),
        .pix         (pix),
        .raddr       (raddr),
        .line_toggle (line_toggle),
        .last_bank   (last_bank),
        .vsync_toggle(vsync_toggle),
        .std_pal     (std_pal),
        .locked      (locked),
        .de          (de),
        .hsync       (hs),
        .vsync       (vs),
        .r           (r),
        .g           (g),
        .b           (b)
    );

    wire [9:0] tmds_b, tmds_g, tmds_r;

    // TMDS data channel 0 carries blue plus HS/VS control symbols.
    svo_tmds u_tmds_b (
        .clk(clk), .resetn(sys_resetn), .de(de),
        .ctrl({vs, hs}), .din(b), .dout(tmds_b)
    );
    svo_tmds u_tmds_g (
        .clk(clk), .resetn(sys_resetn), .de(de),
        .ctrl(2'b00), .din(g), .dout(tmds_g)
    );
    svo_tmds u_tmds_r (
        .clk(clk), .resetn(sys_resetn), .de(de),
        .ctrl(2'b00), .din(r), .dout(tmds_r)
    );

    wire [2:0] tmds_serial;

    OSER10 tmds_serdes[2:0] (
        .Q(tmds_serial),
        .D0({tmds_r[0], tmds_g[0], tmds_b[0]}),
        .D1({tmds_r[1], tmds_g[1], tmds_b[1]}),
        .D2({tmds_r[2], tmds_g[2], tmds_b[2]}),
        .D3({tmds_r[3], tmds_g[3], tmds_b[3]}),
        .D4({tmds_r[4], tmds_g[4], tmds_b[4]}),
        .D5({tmds_r[5], tmds_g[5], tmds_b[5]}),
        .D6({tmds_r[6], tmds_g[6], tmds_b[6]}),
        .D7({tmds_r[7], tmds_g[7], tmds_b[7]}),
        .D8({tmds_r[8], tmds_g[8], tmds_b[8]}),
        .D9({tmds_r[9], tmds_g[9], tmds_b[9]}),
        .PCLK(clk),
        .FCLK(clk_5x),
        .RESET(~sys_resetn)
    );

    ELVDS_OBUF tmds_bufds[3:0] (
        .I({clk, tmds_serial}),
        .O({tmds_clk_p, tmds_d_p}),
        .OB({tmds_clk_n, tmds_d_n})
    );

    // LED1 = lock, LED2 = PAL, LED3 = 40 MHz clock heartbeat,
    // LED4 = captured-line activity.  All active low.
    reg [1:0]  dbg_clk_sync;
    reg [2:0]  line_sync;
    reg        line_d;
    reg [12:0] line_act_cnt;

    always @(posedge clk) begin
        dbg_clk_sync <= {dbg_clk_sync[0], dbg_clk};
        line_sync    <= {line_sync[1:0], line_toggle};
        line_d       <= line_sync[2];
    end

    wire line_edge = line_sync[2] ^ line_d;

    always @(posedge clk) begin
        if (!sys_resetn) line_act_cnt <= 13'd0;
        else if (line_edge) line_act_cnt <= line_act_cnt + 13'd1;
    end

    assign led = ~{2'b00, line_act_cnt[12], dbg_clk_sync[1], std_pal, locked};

endmodule


module Reset_Sync (
    input  wire clk,
    input  wire ext_reset,
    output wire resetn
);

    reg [3:0] reset_cnt = 4'b0;

    always @(posedge clk or negedge ext_reset) begin
        if (~ext_reset)
            reset_cnt <= 4'b0;
        else
            reset_cnt <= reset_cnt + !resetn;
    end

    assign resetn = &reset_cnt;

endmodule
