# ============================================================
# startup.S — Minimal RISC-V startup code for Gomoku firmware.
# ============================================================

.section .text.init, "ax"
.globl _start
_start:
    # Initialize stack pointer
    la sp, _stack_end

    # Copy .data from IROM to DRAM
    la t0, _data_lma
    la t1, _data_start
    la t2, _data_end
    beq t1, t2, 2f
1:
    lw  t3, 0(t0)
    sw  t3, 0(t1)
    addi t0, t0, 4
    addi t1, t1, 4
    bltu t1, t2, 1b
2:

    # Zero .bss
    la t0, _bss_start
    la t1, _bss_end
    beq t0, t1, 2f
1:
    sw  zero, 0(t0)
    addi t0, t0, 4
    bltu t0, t1, 1b
2:

    # Call main
    call main

    # If main returns, loop forever
1:
    wfi
    j 1b
