/**
 * gomoku_ai.c — AI engine implementation.
 *
 * Strategy:
 *   - Evaluate all legal moves using the NN value head.
 *   - Select the move with the highest expected value.
 *   - Medium/Hard: add minimax search (2-ply) with alpha-beta pruning.
 */

#include "gomoku_ai.h"
#include "gomoku_nn.h"

static ai_level_t ai_level = AI_MEDIUM;

// NN input buffer in DDR
#define AI_INPUT_BUF  0x80310000  // int8[900] for 4×15×15

void ai_init(ai_level_t level) {
    ai_level = level;
}

/**
 * Evaluate a board position using the NN.
 * Returns a score in [-1, 1] where positive = good for current player.
 */
static float evaluate_position(gomoku_game_t *game) {
    // Convert board to NN input format (int8)
    volatile int8_t *input_buf = (volatile int8_t *)AI_INPUT_BUF;

    // Create float input then quantize to int8
    float float_input[900];
    gomoku_to_nn_input(game, float_input);

    for (int i = 0; i < 900; i++) {
        int val = (int)(float_input[i] * 127.0f);
        if (val > 127) val = 127;
        if (val < 0)   val = 0;
        input_buf[i] = (int8_t)val;
    }

    float policy[225];
    float value = gomoku_nn_inference((const int8_t *)input_buf, policy);

    return value;
}

/**
 * Simple move selection: evaluate all legal moves, pick best.
 */
static int select_move_medium(gomoku_game_t *game) {
    int moves[225];
    int num_moves = gomoku_legal_moves(game, moves, 225);
    if (num_moves == 0) return -1;

    float best_score = -2.0f;
    int   best_move = moves[0];

    // Evaluate up to 30 candidate moves (for performance)
    int candidates = num_moves;
    if (candidates > 30) candidates = 30;

    for (int i = 0; i < candidates; i++) {
        int row = moves[i] / BOARD_SIZE;
        int col = moves[i] % BOARD_SIZE;

        // Try the move
        gomoku_game_t sim = *game;
        gomoku_place_stone(&sim, row, col);

        float score;
        if (sim.state == GAME_BLACK_WIN || sim.state == GAME_WHITE_WIN) {
            // Winning move!
            score = 1.0f;
        } else {
            score = evaluate_position(&sim);
        }

        if (score > best_score) {
            best_score = score;
            best_move = moves[i];
        }
    }

    return best_move;
}

/**
 * 2-ply minimax with alpha-beta pruning.
 */
static float minimax(gomoku_game_t *game, int depth, float alpha, float beta,
                     int maximizing) {
    if (game->state != GAME_ONGOING) {
        if (game->state == GAME_BLACK_WIN)
            return maximizing ? 1.0f : -1.0f;
        if (game->state == GAME_WHITE_WIN)
            return maximizing ? -1.0f : 1.0f;
        return 0.0f;  // draw
    }

    if (depth == 0) {
        float val = evaluate_position(game);
        return maximizing ? val : -val;
    }

    int moves[225];
    int num_moves = gomoku_legal_moves(game, moves, 225);

    // Limit branching factor
    if (num_moves > 15) num_moves = 15;

    if (maximizing) {
        float max_val = -2.0f;
        for (int i = 0; i < num_moves; i++) {
            gomoku_game_t sim = *game;
            gomoku_place_stone(&sim, moves[i] / BOARD_SIZE,
                               moves[i] % BOARD_SIZE);
            float val = minimax(&sim, depth - 1, alpha, beta, 0);
            if (val > max_val) max_val = val;
            if (val > alpha) alpha = val;
            if (alpha >= beta) break;
        }
        return max_val;
    } else {
        float min_val = 2.0f;
        for (int i = 0; i < num_moves; i++) {
            gomoku_game_t sim = *game;
            gomoku_place_stone(&sim, moves[i] / BOARD_SIZE,
                               moves[i] % BOARD_SIZE);
            float val = minimax(&sim, depth - 1, alpha, beta, 1);
            if (val < min_val) min_val = val;
            if (val < beta) beta = val;
            if (alpha >= beta) break;
        }
        return min_val;
    }
}

static int select_move_hard(gomoku_game_t *game) {
    int moves[225];
    int num_moves = gomoku_legal_moves(game, moves, 225);
    if (num_moves == 0) return -1;

    // Limit root candidates
    int candidates = num_moves;
    if (candidates > 20) candidates = 20;

    float best_score = -2.0f;
    int   best_move = moves[0];

    for (int i = 0; i < candidates; i++) {
        int row = moves[i] / BOARD_SIZE;
        int col = moves[i] % BOARD_SIZE;

        gomoku_game_t sim = *game;
        gomoku_place_stone(&sim, row, col);

        float score = minimax(&sim, 1, -2.0f, 2.0f, 0);  // opponent minimizes

        if (score > best_score) {
            best_score = score;
            best_move = moves[i];
        }
    }

    return best_move;
}

int ai_select_move(gomoku_game_t *game) {
    if (game->state != GAME_ONGOING) return -1;

    // If board is empty, play center
    if (game->move_count == 0) {
        return 7 * BOARD_SIZE + 7;  // center
    }

    switch (ai_level) {
        case AI_EASY: {
            // Pick randomly among top-5 NN-evaluated moves
            int moves[225];
            int num_moves = gomoku_legal_moves(game, moves, 225);
            if (num_moves > 5) num_moves = 5;
            // Simple: just return the best among first 5 (non-random for now)
            return select_move_medium(game);
        }
        case AI_MEDIUM:
            return select_move_medium(game);
        case AI_HARD:
            return select_move_hard(game);
        default:
            return select_move_medium(game);
    }
}
