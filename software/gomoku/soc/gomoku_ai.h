/**
 * gomoku_ai.h — AI engine: evaluates board positions and selects moves.
 */

#ifndef GOMOKU_AI_H
#define GOMOKU_AI_H

#include "gomoku_game.h"

/**
 * AI difficulty levels.
 */
typedef enum {
    AI_EASY = 0,     // Random among top-5 moves
    AI_MEDIUM,       // Best NN-evaluated move
    AI_HARD          // 2-ply minimax + NN evaluation
} ai_level_t;

/**
 * Initialize AI engine.
 */
void ai_init(ai_level_t level);

/**
 * Select the best move for the current player.
 * Returns move index (row * BOARD_SIZE + col), or -1 if no legal moves.
 */
int ai_select_move(gomoku_game_t *game);

#endif /* GOMOKU_AI_H */
