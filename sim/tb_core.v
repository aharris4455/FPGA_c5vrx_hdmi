`timescale 1ns/1ps

// Core simulation for the C5VRX tap -> HDMI converter.
//
// Run with:
//   iverilog -g2012 -o tb_core.vvp sim/tb_core.v rtl/cvbs_capture.v \
//       rtl/line_buffer.v rtl/video_out.v
//   vvp tb_core.vvp +STIM=sim/ntsc.hex +N=668546 +ARM_NS=25000000 \
//       +PIX=345600 +TIMEOUT_NS=60000000
//
// The testbench writes the first full active frame after lock to frame.raw
// (720 x 480 or 720 x 576, 8-bit luma).

module tb_core;

    reg clk27 = 1'b0;
    reg clk40 = 1'b0;
    reg resetn = 1'b0;
    reg [5:0] cvbs = 6'd0;

    always #18.5 clk27 = ~clk27; // ~27.03 MHz
    always #12.5 clk40 = ~clk40; // 40 MHz

    // ------------------------------------------------------------------
    // DUT: capture + line buffer + output
    // ------------------------------------------------------------------
    wire       we;
    wire [9:0] waddr;
    wire [7:0] wdata;
    wire       wbank;
    wire       last_bank;
    wire       line_toggle;
    wire       vsync_toggle;
    wire       locked;
    wire       std_pal;
    wire [5:0] dbg_min;

    cvbs_capture u_cap (
        .clk         (clk40),
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
        .dbg_min     (dbg_min)
    );

    wire [7:0]  pix;
    wire [10:0] raddr;

    line_buffer u_buf (
        .wr_clk (clk40),
        .we     (we),
        .wr_addr({wbank, waddr}),
        .wr_data(wdata),
        .rd_clk (clk27),
        .rd_addr(raddr),
        .rd_data(pix)
    );

    wire       de;
    wire       hs;
    wire       vs;
    wire [7:0] r;
    wire [7:0] g;
    wire [7:0] b;

    video_out u_vid (
        .clk         (clk27),
        .resetn      (resetn),
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

    // ------------------------------------------------------------------
    // Stimulus
    // ------------------------------------------------------------------
    reg [5:0] stim [0:999999];
    reg [1023:0] stim_file;
    integer n;
    integer n_samples;

    initial begin
        if (!$value$plusargs("STIM=%s", stim_file)) stim_file = "cvbs.hex";
        if (!$value$plusargs("N=%d", n_samples)) begin
            $display("ERROR: +N=<samples> is required");
            $finish;
        end
        $readmemh(stim_file, stim);
        n = 0;
    end

    always @(negedge clk40) begin
        cvbs <= stim[n];
        n = (n + 1) % n_samples;
    end

    initial begin
        resetn = 1'b0;
        #500;
        resetn = 1'b1;
    end

    // ------------------------------------------------------------------
    // Frame dump: after lock, wait for the next vertical sync, then write
    // every active pixel of that frame.
    // ------------------------------------------------------------------
    reg vs_d = 1'b1;
    reg capturing = 1'b0;
    reg armed_allowed = 1'b0;
    integer fd;
    integer pixel_count = 0;
    integer total_pixels = 720 * 480;
    integer arm_ns = 25000000;

    always @(posedge clk27) vs_d <= vs;

    initial begin
        if (!$value$plusargs("ARM_NS=%d", arm_ns)) arm_ns = 25000000;
        if (!$value$plusargs("PIX=%d", total_pixels)) total_pixels = 720 * 480;

        fd = $fopen("frame.raw", "wb");
        #(arm_ns);
        armed_allowed = 1'b1;
        $display("ARM t=%0t locked=%b pal=%b min=%0d",
                 $time, locked, std_pal, dbg_min);

        #150000000;
        $display("TIMEOUT t=%0t locked=%b pal=%b pixels=%0d min=%0d",
                 $time, locked, std_pal, pixel_count, dbg_min);
        $finish;
    end

    always @(posedge clk27) begin
        if (armed_allowed && locked && !capturing && vs_d && !vs) begin
            capturing  <= 1'b1;
            pixel_count <= 0;
            $display("CAPTURE t=%0t pal=%b", $time, std_pal);
        end

        if (capturing && de) begin
            $fwrite(fd, "%c", r);
            pixel_count <= pixel_count + 1;
            if ((pixel_count + 1) == total_pixels) begin
                $fclose(fd);
                $display("DONE t=%0t pixels=%0d pal=%b",
                         $time, pixel_count + 1, std_pal);
                $finish;
            end
        end
    end

endmodule
