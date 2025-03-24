ASM_SRC = printf.s
CPP_SRC = main.cpp

OBJ_SRC = main.o printf.o
TARGET  = printf

.PHONY: all clean

all:
	@@nasm -f elf64 $(ASM_SRC)
	@@gcc -c $(CPP_SRC)
	@@gcc -no-pie $(OBJ_SRC) -o $(TARGET)

clean:
	rm $(OBJ_SRC)
	rm $(TARGET)
