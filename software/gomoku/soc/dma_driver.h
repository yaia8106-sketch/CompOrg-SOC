/**
 * dma_driver.h — DMA Engine driver.
 */

#ifndef DMA_DRIVER_H
#define DMA_DRIVER_H

#include <stdint.h>

#define DMA_BASE        0xA0000000

#define DMA_REG_SRC_ADDR    0x00
#define DMA_REG_DST_ADDR    0x04
#define DMA_REG_XFER_LEN    0x08
#define DMA_REG_CTRL        0x0C
#define DMA_REG_STATUS      0x10
#define DMA_REG_BURST_LEN   0x14

#define DMA_CTRL_START      (1 << 0)
#define DMA_CTRL_IRQ_EN     (1 << 1)

#define DMA_STATUS_BUSY     (1 << 0)
#define DMA_STATUS_DONE     (1 << 1)
#define DMA_STATUS_ERROR    (1 << 2)

static inline void dma_write_reg(uint32_t offset, uint32_t value) {
    volatile uint32_t *reg = (volatile uint32_t *)(DMA_BASE + offset);
    *reg = value;
}

static inline uint32_t dma_read_reg(uint32_t offset) {
    volatile uint32_t *reg = (volatile uint32_t *)(DMA_BASE + offset);
    return *reg;
}

/**
 * Perform a DMA transfer.
 * Blocks until transfer completes.
 * Returns 0 on success, -1 on error.
 */
static inline int dma_transfer(uint32_t src_addr, uint32_t dst_addr,
                                uint32_t len_bytes, uint8_t burst_len) {
    // Wait if DMA is busy
    while (dma_read_reg(DMA_REG_STATUS) & DMA_STATUS_BUSY);

    dma_write_reg(DMA_REG_SRC_ADDR,  src_addr);
    dma_write_reg(DMA_REG_DST_ADDR,  dst_addr);
    dma_write_reg(DMA_REG_XFER_LEN,  len_bytes);
    dma_write_reg(DMA_REG_BURST_LEN, burst_len);
    dma_write_reg(DMA_REG_CTRL,      DMA_CTRL_START);

    // Wait for completion
    while (dma_read_reg(DMA_REG_STATUS) & DMA_STATUS_BUSY);

    uint32_t status = dma_read_reg(DMA_REG_STATUS);
    if (status & DMA_STATUS_ERROR) return -1;

    // Clear done flag
    dma_write_reg(DMA_REG_STATUS, 0);
    return 0;
}

/**
 * Blocking memory copy using DMA.
 */
static inline int dma_memcpy(void *dst, const void *src, uint32_t len) {
    return dma_transfer((uint32_t)(uintptr_t)src,
                        (uint32_t)(uintptr_t)dst,
                        len, 8);  // 8-beat bursts
}

#endif /* DMA_DRIVER_H */
