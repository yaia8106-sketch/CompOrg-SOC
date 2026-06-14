// ============================================================
// Module: nn_weight_buf
// Description:
//   Simple 1KB weight buffer (256 × 32-bit BRAM).
//   Weights are stored as packed int8: 4 weights per 32-bit word.
//
//   Read port: outputs 4 int8 weights per cycle for MAC array.
//   Write port: receives data from AXI reads during preload.
//
//   Dual-buffer mode: 2 × 512B banks for ping-pong buffering.
//   While one bank feeds the MAC array, the other can be loaded
//   with the next layer's weights.
// ============================================================

module nn_weight_buf #(
    parameter int BUF_DEPTH = 256,   // 256 × 32b = 1024 bytes = 1024 int8 weights
    parameter int DUAL_BUF = 1       // 1 = dual-buffer ping-pong
) (
    input  logic        clk,
    input  logic        rst,

    // ============================================================
    // Write port (from AXI reads / preload)
    // ============================================================
    input  logic        wr_en,
    input  logic [ 7:0] wr_addr,     // word address (0..255)
    input  logic [31:0] wr_data,     // packed: {w3, w2, w1, w0}
    input  logic        wr_bank,     // which bank to write to (0/1)

    // ============================================================
    // Read port (to MAC array)
    // ============================================================
    input  logic        rd_en,
    input  logic [ 7:0] rd_addr,     // word address
    input  logic        rd_bank,     // which bank to read from (0/1)
    output logic signed [7:0] rd_w0,  // weight byte 0
    output logic signed [7:0] rd_w1,  // weight byte 1
    output logic signed [7:0] rd_w2,  // weight byte 2
    output logic signed [7:0] rd_w3   // weight byte 3
);

    localparam int TOTAL_DEPTH = DUAL_BUF ? BUF_DEPTH * 2 : BUF_DEPTH;

    (* ram_style = "block" *) logic [31:0] buf [TOTAL_DEPTH];

    // Write
    always_ff @(posedge clk) begin
        if (wr_en) begin
            if (DUAL_BUF)
                buf[{wr_bank, wr_addr}] <= wr_data;
            else
                buf[wr_addr] <= wr_data;
        end
    end

    // Read
    logic [31:0] rd_word;
    always_comb begin
        if (DUAL_BUF)
            rd_word = buf[{rd_bank, rd_addr}];
        else
            rd_word = buf[rd_addr];
    end

    // Unpack: 4 × int8 per 32-bit word (little-endian byte order)
    assign rd_w0 = rd_word[ 7: 0];
    assign rd_w1 = rd_word[15: 8];
    assign rd_w2 = rd_word[23:16];
    assign rd_w3 = rd_word[31:24];

endmodule
