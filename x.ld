SECTIONS {
    . = 0xb0b0;
    .text : { *(.text) }
    . = 0x97730;
    .rodata : { *(.rodata) }
    . = 0x00000000000a9778;
    .got : { *(.got) }
}

data = 0x0aa018;
print = 0xa9948;
close = 0xa9940;
