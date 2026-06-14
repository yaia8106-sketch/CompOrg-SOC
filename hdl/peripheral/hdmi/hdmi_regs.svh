// ============================================================
// HDMI Controller Register Definitions
// ============================================================
`ifndef HDMI_REGS_SVH
`define HDMI_REGS_SVH

`define HDMI_REG_CTRL         16'h0000   // R/W: control
`define HDMI_REG_STATUS       16'h0004   // R:   status
`define HDMI_REG_FB_ADDR      16'h0008   // R/W: frame buffer base address
`define HDMI_REG_RESOLUTION   16'h000C   // R/W: {h_active[15:0], v_active[15:0]}
`define HDMI_REG_LINE_STRIDE  16'h0010   // R/W: bytes per line (width * 4)
`define HDMI_REG_HSYNC_PULSE  16'h0014   // R/W: hsync pulse width in pixels
`define HDMI_REG_VSYNC_PULSE  16'h0018   // R/W: vsync pulse width in lines
`define HDMI_REG_H_BPORCH     16'h001C   // R/W: horizontal back porch
`define HDMI_REG_V_BPORCH     16'h0020   // R/W: vertical back porch
`define HDMI_REG_H_FPORCH     16'h0024   // R/W: horizontal front porch
`define HDMI_REG_V_FPORCH     16'h0028   // R/W: vertical front porch

// CTRL bits
`define HDMI_CTRL_ENABLE       0
`define HDMI_CTRL_IRQ_VSYNC    1

// STATUS bits
`define HDMI_STATUS_RUNNING    0
`define HDMI_STATUS_VSYNC      1
`define HDMI_STATUS_UNDERRUN   2

// Default 640x480 @ 60Hz timing (25.175 MHz pixel clock)
// We use 25 MHz for simplicity (divide 200MHz by 8)
`define HDMI_640x480_H_ACTIVE   640
`define HDMI_640x480_H_FPORCH   16
`define HDMI_640x480_H_SYNC     96
`define HDMI_640x480_H_BPORCH   48
`define HDMI_640x480_H_TOTAL    800

`define HDMI_640x480_V_ACTIVE   480
`define HDMI_640x480_V_FPORCH   10
`define HDMI_640x480_V_SYNC     2
`define HDMI_640x480_V_BPORCH   33
`define HDMI_640x480_V_TOTAL    525

`endif /* HDMI_REGS_SVH */
