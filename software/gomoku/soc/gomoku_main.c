/**
 * gomoku_main.c — Gomoku game main program for JYD2026 SoC.
 *
 * Game flow:
 *   1. Initialize HDMI display and frame buffer
 *   2. Initialize NN accelerator and load weights
 *   3. Render empty board
 *   4. Game loop:
 *      a. Wait for player input (KEY/UART)
 *      b. Place stone, check win
 *      c. AI computes move using NN
 *      d. Place AI stone, check win
 *      e. Render updated board
 *   5. Display game result
 *
 * Input method: virtual keys (KEY[0]=select, KEY[1..4]=move cursor)
 * AI difficulty: configured via SW switches
 */

#include "gomoku_game.h"
#include "gomoku_ai.h"
#include "gomoku_nn.h"
#include "gomoku_render.h"
#include "dma_driver.h"
#include "hdmi_driver.h"

// ============================================================
// Board I/O addresses (from CPU local MMIO)
// ============================================================
#define MMIO_BASE       0x80200000
#define MMIO_LED         0x40
#define MMIO_KEY         0x10
#define MMIO_SW          0x00
#define MMIO_SEG         0x20

#define LED_ADDR    (*(volatile uint32_t *)(MMIO_BASE + MMIO_LED))
#define KEY_ADDR    (*(volatile uint32_t *)(MMIO_BASE + MMIO_KEY))
#define SW_ADDR     (*(volatile uint32_t *)(MMIO_BASE + MMIO_SW))

// ============================================================
// NN weights location in DDR
// ============================================================
// Weights are pre-loaded at boot into 0x80320000
// (loaded by bootloader from IROM constants)
#define NN_WEIGHTS_DDR  0x80320000

// ============================================================
// Cursor for player input
// ============================================================
static int cursor_row = 7;
static int cursor_col = 7;

static void update_led(int value) {
    LED_ADDR = value;
}

/**
 * Simple UART output for debug (writes to SEG display as hex).
 */
static void debug_hex(uint32_t val) {
    (void)val;
    // SEG_ADDR = val;  // Uncomment for 7-seg debug output
}

/**
 * Wait for player to select a move.
 * Uses KEY[0] for place stone, KEY[1..4] for cursor movement.
 * Returns move index, or -1 if no input.
 */
static int wait_player_input(void) {
    static uint32_t prev_key = 0;
    uint32_t key = KEY_ADDR;

    // Edge detection
    uint32_t key_changed = key & ~prev_key;
    prev_key = key;

    if (key_changed == 0) return -1;

    // KEY[0]: place stone
    if (key_changed & 0x01) {
        return cursor_row * BOARD_SIZE + cursor_col;
    }

    // KEY[1]: up
    if (key_changed & 0x02) {
        if (cursor_row > 0) cursor_row--;
        debug_hex(cursor_row * BOARD_SIZE + cursor_col);
        return -1;
    }

    // KEY[2]: down
    if (key_changed & 0x04) {
        if (cursor_row < BOARD_SIZE - 1) cursor_row++;
        debug_hex(cursor_row * BOARD_SIZE + cursor_col);
        return -1;
    }

    // KEY[3]: left
    if (key_changed & 0x08) {
        if (cursor_col > 0) cursor_col--;
        debug_hex(cursor_row * BOARD_SIZE + cursor_col);
        return -1;
    }

    // KEY[4]: right
    if (key_changed & 0x10) {
        if (cursor_col < BOARD_SIZE - 1) cursor_col++;
        debug_hex(cursor_row * BOARD_SIZE + cursor_col);
        return -1;
    }

    return -1;
}

/**
 * Display a simple "pixel art" cursor on the board.
 */
static void render_cursor(gomoku_game_t *game) {
    int cx = BOARD_X_OFFSET + cursor_col * CELL_SIZE;
    int cy = BOARD_Y_OFFSET + cursor_row * CELL_SIZE;

    if (game->board[cursor_row][cursor_col] == EMPTY) {
        uint32_t cursor_color = (game->current_player == BLACK)
                                ? 0x00555555 : 0x00CCCCCC;
        fb_fill_circle(cx, cy, STONE_RADIUS / 2, cursor_color);
    }
}

/**
 * Blink LED to show game status.
 */
static void show_game_result(gomoku_game_t *game) {
    switch (game->state) {
        case GAME_BLACK_WIN:
            update_led(0x00000001);  // LED[0] on = black wins
            break;
        case GAME_WHITE_WIN:
            update_led(0x00000002);  // LED[1] on = white wins
            break;
        case GAME_DRAW:
            update_led(0x00000003);  // LED[0:1] on = draw
            break;
        default:
            break;
    }
}

/**
 * Load NN weights from pre-programmed DDR region into weight buffer area.
 * In a real system, weights would be in IROM and copied to DDR at boot.
 */
static void load_nn_weights(void) {
    // Weights are assumed to be pre-loaded at NN_WEIGHTS_DDR
    // by the bootloader from IROM constants.
    // For now, just point the NN driver at them.
    // (The nn_weights.h file contains the binary weight data)
    debug_hex(NN_WEIGHTS_DDR);
}

/**
 * Main entry point.
 */
int main(void) {
    gomoku_game_t game;
    int player_is_black = 1;  // Player = Black, AI = White

    // Read AI difficulty from switches
    uint32_t sw = SW_ADDR;
    ai_level_t level;
    switch (sw & 0x03) {
        case 0:  level = AI_EASY;   break;
        case 1:  level = AI_MEDIUM; break;
        case 2:  level = AI_HARD;   break;
        default: level = AI_MEDIUM; break;
    }

    // Initialize
    gomoku_init(&game);
    ai_init(level);
    load_nn_weights();

    // Initialize HDMI display
    hdmi_init(FB_BASE_ADDR, DISP_WIDTH, DISP_HEIGHT);

    // Initial render
    render_frame(&game);
    update_led(0x00000000);

    // ========================================================
    // Game loop
    // ========================================================
    while (game.state == GAME_ONGOING) {
        // Show cursor
        render_cursor(&game);

        if (game.current_player == BLACK) {
            if (player_is_black) {
                // Player's turn (Black)
                int move = wait_player_input();
                if (move >= 0) {
                    int row = move / BOARD_SIZE;
                    int col = move % BOARD_SIZE;
                    if (gomoku_place_stone(&game, row, col) == 0) {
                        render_frame(&game);
                    }
                }
            } else {
                // AI's turn (Black)
                int move = ai_select_move(&game);
                if (move >= 0) {
                    gomoku_place_stone(&game, move / BOARD_SIZE,
                                       move % BOARD_SIZE);
                    render_frame(&game);
                }
            }
        } else {
            // White's turn
            if (!player_is_black) {
                // Player's turn (White)
                int move = wait_player_input();
                if (move >= 0) {
                    int row = move / BOARD_SIZE;
                    int col = move % BOARD_SIZE;
                    if (gomoku_place_stone(&game, row, col) == 0) {
                        render_frame(&game);
                    }
                }
            } else {
                // AI's turn (White)
                int move = ai_select_move(&game);
                if (move >= 0) {
                    gomoku_place_stone(&game, move / BOARD_SIZE,
                                       move % BOARD_SIZE);
                    render_frame(&game);
                }
            }
        }
    }

    // ========================================================
    // Game over
    // ========================================================
    render_frame(&game);
    show_game_result(&game);

    // Infinite loop (system will be reset to play again)
    while (1) {
        // Blink winning LED
        for (volatile int i = 0; i < 500000; i++);
        update_led(LED_ADDR ^ 0xFFFFFFFF);
    }

    return 0;
}
