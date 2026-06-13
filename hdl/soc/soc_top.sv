// ============================================================
// Module: soc_top
// Description:
//   SoC integration top-level. Instantiates CPU IP and all
//   SoC peripherals (DDR, DMA, accelerator, HDMI).
//
//   CPU IP (jyd2026) exposes:
//     - AXI4 master (32b addr, 32b data) for external memory
//     - Local MMIO (LED, SW, KEY, SEG) — handled internally
//
//   This module only contains interconnect / bus fabric.
//   It does NOT modify IP internals.
// ============================================================

`include "hdl/soc/address_map.svh"

module soc_top #(
    parameter P_SW_CNT  = 64,
    parameter P_LED_CNT = 32,
    parameter P_SEG_CNT = 40,
    parameter P_KEY_CNT = 8
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
    // DDR PHY interface (placeholder)
    // ========================================================
    // TODO: connect to MIG/DDR controller

    // ========================================================
    // HDMI / display interface (placeholder)
    // ========================================================

    // ========================================================
    // Accelerator streaming interface (placeholder)
    // ========================================================
);

    // --------------------------------------------------------
    // CPU <-> AXI Interconnect
    // --------------------------------------------------------
    // Write address channel
    logic [31:0] cpu_axi_awaddr;
    logic [ 7:0] cpu_axi_awlen;
    logic [ 2:0] cpu_axi_awsize;
    logic [ 1:0] cpu_axi_awburst;
    logic        cpu_axi_awlock;
    logic [ 3:0] cpu_axi_awcache;
    logic [ 2:0] cpu_axi_awprot;
    logic [ 3:0] cpu_axi_awqos;
    logic        cpu_axi_awvalid;
    logic        cpu_axi_awready;

    // Write data channel
    logic [31:0] cpu_axi_wdata;
    logic [ 3:0] cpu_axi_wstrb;
    logic        cpu_axi_wlast;
    logic        cpu_axi_wvalid;
    logic        cpu_axi_wready;

    // Write response channel
    logic [ 1:0] cpu_axi_bresp;
    logic        cpu_axi_bvalid;
    logic        cpu_axi_bready;

    // Read address channel
    logic [31:0] cpu_axi_araddr;
    logic [ 7:0] cpu_axi_arlen;
    logic [ 2:0] cpu_axi_arsize;
    logic [ 1:0] cpu_axi_arburst;
    logic        cpu_axi_arlock;
    logic [ 3:0] cpu_axi_arcache;
    logic [ 2:0] cpu_axi_arprot;
    logic [ 3:0] cpu_axi_arqos;
    logic        cpu_axi_arvalid;
    logic        cpu_axi_arready;

    // Read data channel
    logic [31:0] cpu_axi_rdata;
    logic [ 1:0] cpu_axi_rresp;
    logic        cpu_axi_rlast;
    logic        cpu_axi_rvalid;
    logic        cpu_axi_rready;

    // --------------------------------------------------------
    // CPU IP (student_top_axi)
    // --------------------------------------------------------
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

        // AXI4 master
        .m_axi_awaddr   (cpu_axi_awaddr),
        .m_axi_awlen    (cpu_axi_awlen),
        .m_axi_awsize   (cpu_axi_awsize),
        .m_axi_awburst  (cpu_axi_awburst),
        .m_axi_awlock   (cpu_axi_awlock),
        .m_axi_awcache  (cpu_axi_awcache),
        .m_axi_awprot   (cpu_axi_awprot),
        .m_axi_awqos    (cpu_axi_awqos),
        .m_axi_awvalid  (cpu_axi_awvalid),
        .m_axi_awready  (cpu_axi_awready),
        .m_axi_wdata    (cpu_axi_wdata),
        .m_axi_wstrb    (cpu_axi_wstrb),
        .m_axi_wlast    (cpu_axi_wlast),
        .m_axi_wvalid   (cpu_axi_wvalid),
        .m_axi_wready   (cpu_axi_wready),
        .m_axi_bresp    (cpu_axi_bresp),
        .m_axi_bvalid   (cpu_axi_bvalid),
        .m_axi_bready   (cpu_axi_bready),
        .m_axi_araddr   (cpu_axi_araddr),
        .m_axi_arlen    (cpu_axi_arlen),
        .m_axi_arsize   (cpu_axi_arsize),
        .m_axi_arburst  (cpu_axi_arburst),
        .m_axi_arlock   (cpu_axi_arlock),
        .m_axi_arcache  (cpu_axi_arcache),
        .m_axi_arprot   (cpu_axi_arprot),
        .m_axi_arqos    (cpu_axi_arqos),
        .m_axi_arvalid  (cpu_axi_arvalid),
        .m_axi_arready  (cpu_axi_arready),
        .m_axi_rdata    (cpu_axi_rdata),
        .m_axi_rresp    (cpu_axi_rresp),
        .m_axi_rlast    (cpu_axi_rlast),
        .m_axi_rvalid   (cpu_axi_rvalid),
        .m_axi_rready   (cpu_axi_rready)
    );

    // --------------------------------------------------------
    // AXI Interconnect
    // TODO: replace with full crossbar when multiple masters
    //       (CPU + DMA) exist. For now, simple address decode.
    //
    //   CPU AXI master
    //        |
    //   axi_interconnect
    //        |-- DDR slave       (0x8030_0000 ~ 0x8FFF_FFFF)
    //        |-- SoC MMIO slaves (0xA000_0000 ~ 0xAFFF_FFFF)
    //        |-- NC buffer       (0xB000_0000 ~ 0xBFFF_FFFF)
    // --------------------------------------------------------
    axi_interconnect u_interconnect (
        .clk            (w_cpu_clk),
        .rst            (w_clk_rst),

        // Master 0: CPU
        .m0_awaddr      (cpu_axi_awaddr),
        .m0_awlen       (cpu_axi_awlen),
        .m0_awsize      (cpu_axi_awsize),
        .m0_awburst     (cpu_axi_awburst),
        .m0_awlock      (cpu_axi_awlock),
        .m0_awcache     (cpu_axi_awcache),
        .m0_awprot      (cpu_axi_awprot),
        .m0_awqos       (cpu_axi_awqos),
        .m0_awvalid     (cpu_axi_awvalid),
        .m0_awready     (cpu_axi_awready),
        .m0_wdata       (cpu_axi_wdata),
        .m0_wstrb       (cpu_axi_wstrb),
        .m0_wlast       (cpu_axi_wlast),
        .m0_wvalid      (cpu_axi_wvalid),
        .m0_wready      (cpu_axi_wready),
        .m0_bresp       (cpu_axi_bresp),
        .m0_bvalid      (cpu_axi_bvalid),
        .m0_bready      (cpu_axi_bready),
        .m0_araddr      (cpu_axi_araddr),
        .m0_arlen       (cpu_axi_arlen),
        .m0_arsize      (cpu_axi_arsize),
        .m0_arburst     (cpu_axi_arburst),
        .m0_arlock      (cpu_axi_arlock),
        .m0_arcache     (cpu_axi_arcache),
        .m0_arprot      (cpu_axi_arprot),
        .m0_arqos       (cpu_axi_arqos),
        .m0_arvalid     (cpu_axi_arvalid),
        .m0_arready     (cpu_axi_arready),
        .m0_rdata       (cpu_axi_rdata),
        .m0_rresp       (cpu_axi_rresp),
        .m0_rlast       (cpu_axi_rlast),
        .m0_rvalid      (cpu_axi_rvalid),
        .m0_rready      (cpu_axi_rready)

        // Master 1: DMA (TODO)
        // .m1_*

        // Slave 0: DDR (TODO)
        // .s0_*

        // Slave 1: Accelerator (TODO)
        // .s1_*

        // Slave 2: HDMI (TODO)
        // .s2_*
    );

endmodule
