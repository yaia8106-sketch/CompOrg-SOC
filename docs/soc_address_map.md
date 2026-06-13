# SoC Address Map

> 本文件是 SoC 地址映射的文档说明，与 `hdl/soc/address_map.svh` 保持一致。
> 修改地址映射时，必须同时更新本文件和 RTL 头文件。

## 1. Hard Constraints (from contest spec)

| Region | Address Range | Size | Notes |
|--------|--------------|------|-------|
| IROM | `0x8000_0000` ~ `0x8000_3FFF` | 16 KB | Read-only, internal to CPU IP |
| IROM reserved | `0x8000_4000` ~ `0x800F_FFFF` | ~1 MB | Reserved for IROM expansion |
| DRAM | `0x8010_0000` ~ `0x8013_FFFF` | 256 KB | Local BRAM, RW |
| DRAM reserved | `0x8014_0000` ~ `0x801F_FFFF` | ~768 KB | Reserved |
| MMIO | `0x8020_0000` ~ `0x8020_00FF` | 256 B | Local peripherals (LED, SW, KEY, SEG, CNT) |

## 2. SoC Extended Address Space

### Cacheable Region (`0x8000_0000` ~ `0x8FFF_FFFF`)

| Region | Address Range | Size | Notes |
|--------|--------------|------|-------|
| IROM | `0x8000_0000` | 64 KB window | CPU internal |
| DRAM | `0x8010_0000` | 256 KB | CPU local BRAM |
| Local MMIO | `0x8020_0000` | 256 B | CPU internal |
| **DDR** | `0x8030_0000` ~ `0x8FFF_FFFF` | ~253 MB | External DDR via MIG (TODO) |

### SoC MMIO Region (`0xA000_0000` ~ `0xAFFF_FFFF`) — Non-cacheable

| Region | Address Range | Size | Notes |
|--------|--------------|------|-------|
| DMA Engine | `0xA000_0000` | 64 KB | Control/status registers (TODO) |
| Accelerator | `0xA001_0000` | 64 KB | Control/status registers (TODO) |
| HDMI Controller | `0xA002_0000` | 64 KB | Display controller (TODO) |
| Reserved | `0xA003_0000` ~ `0xA0FF_FFFF` | ~16 MB | Future peripherals |

### Non-Cacheable Buffer Region (`0xB000_0000` ~ `0xBFFF_FFFF`)

| Region | Address Range | Size | Notes |
|--------|--------------|------|-------|
| Accelerator Data | `0xB000_0000` ~ `0xBFFF_FFFF` | 256 MB | DMA/accelerator data buffers (TODO) |

## 3. Cacheability Rules

| Address Range | Cacheable | Rationale |
|--------------|-----------|-----------|
| `0x8000_0000` ~ `0x8FFF_FFFF` | Yes | Main memory (DDR/DRAM) |
| `0x8020_0000` ~ `0x8020_00FF` | No | Local MMIO — handled internally, never reaches AXI |
| `0xA000_0000` ~ `0xAFFF_FFFF` | No | SoC peripheral control registers |
| `0xB000_0000` ~ `0xBFFF_FFFF` | No | DMA/accelerator shared buffers |

## 4. Design Rules

- All address definitions live in `hdl/soc/address_map.svh` — that file is the single source of truth.
- CPU local MMIO (`0x8020_xxxx`) must NOT generate AXI transactions; this is enforced by the CPU IP internally.
- New peripherals get 64 KB MMIO windows in the `0xAxxx_xxxx` region.
- All changes to the address map must be reflected here AND in `address_map.svh` simultaneously.
