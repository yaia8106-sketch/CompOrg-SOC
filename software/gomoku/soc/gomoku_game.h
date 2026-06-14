/**
 * gomoku_game.h — Gomoku game logic (board, moves, win detection).
 */

#ifndef GOMOKU_GAME_H
#define GOMOKU_GAME_H

#include <stdint.h>

#define BOARD_SIZE  15
#define BOARD_CELLS (BOARD_SIZE * BOARD_SIZE)
#define NUM_MOVES   225

typedef enum {
    EMPTY  = 0,
    BLACK  = 1,
    WHITE  = 2
} stone_t;

typedef enum {
    GAME_ONGOING = 0,
    GAME_BLACK_WIN,
    GAME_WHITE_WIN,
    GAME_DRAW
} game_state_t;

typedef struct {
    stone_t board[BOARD_SIZE][BOARD_SIZE];
    stone_t current_player;      // BLACK or WHITE
    int     move_count;
    int     last_move_row;
    int     last_move_col;
    game_state_t state;
} gomoku_game_t;

/**
 * Initialize a new game.
 */
void gomoku_init(gomoku_game_t *game);

/**
 * Try to place a stone at (row, col). Returns 0 on success, -1 if illegal.
 */
int gomoku_place_stone(gomoku_game_t *game, int row, int col);

/**
 * Check if the last move resulted in a win (5 in a row).
 * Updates game->state accordingly.
 */
void gomoku_check_win(gomoku_game_t *game);

/**
 * Get list of legal moves. Returns number of legal moves.
 * moves is an array of (row * BOARD_SIZE + col) move indices.
 */
int gomoku_legal_moves(gomoku_game_t *game, int *moves, int max_moves);

/**
 * Check if a move is legal.
 */
int gomoku_is_legal(gomoku_game_t *game, int row, int col);

/**
 * Convert board to NN input tensor (4 channels).
 * Output: in_channels[4][15][15] as flat float array.
 */
void gomoku_to_nn_input(gomoku_game_t *game, float *input_tensor);

#endif /* GOMOKU_GAME_H */
