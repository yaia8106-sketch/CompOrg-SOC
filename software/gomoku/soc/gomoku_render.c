/**
 * gomoku_render.c — Frame buffer rendering implementation.
 */

#include "gomoku_render.h"

void render_init(void) {
    // Clear entire frame buffer to background color
    volatile uint32_t *fb = (volatile uint32_t *)FB_BASE_ADDR;
    for (int i = 0; i < DISP_WIDTH * DISP_HEIGHT; i++) {
        fb[i] = COLOR_BG;
    }
}

void fb_fill_circle(int cx, int cy, int radius, uint32_t color) {
    for (int y = -radius; y <= radius; y++) {
        for (int x = -radius; x <= radius; x++) {
            if (x*x + y*y <= radius*radius) {
                fb_set_pixel(cx + x, cy + y, color);
            }
        }
    }
}

static void draw_rect(int x, int y, int w, int h, uint32_t color) {
    for (int dy = 0; dy < h; dy++)
        for (int dx = 0; dx < w; dx++)
            fb_set_pixel(x + dx, y + dy, color);
}

static void draw_line_h(int x, int y, int len, uint32_t color) {
    for (int i = 0; i < len; i++)
        fb_set_pixel(x + i, y, color);
}

static void draw_line_v(int x, int y, int len, uint32_t color) {
    for (int i = 0; i < len; i++)
        fb_set_pixel(x, y + i, color);
}

void render_board(void) {
    int board_px = (BOARD_SIZE - 1) * CELL_SIZE;

    // Board background
    draw_rect(BOARD_X_OFFSET - 15, BOARD_Y_OFFSET - 15,
              board_px + 30, board_px + 30, COLOR_BOARD);

    // Grid lines
    for (int i = 0; i < BOARD_SIZE; i++) {
        int pos = i * CELL_SIZE;
        draw_line_h(BOARD_X_OFFSET, BOARD_Y_OFFSET + pos, board_px + 1, COLOR_GRID);
        draw_line_v(BOARD_X_OFFSET + pos, BOARD_Y_OFFSET, board_px + 1, COLOR_GRID);
    }

    // Star points (standard Gomoku positions)
    int star_points[][2] = {
        {3, 3}, {3, 7}, {3, 11},
        {7, 3}, {7, 7}, {7, 11},
        {11, 3}, {11, 7}, {11, 11}
    };
    for (int i = 0; i < 9; i++) {
        int sx = BOARD_X_OFFSET + star_points[i][1] * CELL_SIZE;
        int sy = BOARD_Y_OFFSET + star_points[i][0] * CELL_SIZE;
        fb_fill_circle(sx, sy, 3, COLOR_GRID);
    }
}

void render_stones(gomoku_game_t *game) {
    for (int r = 0; r < BOARD_SIZE; r++) {
        for (int c = 0; c < BOARD_SIZE; c++) {
            if (game->board[r][c] == EMPTY) continue;

            int sx = BOARD_X_OFFSET + c * CELL_SIZE;
            int sy = BOARD_Y_OFFSET + r * CELL_SIZE;
            uint32_t color = (game->board[r][c] == BLACK) ? COLOR_BLACK : COLOR_WHITE;

            // Draw shadow first (slight offset)
            fb_fill_circle(sx + 2, sy + 2, STONE_RADIUS, 0x00111111);
            fb_fill_circle(sx, sy, STONE_RADIUS, color);

            // Highlight for white stones
            if (game->board[r][c] == WHITE) {
                fb_fill_circle(sx - 3, sy - 3, STONE_RADIUS / 3, 0x00FFFFFF);
            }
        }
    }
}

void render_last_move(gomoku_game_t *game) {
    if (game->last_move_row < 0) return;

    int sx = BOARD_X_OFFSET + game->last_move_col * CELL_SIZE;
    int sy = BOARD_Y_OFFSET + game->last_move_row * CELL_SIZE;
    fb_fill_circle(sx, sy, 3, COLOR_HIGHLIGHT);
}

void render_status(gomoku_game_t *game) {
    int text_y = BOARD_Y_OFFSET + BOARD_SIZE * CELL_SIZE + 30;
    int text_x = BOARD_X_OFFSET;

    // Simple text rendering: draw colored rectangles as placeholder for
    // status indication (full font rendering would add significant code)

    uint32_t status_color;
    switch (game->state) {
        case GAME_BLACK_WIN:
            status_color = COLOR_BLACK;
            break;
        case GAME_WHITE_WIN:
            status_color = COLOR_WHITE;
            break;
        case GAME_DRAW:
            status_color = COLOR_TEXT;
            break;
        default:
            status_color = (game->current_player == BLACK) ? COLOR_BLACK : COLOR_WHITE;
            break;
    }

    // Draw a status indicator bar
    draw_rect(text_x, text_y, 200, 20, status_color);

    // Draw move counter as small dots
    for (int i = 0; i < game->move_count && i < 100; i++) {
        fb_set_pixel(text_x + 210 + (i % 20) * 3, text_y + 5 + (i / 20) * 4,
                     0x00AAAAAA);
    }
}

void render_frame(gomoku_game_t *game) {
    render_init();
    render_board();
    render_stones(game);
    render_last_move(game);
    render_status(game);
}
