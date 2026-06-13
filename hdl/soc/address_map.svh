// ============================================================
// SoC Address Map — single source of truth for all address
// regions used by CPU, interconnect, and peripherals.
//
// Contest hard constraints (do NOT modify):
//   IROM  : 0x8000_0000 ~ 0x8000_3FFF  (16KB)
//   DRAM  : 0x8010_0000 ~ 0x8013_FFFF  (256KB)
//   MMIO  : 0x8020_0000 ~ 0x8020_00FF  (local peripherals)
// ============================================================

`ifndef SOC_ADDRESS_MAP_SVH
`define SOC_ADDRESS_MAP_SVH

// ------------------------------------------------------------
// Region: Cacheable memory space (0x8000_0000 ~ 0x8FFF_FFFF)
// ------------------------------------------------------------
`define SOC_ADDR_IROM_BASE        32'h8000_0000
`define SOC_ADDR_IROM_SIZE        32'h0001_0000   // 64KB window (16KB used)

`define SOC_ADDR_DRAM_BASE        32'h8010_0000
`define SOC_ADDR_DRAM_SIZE        32'h0004_0000   // 256KB

`define SOC_ADDR_LOCAL_MMIO_BASE  32'h8020_0000
`define SOC_ADDR_LOCAL_MMIO_SIZE  32'h0000_0100   // 256B

`define SOC_ADDR_DDR_BASE         32'h8030_0000
`define SOC_ADDR_DDR_SIZE         32'h0FD0_0000   // ~253MB (up to 0x8FFF_FFFF)

// ------------------------------------------------------------
// Region: Non-cacheable SoC MMIO (0xA000_0000 ~ 0xAFFF_FFFF)
// ------------------------------------------------------------
`define SOC_ADDR_SOC_MMIO_BASE    32'hA000_0000
`define SOC_ADDR_SOC_MMIO_SIZE    32'h1000_0000   // 256MB window

// Sub-regions (each 64KB):
`define SOC_ADDR_DMA_BASE         32'hA000_0000
`define SOC_ADDR_ACCEL_BASE       32'hA001_0000
`define SOC_ADDR_HDMI_BASE        32'hA002_0000
// 0xA003_0000 ~ 0xA0FF_FFFF reserved for additional peripherals

// ------------------------------------------------------------
// Region: Non-cacheable data buffers (0xB000_0000 ~ 0xBFFF_FFFF)
// ------------------------------------------------------------
`define SOC_ADDR_NC_BUFFER_BASE   32'hB000_0000
`define SOC_ADDR_NC_BUFFER_SIZE   32'h1000_0000   // 256MB

// ------------------------------------------------------------
// Helper macros
// ------------------------------------------------------------
`define SOC_ADDR_IS_CACHEABLE(addr)  ((addr) >= 32'h8000_0000 && (addr) < 32'h9000_0000)
`define SOC_ADDR_IS_SOC_MMIO(addr)   ((addr) >= 32'hA000_0000 && (addr) < 32'hB000_0000)
`define SOC_ADDR_IS_NC_BUFFER(addr)  ((addr) >= `SOC_ADDR_NC_BUFFER_BASE && (addr) < 32'hC000_0000)

`endif /* SOC_ADDRESS_MAP_SVH */
