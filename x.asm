.global _start 

.set DATA, 0x080df900
.set printf, 0x804fd50

_start:
    pushl $DATA+0x51
    pushl $fmt
    call printf

    mov  $1, %al
    xor  %ebx, %ebx
    int  $0x80

fmt: .asciz "%s\n"
