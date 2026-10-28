#!/bin/bash
# Builds the in-game code (arm/) into lua/mmo_code.lua, the blob the Lua script writes into the game.
# Needs devkitARM (WSL or Linux: /opt/devkitpro/devkitARM) and python3.
set -euo pipefail
cd "$(dirname "$0")/.."
BIN=${DEVKITARM:-/opt/devkitpro/devkitARM}/bin
mkdir -p build
"$BIN/arm-none-eabi-gcc" -mthumb -march=armv5te -mtune=arm946e-s -Os -std=gnu11 -Wall -Wextra -Werror \
  -ffreestanding -fno-builtin -nostdlib -ffunction-sections -fno-jump-tables -mno-unaligned-access \
  -Wl,-T,arm/link.ld -Wl,--gc-sections -Wl,--no-warn-rwx-segments -Wl,-Map,build/mmo.map -o build/mmo.elf arm/*.c -lgcc
"$BIN/arm-none-eabi-objcopy" -O binary -j .text -j .data build/mmo.elf build/mmo.bin
"$BIN/arm-none-eabi-nm" build/mmo.elf > build/mmo.syms
python3 scripts/gen_code_lua.py build/mmo.bin build/mmo.syms lua/mmo_code.lua
