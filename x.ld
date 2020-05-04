SECTIONS {
    . = 0x8051500;
    .text : { *(.text) }
    . = 0x80c2fc0;
    .rodata : { *(.rodata) }
}
