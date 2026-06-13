// ============================================================
// Module: axi_interconnect
// Description:
//   Simple AXI4 address decoder / 1:N demux.
//   Routes a single AXI master to one of several slaves based
//   on the transaction address.
//
//   Upgrade to a full crossbar (N:M with arbitration) when a
//   second master (e.g. DMA) is added.
// ============================================================

`include "hdl/soc/address_map.svh"

module axi_interconnect (
    input  logic        clk,
    input  logic        rst,

    // ------------------------------------------------------------
    // Master 0 — CPU
    // ------------------------------------------------------------
    input  logic [31:0] m0_awaddr,
    input  logic [ 7:0] m0_awlen,
    input  logic [ 2:0] m0_awsize,
    input  logic [ 1:0] m0_awburst,
    input  logic        m0_awlock,
    input  logic [ 3:0] m0_awcache,
    input  logic [ 2:0] m0_awprot,
    input  logic [ 3:0] m0_awqos,
    input  logic        m0_awvalid,
    output logic        m0_awready,

    input  logic [31:0] m0_wdata,
    input  logic [ 3:0] m0_wstrb,
    input  logic        m0_wlast,
    input  logic        m0_wvalid,
    output logic        m0_wready,

    output logic [ 1:0] m0_bresp,
    output logic        m0_bvalid,
    input  logic        m0_bready,

    input  logic [31:0] m0_araddr,
    input  logic [ 7:0] m0_arlen,
    input  logic [ 2:0] m0_arsize,
    input  logic [ 1:0] m0_arburst,
    input  logic        m0_arlock,
    input  logic [ 3:0] m0_arcache,
    input  logic [ 2:0] m0_arprot,
    input  logic [ 3:0] m0_arqos,
    input  logic        m0_arvalid,
    output logic        m0_arready,

    output logic [31:0] m0_rdata,
    output logic [ 1:0] m0_rresp,
    output logic        m0_rlast,
    output logic        m0_rvalid,
    input  logic        m0_rready

    // ------------------------------------------------------------
    // Slave ports (TODO: add as peripherals are integrated)
    //
    // Slave 0: DDR controller
    // Slave 1: Accelerator control (AXI-Lite)
    // Slave 2: HDMI display controller
    // Slave 3: DMA engine
    // ------------------------------------------------------------
);

    // ------------------------------------------------------------
    // Default response: DECERR for unmapped addresses
    // ------------------------------------------------------------
    // For now, all AXI transactions from the CPU get a DECERR
    // response. This is a placeholder until real slaves are
    // connected.
    // ------------------------------------------------------------

    // Write address channel: stall indefinitely (no slave to accept)
    // In a real implementation, route to the correct slave based
    // on address decode.
    assign m0_awready = 1'b0;

    // Write data channel
    assign m0_wready  = 1'b0;

    // Write response channel
    assign m0_bresp   = 2'b11;  // DECERR
    assign m0_bvalid  = m0_awvalid;  // Respond to any write request
    // m0_bready is an input

    // Read address channel
    assign m0_arready = 1'b0;

    // Read data channel
    assign m0_rdata   = 32'hDEAD_BEEF;
    assign m0_rresp   = 2'b11;  // DECERR
    assign m0_rlast   = 1'b0;
    assign m0_rvalid  = 1'b0;

endmodule
