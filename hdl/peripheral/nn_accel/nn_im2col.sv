// ============================================================
// Module: nn_im2col
// Description:
//   Converts a convolution operation into a matrix multiplication
//   via the im2col (image-to-column) transformation.
//
//   For a Conv2D layer with:
//     - Input:  H×W×C_in
//     - Kernel: K_h×K_w×C_in×C_out
//     - Output: OH×OW×C_out
//
//   im2col transforms each K_h×K_w×C_in receptive field into
//   a column vector of length K_h*K_w*C_in. The result is a
//   matrix of size (K_h*K_w*C_in) × (OH*OW).
//
//   This module generates AXI read addresses for the input
//   feature map to load data in the correct im2col order.
//
//   Parameters are configured via input ports (from sequencer).
//
//   Simplified for 3×3 kernels (the most common case for our NN).
// ============================================================

module nn_im2col (
    input  logic        clk,
    input  logic        rst,

    // ============================================================
    // Configuration (from sequencer/registers)
    // ============================================================
    input  logic [ 7:0] in_h,           // input height
    input  logic [ 7:0] in_w,           // input width
    input  logic [ 7:0] in_ch,          // input channels
    input  logic [ 7:0] kernel_h,       // kernel height
    input  logic [ 7:0] kernel_w,       // kernel width
    input  logic [ 7:0] stride,         // stride
    input  logic [ 7:0] pad,            // padding

    // ============================================================
    // Control
    // ============================================================
    input  logic        start,           // start im2col generation
    output logic        done,            // all patches generated
    input  logic        next_patch,      // advance to next patch

    // ============================================================
    // Output: AXI read address for next input word
    // Each word contains 4 int8 activations (packed)
    // ============================================================
    output logic [31:0] axi_rd_addr,     // AXI address to read
    output logic        axi_rd_valid,    // address is valid
    output logic        is_last_patch    // this is the last patch
);

    // ============================================================
    // Derived dimensions
    // ============================================================
    logic [ 7:0] out_h, out_w;
    logic [15:0] total_patches;   // OH * OW
    logic [15:0] patch_size;      // K_h * K_w * ceil(C_in/4)

    assign out_h = ((in_h + 2*pad - kernel_h) / stride) + 8'd1;
    assign out_w = ((in_w + 2*pad - kernel_w) / stride) + 8'd1;
    assign total_patches = out_h * out_w;
    assign patch_size = kernel_h * kernel_w * ((in_ch + 3) / 4);  // ceil(C_in/4)

    // ============================================================
    // Patch counter state
    // ============================================================
    logic [15:0] patch_idx;      // which patch (0..total_patches-1)
    logic [15:0] elem_idx;       // which element within patch (0..patch_size-1)
    logic [ 7:0] oh, ow;         // output position
    logic [ 7:0] kh, kw;         // kernel position
    logic [ 7:0] ch_grp;         // channel group (4 channels per word)

    typedef enum logic [1:0] {
        I2C_IDLE,
        I2C_RUN,
        I2C_DONE
    } i2c_state_t;
    i2c_state_t state;

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            state     <= I2C_IDLE;
            patch_idx <= '0;
            elem_idx  <= '0;
            oh        <= '0;
            ow        <= '0;
            kh        <= '0;
            kw        <= '0;
            ch_grp    <= '0;
            done      <= 1'b0;
        end else begin
            case (state)
                I2C_IDLE: begin
                    done <= 1'b0;
                    if (start) begin
                        state     <= I2C_RUN;
                        patch_idx <= '0;
                        elem_idx  <= '0;
                        oh        <= '0;
                        ow        <= '0;
                        kh        <= '0;
                        kw        <= '0;
                        ch_grp    <= '0;
                    end
                end

                I2C_RUN: begin
                    if (next_patch) begin
                        // Advance through patch elements
                        if (elem_idx == patch_size - 1) begin
                            // Move to next patch
                            elem_idx <= '0;
                            kh       <= '0;
                            kw       <= '0;
                            ch_grp   <= '0;

                            if (patch_idx == total_patches - 1) begin
                                state <= I2C_DONE;
                                done  <= 1'b1;
                            end else begin
                                patch_idx <= patch_idx + 1;

                                // Update output position
                                if (ow == out_w - 1) begin
                                    ow <= '0;
                                    oh <= oh + 1;
                                end else begin
                                    ow <= ow + 1;
                                end
                            end
                        end else begin
                            elem_idx <= elem_idx + 1;

                            // Advance kernel position and channel
                            if (ch_grp == (in_ch + 3) / 4 - 1) begin
                                ch_grp <= '0;
                                if (kw == kernel_w - 1) begin
                                    kw <= '0;
                                    kh <= kh + 1;
                                end else begin
                                    kw <= kw + 1;
                                end
                            end else begin
                                ch_grp <= ch_grp + 1;
                            end
                        end
                    end
                end

                I2C_DONE: begin
                    done <= 1'b0;
                    if (!start)
                        state <= I2C_IDLE;
                end

                default: state <= I2C_IDLE;
            endcase
        end
    end

    // ============================================================
    // Compute AXI read address for current element
    // ============================================================
    // Input address for element (oh*stride+kh-pad, ow*stride+kw-pad, ch_grp*4)
    // Address = base + ((h * in_w + w) * ceil(C_in/4) + ch_grp) * 4
    // ============================================================
    logic signed [8:0] in_y, in_x;   // input coordinates (signed for pad check)
    logic        out_of_bounds;

    assign in_y = (oh * stride) + kh - pad;
    assign in_x = (ow * stride) + kw - pad;

    assign out_of_bounds = (in_y < 0) || (in_y >= in_h) ||
                           (in_x < 0) || (in_x >= in_w);

    // Address offset from base (in 32-bit words)
    logic [31:0] addr_offset;
    assign addr_offset = (out_of_bounds) ?
        32'hFFFF_FFFF :  // sentinel for zero-padding (handled by sequencer)
        (((in_y * in_w) + in_x) * ((in_ch + 3) / 4) + ch_grp);

    assign axi_rd_addr  = addr_offset;
    assign axi_rd_valid = (state == I2C_RUN);
    assign is_last_patch = (state == I2C_RUN) && (patch_idx == total_patches - 1) &&
                           (elem_idx == patch_size - 1);

endmodule
