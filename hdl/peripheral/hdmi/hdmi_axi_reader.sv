// ============================================================
// Module: hdmi_axi_reader
// Description:
//   AXI read engine for HDMI frame buffer scan-out.
//
//   At the start of each video line, issues an AXI read burst
//   to fetch the next line from the frame buffer in DDR.
//   Received pixels are written into the line buffer.
//
//   Uses INCR bursts sized to the line width.
//   Pixel format: 32b per pixel (RGBx8888).
// ============================================================

module hdmi_axi_reader #(
    parameter int MAX_LINE_PIXELS = 1024
) (
    input  logic        clk,
    input  logic        rst,

    // ============================================================
    // Control interface
    // ============================================================
    input  logic        line_start,      // pulse: start fetching next line
    input  logic [31:0] fb_base_addr,    // frame buffer base address
    input  logic [15:0] line_width,      // pixels per line
    input  logic [15:0] line_stride,     // bytes per line (including any padding)
    input  logic [15:0] current_line,    // Y coordinate of line to fetch

    // ============================================================
    // Line buffer write interface
    // ============================================================
    output logic        buf_wr_en,
    output logic [ 9:0] buf_wr_addr,
    output logic [31:0] buf_wr_data,
    output logic        buf_wr_swap,     // pulse: swap write buffer

    // ============================================================
    // AXI Read Master
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
    output logic        m_rready
);

    localparam AXI_SIZE  = 3'd2;
    localparam AXI_BURST = 2'b01;

    typedef enum logic [1:0] {
        RD_IDLE,
        RD_ADDR,
        RD_DATA
    } rd_state_t;
    rd_state_t state;

    logic [ 7:0] rd_burst_len;
    logic [ 9:0] pixel_cnt;
    logic        swap_pending;

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            state       <= RD_IDLE;
            pixel_cnt   <= '0;
            buf_wr_en   <= 1'b0;
            buf_wr_addr <= '0;
            buf_wr_data <= '0;
            buf_wr_swap <= 1'b0;
            m_arvalid   <= 1'b0;
            m_rready    <= 1'b0;
            swap_pending <= 1'b0;
        end else begin
            // Default: pulse signals low
            buf_wr_en   <= 1'b0;
            buf_wr_swap <= 1'b0;

            case (state)
                RD_IDLE: begin
                    if (line_start) begin
                        // Calculate burst length for this line
                        rd_burst_len <= line_width[7:0] - 8'd1; // AXLEN = width - 1
                        pixel_cnt    <= '0;
                        m_araddr     <= fb_base_addr + (current_line * line_stride);
                        m_arlen      <= line_width[7:0] - 8'd1;
                        m_arvalid    <= 1'b1;
                        state        <= RD_ADDR;
                    end
                end

                RD_ADDR: begin
                    if (m_arvalid && m_arready) begin
                        m_arvalid <= 1'b0;
                        m_rready  <= 1'b1;
                        state     <= RD_DATA;
                    end
                end

                RD_DATA: begin
                    if (m_rvalid && m_rready) begin
                        // Write pixel to line buffer
                        buf_wr_en   <= 1'b1;
                        buf_wr_addr <= pixel_cnt;
                        buf_wr_data <= m_rdata;
                        pixel_cnt   <= pixel_cnt + 10'd1;

                        if (m_rlast) begin
                            m_rready  <= 1'b0;
                            buf_wr_swap <= 1'b1;
                            state     <= RD_IDLE;
                        end
                    end
                end
            endcase
        end
    end

    assign m_arsize  = AXI_SIZE;
    assign m_arburst = AXI_BURST;
    assign m_arlock  = 1'b0;
    assign m_arcache = 4'b0011;
    assign m_arprot  = 3'b000;
    assign m_arqos   = 4'b0000;

endmodule
