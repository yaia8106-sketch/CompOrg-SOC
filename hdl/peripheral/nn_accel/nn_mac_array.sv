// ============================================================
// Module: nn_mac_array
// Description:
//   4×4 systolic-style MAC array for int8 matrix multiplication.
//
//   Architecture:
//     - 4 rows × 4 columns = 16 MAC units
//     - Weights flow horizontally (broadcast per row)
//     - Activations flow vertically (broadcast per column)
//     - Each column accumulates one output channel partial sum
//
//   Each cycle:
//     - Load 4 weights (one per row)
//     - Load 4 activations (one per column)
//     - 16 MACs fire in parallel
//     - 4 partial sums output (one per column)
//
//   Throughput: 16 MACs/cycle @ 200MHz = 3.2 GOPS (int8)
// ============================================================

module nn_mac_array #(
    parameter int ARRAY_ROWS = 4,
    parameter int ARRAY_COLS = 4
) (
    input  logic        clk,
    input  logic        rst,

    input  logic        en,              // enable MAC operation
    input  logic        clear,           // clear all accumulators

    // Weight inputs (ARRAY_ROWS × 8-bit)
    input  logic signed [7:0] weight [ARRAY_ROWS],

    // Activation inputs (ARRAY_COLS × 8-bit)
    input  logic signed [7:0] activ [ARRAY_COLS],

    // Partial sum outputs (ARRAY_COLS × 32-bit)
    output logic signed [31:0] psum  [ARRAY_COLS]
);

    // MAC unit grid: mac[row][col]
    // weight[row] × activ[col] → accumulates to psum[col]
    logic signed [31:0] mac_out [ARRAY_ROWS][ARRAY_COLS];

    for (genvar r = 0; r < ARRAY_ROWS; r++) begin : row
        for (genvar c = 0; c < ARRAY_COLS; c++) begin : col
            nn_mac_unit u_mac (
                .clk    (clk),
                .rst    (rst),
                .en     (en),
                .clear  (clear),
                .a      (weight[r]),
                .b      (activ[c]),
                .result (mac_out[r][c])
            );
        end
    end

    // Column-wise reduction: sum across rows to get psum[col]
    for (genvar c = 0; c < ARRAY_COLS; c++) begin : col_reduce
        always_comb begin
            psum[c] = mac_out[0][c] + mac_out[1][c] +
                      mac_out[2][c] + mac_out[3][c];
        end
    end

endmodule
