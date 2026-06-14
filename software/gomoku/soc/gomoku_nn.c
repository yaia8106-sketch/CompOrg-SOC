/**
 * gomoku_nn.c — NN Accelerator driver implementation.
 */

#include "gomoku_nn.h"

// DDR memory layout for NN data buffers
// (These overlap with temporary workspaces; manage carefully.)
#define NN_INPUT_BUF    0x80310000   // 4KB for input tensor
#define NN_OUTPUT_BUF   0x80311000   // 4KB for output tensor
#define NN_WEIGHT_BUF   0x80320000   // 32KB for preloaded weights
#define NN_TEMP_BUF     0x80330000   // 16KB temporary workspace

void nn_execute_conv2d(uint32_t input_addr, uint32_t weight_addr,
                       uint32_t bias_addr, uint32_t output_addr,
                       int in_h, int in_w, int in_ch, int out_ch,
                       int kernel, int stride, int pad, int with_relu) {
    nn_wait_done();

    nn_write_reg(NN_REG_INPUT_ADDR,  input_addr);
    nn_write_reg(NN_REG_WEIGHT_ADDR, weight_addr);
    nn_write_reg(NN_REG_BIAS_ADDR,   bias_addr);
    nn_write_reg(NN_REG_OUTPUT_ADDR, output_addr);
    nn_write_reg(NN_REG_INPUT_DIM,   ((in_h & 0xFF) << 8) | (in_w & 0xFF));
    nn_write_reg(NN_REG_INPUT_CH,    in_ch);
    nn_write_reg(NN_REG_OUTPUT_CH,   out_ch);

    int out_h = (in_h + 2*pad - kernel) / stride + 1;
    int out_w = (in_w + 2*pad - kernel) / stride + 1;
    nn_write_reg(NN_REG_OUTPUT_DIM,  ((out_h & 0xFF) << 8) | (out_w & 0xFF));
    nn_write_reg(NN_REG_KERNEL,      ((kernel & 0xFF) << 8) | (kernel & 0xFF));
    nn_write_reg(NN_REG_STRIDE_PAD,  ((stride & 0xFF) << 8) | (pad & 0xFF));
    nn_write_reg(NN_REG_LAYER_TYPE,  with_relu ? NN_LAYER_CONV2D : NN_LAYER_CONV2D);
    // Note: ReLU after Conv2D is handled by the Conv2D path in hardware
    // For separate ReLU, use nn_execute_relu()

    // Start
    nn_write_reg(NN_REG_CTRL, NN_CTRL_START);
}

void nn_execute_fc(uint32_t input_addr, uint32_t weight_addr,
                   uint32_t bias_addr, uint32_t output_addr,
                   int in_features, int out_features, int with_relu) {
    nn_wait_done();

    nn_write_reg(NN_REG_INPUT_ADDR,  input_addr);
    nn_write_reg(NN_REG_WEIGHT_ADDR, weight_addr);
    nn_write_reg(NN_REG_BIAS_ADDR,   bias_addr);
    nn_write_reg(NN_REG_OUTPUT_ADDR, output_addr);
    nn_write_reg(NN_REG_INPUT_DIM,   in_features & 0xFFFF);
    nn_write_reg(NN_REG_INPUT_CH,    1);
    nn_write_reg(NN_REG_OUTPUT_DIM,  out_features & 0xFFFF);
    nn_write_reg(NN_REG_OUTPUT_CH,   1);
    nn_write_reg(NN_REG_LAYER_TYPE,  NN_LAYER_FC);

    nn_write_reg(NN_REG_CTRL, NN_CTRL_START);

    if (with_relu) {
        nn_wait_done();
        // FC output at output_addr; apply ReLU in-place
        // (handled by sequencer or separate ReLU pass)
    }
}

void nn_execute_relu(uint32_t data_addr, int num_elements) {
    nn_wait_done();

    nn_write_reg(NN_REG_INPUT_ADDR,  data_addr);
    nn_write_reg(NN_REG_OUTPUT_ADDR, data_addr);  // in-place
    nn_write_reg(NN_REG_INPUT_DIM,   num_elements & 0xFFFF);
    nn_write_reg(NN_REG_LAYER_TYPE,  NN_LAYER_RELU);

    nn_write_reg(NN_REG_CTRL, NN_CTRL_START);
}

void nn_execute_global_avg_pool(uint32_t input_addr, uint32_t output_addr,
                                int h, int w, int channels) {
    nn_wait_done();

    nn_write_reg(NN_REG_INPUT_ADDR,  input_addr);
    nn_write_reg(NN_REG_OUTPUT_ADDR, output_addr);
    nn_write_reg(NN_REG_INPUT_DIM,   ((h & 0xFF) << 8) | (w & 0xFF));
    nn_write_reg(NN_REG_INPUT_CH,    channels);
    nn_write_reg(NN_REG_OUTPUT_DIM,  1);
    nn_write_reg(NN_REG_OUTPUT_CH,   channels);
    nn_write_reg(NN_REG_LAYER_TYPE,  NN_LAYER_GLOBALAVG);

    nn_write_reg(NN_REG_CTRL, NN_CTRL_START);
}

// ============================================================
// Helper: quantize float input to int8 and copy to DDR
// ============================================================
static void quantize_input(const float *src, int8_t *dst, int count) {
    // Simple symmetric quantization: scale is fixed at 1/127
    // Inputs are in [0, 1], map to [0, 127]
    for (int i = 0; i < count; i++) {
        int val = (int)(src[i] * 127.0f);
        if (val > 127) val = 127;
        if (val < 0)   val = 0;
        dst[i] = (int8_t)val;
    }
}

// ============================================================
// Full Gomoku CNN inference
// ============================================================
float gomoku_nn_inference(const int8_t *board_input, float *policy_out) {
    // Step 1: Conv2D 4→16, 3×3, pad=1, stride=1 → 15×15×16
    nn_execute_conv2d(
        (uint32_t)(uintptr_t)board_input,  // input: 15×15×4 int8
        NN_WEIGHT_BUF + 0x0000,            // conv1 weights
        NN_WEIGHT_BUF + 0x1000,            // conv1 bias
        NN_TEMP_BUF,                       // output → temp buf
        15, 15, 4, 16, 3, 1, 1, 1  // ReLU included
    );
    nn_wait_done();

    // Step 2: Conv2D 16→32, 3×3, pad=1, stride=1 → 15×15×32
    nn_execute_conv2d(
        NN_TEMP_BUF,                       // input from step 1
        NN_WEIGHT_BUF + 0x2000,            // conv2 weights
        NN_WEIGHT_BUF + 0x3000,            // conv2 bias
        NN_OUTPUT_BUF,                     // output → output buf
        15, 15, 16, 32, 3, 1, 1, 1
    );
    nn_wait_done();

    // Step 3: Conv2D 32→16, 3×3, pad=1, stride=1 → 15×15×16
    nn_execute_conv2d(
        NN_OUTPUT_BUF,
        NN_WEIGHT_BUF + 0x4000,
        NN_WEIGHT_BUF + 0x5000,
        NN_TEMP_BUF,
        15, 15, 32, 16, 3, 1, 1, 1
    );
    nn_wait_done();

    // Step 4: Policy head — Conv2D 1×1, 16→1 → 15×15×1
    nn_execute_conv2d(
        NN_TEMP_BUF,
        NN_WEIGHT_BUF + 0x6000,
        NN_WEIGHT_BUF + 0x7000,
        NN_OUTPUT_BUF,
        15, 15, 16, 1, 1, 1, 0, 0  // no ReLU for policy
    );
    nn_wait_done();

    // Read policy from NN_OUTPUT_BUF (15×15 = 225 int8 values)
    volatile int8_t *policy_buf = (volatile int8_t *)NN_OUTPUT_BUF;
    float policy_sum = 0.0f;
    for (int i = 0; i < 225; i++) {
        policy_out[i] = (float)policy_buf[i];
        policy_sum += policy_out[i];
    }
    // Softmax normalization (simplified: just normalize)
    if (policy_sum > 0) {
        for (int i = 0; i < 225; i++)
            policy_out[i] /= policy_sum;
    }

    // Step 5: Value head — GlobalAvgPool → FC 16→64 → ReLU → FC 64→1 → Tanh
    nn_execute_global_avg_pool(NN_TEMP_BUF, NN_OUTPUT_BUF, 15, 15, 16);
    nn_wait_done();

    nn_execute_fc(NN_OUTPUT_BUF,
                  NN_WEIGHT_BUF + 0x8000,
                  NN_WEIGHT_BUF + 0x9000,
                  NN_TEMP_BUF,
                  16, 64, 1);
    nn_wait_done();

    nn_execute_fc(NN_TEMP_BUF,
                  NN_WEIGHT_BUF + 0xA000,
                  NN_WEIGHT_BUF + 0xB000,
                  NN_OUTPUT_BUF,
                  64, 1, 0);
    nn_wait_done();

    // Read value (single int8, scale back to float)
    volatile int8_t *value_buf = (volatile int8_t *)NN_OUTPUT_BUF;
    float value = (float)value_buf[0] / 127.0f;  // approximate [-1, 1]

    return value;
}
