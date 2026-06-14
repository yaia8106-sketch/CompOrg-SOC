// ============================================================
// Module: soc_top
// Description:
//   SoC integration top-level. Instantiates:
//     - JYD2026 CPU IP (student_top_axi)
//     - AXI4 Crossbar (4 masters, 3 slaves)
//     - AXI RAM Slave (DDR placeholder, 256KB)
//     - SoC MMIO Decoder (peripheral register routing)
//     - DMA Engine (Phase 2)
//     - NN Accelerator (Phase 3)
//     - HDMI Controller (Phase 4)
//
//   CPU IP (jyd2026) exposes:
//     - AXI4 master (32b addr, 32b data) — DCache backend
//     - Local MMIO (LED, SW, KEY, SEG) — handled internally
//
//   Crossbar topology:
//     M0: CPU        ─┐
//     M1: DMA        ─┤
//     M2: NN Accel   ─┤
//     M3: HDMI       ─┤
//                     ├──→ S0: DDR RAM      (0x8030_0000)
//                     ├──→ S1: SoC MMIO     (0xA000_0000)
//                     └──→ S2: NC Buffer    (0xB000_0000)
// ============================================================

`include "hdl/soc/address_map.svh"

module soc_top #(
    parameter P_SW_CNT  = 64,
    parameter P_LED_CNT = 32,
    parameter P_SEG_CNT = 40,
    parameter P_KEY_CNT = 8,
    parameter DDR_DEPTH  = 65536    // 256KB DDR (words)
) (
    input                            w_cpu_clk,
    input                            w_clk_50Mhz,
    input                            w_clk_rst,

    // Board I/O — passed through to CPU's local MMIO
    input  [P_KEY_CNT - 1:0]        virtual_key,
    input  [P_SW_CNT  - 1:0]        virtual_sw,
    output [P_LED_CNT - 1:0]        virtual_led,
    output [P_SEG_CNT - 1:0]        virtual_seg,

    // ========================================================
    // DDR PHY interface (placeholder — AXI RAM slave on-chip)
    // ========================================================

    // ========================================================
    // HDMI / display interface
    // ========================================================
    output        hdmi_clk,
    output        hdmi_hsync,
    output        hdmi_vsync,
    output        hdmi_de,
    output [23:0] hdmi_rgb,

    // ========================================================
    // Interrupt lines from peripherals (internal, connected below)
    // ========================================================
    // dma_irq, nn_irq, hdmi_irq are internal wire/logic signals
);

    // ========================================================
    // Parameters
    // ========================================================
    localparam int NUM_MASTERS = 4;
    localparam int NUM_SLAVES  = 3;

    // Slave address ranges
    localparam bit [31:0] XBAR_SLAVE_BASE [NUM_SLAVES] = '{
        `SOC_ADDR_DDR_BASE,       // S0: DDR
        `SOC_ADDR_SOC_MMIO_BASE,  // S1: SoC MMIO
        `SOC_ADDR_NC_BUFFER_BASE  // S2: NC Buffer
    };
    localparam bit [31:0] XBAR_SLAVE_MASK [NUM_SLAVES] = '{
        32'hFF00_0000,            // S0: 0x8000_0000 ~ 0x8FFF_FFFF
        32'hFFF0_0000,            // S1: 0xA000_0000 ~ 0xAFFF_FFFF (tighter: 0xA00x)
        32'hFF00_0000             // S2: 0xB000_0000 ~ 0xBFFF_FFFF
    };

    // ========================================================
    // AXI signal arrays (packed: [NUM_MASTERS-1:0] or [NUM_SLAVES-1:0])
    // ========================================================

    // ---- Master-side signals (connected to crossbar) ----
    logic [NUM_MASTERS-1:0][31:0] xb_m_awaddr;
    logic [NUM_MASTERS-1:0][ 7:0] xb_m_awlen;
    logic [NUM_MASTERS-1:0][ 2:0] xb_m_awsize;
    logic [NUM_MASTERS-1:0][ 1:0] xb_m_awburst;
    logic [NUM_MASTERS-1:0]       xb_m_awlock;
    logic [NUM_MASTERS-1:0][ 3:0] xb_m_awcache;
    logic [NUM_MASTERS-1:0][ 2:0] xb_m_awprot;
    logic [NUM_MASTERS-1:0][ 3:0] xb_m_awqos;
    logic [NUM_MASTERS-1:0]       xb_m_awvalid;
    logic [NUM_MASTERS-1:0]       xb_m_awready;

    logic [NUM_MASTERS-1:0][31:0] xb_m_wdata;
    logic [NUM_MASTERS-1:0][ 3:0] xb_m_wstrb;
    logic [NUM_MASTERS-1:0]       xb_m_wlast;
    logic [NUM_MASTERS-1:0]       xb_m_wvalid;
    logic [NUM_MASTERS-1:0]       xb_m_wready;

    logic [NUM_MASTERS-1:0][ 1:0] xb_m_bresp;
    logic [NUM_MASTERS-1:0]       xb_m_bvalid;
    logic [NUM_MASTERS-1:0]       xb_m_bready;

    logic [NUM_MASTERS-1:0][31:0] xb_m_araddr;
    logic [NUM_MASTERS-1:0][ 7:0] xb_m_arlen;
    logic [NUM_MASTERS-1:0][ 2:0] xb_m_arsize;
    logic [NUM_MASTERS-1:0][ 1:0] xb_m_arburst;
    logic [NUM_MASTERS-1:0]       xb_m_arlock;
    logic [NUM_MASTERS-1:0][ 3:0] xb_m_arcache;
    logic [NUM_MASTERS-1:0][ 2:0] xb_m_arprot;
    logic [NUM_MASTERS-1:0][ 3:0] xb_m_arqos;
    logic [NUM_MASTERS-1:0]       xb_m_arvalid;
    logic [NUM_MASTERS-1:0]       xb_m_arready;

    logic [NUM_MASTERS-1:0][31:0] xb_m_rdata;
    logic [NUM_MASTERS-1:0][ 1:0] xb_m_rresp;
    logic [NUM_MASTERS-1:0]       xb_m_rlast;
    logic [NUM_MASTERS-1:0]       xb_m_rvalid;
    logic [NUM_MASTERS-1:0]       xb_m_rready;

    // ---- Slave-side signals (from crossbar) ----
    logic [NUM_SLAVES-1:0][31:0]  xb_s_awaddr;
    logic [NUM_SLAVES-1:0][ 7:0]  xb_s_awlen;
    logic [NUM_SLAVES-1:0][ 2:0]  xb_s_awsize;
    logic [NUM_SLAVES-1:0][ 1:0]  xb_s_awburst;
    logic [NUM_SLAVES-1:0]        xb_s_awlock;
    logic [NUM_SLAVES-1:0][ 3:0]  xb_s_awcache;
    logic [NUM_SLAVES-1:0][ 2:0]  xb_s_awprot;
    logic [NUM_SLAVES-1:0][ 3:0]  xb_s_awqos;
    logic [NUM_SLAVES-1:0]        xb_s_awvalid;
    logic [NUM_SLAVES-1:0]        xb_s_awready;

    logic [NUM_SLAVES-1:0][31:0]  xb_s_wdata;
    logic [NUM_SLAVES-1:0][ 3:0]  xb_s_wstrb;
    logic [NUM_SLAVES-1:0]        xb_s_wlast;
    logic [NUM_SLAVES-1:0]        xb_s_wvalid;
    logic [NUM_SLAVES-1:0]        xb_s_wready;

    logic [NUM_SLAVES-1:0][ 1:0]  xb_s_bresp;
    logic [NUM_SLAVES-1:0]        xb_s_bvalid;
    logic [NUM_SLAVES-1:0]        xb_s_bready;

    logic [NUM_SLAVES-1:0][31:0]  xb_s_araddr;
    logic [NUM_SLAVES-1:0][ 7:0]  xb_s_arlen;
    logic [NUM_SLAVES-1:0][ 2:0]  xb_s_arsize;
    logic [NUM_SLAVES-1:0][ 1:0]  xb_s_arburst;
    logic [NUM_SLAVES-1:0]        xb_s_arlock;
    logic [NUM_SLAVES-1:0][ 3:0]  xb_s_arcache;
    logic [NUM_SLAVES-1:0][ 2:0]  xb_s_arprot;
    logic [NUM_SLAVES-1:0][ 3:0]  xb_s_arqos;
    logic [NUM_SLAVES-1:0]        xb_s_arvalid;
    logic [NUM_SLAVES-1:0]        xb_s_arready;

    logic [NUM_SLAVES-1:0][31:0]  xb_s_rdata;
    logic [NUM_SLAVES-1:0][ 1:0]  xb_s_rresp;
    logic [NUM_SLAVES-1:0]        xb_s_rlast;
    logic [NUM_SLAVES-1:0]        xb_s_rvalid;
    logic [NUM_SLAVES-1:0]        xb_s_rready;

    // ========================================================
    // MMIO Decoder → Peripheral Register Interfaces
    // ========================================================
    // DMA
    logic        dma_reg_sel,  dma_reg_wen,  dma_reg_ren;
    logic [15:0] dma_reg_addr;
    logic [31:0] dma_reg_wdata, dma_reg_rdata;
    logic [ 3:0] dma_reg_wstrb;
    logic        dma_reg_rvalid;

    // NN Accelerator
    logic        nn_reg_sel,   nn_reg_wen,   nn_reg_ren;
    logic [15:0] nn_reg_addr;
    logic [31:0] nn_reg_wdata, nn_reg_rdata;
    logic [ 3:0] nn_reg_wstrb;
    logic        nn_reg_rvalid;

    // HDMI
    logic        hdmi_reg_sel,  hdmi_reg_wen,  hdmi_reg_ren;
    logic [15:0] hdmi_reg_addr;
    logic [31:0] hdmi_reg_wdata, hdmi_reg_rdata;
    logic [ 3:0] hdmi_reg_wstrb;
    logic        hdmi_reg_rvalid;

    // ========================================================
    // CPU (student_top_axi)
    // ========================================================
    student_top_axi #(
        .P_SW_CNT  (P_SW_CNT),
        .P_LED_CNT (P_LED_CNT),
        .P_SEG_CNT (P_SEG_CNT),
        .P_KEY_CNT (P_KEY_CNT)
    ) u_cpu (
        .w_cpu_clk      (w_cpu_clk),
        .w_clk_50Mhz    (w_clk_50Mhz),
        .w_clk_rst      (w_clk_rst),
        .virtual_key    (virtual_key),
        .virtual_sw     (virtual_sw),
        .virtual_led    (virtual_led),
        .virtual_seg    (virtual_seg),

        // AXI4 master → crossbar M0
        .m_axi_awaddr   (xb_m_awaddr  [0]),
        .m_axi_awlen    (xb_m_awlen   [0]),
        .m_axi_awsize   (xb_m_awsize  [0]),
        .m_axi_awburst  (xb_m_awburst [0]),
        .m_axi_awlock   (xb_m_awlock  [0]),
        .m_axi_awcache  (xb_m_awcache [0]),
        .m_axi_awprot   (xb_m_awprot  [0]),
        .m_axi_awqos    (xb_m_awqos   [0]),
        .m_axi_awvalid  (xb_m_awvalid [0]),
        .m_axi_awready  (xb_m_awready [0]),
        .m_axi_wdata    (xb_m_wdata   [0]),
        .m_axi_wstrb    (xb_m_wstrb   [0]),
        .m_axi_wlast    (xb_m_wlast   [0]),
        .m_axi_wvalid   (xb_m_wvalid  [0]),
        .m_axi_wready   (xb_m_wready  [0]),
        .m_axi_bresp    (xb_m_bresp   [0]),
        .m_axi_bvalid   (xb_m_bvalid  [0]),
        .m_axi_bready   (xb_m_bready  [0]),
        .m_axi_araddr   (xb_m_araddr  [0]),
        .m_axi_arlen    (xb_m_arlen   [0]),
        .m_axi_arsize   (xb_m_arsize  [0]),
        .m_axi_arburst  (xb_m_arburst [0]),
        .m_axi_arlock   (xb_m_arlock  [0]),
        .m_axi_arcache  (xb_m_arcache [0]),
        .m_axi_arprot   (xb_m_arprot  [0]),
        .m_axi_arqos    (xb_m_arqos   [0]),
        .m_axi_arvalid  (xb_m_arvalid [0]),
        .m_axi_arready  (xb_m_arready [0]),
        .m_axi_rdata    (xb_m_rdata   [0]),
        .m_axi_rresp    (xb_m_rresp   [0]),
        .m_axi_rlast    (xb_m_rlast   [0]),
        .m_axi_rvalid   (xb_m_rvalid  [0]),
        .m_axi_rready   (xb_m_rready  [0])
    );

    // ========================================================
    // DMA Engine (M1)
    // ========================================================
    logic dma_irq;

    dma_engine #(
        .FIFO_DEPTH (16),
        .MAX_BURST  (16)
    ) u_dma (
        .clk        (w_cpu_clk),
        .rst        (w_clk_rst),
        .reg_sel    (dma_reg_sel),
        .reg_addr   (dma_reg_addr),
        .reg_wdata  (dma_reg_wdata),
        .reg_wstrb  (dma_reg_wstrb),
        .reg_wen    (dma_reg_wen),
        .reg_ren    (dma_reg_ren),
        .reg_rdata  (dma_reg_rdata),
        .reg_rvalid (dma_reg_rvalid),
        .dma_irq    (dma_irq),

        // AXI master → crossbar M1
        .m_awaddr   (xb_m_awaddr  [1]),
        .m_awlen    (xb_m_awlen   [1]),
        .m_awsize   (xb_m_awsize  [1]),
        .m_awburst  (xb_m_awburst [1]),
        .m_awlock   (xb_m_awlock  [1]),
        .m_awcache  (xb_m_awcache [1]),
        .m_awprot   (xb_m_awprot  [1]),
        .m_awqos    (xb_m_awqos   [1]),
        .m_awvalid  (xb_m_awvalid [1]),
        .m_awready  (xb_m_awready [1]),
        .m_wdata    (xb_m_wdata   [1]),
        .m_wstrb    (xb_m_wstrb   [1]),
        .m_wlast    (xb_m_wlast   [1]),
        .m_wvalid   (xb_m_wvalid  [1]),
        .m_wready   (xb_m_wready  [1]),
        .m_bresp    (xb_m_bresp   [1]),
        .m_bvalid   (xb_m_bvalid  [1]),
        .m_bready   (xb_m_bready  [1]),
        .m_araddr   (xb_m_araddr  [1]),
        .m_arlen    (xb_m_arlen   [1]),
        .m_arsize   (xb_m_arsize  [1]),
        .m_arburst  (xb_m_arburst [1]),
        .m_arlock   (xb_m_arlock  [1]),
        .m_arcache  (xb_m_arcache [1]),
        .m_arprot   (xb_m_arprot  [1]),
        .m_arqos    (xb_m_arqos   [1]),
        .m_arvalid  (xb_m_arvalid [1]),
        .m_arready  (xb_m_arready [1]),
        .m_rdata    (xb_m_rdata   [1]),
        .m_rresp    (xb_m_rresp   [1]),
        .m_rlast    (xb_m_rlast   [1]),
        .m_rvalid   (xb_m_rvalid  [1]),
        .m_rready   (xb_m_rready  [1])
    );

    // ========================================================
    // NN Accelerator (M2)
    // ========================================================
    logic nn_irq;

    nn_accel_top #(
        .WEIGHT_BUF_DEPTH (256)
    ) u_nn_accel (
        .clk        (w_cpu_clk),
        .rst        (w_clk_rst),
        .reg_sel    (nn_reg_sel),
        .reg_addr   (nn_reg_addr),
        .reg_wdata  (nn_reg_wdata),
        .reg_wstrb  (nn_reg_wstrb),
        .reg_wen    (nn_reg_wen),
        .reg_ren    (nn_reg_ren),
        .reg_rdata  (nn_reg_rdata),
        .reg_rvalid (nn_reg_rvalid),
        .nn_irq     (nn_irq),

        // AXI master → crossbar M2
        .m_awaddr   (xb_m_awaddr  [2]),
        .m_awlen    (xb_m_awlen   [2]),
        .m_awsize   (xb_m_awsize  [2]),
        .m_awburst  (xb_m_awburst [2]),
        .m_awlock   (xb_m_awlock  [2]),
        .m_awcache  (xb_m_awcache [2]),
        .m_awprot   (xb_m_awprot  [2]),
        .m_awqos    (xb_m_awqos   [2]),
        .m_awvalid  (xb_m_awvalid [2]),
        .m_awready  (xb_m_awready [2]),
        .m_wdata    (xb_m_wdata   [2]),
        .m_wstrb    (xb_m_wstrb   [2]),
        .m_wlast    (xb_m_wlast   [2]),
        .m_wvalid   (xb_m_wvalid  [2]),
        .m_wready   (xb_m_wready  [2]),
        .m_bresp    (xb_m_bresp   [2]),
        .m_bvalid   (xb_m_bvalid  [2]),
        .m_bready   (xb_m_bready  [2]),
        .m_araddr   (xb_m_araddr  [2]),
        .m_arlen    (xb_m_arlen   [2]),
        .m_arsize   (xb_m_arsize  [2]),
        .m_arburst  (xb_m_arburst [2]),
        .m_arlock   (xb_m_arlock  [2]),
        .m_arcache  (xb_m_arcache [2]),
        .m_arprot   (xb_m_arprot  [2]),
        .m_arqos    (xb_m_arqos   [2]),
        .m_arvalid  (xb_m_arvalid [2]),
        .m_arready  (xb_m_arready [2]),
        .m_rdata    (xb_m_rdata   [2]),
        .m_rresp    (xb_m_rresp   [2]),
        .m_rlast    (xb_m_rlast   [2]),
        .m_rvalid   (xb_m_rvalid  [2]),
        .m_rready   (xb_m_rready  [2])
    );

    // ========================================================
    // HDMI Controller (M3)
    // ========================================================
    logic hdmi_irq;

    hdmi_controller #(
        .MAX_LINE_WIDTH (1024)
    ) u_hdmi (
        .clk        (w_cpu_clk),
        .rst        (w_clk_rst),
        .reg_sel    (hdmi_reg_sel),
        .reg_addr   (hdmi_reg_addr),
        .reg_wdata  (hdmi_reg_wdata),
        .reg_wstrb  (hdmi_reg_wstrb),
        .reg_wen    (hdmi_reg_wen),
        .reg_ren    (hdmi_reg_ren),
        .reg_rdata  (hdmi_reg_rdata),
        .reg_rvalid (hdmi_reg_rvalid),
        .hdmi_irq   (hdmi_irq),

        // AXI master → crossbar M3 (read-only)
        .m_araddr   (xb_m_araddr  [3]),
        .m_arlen    (xb_m_arlen   [3]),
        .m_arsize   (xb_m_arsize  [3]),
        .m_arburst  (xb_m_arburst [3]),
        .m_arlock   (xb_m_arlock  [3]),
        .m_arcache  (xb_m_arcache [3]),
        .m_arprot   (xb_m_arprot  [3]),
        .m_arqos    (xb_m_arqos   [3]),
        .m_arvalid  (xb_m_arvalid [3]),
        .m_arready  (xb_m_arready [3]),
        .m_rdata    (xb_m_rdata   [3]),
        .m_rresp    (xb_m_rresp   [3]),
        .m_rlast    (xb_m_rlast   [3]),
        .m_rvalid   (xb_m_rvalid  [3]),
        .m_rready   (xb_m_rready  [3]),

        // HDMI outputs
        .hdmi_clk   (hdmi_clk),
        .hdmi_hsync (hdmi_hsync),
        .hdmi_vsync (hdmi_vsync),
        .hdmi_de    (hdmi_de),
        .hdmi_rgb   (hdmi_rgb)
    );

    // HDMI is read-only master — tie off write channel
    assign xb_m_awvalid [3] = 1'b0;
    assign xb_m_wvalid  [3] = 1'b0;
    assign xb_m_bready  [3] = 1'b0;
    assign xb_m_awaddr  [3] = '0;
    assign xb_m_awlen   [3] = '0;
    assign xb_m_awsize  [3] = '0;
    assign xb_m_awburst [3] = '0;
    assign xb_m_awlock  [3] = 1'b0;
    assign xb_m_awcache [3] = '0;
    assign xb_m_awprot  [3] = '0;
    assign xb_m_awqos   [3] = '0;
    assign xb_m_wdata   [3] = '0;
    assign xb_m_wstrb   [3] = '0;
    assign xb_m_wlast   [3] = 1'b0;

    // ========================================================
    // AXI Crossbar (4 masters × 3 slaves)
    // ========================================================
    axi_crossbar #(
        .NUM_MASTERS (NUM_MASTERS),
        .NUM_SLAVES  (NUM_SLAVES),
        .ADDR_WIDTH  (32),
        .DATA_WIDTH  (32),
        .SLAVE_BASE  (XBAR_SLAVE_BASE),
        .SLAVE_MASK  (XBAR_SLAVE_MASK)
    ) u_crossbar (
        .clk         (w_cpu_clk),
        .rst         (w_clk_rst),

        // Master ports
        .m_awaddr    (xb_m_awaddr),
        .m_awlen     (xb_m_awlen),
        .m_awsize    (xb_m_awsize),
        .m_awburst   (xb_m_awburst),
        .m_awlock    (xb_m_awlock),
        .m_awcache   (xb_m_awcache),
        .m_awprot    (xb_m_awprot),
        .m_awqos     (xb_m_awqos),
        .m_awvalid   (xb_m_awvalid),
        .m_awready   (xb_m_awready),
        .m_wdata     (xb_m_wdata),
        .m_wstrb     (xb_m_wstrb),
        .m_wlast     (xb_m_wlast),
        .m_wvalid    (xb_m_wvalid),
        .m_wready    (xb_m_wready),
        .m_bresp     (xb_m_bresp),
        .m_bvalid    (xb_m_bvalid),
        .m_bready    (xb_m_bready),
        .m_araddr    (xb_m_araddr),
        .m_arlen     (xb_m_arlen),
        .m_arsize    (xb_m_arsize),
        .m_arburst   (xb_m_arburst),
        .m_arlock    (xb_m_arlock),
        .m_arcache   (xb_m_arcache),
        .m_arprot    (xb_m_arprot),
        .m_arqos     (xb_m_arqos),
        .m_arvalid   (xb_m_arvalid),
        .m_arready   (xb_m_arready),
        .m_rdata     (xb_m_rdata),
        .m_rresp     (xb_m_rresp),
        .m_rlast     (xb_m_rlast),
        .m_rvalid    (xb_m_rvalid),
        .m_rready    (xb_m_rready),

        // Slave ports
        .s_awaddr    (xb_s_awaddr),
        .s_awlen     (xb_s_awlen),
        .s_awsize    (xb_s_awsize),
        .s_awburst   (xb_s_awburst),
        .s_awlock    (xb_s_awlock),
        .s_awcache   (xb_s_awcache),
        .s_awprot    (xb_s_awprot),
        .s_awqos     (xb_s_awqos),
        .s_awvalid   (xb_s_awvalid),
        .s_awready   (xb_s_awready),
        .s_wdata     (xb_s_wdata),
        .s_wstrb     (xb_s_wstrb),
        .s_wlast     (xb_s_wlast),
        .s_wvalid    (xb_s_wvalid),
        .s_wready    (xb_s_wready),
        .s_bresp     (xb_s_bresp),
        .s_bvalid    (xb_s_bvalid),
        .s_bready    (xb_s_bready),
        .s_araddr    (xb_s_araddr),
        .s_arlen     (xb_s_arlen),
        .s_arsize    (xb_s_arsize),
        .s_arburst   (xb_s_arburst),
        .s_arlock    (xb_s_arlock),
        .s_arcache   (xb_s_arcache),
        .s_arprot    (xb_s_arprot),
        .s_arqos     (xb_s_arqos),
        .s_arvalid   (xb_s_arvalid),
        .s_arready   (xb_s_arready),
        .s_rdata     (xb_s_rdata),
        .s_rresp     (xb_s_rresp),
        .s_rlast     (xb_s_rlast),
        .s_rvalid    (xb_s_rvalid),
        .s_rready    (xb_s_rready)
    );

    // ========================================================
    // Slave 0: DDR (AXI RAM Slave — 256KB on-chip BRAM)
    // ========================================================
    axi_ram_slave #(
        .DEPTH_WORDS (DDR_DEPTH),
        .BASE_ADDR   (`SOC_ADDR_DDR_BASE),
        .ADDR_MASK   (32'hFF00_0000),
        .READ_LATENCY(2)
    ) u_ddr_ram (
        .clk        (w_cpu_clk),
        .rst        (w_clk_rst),
        .s_awaddr   (xb_s_awaddr  [0]),
        .s_awlen    (xb_s_awlen   [0]),
        .s_awsize   (xb_s_awsize  [0]),
        .s_awburst  (xb_s_awburst [0]),
        .s_awlock   (xb_s_awlock  [0]),
        .s_awcache  (xb_s_awcache [0]),
        .s_awprot   (xb_s_awprot  [0]),
        .s_awqos    (xb_s_awqos   [0]),
        .s_awvalid  (xb_s_awvalid [0]),
        .s_awready  (xb_s_awready [0]),
        .s_wdata    (xb_s_wdata   [0]),
        .s_wstrb    (xb_s_wstrb   [0]),
        .s_wlast    (xb_s_wlast   [0]),
        .s_wvalid   (xb_s_wvalid  [0]),
        .s_wready   (xb_s_wready  [0]),
        .s_bresp    (xb_s_bresp   [0]),
        .s_bvalid   (xb_s_bvalid  [0]),
        .s_bready   (xb_s_bready  [0]),
        .s_araddr   (xb_s_araddr  [0]),
        .s_arlen    (xb_s_arlen   [0]),
        .s_arsize   (xb_s_arsize  [0]),
        .s_arburst  (xb_s_arburst [0]),
        .s_arlock   (xb_s_arlock  [0]),
        .s_arcache  (xb_s_arcache [0]),
        .s_arprot   (xb_s_arprot  [0]),
        .s_arqos    (xb_s_arqos   [0]),
        .s_arvalid  (xb_s_arvalid [0]),
        .s_arready  (xb_s_arready [0]),
        .s_rdata    (xb_s_rdata   [0]),
        .s_rresp    (xb_s_rresp   [0]),
        .s_rlast    (xb_s_rlast   [0]),
        .s_rvalid   (xb_s_rvalid  [0]),
        .s_rready   (xb_s_rready  [0])
    );

    // ========================================================
    // Slave 1: SoC MMIO Decoder
    // ========================================================
    soc_mmio_decoder u_mmio_decoder (
        .clk            (w_cpu_clk),
        .rst            (w_clk_rst),
        .s_awaddr       (xb_s_awaddr  [1]),
        .s_awlen        (xb_s_awlen   [1]),
        .s_awsize       (xb_s_awsize  [1]),
        .s_awburst      (xb_s_awburst [1]),
        .s_awlock       (xb_s_awlock  [1]),
        .s_awcache      (xb_s_awcache [1]),
        .s_awprot       (xb_s_awprot  [1]),
        .s_awqos        (xb_s_awqos   [1]),
        .s_awvalid      (xb_s_awvalid [1]),
        .s_awready      (xb_s_awready [1]),
        .s_wdata        (xb_s_wdata   [1]),
        .s_wstrb        (xb_s_wstrb   [1]),
        .s_wlast        (xb_s_wlast   [1]),
        .s_wvalid       (xb_s_wvalid  [1]),
        .s_wready       (xb_s_wready  [1]),
        .s_bresp        (xb_s_bresp   [1]),
        .s_bvalid       (xb_s_bvalid  [1]),
        .s_bready       (xb_s_bready  [1]),
        .s_araddr       (xb_s_araddr  [1]),
        .s_arlen        (xb_s_arlen   [1]),
        .s_arsize       (xb_s_arsize  [1]),
        .s_arburst      (xb_s_arburst [1]),
        .s_arlock       (xb_s_arlock  [1]),
        .s_arcache      (xb_s_arcache [1]),
        .s_arprot       (xb_s_arprot  [1]),
        .s_arqos        (xb_s_arqos   [1]),
        .s_arvalid      (xb_s_arvalid [1]),
        .s_arready      (xb_s_arready [1]),
        .s_rdata        (xb_s_rdata   [1]),
        .s_rresp        (xb_s_rresp   [1]),
        .s_rlast        (xb_s_rlast   [1]),
        .s_rvalid       (xb_s_rvalid  [1]),
        .s_rready       (xb_s_rready  [1]),

        // Peripheral register interfaces
        .dma_reg_sel    (dma_reg_sel),
        .dma_reg_addr   (dma_reg_addr),
        .dma_reg_wdata  (dma_reg_wdata),
        .dma_reg_wstrb  (dma_reg_wstrb),
        .dma_reg_wen    (dma_reg_wen),
        .dma_reg_ren    (dma_reg_ren),
        .dma_reg_rdata  (dma_reg_rdata),
        .dma_reg_rvalid (dma_reg_rvalid),

        .nn_reg_sel     (nn_reg_sel),
        .nn_reg_addr    (nn_reg_addr),
        .nn_reg_wdata   (nn_reg_wdata),
        .nn_reg_wstrb   (nn_reg_wstrb),
        .nn_reg_wen     (nn_reg_wen),
        .nn_reg_ren     (nn_reg_ren),
        .nn_reg_rdata   (nn_reg_rdata),
        .nn_reg_rvalid  (nn_reg_rvalid),

        .hdmi_reg_sel   (hdmi_reg_sel),
        .hdmi_reg_addr  (hdmi_reg_addr),
        .hdmi_reg_wdata (hdmi_reg_wdata),
        .hdmi_reg_wstrb (hdmi_reg_wstrb),
        .hdmi_reg_wen   (hdmi_reg_wen),
        .hdmi_reg_ren   (hdmi_reg_ren),
        .hdmi_reg_rdata (hdmi_reg_rdata),
        .hdmi_reg_rvalid(hdmi_reg_rvalid)
    );

    // ========================================================
    // Slave 2: NC Buffer (AXI RAM Slave — 64KB on-chip BRAM)
    // ========================================================
    axi_ram_slave #(
        .DEPTH_WORDS (16384),   // 64KB
        .BASE_ADDR   (`SOC_ADDR_NC_BUFFER_BASE),
        .ADDR_MASK   (32'hFF00_0000),
        .READ_LATENCY(2)
    ) u_nc_buffer (
        .clk        (w_cpu_clk),
        .rst        (w_clk_rst),
        .s_awaddr   (xb_s_awaddr  [2]),
        .s_awlen    (xb_s_awlen   [2]),
        .s_awsize   (xb_s_awsize  [2]),
        .s_awburst  (xb_s_awburst [2]),
        .s_awlock   (xb_s_awlock  [2]),
        .s_awcache  (xb_s_awcache [2]),
        .s_awprot   (xb_s_awprot  [2]),
        .s_awqos    (xb_s_awqos   [2]),
        .s_awvalid  (xb_s_awvalid [2]),
        .s_awready  (xb_s_awready [2]),
        .s_wdata    (xb_s_wdata   [2]),
        .s_wstrb    (xb_s_wstrb   [2]),
        .s_wlast    (xb_s_wlast   [2]),
        .s_wvalid   (xb_s_wvalid  [2]),
        .s_wready   (xb_s_wready  [2]),
        .s_bresp    (xb_s_bresp   [2]),
        .s_bvalid   (xb_s_bvalid  [2]),
        .s_bready   (xb_s_bready  [2]),
        .s_araddr   (xb_s_araddr  [2]),
        .s_arlen    (xb_s_arlen   [2]),
        .s_arsize   (xb_s_arsize  [2]),
        .s_arburst  (xb_s_arburst [2]),
        .s_arlock   (xb_s_arlock  [2]),
        .s_arcache  (xb_s_arcache [2]),
        .s_arprot   (xb_s_arprot  [2]),
        .s_arqos    (xb_s_arqos   [2]),
        .s_arvalid  (xb_s_arvalid [2]),
        .s_arready  (xb_s_arready [2]),
        .s_rdata    (xb_s_rdata   [2]),
        .s_rresp    (xb_s_rresp   [2]),
        .s_rlast    (xb_s_rlast   [2]),
        .s_rvalid   (xb_s_rvalid  [2]),
        .s_rready   (xb_s_rready  [2])
    );

endmodule
