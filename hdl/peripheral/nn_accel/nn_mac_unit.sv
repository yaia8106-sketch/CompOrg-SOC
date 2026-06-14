// ============================================================
// Module: nn_mac_unit
// Description:
//   Single int8 multiply-accumulate unit.
//   Computes: accum = accum + (a * b)
//   where a and b are signed 8-bit, accum is signed 32-bit.
// ============================================================

module nn_mac_unit (
    input  logic        clk,
    input  logic        rst,
    input  logic        en,           // enable this cycle
    input  logic        clear,        // reset accumulator to 0
    input  logic signed [7:0] a,      // weight (int8)
    input  logic signed [7:0] b,      // activation (int8)
    output logic signed [31:0] result // accumulator output
);

    logic signed [15:0] product;
    logic signed [31:0] accum;

    assign product = a * b;

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            accum <= '0;
        end else if (clear) begin
            accum <= '0;
        end else if (en) begin
            accum <= accum + product;
        end
    end

    assign result = accum;

endmodule
