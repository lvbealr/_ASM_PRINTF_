#include <stdio.h>

extern "C" int myPrintf(const char *fmt, ...); // no name mangling -> DO it?

#define CHAR   'a'
#define STRING "DED32"
#define INT1   123
#define INT2  -998
#define HEX    0xabc123
#define OCT    012345670
#define BIN    0b1101
#define END    "END"

int main() {
  // myPrintf("%%c -> [%c] ABOBA | %%s -> [%s] ADODA | %%d -> [%d] | %%x -> [%x] |"
  //  " %%o -> [%o] | %%b -> [%b] | %%d -> [%d] | %%s -> [%s] %d %s %x %d%%%c%b",
  //  CHAR, STRING, INT1, HEX, OCT, BIN, INT2, END, -1, "LOVE", 3802, 100, 33, 126);
  
  printf("Hello World");

  return 0;
}

