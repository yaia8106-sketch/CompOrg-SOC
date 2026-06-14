/**
 * gomoku_render.h — Frame buffer rendering for Gomoku board.
 */

#ifndef GOMOKU_RENDER_H
#define GOMOKU_RENDER_H

#include "gomoku_game.h"
#include <stdint.h>

// Frame buffer base address (DDR)
#define FB_BASE_ADDR    0x80300000

// Display parameters
#define DISP_WIDTH      640
#define DISP_HEIGHT     480
#define BOARD_X_OFFSET  40
#define BOARD_Y_OFFSET  40
#define CELL_SIZE       26
#define STONE_RADIUS    11

// Colors (RGB888 packed as 32-bit: 0x00RRGGBB)
#define COLOR_BG        0x00003F1F   // Dark green background
#define COLOR_BOARD      0x00DEB887   // Burlywood board color
#define COLOR_GRID      0x00333333   // Dark gray grid lines
#define COLOR_BLACK     0x00111111   // Black stone
#define COLOR_WHITE     0x00EEEEEE   // White stone
#define COLOR_HIGHLIGHT 0x00FF3333   // Red highlight (last move)
#define COLOR_TEXT      0x00FFFFFF   // White text
#define COLOR_WIN_LINE  0x00FFD700   // Gold win line

/**
 * Initialize the frame buffer (clear to background).
 */
void render_init(void);

/**
 * Draw the full board grid on the frame buffer.
 */
void render_board(void);

/**
 * Draw all stones on the board.
 */
void render_stones(gomoku_game_t *game);

/**
 * Highlight the last move.
 */
void render_last_move(gomoku_game_t *game);

/**
 * Draw game status text (current player, win/draw).
 */
void render_status(gomoku_game_t *game);

/**
 * Full frame render: board + stones + status.
 */
void render_frame(gomoku_game_t *game);

/**
 * Set a single pixel in the frame buffer.
 */
static inline void fb_set_pixel(int x, int y, uint32_t color) {
    if (x >= 0 && x < DISP_WIDTH && y >= 0 && y < DISP_HEIGHT) {
        volatile uint32_t *fb = (volatile uint32_t *)FB_BASE_ADDR;
        fb[y * DISP_WIDTH + x] = color;
    }
}

/**
 * Draw a filled circle (for stones).
 */
void fb_fill_circle(int cx, int cy, int radius, uint32_t color);

#endif /* GOMOKU_RENDER_H */
