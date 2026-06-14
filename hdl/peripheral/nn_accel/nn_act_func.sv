// ============================================================
// Module: nn_act_func
// Description:
//   Activation function unit.
//   Supports: ReLU, ReLU6, and simple Tanh approximation.
//
//   ReLU:  out = max(0, in)
//   Tanh:  piecewise linear approximation (fast, no LUT needed)
//          out = clip(in, -1, 1) simplified to:
//          if in > 128 → 127 (saturate)
//          if in < -128 → -128 (saturate)
//          else out = in (identity for small values)
//          For better accuracy, use a small LUT.
//
//   Input:  int32 accumulated sum
//   Output: int8 (quantized activation for next layer)
// ============================================================

module nn_act_func (
    input  logic        clk,
    input  logic        rst,

    input  logic        en,
    input  logic [ 2:0] func_sel,    // 0=ReLU, 1=Tanh, 2=Sigmoid, 3=Identity

    input  logic signed [31:0] data_in,
    output logic signed [ 7:0] data_out,
    output logic               out_valid
);

    // ============================================================
    // ReLU
    // ============================================================
    // For int32 → int8: first quantize (right-shift by requant_shift),
    // then clip to [0, 127].
    // ============================================================
    logic signed [31:0] requant;
    localparam int REQUANT_SHIFT = 8;  // Q8.8 → Q0.0 (int8)

    // Right-shift with rounding
    logic signed [31:0] shifted;
    assign shifted = (data_in >>> REQUANT_SHIFT) +
                     {{31{1'b0}}, data_in[REQUANT_SHIFT-1]};  // round half-up

    // Clip to int8 range
    logic signed [7:0] relu_out;
    always_comb begin
        if (shifted > 127)
            relu_out = 8'sd127;
        else if (shifted < 0)
            relu_out = 8'sd0;
        else
            relu_out = shifted[7:0];
    end

    // ============================================================
    // Tanh approximation (piecewise linear)
    // ============================================================
    // Quantized tanh: maps int32 → int8 in [-127, 127]
    // Used for value head output.
    // ============================================================
    logic signed [7:0] tanh_out;
    always_comb begin
        // Simple saturating approximation
        // Scale down by 6 bits first
        logic signed [31:0] scaled;
        scaled = data_in >>> 6;
        if (scaled > 127)
            tanh_out = 8'sd127;
        else if (scaled < -128)
            tanh_out = -8'sd128;
        else
            tanh_out = scaled[7:0];
    end

    // ============================================================
    // Sigmoid approximation (for policy/value)
    // ============================================================
    logic signed [7:0] sigmoid_out;
    always_comb begin
        // Simple: map to [0, 127]
        logic signed [31:0] scaled;
        scaled = (data_in >>> 7) + 32'sd64;
        if (scaled > 127)
            sigmoid_out = 8'sd127;
        else if (scaled < 0)
            sigmoid_out = 8'sd0;
        else
            sigmoid_out = scaled[7:0];
    end

    // ============================================================
    // Output mux
    // ============================================================
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            data_out  <= '0;
            out_valid <= 1'b0;
        end else begin
            out_valid <= en;
            if (en) begin
                case (func_sel)
                    3'd0: data_out <= relu_out;      // ReLU
                    3'd1: data_out <= tanh_out;      // Tanh
                    3'd2: data_out <= sigmoid_out;   // Sigmoid
                    3'd3: data_out <= shifted[7:0];  // Identity (linear)
                    default: data_out <= relu_out;
                endcase
            end
        end
    end

endmodule
