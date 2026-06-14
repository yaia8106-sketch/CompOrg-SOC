// ============================================================
// Module: nn_accel_top
// Description:
//   Neural Network Accelerator top-level. Integrates:
//     - Weight buffer (1KB dual-bank BRAM)
//     - 4×4 MAC array (16 int8 MACs)
//     - im2col address generator
//     - Activation function unit
//     - Sequencer (layer execution FSM)
//     - MMIO register file
//     - AXI4 master port
//
//   The accelerator executes one layer at a time under software
//   control. The CPU writes layer configuration to MMIO registers,
//   then sets the START bit. The accelerator reads input data
//   and weights from DDR via AXI, performs the computation, and
//   writes output data back to DDR.
//
//   Supported layers:
//     - Conv2D (3×3, stride 1-2, pad 1)
//     - Fully Connected
//     - ReLU activation
//     - MaxPool 2×2
//     - Global Average Pooling
// ============================================================

`include "hdl/peripheral/nn_accel/nn_regs.svh"

module nn_accel_top #(
    parameter int WEIGHT_BUF_DEPTH = 256   // 1KB
) (
    input  logic        clk,
    input  logic        rst,

    // ============================================================
    // MMIO Register Interface (from soc_mmio_decoder)
    // ============================================================
    input  logic        reg_sel,
    input  logic [15:0] reg_addr,
    input  logic [31:0] reg_wdata,
    input  logic [ 3:0] reg_wstrb,
    input  logic        reg_wen,
    input  logic        reg_ren,
    output logic [31:0] reg_rdata,
    output logic        reg_rvalid,

    // ============================================================
    // Interrupt
    // ============================================================
    output logic        nn_irq,

    // ============================================================
    // AXI4 Master Port
    // ============================================================
    output logic [31:0] m_awaddr,
    output logic [ 7:0] m_awlen,
    output logic [ 2:0] m_awsize,
    output logic [ 1:0] m_awburst,
    output logic        m_awlock,
    output logic [ 3:0] m_awcache,
    output logic [ 2:0] m_awprot,
    output logic [ 3:0] m_awqos,
    output logic        m_awvalid,
    input  logic        m_awready,

    output logic [31:0] m_wdata,
    output logic [ 3:0] m_wstrb,
    output logic        m_wlast,
    output logic        m_wvalid,
    input  logic        m_wready,

    input  logic [ 1:0] m_bresp,
    input  logic        m_bvalid,
    output logic        m_bready,

    output logic [31:0] m_araddr,
    output logic [ 7:0] m_arlen,
    output logic [ 2:0] m_arsize,
    output logic [ 1:0] m_arburst,
    output logic        m_arlock,
    output logic [ 3:0] m_arcache,
    output logic [ 2:0] m_arprot,
    output logic [ 3:0] m_arqos,
    output logic        m_arvalid,
    input  logic        m_arready,

    input  logic [31:0] m_rdata,
    input  logic [ 1:0] m_rresp,
    input  logic        m_rlast,
    input  logic        m_rvalid,
    output logic        m_rready
);

    // ============================================================
    // AXI constants
    // ============================================================
    localparam AXI_SIZE  = 3'd2;
    localparam AXI_BURST = 2'b01;

    // ============================================================
    // Registers
    // ============================================================
    logic        ctrl_start, ctrl_irq_en, ctrl_weight_preload;
    logic        status_busy, status_done, status_error;
    logic [ 7:0] layer_type;
    logic [31:0] input_addr, weight_addr, output_addr, bias_addr;
    logic [ 7:0] in_h, in_w, in_ch, out_h, out_w, out_ch;
    logic [ 7:0] kernel_h, kernel_w, stride, pad;
    logic [ 7:0] pool_h, pool_w;

    // ============================================================
    // Sequencer ↔ MAC array, im2col, weight buf, act func
    // ============================================================
    logic        seq_i2c_start, seq_i2c_done, seq_i2c_next;
    logic [31:0] seq_i2c_rd_addr;
    logic        seq_i2c_rd_valid, seq_i2c_is_last;

    logic        seq_wbuf_wr_en, seq_wbuf_rd_en, seq_wbuf_wr_bank, seq_wbuf_rd_bank;
    logic [ 7:0] seq_wbuf_wr_addr, seq_wbuf_rd_addr;
    logic [31:0] seq_wbuf_wr_data;
    logic signed [7:0] seq_wbuf_rd_w [4];

    logic        seq_mac_en, seq_mac_clear;
    logic signed [7:0] seq_mac_weight [4], seq_mac_activ [4];
    logic signed [31:0] mac_psum [4];

    logic        seq_act_en;
    logic [ 2:0] seq_act_func;
    logic signed [31:0] seq_act_data_in [4];
    logic signed [ 7:0] act_data_out [4];
    logic        act_out_valid;

    // ============================================================
    // Sequencer
    // ============================================================
    nn_sequencer u_sequencer (
        .clk            (clk),
        .rst            (rst),
        .start          (ctrl_start),
        .busy           (status_busy),
        .done           (status_done),
        .error          (status_error),
        .layer_type     (layer_type),
        .input_addr     (input_addr),
        .weight_addr    (weight_addr),
        .output_addr    (output_addr),
        .bias_addr      (bias_addr),
        .in_h           (in_h),
        .in_w           (in_w),
        .in_ch          (in_ch),
        .out_h          (out_h),
        .out_w          (out_w),
        .out_ch         (out_ch),
        .kernel_h       (kernel_h),
        .kernel_w       (kernel_w),
        .stride         (stride),
        .pad            (pad),
        .pool_h         (pool_h),
        .pool_w         (pool_w),
        .i2c_start      (seq_i2c_start),
        .i2c_done       (seq_i2c_done),
        .i2c_next       (seq_i2c_next),
        .i2c_rd_addr    (seq_i2c_rd_addr),
        .i2c_rd_valid   (seq_i2c_rd_valid),
        .i2c_is_last    (seq_i2c_is_last),
        .wbuf_wr_en     (seq_wbuf_wr_en),
        .wbuf_wr_addr   (seq_wbuf_wr_addr),
        .wbuf_wr_data   (seq_wbuf_wr_data),
        .wbuf_wr_bank   (seq_wbuf_wr_bank),
        .wbuf_rd_en     (seq_wbuf_rd_en),
        .wbuf_rd_addr   (seq_wbuf_rd_addr),
        .wbuf_rd_bank   (seq_wbuf_rd_bank),
        .wbuf_rd_w0     (seq_wbuf_rd_w[0]),
        .wbuf_rd_w1     (seq_wbuf_rd_w[1]),
        .wbuf_rd_w2     (seq_wbuf_rd_w[2]),
        .wbuf_rd_w3     (seq_wbuf_rd_w[3]),
        .mac_en         (seq_mac_en),
        .mac_clear      (seq_mac_clear),
        .mac_weight     (seq_mac_weight),
        .mac_activ      (seq_mac_activ),
        .mac_psum       (mac_psum),
        .act_en         (seq_act_en),
        .act_func       (seq_act_func),
        .act_data_in    (seq_act_data_in),
        .act_data_out   (act_data_out),
        .act_out_valid  (act_out_valid),
        .axi_araddr     (m_araddr),
        .axi_arvalid    (m_arvalid),
        .axi_arready    (m_arready),
        .axi_rdata      (m_rdata),
        .axi_rvalid     (m_rvalid),
        .axi_rlast      (m_rlast),
        .axi_rready     (m_rready),
        .axi_awaddr     (m_awaddr),
        .axi_awvalid    (m_awvalid),
        .axi_awready    (m_awready),
        .axi_wdata      (m_wdata),
        .axi_wvalid     (m_wvalid),
        .axi_wready     (m_wready),
        .axi_bresp      (m_bresp),
        .axi_bvalid     (m_bvalid),
        .axi_bready     (m_bready)
    );

    // ============================================================
    // Weight Buffer
    // ============================================================
    nn_weight_buf #(
        .BUF_DEPTH (WEIGHT_BUF_DEPTH),
        .DUAL_BUF  (1)
    ) u_weight_buf (
        .clk      (clk),
        .rst      (rst),
        .wr_en    (seq_wbuf_wr_en),
        .wr_addr  (seq_wbuf_wr_addr),
        .wr_data  (seq_wbuf_wr_data),
        .wr_bank  (seq_wbuf_wr_bank),
        .rd_en    (seq_wbuf_rd_en),
        .rd_addr  (seq_wbuf_rd_addr),
        .rd_bank  (seq_wbuf_rd_bank),
        .rd_w0    (seq_wbuf_rd_w[0]),
        .rd_w1    (seq_wbuf_rd_w[1]),
        .rd_w2    (seq_wbuf_rd_w[2]),
        .rd_w3    (seq_wbuf_rd_w[3])
    );

    // ============================================================
    // MAC Array
    // ============================================================
    nn_mac_array #(
        .ARRAY_ROWS (4),
        .ARRAY_COLS (4)
    ) u_mac_array (
        .clk    (clk),
        .rst    (rst),
        .en     (seq_mac_en),
        .clear  (seq_mac_clear),
        .weight (seq_mac_weight),
        .activ  (seq_mac_activ),
        .psum   (mac_psum)
    );

    // ============================================================
    // Activation Function Unit
    // ============================================================
    // Instantiate 4 activation units (one per output channel)
    for (genvar i = 0; i < 4; i++) begin : act_gen
        nn_act_func u_act (
            .clk       (clk),
            .rst       (rst),
            .en        (seq_act_en),
            .func_sel  (seq_act_func),
            .data_in   (seq_act_data_in[i]),
            .data_out  (act_data_out[i]),
            .out_valid (act_out_valid)  // all 4 have same timing
        );
    end

    // ============================================================
    // im2col
    // ============================================================
    nn_im2col u_im2col (
        .clk           (clk),
        .rst           (rst),
        .in_h          (in_h),
        .in_w          (in_w),
        .in_ch         (in_ch),
        .kernel_h      (kernel_h),
        .kernel_w      (kernel_w),
        .stride        (stride),
        .pad           (pad),
        .start         (seq_i2c_start),
        .done          (seq_i2c_done),
        .next_patch    (seq_i2c_next),
        .axi_rd_addr   (seq_i2c_rd_addr),
        .axi_rd_valid  (seq_i2c_rd_valid),
        .is_last_patch (seq_i2c_is_last)
    );

    // ============================================================
    // AXI tie-offs (fixed signals)
    // ============================================================
    assign m_awlen   = 8'd0;     // single beat writes
    assign m_awsize  = AXI_SIZE;
    assign m_awburst = AXI_BURST;
    assign m_awlock  = 1'b0;
    assign m_awcache = 4'b0011;
    assign m_awprot  = 3'b000;
    assign m_awqos   = 4'b0000;

    assign m_arlen   = 8'd0;     // single beat reads
    assign m_arsize  = AXI_SIZE;
    assign m_arburst = AXI_BURST;
    assign m_arlock  = 1'b0;
    assign m_arcache = 4'b0011;
    assign m_arprot  = 3'b000;
    assign m_arqos   = 4'b0000;

    assign m_wstrb   = 4'b1111;
    assign m_wlast   = 1'b1;     // single beat

    // ============================================================
    // Interrupt
    // ============================================================
    assign nn_irq = ctrl_irq_en && (status_done || status_error);

    // ============================================================
    // MMIO Register File
    // ============================================================
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            ctrl_start          <= 1'b0;
            ctrl_irq_en         <= 1'b0;
            ctrl_weight_preload <= 1'b0;
            layer_type          <= '0;
            input_addr          <= '0;
            weight_addr         <= '0;
            output_addr         <= '0;
            bias_addr           <= '0;
            in_h                <= '0;
            in_w                <= '0;
            in_ch               <= '0;
            out_h               <= '0;
            out_w               <= '0;
            out_ch              <= '0;
            kernel_h            <= 8'd3;
            kernel_w            <= 8'd3;
            stride              <= 8'd1;
            pad                 <= 8'd1;
            pool_h              <= 8'd2;
            pool_w              <= 8'd2;
        end else begin
            ctrl_start <= 1'b0;  // self-clearing

            if (reg_sel && reg_wen) begin
                case (reg_addr)
                    `NN_REG_CTRL: begin
                        ctrl_start  <= reg_wdata[`NN_CTRL_START];
                        ctrl_irq_en <= reg_wdata[`NN_CTRL_IRQ_EN];
                        ctrl_weight_preload <= reg_wdata[`NN_CTRL_WEIGHT_PRELOAD];
                    end
                    `NN_REG_LAYER_TYPE:  layer_type  <= reg_wdata[7:0];
                    `NN_REG_INPUT_ADDR:  input_addr  <= reg_wdata;
                    `NN_REG_WEIGHT_ADDR: weight_addr <= reg_wdata;
                    `NN_REG_OUTPUT_ADDR: output_addr <= reg_wdata;
                    `NN_REG_BIAS_ADDR:   bias_addr   <= reg_wdata;
                    `NN_REG_INPUT_DIM:   {in_h, in_w} <= reg_wdata[15:0];
                    `NN_REG_INPUT_CH:    in_ch  <= reg_wdata[7:0];
                    `NN_REG_OUTPUT_DIM:  {out_h, out_w} <= reg_wdata[15:0];
                    `NN_REG_OUTPUT_CH:   out_ch <= reg_wdata[7:0];
                    `NN_REG_KERNEL:      {kernel_h, kernel_w} <= reg_wdata[15:0];
                    `NN_REG_STRIDE_PAD:  {stride, pad} <= reg_wdata[15:0];
                    `NN_REG_POOL_SIZE:   {pool_h, pool_w} <= reg_wdata[15:0];
                    default: ;
                endcase
            end
        end
    end

    // MMIO read mux
    always_comb begin
        reg_rdata  = 32'h0000_0000;
        reg_rvalid = 1'b0;

        if (reg_sel && reg_ren) begin
            reg_rvalid = 1'b1;
            case (reg_addr)
                `NN_REG_CTRL:        reg_rdata = {29'd0, ctrl_weight_preload, ctrl_irq_en, 1'b0, ctrl_start};
                `NN_REG_STATUS:      reg_rdata = {29'd0, status_error, status_done, status_busy};
                `NN_REG_LAYER_TYPE:  reg_rdata = {24'd0, layer_type};
                `NN_REG_INPUT_ADDR:  reg_rdata = input_addr;
                `NN_REG_WEIGHT_ADDR: reg_rdata = weight_addr;
                `NN_REG_OUTPUT_ADDR: reg_rdata = output_addr;
                `NN_REG_BIAS_ADDR:   reg_rdata = bias_addr;
                `NN_REG_INPUT_DIM:   reg_rdata = {16'd0, in_h, in_w};
                `NN_REG_INPUT_CH:    reg_rdata = {24'd0, in_ch};
                `NN_REG_OUTPUT_DIM:  reg_rdata = {16'd0, out_h, out_w};
                `NN_REG_OUTPUT_CH:   reg_rdata = {24'd0, out_ch};
                `NN_REG_KERNEL:      reg_rdata = {16'd0, kernel_h, kernel_w};
                `NN_REG_STRIDE_PAD:  reg_rdata = {16'd0, stride, pad};
                `NN_REG_POOL_SIZE:   reg_rdata = {16'd0, pool_h, pool_w};
                default:             reg_rdata = 32'hDEAD_BEEF;
            endcase
        end
    end

endmodule
