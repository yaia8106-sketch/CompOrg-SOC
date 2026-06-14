// ============================================================
// Module: dma_engine
// Description:
//   Simple single-channel DMA engine with AXI4 master port.
//
//   Architecture:
//     Read Engine (AXI-Rd) → Data FIFO → Write Engine (AXI-Wr)
//
//   The read engine fetches data from the source address in
//   configurable burst lengths. Data passes through a FIFO.
//   The write engine drains the FIFO and writes to the
//   destination address.
//
//   Control via MMIO register interface (from soc_mmio_decoder).
//
//   Parameters:
//     FIFO_DEPTH — data FIFO depth in 32-bit words
//     MAX_BURST  — maximum AXI burst length in beats
// ============================================================

`include "hdl/peripheral/dma/dma_regs.svh"

module dma_engine #(
    parameter int FIFO_DEPTH = 16,
    parameter int MAX_BURST  = 16
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
    // Interrupt output
    // ============================================================
    output logic        dma_irq,

    // ============================================================
    // AXI4 Master Port
    // ============================================================
    // Write address channel
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

    // Write data channel
    output logic [31:0] m_wdata,
    output logic [ 3:0] m_wstrb,
    output logic        m_wlast,
    output logic        m_wvalid,
    input  logic        m_wready,

    // Write response channel
    input  logic [ 1:0] m_bresp,
    input  logic        m_bvalid,
    output logic        m_bready,

    // Read address channel
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

    // Read data channel
    input  logic [31:0] m_rdata,
    input  logic [ 1:0] m_rresp,
    input  logic        m_rlast,
    input  logic        m_rvalid,
    output logic        m_rready
);

    // ============================================================
    // AXI constants (fixed for this DMA)
    // ============================================================
    localparam AXI_SIZE  = 3'd2;     // 4 bytes per beat
    localparam AXI_BURST = 2'b01;    // INCR

    // ============================================================
    // Internal registers
    // ============================================================
    logic [31:0] src_addr;
    logic [31:0] dst_addr;
    logic [31:0] xfer_len;       // remaining bytes to transfer
    logic        ctrl_start;
    logic        ctrl_irq_en;
    logic        status_busy;
    logic        status_done;
    logic        status_error;
    logic [ 7:0] burst_len;      // configured burst length (1-16)

    // ============================================================
    // Data FIFO
    // ============================================================
    logic [31:0] fifo_mem [FIFO_DEPTH];
    logic [$clog2(FIFO_DEPTH):0] fifo_wr_ptr;  // write pointer (one extra bit for full/empty)
    logic [$clog2(FIFO_DEPTH):0] fifo_rd_ptr;

    wire fifo_full  = (fifo_wr_ptr[$clog2(FIFO_DEPTH)] != fifo_rd_ptr[$clog2(FIFO_DEPTH)]) &&
                      (fifo_wr_ptr[$clog2(FIFO_DEPTH)-1:0] == fifo_rd_ptr[$clog2(FIFO_DEPTH)-1:0]);
    wire fifo_empty = (fifo_wr_ptr == fifo_rd_ptr);
    wire fifo_wen;
    wire fifo_ren;

    // Write side
    always_ff @(posedge clk) begin
        if (fifo_wen)
            fifo_mem[fifo_wr_ptr[$clog2(FIFO_DEPTH)-1:0]] <= m_rdata;
    end

    // Read side
    logic [31:0] fifo_rdata;
    assign fifo_rdata = fifo_mem[fifo_rd_ptr[$clog2(FIFO_DEPTH)-1:0]];

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            fifo_wr_ptr <= '0;
            fifo_rd_ptr <= '0;
        end else begin
            if (fifo_wen)
                fifo_wr_ptr <= fifo_wr_ptr + 1;
            if (fifo_ren)
                fifo_rd_ptr <= fifo_rd_ptr + 1;
        end
    end

    // ============================================================
    // DMA FSM
    // ============================================================
    typedef enum logic [2:0] {
        DMA_IDLE,
        DMA_RD_REQ,        // Issue AXI read request
        DMA_RD_DATA,       // Receive AXI read data → FIFO
        DMA_WR_REQ,        // Issue AXI write request
        DMA_WR_DATA,       // Send AXI write data ← FIFO
        DMA_WR_RESP,       // Wait for write response
        DMA_DONE,
        DMA_ERR
    } dma_state_t;
    dma_state_t state;

    // Transfer tracking
    logic [31:0] xfer_remaining;   // bytes remaining in current transfer
    logic [31:0] current_src;
    logic [31:0] current_dst;
    logic [ 7:0] rd_beat_cnt;
    logic [ 7:0] wr_beat_cnt;
    logic [ 7:0] pending_burst_len; // how many beats for current sub-transfer

    // AXI master FSM outputs
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            state             <= DMA_IDLE;
            xfer_remaining    <= '0;
            current_src       <= '0;
            current_dst       <= '0;
            rd_beat_cnt       <= '0;
            wr_beat_cnt       <= '0;
            pending_burst_len <= '0;
            status_busy       <= 1'b0;
            status_done       <= 1'b0;
            status_error      <= 1'b0;
        end else begin
            case (state)
                DMA_IDLE: begin
                    if (ctrl_start) begin
                        xfer_remaining <= xfer_len;
                        current_src    <= src_addr;
                        current_dst    <= dst_addr;
                        status_busy    <= 1'b1;
                        status_done    <= 1'b0;
                        status_error   <= 1'b0;
                        state          <= DMA_RD_REQ;
                    end
                end

                // ---- Read Phase ----
                DMA_RD_REQ: begin
                    if (m_arvalid && m_arready) begin
                        state <= DMA_RD_DATA;
                    end
                end

                DMA_RD_DATA: begin
                    if (m_rvalid && m_rready) begin
                        rd_beat_cnt <= rd_beat_cnt + 8'd1;
                        if (m_rlast) begin
                            state <= DMA_WR_REQ;
                            wr_beat_cnt <= '0;
                            // pending_burst_len = number of beats read
                            pending_burst_len <= rd_beat_cnt + 8'd1;
                            rd_beat_cnt <= '0;
                        end
                    end
                    // Check for AXI read error
                    if (m_rvalid && m_rready && m_rresp != 2'b00) begin
                        state <= DMA_ERR;
                    end
                end

                // ---- Write Phase ----
                DMA_WR_REQ: begin
                    if (m_awvalid && m_awready) begin
                        state <= DMA_WR_DATA;
                    end
                end

                DMA_WR_DATA: begin
                    if (m_wvalid && m_wready) begin
                        wr_beat_cnt <= wr_beat_cnt + 8'd1;
                        if (m_wlast) begin
                            state <= DMA_WR_RESP;
                        end
                    end
                end

                DMA_WR_RESP: begin
                    if (m_bvalid && m_bready) begin
                        // Check for AXI write error
                        if (m_bresp != 2'b00) begin
                            state <= DMA_ERR;
                        end else begin
                            // Update pointers
                            current_src <= current_src + (pending_burst_len << 2);
                            current_dst <= current_dst + (pending_burst_len << 2);
                            xfer_remaining <= xfer_remaining - (pending_burst_len << 2);

                            // More data to transfer?
                            if (xfer_remaining <= (pending_burst_len << 2)) begin
                                state <= DMA_DONE;
                            end else if (!fifo_empty) begin
                                // FIFO has data from next read burst already
                                state <= DMA_WR_REQ;
                            end else begin
                                state <= DMA_RD_REQ;
                            end
                        end
                    end
                end

                DMA_DONE: begin
                    status_busy  <= 1'b0;
                    status_done  <= 1'b1;
                    state        <= DMA_IDLE;
                end

                DMA_ERR: begin
                    status_busy  <= 1'b0;
                    status_error <= 1'b1;
                    state        <= DMA_IDLE;
                end

                default: state <= DMA_IDLE;
            endcase
        end
    end

    // ============================================================
    // Compute AXI read request parameters
    // ============================================================
    logic [7:0] rd_burst;
    always_comb begin
        // Burst length = min(burst_len, remaining bytes/4 - 1)
        // but capped at MAX_BURST-1 and must not overflow FIFO
        logic [31:0] remain_beats;
        remain_beats = xfer_remaining >> 2;  // bytes → beats
        if (remain_beats > {24'd0, burst_len})
            rd_burst = burst_len - 8'd1;       // AXLEN = burst_len - 1
        else if (remain_beats > 0)
            rd_burst = remain_beats[7:0] - 8'd1;
        else
            rd_burst = 8'd0;
    end

    // ============================================================
    // AXI Read Master signals
    // ============================================================
    assign m_araddr  = current_src;
    assign m_arlen   = rd_burst;
    assign m_arsize  = AXI_SIZE;
    assign m_arburst = AXI_BURST;
    assign m_arlock  = 1'b0;
    assign m_arcache = 4'b0011;
    assign m_arprot  = 3'b000;
    assign m_arqos   = 4'b0000;
    assign m_arvalid = (state == DMA_RD_REQ) && !fifo_full;
    assign m_rready  = (state == DMA_RD_DATA) && !fifo_full;

    assign fifo_wen  = m_rvalid && m_rready;

    // ============================================================
    // AXI Write Master signals
    // ============================================================
    assign m_awaddr  = current_dst;
    assign m_awlen   = pending_burst_len - 8'd1;  // 0-based length
    assign m_awsize  = AXI_SIZE;
    assign m_awburst = AXI_BURST;
    assign m_awlock  = 1'b0;
    assign m_awcache = 4'b0011;
    assign m_awprot  = 3'b000;
    assign m_awqos   = 4'b0000;
    assign m_awvalid = (state == DMA_WR_REQ) && !fifo_empty;

    assign m_wdata   = fifo_rdata;
    assign m_wstrb   = 4'b1111;   // full word writes for DMA
    assign m_wlast   = (wr_beat_cnt == pending_burst_len - 1);
    assign m_wvalid  = (state == DMA_WR_DATA) && !fifo_empty;
    assign m_bready  = (state == DMA_WR_RESP);

    assign fifo_ren  = m_wvalid && m_wready;

    // ============================================================
    // Interrupt
    // ============================================================
    assign dma_irq = ctrl_irq_en && (status_done || status_error);

    // ============================================================
    // MMIO Register Read/Write
    // ============================================================
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            src_addr    <= '0;
            dst_addr    <= '0;
            xfer_len    <= '0;
            ctrl_start  <= 1'b0;
            ctrl_irq_en <= 1'b0;
            burst_len   <= 8'd4;  // default 4-beat bursts
        end else begin
            // Self-clearing start bit
            ctrl_start <= 1'b0;

            if (reg_sel && reg_wen) begin
                case (reg_addr)
                    `DMA_REG_SRC_ADDR: begin
                        if (reg_wstrb[0]) src_addr[ 7: 0] <= reg_wdata[ 7: 0];
                        if (reg_wstrb[1]) src_addr[15: 8] <= reg_wdata[15: 8];
                        if (reg_wstrb[2]) src_addr[23:16] <= reg_wdata[23:16];
                        if (reg_wstrb[3]) src_addr[31:24] <= reg_wdata[31:24];
                    end
                    `DMA_REG_DST_ADDR: begin
                        if (reg_wstrb[0]) dst_addr[ 7: 0] <= reg_wdata[ 7: 0];
                        if (reg_wstrb[1]) dst_addr[15: 8] <= reg_wdata[15: 8];
                        if (reg_wstrb[2]) dst_addr[23:16] <= reg_wdata[23:16];
                        if (reg_wstrb[3]) dst_addr[31:24] <= reg_wdata[31:24];
                    end
                    `DMA_REG_XFER_LEN: begin
                        if (reg_wstrb[0]) xfer_len[ 7: 0] <= reg_wdata[ 7: 0];
                        if (reg_wstrb[1]) xfer_len[15: 8] <= reg_wdata[15: 8];
                        if (reg_wstrb[2]) xfer_len[23:16] <= reg_wdata[23:16];
                        if (reg_wstrb[3]) xfer_len[31:24] <= reg_wdata[31:24];
                    end
                    `DMA_REG_CTRL: begin
                        if (reg_wstrb[0]) begin
                            ctrl_start  <= reg_wdata[`DMA_CTRL_START];
                            ctrl_irq_en <= reg_wdata[`DMA_CTRL_IRQ_EN];
                        end
                    end
                    `DMA_REG_BURST_LEN: begin
                        if (reg_wstrb[0]) burst_len <= reg_wdata[7:0];
                    end
                    default: ;
                endcase
            end

            // Clear done/error on status read (optional) or on new start
            if (ctrl_start)
                {status_done, status_error} <= 2'b00;
        end
    end

    // MMIO read mux
    always_comb begin
        reg_rdata  = 32'h0000_0000;
        reg_rvalid = 1'b0;

        if (reg_sel && reg_ren) begin
            reg_rvalid = 1'b1;
            case (reg_addr)
                `DMA_REG_SRC_ADDR:  reg_rdata = src_addr;
                `DMA_REG_DST_ADDR:  reg_rdata = dst_addr;
                `DMA_REG_XFER_LEN:  reg_rdata = xfer_len;
                `DMA_REG_CTRL:      reg_rdata = {30'd0, ctrl_irq_en, 1'b0, ctrl_start};
                `DMA_REG_STATUS:    reg_rdata = {29'd0, status_error, status_done, status_busy};
                `DMA_REG_BURST_LEN: reg_rdata = {24'd0, burst_len};
                default:            reg_rdata = 32'hDEAD_BEEF;
            endcase
        end
    end

`ifndef SYNTHESIS
    // Assertions
    property p_no_overflow;
        @(posedge clk) (state == DMA_RD_DATA && m_rvalid && m_rready) |-> !fifo_full;
    endproperty
    a_no_overflow: assert property(p_no_overflow)
        else $error("[DMA] FIFO overflow detected");

    property p_no_underflow;
        @(posedge clk) (state == DMA_WR_DATA && m_wvalid && m_wready) |-> !fifo_empty;
    endproperty
    a_no_underflow: assert property(p_no_underflow)
        else $error("[DMA] FIFO underflow detected");
`endif

endmodule
