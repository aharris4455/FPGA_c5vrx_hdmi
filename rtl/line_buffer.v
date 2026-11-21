// Dual-clock ping-pong line buffer.
//
// Two 1024 x 8 banks are addressed as {bank, offset}; the write port runs in
// the 40 MHz capture domain, the read port in the 27 MHz pixel domain.  The
// capture side alternates banks at every completed line and tells the reader
// which bank is complete with last_bank / line_toggle.

module line_buffer (
    input  wire        wr_clk,
    input  wire        we,
    input  wire [10:0] wr_addr,  // {bank, offset}
    input  wire [7:0]  wr_data,

    input  wire        rd_clk,
    input  wire [10:0] rd_addr,  // {bank, offset}
    output reg  [7:0]  rd_data
);

    reg [7:0] mem [0:2047];

    always @(posedge wr_clk) begin
        if (we) mem[wr_addr] <= wr_data;
    end

    always @(posedge rd_clk) begin
        rd_data <= mem[rd_addr];
    end

endmodule
