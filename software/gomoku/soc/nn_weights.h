/**
 * nn_weights.h — Placeholder NN weights.
 *
 * This file should be REPLACED by the output of export_weights.py
 * after training the GomokuCNN model.
 *
 * Current content: dummy weights for compilation testing only.
 * The real weights will give meaningful gameplay — these are random.
 */

#ifndef NN_WEIGHTS_H
#define NN_WEIGHTS_H

#include <stdint.h>

// Layer dimensions
#define NN_IN_CHANNELS     4
#define NN_BOARD_SIZE       15
#define NN_NUM_MOVES        225

#define CONV1_OUT_CH        16
#define CONV2_OUT_CH        32
#define CONV3_OUT_CH        16
#define POLICY_OUT_CH       1
#define VALUE_FC1_OUT       64
#define VALUE_FC2_OUT       1

// ============================================================
// Weights array (packed int8, 4 per uint32)
//
// These will be loaded at address 0x80320000 in DDR.
//
// Total weight size: ~6KB quantized
// ============================================================

// conv1 weight: [16, 4, 3, 3] = 576 int8 = 144 words
#define CONV1_WEIGHT_WORDS  144
// conv2 weight: [32, 16, 3, 3] = 4608 int8 = 1152 words
#define CONV2_WEIGHT_WORDS  1152
// conv3 weight: [16, 32, 3, 3] = 4608 int8 = 1152 words
#define CONV3_WEIGHT_WORDS  1152
// policy weight: [1, 16, 1, 1] = 16 int8 = 4 words
#define POLICY_WEIGHT_WORDS 4
// value fc1: [64, 16] = 1024 int8 = 256 words
#define VALUE_FC1_WORDS     256
// value fc2: [1, 64] = 64 int8 = 16 words
#define VALUE_FC2_WORDS     16

// Total: 2724 words ≈ 10.9 KB

// Placeholder arrays (will be filled by export_weights.py)
// For now, use zero-initialized sections placed at 0x80320000

#endif /* NN_WEIGHTS_H */
