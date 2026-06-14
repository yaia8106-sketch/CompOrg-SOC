// ============================================================
// NN Accelerator Register Definitions
// ============================================================
`ifndef NN_REGS_SVH
`define NN_REGS_SVH

// Register offsets
`define NN_REG_CTRL          16'h0000   // R/W: control
`define NN_REG_STATUS        16'h0004   // R:   status
`define NN_REG_LAYER_TYPE    16'h0008   // R/W: layer type
`define NN_REG_INPUT_ADDR    16'h000C   // R/W: DDR address of input data
`define NN_REG_WEIGHT_ADDR   16'h0010   // R/W: DDR address of weights
`define NN_REG_OUTPUT_ADDR   16'h0014   // R/W: DDR address for output data
`define NN_REG_BIAS_ADDR     16'h0018   // R/W: DDR address of bias data
`define NN_REG_INPUT_DIM     16'h001C   // R/W: {in_h[15:8], in_w[7:0]} — for FC: in_features
`define NN_REG_INPUT_CH      16'h0020   // R/W: input channels
`define NN_REG_OUTPUT_DIM    16'h0024   // R/W: {out_h[15:8], out_w[7:0]} — for FC: out_features
`define NN_REG_OUTPUT_CH     16'h0028   // R/W: output channels
`define NN_REG_KERNEL        16'h002C   // R/W: {kernel_h[15:8], kernel_w[7:0]}
`define NN_REG_STRIDE_PAD    16'h0030   // R/W: {stride[15:8], pad[7:0]}
`define NN_REG_POOL_SIZE     16'h0034   // R/W: {pool_h[15:8], pool_w[7:0]}
`define NN_REG_LAYER_PARAM   16'h0038   // R/W: misc layer parameter

// NN_CTRL bits
`define NN_CTRL_START         0
`define NN_CTRL_IRQ_EN        1
`define NN_CTRL_WEIGHT_PRELOAD 2   // Preload weights from DDR to buffer

// NN_STATUS bits
`define NN_STATUS_BUSY        0
`define NN_STATUS_DONE        1
`define NN_STATUS_ERROR       2

// Layer types
`define NN_LAYER_CONV2D       8'd0
`define NN_LAYER_FC           8'd1
`define NN_LAYER_RELU         8'd2
`define NN_LAYER_MAXPOOL      8'd3
`define NN_LAYER_GLOBALAVG    8'd4
`define NN_LAYER_SOFTMAX      8'd5
`define NN_LAYER_TANH         8'd6

`endif /* NN_REGS_SVH */
