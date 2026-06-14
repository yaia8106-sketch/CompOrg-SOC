# ============================================================
# Makefile — Gomoku SoC firmware build
# ============================================================

CROSS_COMPILE ?= riscv64-unknown-elf-
CC      = $(CROSS_COMPILE)gcc
OBJCOPY = $(CROSS_COMPILE)objcopy
OBJDUMP = $(CROSS_COMPILE)objdump
SIZE    = $(CROSS_COMPILE)size

CFLAGS  = -march=rv32im_zicsr -mabi=ilp32 -O2 -ffreestanding -nostdlib
CFLAGS += -Wall -Wextra -Wno-unused-parameter
CFLAGS += -I.

LDFLAGS = -T linker.ld -nostdlib

TARGET  = gomoku_firmware

OBJS = \
    gomoku_main.o \
    gomoku_game.o \
    gomoku_ai.o \
    gomoku_nn.o \
    gomoku_render.o \
    startup.o

all: $(TARGET).elf $(TARGET).hex $(TARGET).bin

$(TARGET).elf: $(OBJS) linker.ld
	$(CC) $(CFLAGS) $(LDFLAGS) -o $@ $(OBJS) -Wl,-Map=$(TARGET).map
	$(SIZE) $@

%.o: %.c
	$(CC) $(CFLAGS) -c -o $@ $<

startup.o: startup.S
	$(CC) $(CFLAGS) -c -o $@ $<

%.hex: %.elf
	$(OBJCOPY) -O verilog $< $@

%.bin: %.elf
	$(OBJCOPY) -O binary $< $@

%.dis: %.elf
	$(OBJDUMP) -d $< > $@

# Generate COE files for Vivado IROM
coe: $(TARGET).hex
	python3 ../tools/elf2coe.py $(TARGET).hex irom.coe

clean:
	rm -f *.o *.elf *.hex *.bin *.map *.dis *.coe

.PHONY: all clean coe
