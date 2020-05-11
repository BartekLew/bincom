awk2: awk.o awk.ld
	ld -T awk.ld awk.o -o awk2

awk.o: awk.asm
	as awk.asm -o awk.o

inject: x.raw awk.data
	cp /usr/bin/awk awk
	dd conv=notrunc if=x.raw of=awk obs=1 seek=45232
	objcopy --update-section .rodata=awk.data awk

x.o: x.c
	gcc -nostdlib x.c -c -o x.o

x: x.o x.ld
	ld -T x.ld x.o -o x

awk.data: x
	objcopy -O binary -j .rodata /usr/bin/awk awk.data
	objcopy -O binary -j .rodata x x.data
	dd if=x.data of=awk.data obs=1 seek=63280

x.raw: x
	objcopy -O binary -j .text x x.raw

clean:
	-rm x x.o x.raw awk.data x.data

.PHONY: clean inject
