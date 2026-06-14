/**
 * gomoku_nn.h — NN Accelerator driver interface.
 *
 * Uses the NN accelerator at MMIO base 0xA001_0000.
 * Layer execution is configured via registers, then
 * the START bit triggers hardware execution.
 */

#ifndef GOMOKU_NN_H
#define GOMOKU_NN_H

#include <stdint.h>

// NN Accelerator MMIO base address
#define NN_ACCEL_BASE   0xA0010000

// Register offsets (from nn_regs.svh)
#define NN_REG_CTRL         0x00
#define NN_REG_STATUS       0x04
#define NN_REG_LAYER_TYPE   0x08
#define NN_REG_INPUT_ADDR   0x0C
#define NN_REG_WEIGHT_ADDR  0x10
#define NN_REG_OUTPUT_ADDR  0x14
#define NN_REG_BIAS_ADDR    0x18
#define NN_REG_INPUT_DIM    0x1C
#define NN_REG_INPUT_CH     0x20
#define NN_REG_OUTPUT_DIM   0x24
#define NN_REG_OUTPUT_CH    0x28
#define NN_REG_KERNEL       0x2C
#define NN_REG_STRIDE_PAD   0x30
#define NN_REG_POOL_SIZE    0x34

// Layer types
#define NN_LAYER_CONV2D     0
#define NN_LAYER_FC         1
#define NN_LAYER_RELU       2
#define NN_LAYER_MAXPOOL    3
#define NN_LAYER_GLOBALAVG  4

// Control bits
#define NN_CTRL_START       (1 << 0)
#define NN_CTRL_IRQ_EN      (1 << 1)

// Status bits
#define NN_STATUS_BUSY      (1 << 0)
#define NN_STATUS_DONE      (1 << 1)
#define NN_STATUS_ERROR     (1 << 2)

/**
 * Write to an NN accelerator register.
 */
static inline void nn_write_reg(uint32_t offset, uint32_t value) {
    volatile uint32_t *reg = (volatile uint32_t *)(NN_ACCEL_BASE + offset);
    *reg = value;
}

/**
 * Read from an NN accelerator register.
 */
static inline uint32_t nn_read_reg(uint32_t offset) {
    volatile uint32_t *reg = (volatile uint32_t *)(NN_ACCEL_BASE + offset);
    return *reg;
}

/**
 * Wait for accelerator to finish current operation.
 */
static inline void nn_wait_done(void) {
    while (nn_read_reg(NN_REG_STATUS) & NN_STATUS_BUSY) {
        // spin-wait
    }
}

/**
 * Execute a Conv2D layer on the accelerator.
 *
 * @param input_addr   DDR address of input feature map (int8 packed)
 * @param weight_addr  DDR address of weights (int8 packed, 4 per word)
 * @param bias_addr    DDR address of bias values
 * @param output_addr  DDR address for output feature map
 * @param in_h         Input height
 * @param in_w         Input width
 * @param in_ch        Input channels
 * @param out_ch       Output channels
 * @param kernel       Kernel size (3 for 3×3)
 * @param stride       Stride (1 or 2)
 * @param pad          Padding (0 or 1)
 * @param with_relu    Apply ReLU after conv (1=yes, 0=no)
 */
void nn_execute_conv2d(uint32_t input_addr, uint32_t weight_addr,
                       uint32_t bias_addr, uint32_t output_addr,
                       int in_h, int in_w, int in_ch, int out_ch,
                       int kernel, int stride, int pad, int with_relu);

/**
 * Execute a Fully-Connected layer.
 */
void nn_execute_fc(uint32_t input_addr, uint32_t weight_addr,
                   uint32_t bias_addr, uint32_t output_addr,
                   int in_features, int out_features, int with_relu);

/**
 * Execute ReLU activation in-place.
 */
void nn_execute_relu(uint32_t data_addr, int num_elements);

/**
 * Execute Global Average Pooling.
 */
void nn_execute_global_avg_pool(uint32_t input_addr, uint32_t output_addr,
                                int h, int w, int channels);

/**
 * Run full Gomoku CNN inference.
 *
 * Input:  15×15×4 board tensor (int8, packed 4 per word)
 * Output: policy[225] (float-ish scores) and value (single score)
 *
 * Returns the value (position evaluation, approximately -1 to 1).
 * Policy scores are written to policy_out buffer.
 */
float gomoku_nn_inference(const int8_t *board_input,
                          float *policy_out);

#endif /* GOMOKU_NN_H */
