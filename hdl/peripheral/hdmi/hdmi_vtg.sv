// ============================================================
// Module: hdmi_vtg
// Description:
//   Video Timing Generator for VGA/HDMI display output.
//
//   Generates horizontal and vertical sync signals along with
//   pixel position counters and data enable.
//
//   Supports configurable timing parameters for different
//   resolutions (640×480, 800×600, 1280×720).
//
//   Pixel clock: 25 MHz (derived from 200MHz ÷ 8 externally,
//   or generated internally with a clock enable).
//   This module uses a pixel_clk_ena strobe from the 200MHz
//   system clock domain.
// ============================================================

`include "hdl/peripheral/hdmi/hdmi_regs.svh"

module hdmi_vtg (
    input  logic        clk,           // system clock (200MHz)
    input  logic        rst,
    input  logic        pix_clk_ena,   // pixel clock enable strobe (25MHz)

    // Timing parameters (from registers)
    input  logic [15:0] h_active,
    input  logic [15:0] h_fporch,
    input  logic [15:0] h_sync,
    input  logic [15:0] h_bporch,
    input  logic [15:0] v_active,
    input  logic [15:0] v_fporch,
    input  logic [15:0] v_sync,
    input  logic [15:0] v_bporch,

    // Timing outputs
    output logic        hsync,
    output logic        vsync,
    output logic        de,            // data enable (active video)
    output logic [15:0] pixel_x,       // current pixel X (0..h_active-1)
    output logic [15:0] pixel_y,       // current pixel Y (0..v_active-1)
    output logic        frame_start,   // pulse at start of new frame
    output logic        line_start     // pulse at start of new line
);

    // ============================================================
    // Derived timing
    // ============================================================
    logic [15:0] h_total, v_total;
    logic [15:0] h_sync_start, h_sync_end;
    logic [15:0] h_active_end;
    logic [15:0] v_sync_start, v_sync_end;
    logic [15:0] v_active_end;

    assign h_total      = h_active + h_fporch + h_sync + h_bporch;
    assign h_sync_start = h_active + h_fporch;
    assign h_sync_end   = h_sync_start + h_sync;
    assign h_active_end = h_active;

    assign v_total      = v_active + v_fporch + v_sync + v_bporch;
    assign v_sync_start = v_active + v_fporch;
    assign v_sync_end   = v_sync_start + v_sync;
    assign v_active_end = v_active;

    // ============================================================
    // Pixel counters
    // ============================================================
    logic [15:0] h_cnt, v_cnt;
    logic        in_active;

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            h_cnt <= '0;
            v_cnt <= '0;
        end else if (pix_clk_ena) begin
            if (h_cnt == h_total - 1) begin
                h_cnt <= '0;
                if (v_cnt == v_total - 1)
                    v_cnt <= '0;
                else
                    v_cnt <= v_cnt + 16'd1;
            end else begin
                h_cnt <= h_cnt + 16'd1;
            end
        end
    end

    // ============================================================
    // Sync and DE generation
    // ============================================================
    assign hsync = (h_cnt >= h_sync_start) && (h_cnt < h_sync_end);
    assign vsync = (v_cnt >= v_sync_start) && (v_cnt < v_sync_end);
    assign de    = (h_cnt < h_active) && (v_cnt < v_active);

    // ============================================================
    // Pixel position outputs (valid during active video)
    // ============================================================
    assign pixel_x = (de) ? h_cnt : '0;
    assign pixel_y = (de) ? v_cnt : '0;

    // ============================================================
    // Frame / line start pulses
    // ============================================================
    assign frame_start = pix_clk_ena && (h_cnt == '0) && (v_cnt == '0);
    assign line_start  = pix_clk_ena && (h_cnt == '0) && de;

endmodule
