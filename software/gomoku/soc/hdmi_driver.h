/**
 * hdmi_driver.h — HDMI Display Controller driver.
 */

#ifndef HDMI_DRIVER_H
#define HDMI_DRIVER_H

#include <stdint.h>

#define HDMI_BASE           0xA0020000

#define HDMI_REG_CTRL       0x00
#define HDMI_REG_STATUS     0x04
#define HDMI_REG_FB_ADDR    0x08
#define HDMI_REG_RESOLUTION 0x0C
#define HDMI_REG_LINE_STRIDE 0x10
#define HDMI_REG_HSYNC      0x14
#define HDMI_REG_VSYNC      0x18
#define HDMI_REG_H_BPORCH   0x1C
#define HDMI_REG_V_BPORCH   0x20
#define HDMI_REG_H_FPORCH   0x24
#define HDMI_REG_V_FPORCH   0x28

#define HDMI_CTRL_ENABLE    (1 << 0)
#define HDMI_CTRL_IRQ_VSYNC (1 << 1)

#define HDMI_STATUS_RUNNING (1 << 0)
#define HDMI_STATUS_VSYNC   (1 << 1)
#define HDMI_STATUS_UNDERRUN (1 << 2)

// Default 640×480 @ 60Hz timing
#define H_ACTIVE  640
#define H_FPORCH  16
#define H_SYNC    96
#define H_BPORCH  48

#define V_ACTIVE  480
#define V_FPORCH  10
#define V_SYNC    2
#define V_BPORCH  33

static inline void hdmi_write_reg(uint32_t offset, uint32_t value) {
    volatile uint32_t *reg = (volatile uint32_t *)(HDMI_BASE + offset);
    *reg = value;
}

static inline uint32_t hdmi_read_reg(uint32_t offset) {
    volatile uint32_t *reg = (volatile uint32_t *)(HDMI_BASE + offset);
    return *reg;
}

/**
 * Initialize and enable the HDMI display.
 *
 * @param fb_addr   Frame buffer base address in DDR
 * @param width     Display width in pixels
 * @param height    Display height in pixels
 */
static inline void hdmi_init(uint32_t fb_addr, int width, int height) {
    // Configure timing for 640×480 @ 60Hz
    hdmi_write_reg(HDMI_REG_FB_ADDR,     fb_addr);
    hdmi_write_reg(HDMI_REG_RESOLUTION,  ((width & 0xFFFF) << 16) | (height & 0xFFFF));
    hdmi_write_reg(HDMI_REG_LINE_STRIDE, width * 4);  // 4 bytes per pixel

    // VGA timing parameters
    hdmi_write_reg(HDMI_REG_HSYNC,       H_SYNC);
    hdmi_write_reg(HDMI_REG_VSYNC,       V_SYNC);
    hdmi_write_reg(HDMI_REG_H_BPORCH,    H_BPORCH);
    hdmi_write_reg(HDMI_REG_V_BPORCH,    V_BPORCH);
    hdmi_write_reg(HDMI_REG_H_FPORCH,    H_FPORCH);
    hdmi_write_reg(HDMI_REG_V_FPORCH,    V_FPORCH);

    // Enable
    hdmi_write_reg(HDMI_REG_CTRL, HDMI_CTRL_ENABLE);
}

/**
 * Wait for vertical sync (frame start).
 */
static inline void hdmi_wait_vsync(void) {
    while (!(hdmi_read_reg(HDMI_REG_STATUS) & HDMI_STATUS_VSYNC)) {
        // spin-wait
    }
    // Clear vsync flag by reading status
    hdmi_read_reg(HDMI_REG_STATUS);
}

#endif /* HDMI_DRIVER_H */
