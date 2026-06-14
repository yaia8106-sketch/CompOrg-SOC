// ============================================================
// Module: hdmi_linebuf
// Description:
//   Double-buffered line buffer for HDMI scan-out.
//
//   Architecture:
//     - Two ping-pong line buffers (BRAM)
//     - While buffer A is being scanned out (read side),
//       buffer B is being filled by the AXI reader (write side)
//     - Swaps at each line boundary
//
//   Configuration:
//     - MAX_LINE_WIDTH: 1024 pixels (4KB per buffer)
//     - 2 × 1024 × 32b = 8KB total
// ============================================================

module hdmi_linebuf #(
    parameter int MAX_LINE_WIDTH = 1024  // in pixels (32-bit each)
) (
    input  logic        clk,
    input  logic        rst,

    // ============================================================
    // Write port (from AXI reader)
    // ============================================================
    input  logic        wr_en,
    input  logic [ 9:0] wr_addr,    // pixel offset in line (0..width-1)
    input  logic [31:0] wr_data,    // RGBx8888
    input  logic        wr_swap,    // swap buffers: write bank flips

    // ============================================================
    // Read port (to pixel output)
    // ============================================================
    input  logic        rd_en,
    input  logic [ 9:0] rd_addr,    // pixel offset
    input  logic        rd_swap,    // swap buffers: read bank flips
    output logic [31:0] rd_data,

    // Status
    output logic        wr_underrun  // write didn't finish before swap
);

    // Dual-bank BRAM
    (* ram_style = "block" *) logic [31:0] buf [2 * MAX_LINE_WIDTH];

    // Buffer bank select (toggled by swap signals)
    logic wr_bank, rd_bank;

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            wr_bank <= 1'b0;
            rd_bank <= 1'b1;
        end else begin
            if (wr_swap) wr_bank <= ~wr_bank;
            if (rd_swap) rd_bank <= ~rd_bank;
        end
    end

    // Write logic
    logic wr_done;  // set when all pixels of a line have been written
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            wr_done <= 1'b0;
        end else begin
            if (wr_swap)
                wr_done <= 1'b0;
            else if (wr_en)
                buf[{wr_bank, wr_addr}] <= wr_data;
        end
    end

    // Read logic (combinational for minimum latency)
    assign rd_data = buf[{rd_bank, rd_addr}];

    // Underrun: if bank swap happens but write didn't complete the full line
    assign wr_underrun = rd_swap && !wr_done;

endmodule
