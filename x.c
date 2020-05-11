extern void (*print)(int, char *fmt, ...);
extern void (*close)(int code);
extern char data;

int _start(int argc, char **argv) {
    print(10, "%s\n", &data);
    close(0);
}
