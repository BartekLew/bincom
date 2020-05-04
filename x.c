typedef void (*PrintCall) (char *fmt, ...);
typedef void (*ExitCall) (int code);

const PrintCall print = (PrintCall) 0x804fd50;
const ExitCall close = (ExitCall) 0x8050490;

int _start(int argc, char **argv) {
    print("%s\n", 0x80df951);
    close(0);
}
