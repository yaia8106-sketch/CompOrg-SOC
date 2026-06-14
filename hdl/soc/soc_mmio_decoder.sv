// ============================================================
// Module: soc_mmio_decoder
// Description:
//   AXI4 slave that decodes the SoC MMIO region
//   (0xA000_0000 ~ 0xA0FF_FFFF) into per-peripheral register
//   access ports.
//
//   Each peripheral gets a 64KB window with simple 32-bit
//   register R/W interface. Only single-beat transactions
//   are supported (AXI4-Lite-like).
//
//   Peripheral address map:
//     0xA000_0000 — DMA       (dma_reg_*)
//     0xA001_0000 — NN Accel  (nn_reg_*)
//     0xA002_0000 — HDMI      (hdmi_reg_*)
// ============================================================

module soc_mmio_decoder (
    input  logic        clk,
    input  logic        rst,

    // ============================================================
    // AXI4 slave (from crossbar)
    // ============================================================
    input  logic [31:0] s_awaddr,
    input  logic [ 7:0] s_awlen,
    input  logic [ 2:0] s_awsize,
    input  logic [ 1:0] s_awburst,
    input  logic        s_awlock,
    input  logic [ 3:0] s_awcache,
    input  logic [ 2:0] s_awprot,
    input  logic [ 3:0] s_awqos,
    input  logic        s_awvalid,
    output logic        s_awready,

    input  logic [31:0] s_wdata,
    input  logic [ 3:0] s_wstrb,
    input  logic        s_wlast,
    input  logic        s_wvalid,
    output logic        s_wready,

    output logic [ 1:0] s_bresp,
    output logic        s_bvalid,
    input  logic        s_bready,

    input  logic [31:0] s_araddr,
    input  logic [ 7:0] s_arlen,
    input  logic [ 2:0] s_arsize,
    input  logic [ 1:0] s_arburst,
    input  logic        s_arlock,
    input  logic [ 3:0] s_arcache,
    input  logic [ 2:0] s_arprot,
    input  logic [ 3:0] s_arqos,
    input  logic        s_arvalid,
    output logic        s_arready,

    output logic [31:0] s_rdata,
    output logic [ 1:0] s_rresp,
    output logic        s_rlast,
    output logic        s_rvalid,
    input  logic        s_rready,

    // ============================================================
    // DMA Register Interface
    // ============================================================
    output logic        dma_reg_sel,
    output logic [15:0] dma_reg_addr,
    output logic [31:0] dma_reg_wdata,
    output logic [ 3:0] dma_reg_wstrb,
    output logic        dma_reg_wen,
    output logic        dma_reg_ren,
    input  logic [31:0] dma_reg_rdata,
    input  logic        dma_reg_rvalid,

    // ============================================================
    // NN Accelerator Register Interface
    // ============================================================
    output logic        nn_reg_sel,
    output logic [15:0] nn_reg_addr,
    output logic [31:0] nn_reg_wdata,
    output logic [ 3:0] nn_reg_wstrb,
    output logic        nn_reg_wen,
    output logic        nn_reg_ren,
    input  logic [31:0] nn_reg_rdata,
    input  logic        nn_reg_rvalid,

    // ============================================================
    // HDMI Controller Register Interface
    // ============================================================
    output logic        hdmi_reg_sel,
    output logic [15:0] hdmi_reg_addr,
    output logic [31:0] hdmi_reg_wdata,
    output logic [ 3:0] hdmi_reg_wstrb,
    output logic        hdmi_reg_wen,
    output logic        hdmi_reg_ren,
    input  logic [31:0] hdmi_reg_rdata,
    input  logic        hdmi_reg_rvalid
);

    // ============================================================
    // Address decode
    // ============================================================
    // Which peripheral does the address target?
    //   [31:16] = 0xA000 → DMA
    //   [31:16] = 0xA001 → NN Accel
    //   [31:16] = 0xA002 → HDMI
    // ============================================================
    typedef enum logic [1:0] {
        PERIPH_DMA  = 2'b00,
        PERIPH_NN   = 2'b01,
        PERIPH_HDMI = 2'b10,
        PERIPH_NONE = 2'b11
    } periph_sel_t;

    function automatic periph_sel_t addr_to_periph(logic [31:0] addr);
        case (addr[31:16])
            16'hA000: return PERIPH_DMA;
            16'hA001: return PERIPH_NN;
            16'hA002: return PERIPH_HDMI;
            default:  return PERIPH_NONE;
        endcase
    endfunction

    // ============================================================
    // Write path (single-beat only)
    // ============================================================
    typedef enum logic [1:0] {
        WR_IDLE,
        WR_WAIT_DATA,
        WR_SEND_RESP
    } wr_state_t;
    wr_state_t wr_st;

    periph_sel_t wr_periph;
    logic [15:0] wr_reg_addr;   // offset within peripheral's 64KB window
    logic [31:0] wr_wdata;
    logic [ 3:0] wr_wstrb;

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            wr_st       <= WR_IDLE;
            wr_periph   <= PERIPH_NONE;
            wr_reg_addr <= '0;
            wr_wdata    <= '0;
            wr_wstrb    <= '0;
        end else begin
            case (wr_st)
                WR_IDLE: begin
                    if (s_awvalid && s_awready) begin
                        wr_periph   <= addr_to_periph(s_awaddr);
                        wr_reg_addr <= s_awaddr[15:0];
                        wr_st       <= WR_WAIT_DATA;
                    end
                end

                WR_WAIT_DATA: begin
                    if (s_wvalid && s_wready) begin
                        wr_wdata <= s_wdata;
                        wr_wstrb <= s_wstrb;
                        wr_st    <= WR_SEND_RESP;
                    end
                end

                WR_SEND_RESP: begin
                    if (s_bvalid && s_bready) begin
                        wr_st <= WR_IDLE;
                    end
                end

                default: wr_st <= WR_IDLE;
            endcase
        end
    end

    assign s_awready = (wr_st == WR_IDLE) && (addr_to_periph(s_awaddr) != PERIPH_NONE);
    assign s_wready  = (wr_st == WR_WAIT_DATA);
    assign s_bvalid  = (wr_st == WR_SEND_RESP);
    assign s_bresp   = 2'b00;  // OKAY

    // Write strobes to peripherals (pulsed)
    assign dma_reg_sel   = (wr_periph == PERIPH_DMA);
    assign dma_reg_addr  = wr_reg_addr;
    assign dma_reg_wdata = wr_wdata;
    assign dma_reg_wstrb = wr_wstrb;
    assign dma_reg_wen   = (wr_st == WR_SEND_RESP);  // pulse on entering resp state
    assign dma_reg_ren   = 1'b0;

    assign nn_reg_sel    = (wr_periph == PERIPH_NN);
    assign nn_reg_addr   = wr_reg_addr;
    assign nn_reg_wdata  = wr_wdata;
    assign nn_reg_wstrb  = wr_wstrb;
    assign nn_reg_wen    = (wr_st == WR_SEND_RESP) && (wr_periph == PERIPH_NN);
    assign nn_reg_ren    = 1'b0;

    assign hdmi_reg_sel  = (wr_periph == PERIPH_HDMI);
    assign hdmi_reg_addr = wr_reg_addr;
    assign hdmi_reg_wdata = wr_wdata;
    assign hdmi_reg_wstrb = wr_wstrb;
    assign hdmi_reg_wen   = (wr_st == WR_SEND_RESP) && (wr_periph == PERIPH_HDMI);
    assign hdmi_reg_ren   = 1'b0;

    // ============================================================
    // Read path (single-beat only)
    // ============================================================
    typedef enum logic [1:0] {
        RD_IDLE,
        RD_WAIT_PERIPH,
        RD_SEND_DATA
    } rd_state_t;
    rd_state_t rd_st;

    periph_sel_t rd_periph;
    logic [15:0] rd_reg_addr;

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            rd_st       <= RD_IDLE;
            rd_periph   <= PERIPH_NONE;
            rd_reg_addr <= '0;
        end else begin
            case (rd_st)
                RD_IDLE: begin
                    if (s_arvalid && s_arready) begin
                        rd_periph   <= addr_to_periph(s_araddr);
                        rd_reg_addr <= s_araddr[15:0];
                        rd_st       <= RD_WAIT_PERIPH;
                    end
                end

                RD_WAIT_PERIPH: begin
                    // Wait 1 cycle for peripheral to respond
                    rd_st <= RD_SEND_DATA;
                end

                RD_SEND_DATA: begin
                    if (s_rvalid && s_rready) begin
                        rd_st <= RD_IDLE;
                    end
                end

                default: rd_st <= RD_IDLE;
            endcase
        end
    end

    assign s_arready = (rd_st == RD_IDLE) && (addr_to_periph(s_araddr) != PERIPH_NONE);
    assign s_rvalid  = (rd_st == RD_SEND_DATA);
    assign s_rlast   = 1'b1;  // single beat
    assign s_rresp   = 2'b00; // OKAY

    // Read data mux from the selected peripheral
    always_comb begin
        case (rd_periph)
            PERIPH_DMA:  s_rdata = dma_reg_rdata;
            PERIPH_NN:   s_rdata = nn_reg_rdata;
            PERIPH_HDMI: s_rdata = hdmi_reg_rdata;
            default:     s_rdata = 32'hDEAD_BEEF;
        endcase
    end

    // Read strobes to peripherals
    assign dma_reg_ren  = (rd_st == RD_WAIT_PERIPH) && (rd_periph == PERIPH_DMA);
    assign nn_reg_ren   = (rd_st == RD_WAIT_PERIPH) && (rd_periph == PERIPH_NN);
    assign hdmi_reg_ren = (rd_st == RD_WAIT_PERIPH) && (rd_periph == PERIPH_HDMI);

    // Write-side read strobes (set to 0, reads only happen on read path)
    // Note: reg_sel is OR of write-side and read-side selection
    // For simplicity, reg_sel indicates any access (read or write)

`ifndef SYNTHESIS
    // Check single-beat only
    property p_single_beat_aw;
        @(posedge clk) (s_awvalid && s_awready) |-> (s_awlen == 8'd0);
    endproperty
    a_single_beat_aw: assert property(p_single_beat_aw)
        else $error("[MMIO_DEC] Write burst not supported (awlen=%0d)", s_awlen);

    property p_single_beat_ar;
        @(posedge clk) (s_arvalid && s_arready) |-> (s_arlen == 8'd0);
    endproperty
    a_single_beat_ar: assert property(p_single_beat_ar)
        else $error("[MMIO_DEC] Read burst not supported (arlen=%0d)", s_arlen);
`endif

endmodule
