// ============================================================
// Module: hdmi_controller
// Description:
//   HDMI display controller top-level. Integrates:
//     - Video Timing Generator (VTG)
//     - AXI frame buffer reader
//     - Double-buffered line buffer
//     - Pixel output
//     - MMIO register file
//
//   Resolution: configurable, default 640×480 @ 60Hz
//   Pixel clock: system clock / 8 (25 MHz for 200 MHz sys clk)
//   Pixel format: RGB888 (32-bit packed, top byte ignored)
//
//   Scan flow:
//     1. At line_start, AXI reader fetches next line from DDR
//     2. Pixels stream into write-buffer
//     3. At line swap, buffers flip: write → read, read → write
//     4. VTG drives hsync/vsync/de based on timing params
//     5. Pixel output muxes from read-buffer during active video
// ============================================================

`include "hdl/peripheral/hdmi/hdmi_regs.svh"

module hdmi_controller #(
    parameter int MAX_LINE_WIDTH = 1024
) (
    input  logic        clk,              // 200 MHz system clock
    input  logic        rst,

    // ============================================================
    // MMIO Register Interface
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
    output logic        hdmi_irq,

    // ============================================================
    // AXI4 Master Port (frame buffer read)
    // ============================================================
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
    output logic        m_rready,

    // ============================================================
    // HDMI output signals (synchronous to pixel clock domain)
    // ============================================================
    output logic        hdmi_clk,     // pixel clock (25 MHz)
    output logic        hdmi_hsync,
    output logic        hdmi_vsync,
    output logic        hdmi_de,
    output logic [23:0] hdmi_rgb      // RGB888
);

    // ============================================================
    // Pixel clock generation (200 MHz / 8 = 25 MHz)
    // ============================================================
    logic [2:0] pix_clk_div;
    logic       pix_clk_ena;

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            pix_clk_div <= '0;
            pix_clk_ena <= 1'b0;
        end else begin
            pix_clk_div <= pix_clk_div + 3'd1;
            pix_clk_ena <= (pix_clk_div == 3'd0);
        end
    end

    // Pixel clock output (25 MHz, derived from 200 MHz / 8)
    assign hdmi_clk = pix_clk_div[2];  // 25 MHz toggle

    // ============================================================
    // Registers
    // ============================================================
    logic        ctrl_enable, ctrl_irq_vsync;
    logic [31:0] fb_addr;
    logic [15:0] h_active, v_active;
    logic [15:0] line_stride;
    logic [15:0] hsync_pulse, vsync_pulse, h_bporch, v_bporch;
    logic [15:0] h_fporch, v_fporch;

    // ============================================================
    // VTG signals
    // ============================================================
    logic        vtg_hsync, vtg_vsync, vtg_de;
    logic [15:0] vtg_pixel_x, vtg_pixel_y;
    logic        vtg_frame_start, vtg_line_start;

    // ============================================================
    // AXI reader → line buffer
    // ============================================================
    logic        buf_wr_en, buf_wr_swap;
    logic [ 9:0] buf_wr_addr;
    logic [31:0] buf_wr_data;

    // Line buffer → pixel output
    logic        buf_rd_en;
    logic [ 9:0] buf_rd_addr;
    logic        buf_rd_swap;
    logic [31:0] buf_rd_data;
    logic        buf_underrun;

    // ============================================================
    // VTG instantiation
    // ============================================================
    hdmi_vtg u_vtg (
        .clk         (clk),
        .rst         (rst),
        .pix_clk_ena (pix_clk_ena),
        .h_active    (h_active),
        .h_fporch    (h_fporch),
        .h_sync      (hsync_pulse),
        .h_bporch    (h_bporch),
        .v_active    (v_active),
        .v_fporch    (v_fporch),
        .v_sync      (vsync_pulse),
        .v_bporch    (v_bporch),
        .hsync       (vtg_hsync),
        .vsync       (vtg_vsync),
        .de          (vtg_de),
        .pixel_x     (vtg_pixel_x),
        .pixel_y     (vtg_pixel_y),
        .frame_start (vtg_frame_start),
        .line_start  (vtg_line_start)
    );

    // ============================================================
    // AXI frame buffer reader
    // ============================================================
    hdmi_axi_reader #(
        .MAX_LINE_PIXELS (MAX_LINE_WIDTH)
    ) u_axi_reader (
        .clk          (clk),
        .rst          (rst),
        .line_start   (vtg_line_start && ctrl_enable),
        .fb_base_addr (fb_addr),
        .line_width   (h_active),
        .line_stride  (line_stride),
        .current_line (vtg_pixel_y),
        .buf_wr_en    (buf_wr_en),
        .buf_wr_addr  (buf_wr_addr),
        .buf_wr_data  (buf_wr_data),
        .buf_wr_swap  (buf_wr_swap),
        .m_araddr     (m_araddr),
        .m_arlen      (m_arlen),
        .m_arsize     (m_arsize),
        .m_arburst    (m_arburst),
        .m_arlock     (m_arlock),
        .m_arcache    (m_arcache),
        .m_arprot     (m_arprot),
        .m_arqos      (m_arqos),
        .m_arvalid    (m_arvalid),
        .m_arready    (m_arready),
        .m_rdata      (m_rdata),
        .m_rresp      (m_rresp),
        .m_rlast      (m_rlast),
        .m_rvalid     (m_rvalid),
        .m_rready     (m_rready)
    );

    // ============================================================
    // Line buffer
    // ============================================================
    hdmi_linebuf #(
        .MAX_LINE_WIDTH (MAX_LINE_WIDTH)
    ) u_linebuf (
        .clk        (clk),
        .rst        (rst),
        .wr_en      (buf_wr_en),
        .wr_addr    (buf_wr_addr),
        .wr_data    (buf_wr_data),
        .wr_swap    (buf_wr_swap),
        .rd_en      (vtg_de && pix_clk_ena),
        .rd_addr    (vtg_pixel_x[9:0]),
        .rd_swap    (vtg_line_start && ctrl_enable),
        .rd_data    (buf_rd_data),
        .wr_underrun(buf_underrun)
    );

    // ============================================================
    // HDMI output (registered on pixel clock enable)
    // ============================================================
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            hdmi_hsync <= 1'b0;
            hdmi_vsync <= 1'b0;
            hdmi_de    <= 1'b0;
            hdmi_rgb   <= '0;
        end else if (pix_clk_ena) begin
            hdmi_hsync <= vtg_hsync;
            hdmi_vsync <= vtg_vsync;
            hdmi_de    <= vtg_de && ctrl_enable;
            hdmi_rgb   <= vtg_de ? buf_rd_data[23:0] : 24'h00_00_00;
        end
    end

    // ============================================================
    // Interrupt (vsync)
    // ============================================================
    logic vsync_latched;
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            vsync_latched <= 1'b0;
        end else begin
            if (vtg_frame_start)
                vsync_latched <= 1'b1;
            else if (reg_sel && reg_wen && reg_addr == `HDMI_REG_STATUS)
                vsync_latched <= 1'b0;  // clear on status read
        end
    end
    assign hdmi_irq = ctrl_irq_vsync && vsync_latched;

    // ============================================================
    // MMIO Register File
    // ============================================================
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            ctrl_enable    <= 1'b0;
            ctrl_irq_vsync <= 1'b0;
            fb_addr        <= `SOC_ADDR_DDR_BASE + 32'h0100_0000;  // default: DDR + 16MB
            h_active       <= `HDMI_640x480_H_ACTIVE;
            v_active       <= `HDMI_640x480_V_ACTIVE;
            line_stride    <= `HDMI_640x480_H_ACTIVE * 4;
            hsync_pulse    <= `HDMI_640x480_H_SYNC;
            vsync_pulse    <= `HDMI_640x480_V_SYNC;
            h_bporch       <= `HDMI_640x480_H_BPORCH;
            v_bporch       <= `HDMI_640x480_V_BPORCH;
            h_fporch       <= `HDMI_640x480_H_FPORCH;
            v_fporch       <= `HDMI_640x480_V_FPORCH;
        end else begin
            if (reg_sel && reg_wen) begin
                case (reg_addr)
                    `HDMI_REG_CTRL: begin
                        ctrl_enable    <= reg_wdata[`HDMI_CTRL_ENABLE];
                        ctrl_irq_vsync <= reg_wdata[`HDMI_CTRL_IRQ_VSYNC];
                    end
                    `HDMI_REG_FB_ADDR:     fb_addr     <= reg_wdata;
                    `HDMI_REG_RESOLUTION:  {h_active, v_active} <= reg_wdata;
                    `HDMI_REG_LINE_STRIDE: line_stride <= reg_wdata[15:0];
                    `HDMI_REG_HSYNC_PULSE: hsync_pulse <= reg_wdata[15:0];
                    `HDMI_REG_VSYNC_PULSE: vsync_pulse <= reg_wdata[15:0];
                    `HDMI_REG_H_BPORCH:    h_bporch    <= reg_wdata[15:0];
                    `HDMI_REG_V_BPORCH:    v_bporch    <= reg_wdata[15:0];
                    `HDMI_REG_H_FPORCH:    h_fporch    <= reg_wdata[15:0];
                    `HDMI_REG_V_FPORCH:    v_fporch    <= reg_wdata[15:0];
                    default: ;
                endcase
            end
        end
    end

    // MMIO read
    always_comb begin
        reg_rdata  = 32'h0000_0000;
        reg_rvalid = 1'b0;

        if (reg_sel && reg_ren) begin
            reg_rvalid = 1'b1;
            case (reg_addr)
                `HDMI_REG_CTRL:        reg_rdata = {30'd0, ctrl_irq_vsync, ctrl_enable};
                `HDMI_REG_STATUS:      reg_rdata = {29'd0, buf_underrun, vsync_latched, ctrl_enable};
                `HDMI_REG_FB_ADDR:     reg_rdata = fb_addr;
                `HDMI_REG_RESOLUTION:  reg_rdata = {h_active, v_active};
                `HDMI_REG_LINE_STRIDE: reg_rdata = {16'd0, line_stride};
                `HDMI_REG_HSYNC_PULSE: reg_rdata = {16'd0, hsync_pulse};
                `HDMI_REG_VSYNC_PULSE: reg_rdata = {16'd0, vsync_pulse};
                `HDMI_REG_H_BPORCH:    reg_rdata = {16'd0, h_bporch};
                `HDMI_REG_V_BPORCH:    reg_rdata = {16'd0, v_bporch};
                `HDMI_REG_H_FPORCH:    reg_rdata = {16'd0, h_fporch};
                `HDMI_REG_V_FPORCH:    reg_rdata = {16'd0, v_fporch};
                default:               reg_rdata = 32'hDEAD_BEEF;
            endcase
        end
    end

endmodule
