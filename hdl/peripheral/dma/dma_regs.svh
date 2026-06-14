// ============================================================
// DMA Register Definitions
// ============================================================
`ifndef DMA_REGS_SVH
`define DMA_REGS_SVH

// Register offsets (word-aligned)
`define DMA_REG_SRC_ADDR      16'h0000   // R/W: source address
`define DMA_REG_DST_ADDR      16'h0004   // R/W: destination address
`define DMA_REG_XFER_LEN      16'h0008   // R/W: transfer length (bytes)
`define DMA_REG_CTRL          16'h000C   // R/W: control register
`define DMA_REG_STATUS        16'h0010   // R:   status register
`define DMA_REG_BURST_LEN     16'h0014   // R/W: AXI burst length (1-16 beats)

// DMA_CTRL bits
`define DMA_CTRL_START        0    // Write 1 to start transfer (self-clearing)
`define DMA_CTRL_IRQ_EN       1    // Interrupt enable on completion
`define DMA_CTRL_DIR_S2D      2    // 0=memory→peripheral, 1=peripheral→memory (reserved)

// DMA_STATUS bits
`define DMA_STATUS_BUSY       0    // Transfer in progress
`define DMA_STATUS_DONE       1    // Transfer complete (write 1 to clear)
`define DMA_STATUS_ERROR      2    // Transfer error (AXI DECERR/SLVERR)

`endif /* DMA_REGS_SVH */
