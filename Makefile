inject: x.raw
	cp /usr/bin/awk awk
	dd conv=notrunc if=x.raw of=awk obs=1 seek=38144

x.o: x.asm
	as x.asm -o x.o

x: x.o x.ld
	ld -T x.ld x.o -o x

x.raw: x
	objcopy -O binary -j .text x x.raw
