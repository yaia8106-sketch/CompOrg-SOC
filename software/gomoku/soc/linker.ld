/**
 * linker.ld — Linker script for Gomoku SoC program.
 *
 * Memory layout:
 *   IROM:  0x8000_0000 - 0x8000_3FFF  (16KB) — instruction code
 *   DRAM:  0x8010_0000 - 0x8013_FFFF  (256KB) — stack, heap, bss
 *   DDR:   0x8030_0000 - 0x8FFF_FFFF  — frame buffer, NN data
 */

OUTPUT_FORMAT("elf32-littleriscv", "elf32-littleriscv", "elf32-littleriscv")
OUTPUT_ARCH(riscv)
ENTRY(_start)

MEMORY
{
    IROM (rx)  : ORIGIN = 0x80000000, LENGTH = 16K
    DRAM (rwx) : ORIGIN = 0x80100000, LENGTH = 256K
}

SECTIONS
{
    .text : {
        *(.text.init)
        *(.text*)
        *(.rodata*)
        . = ALIGN(4);
    } > IROM

    .data : {
        *(.data*)
        . = ALIGN(4);
    } > DRAM AT > IROM

    .bss : {
        *(.bss*)
        *(COMMON)
        . = ALIGN(4);
    } > DRAM

    .stack (NOLOAD) : {
        . = ALIGN(16);
        _stack_start = .;
        . += 16K;
        _stack_end = .;
    } > DRAM

    _data_lma = LOADADDR(.data);
    _data_start = ADDR(.data);
    _data_end = ADDR(.data) + SIZEOF(.data);
    _bss_start = ADDR(.bss);
    _bss_end = ADDR(.bss) + SIZEOF(.bss);

    /* NN weights loaded at 0x80320000 (in DDR) */
    .nn_weights 0x80320000 (NOLOAD) : {
        *(.nn_weights*)
    }
}
