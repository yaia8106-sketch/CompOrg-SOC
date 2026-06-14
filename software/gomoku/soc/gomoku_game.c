/**
 * gomoku_game.c — Gomoku game logic implementation.
 */

#include "gomoku_game.h"

static const int DIRECTIONS[4][2] = {
    {0, 1},   // horizontal
    {1, 0},   // vertical
    {1, 1},   // diagonal
    {1, -1}   // anti-diagonal
};

void gomoku_init(gomoku_game_t *game) {
    for (int r = 0; r < BOARD_SIZE; r++)
        for (int c = 0; c < BOARD_SIZE; c++)
            game->board[r][c] = EMPTY;

    game->current_player = BLACK;
    game->move_count = 0;
    game->last_move_row = -1;
    game->last_move_col = -1;
    game->state = GAME_ONGOING;
}

int gomoku_is_legal(gomoku_game_t *game, int row, int col) {
    if (game->state != GAME_ONGOING) return 0;
    if (row < 0 || row >= BOARD_SIZE || col < 0 || col >= BOARD_SIZE) return 0;
    return game->board[row][col] == EMPTY;
}

int gomoku_place_stone(gomoku_game_t *game, int row, int col) {
    if (!gomoku_is_legal(game, row, col)) return -1;

    game->board[row][col] = game->current_player;
    game->last_move_row = row;
    game->last_move_col = col;
    game->move_count++;

    gomoku_check_win(game);

    if (game->state == GAME_ONGOING) {
        game->current_player = (game->current_player == BLACK) ? WHITE : BLACK;
    }

    return 0;
}

void gomoku_check_win(gomoku_game_t *game) {
    if (game->last_move_row < 0) return;

    int r0 = game->last_move_row;
    int c0 = game->last_move_col;
    stone_t player = game->board[r0][c0];

    for (int d = 0; d < 4; d++) {
        int count = 1;

        // Positive direction
        for (int i = 1; i < 5; i++) {
            int r = r0 + DIRECTIONS[d][0] * i;
            int c = c0 + DIRECTIONS[d][1] * i;
            if (r >= 0 && r < BOARD_SIZE && c >= 0 && c < BOARD_SIZE &&
                game->board[r][c] == player)
                count++;
            else
                break;
        }

        // Negative direction
        for (int i = 1; i < 5; i++) {
            int r = r0 - DIRECTIONS[d][0] * i;
            int c = c0 - DIRECTIONS[d][1] * i;
            if (r >= 0 && r < BOARD_SIZE && c >= 0 && c < BOARD_SIZE &&
                game->board[r][c] == player)
                count++;
            else
                break;
        }

        if (count >= 5) {
            game->state = (player == BLACK) ? GAME_BLACK_WIN : GAME_WHITE_WIN;
            return;
        }
    }

    // Check for draw
    if (game->move_count >= BOARD_CELLS)
        game->state = GAME_DRAW;
}

int gomoku_legal_moves(gomoku_game_t *game, int *moves, int max_moves) {
    int count = 0;
    for (int r = 0; r < BOARD_SIZE && count < max_moves; r++) {
        for (int c = 0; c < BOARD_SIZE && count < max_moves; c++) {
            if (game->board[r][c] == EMPTY) {
                moves[count++] = r * BOARD_SIZE + c;
            }
        }
    }
    return count;
}

void gomoku_to_nn_input(gomoku_game_t *game, float *input_tensor) {
    // input_tensor: 4 * 15 * 15 = 900 floats
    for (int i = 0; i < 900; i++) input_tensor[i] = 0.0f;

    for (int r = 0; r < BOARD_SIZE; r++) {
        for (int c = 0; c < BOARD_SIZE; c++) {
            int idx = r * BOARD_SIZE + c;
            stone_t s = game->board[r][c];

            if (s == BLACK)
                input_tensor[0 * BOARD_CELLS + idx] = 1.0f;  // channel 0: black
            else if (s == WHITE)
                input_tensor[1 * BOARD_CELLS + idx] = 1.0f;  // channel 1: white

            // channel 2: current player
            if (game->current_player == BLACK)
                input_tensor[2 * BOARD_CELLS + idx] = 1.0f;

            // channel 3: last move (simplified: mark all opponent stones)
            stone_t opp = (game->current_player == BLACK) ? WHITE : BLACK;
            if (s == opp)
                input_tensor[3 * BOARD_CELLS + idx] = 1.0f;
        }
    }
}
