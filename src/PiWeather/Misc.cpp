#include "Arduino.h"
#include <avr/pgmspace.h>
#include "PiWeather.h"
#include <stdlib.h> // needed for ftoa()
#define MAX_SPRINTF 128

/* 
 * Print functions using Flash memory to avoid copying string constants to RAM 
 * at initialization.  Does nothing if DEBUG is not defined
 */
void 
DebugPrint_P(const char *addr) {
#ifdef DEBUG
    char c;
    while ((c = pgm_read_byte(addr++)))
        Serial.write(c);
#endif
}

void 
DebugPrintln_P(const char *addr) {
#ifdef DEBUG
    DebugPrint_P(addr);
    Serial.println();
#endif
}

void 
printHex(byte data) {
    if (data < 16)
        Serial.print('0');
    Serial.print(data, HEX);
}

void 
serial_printf(char *fmt, ... ) {
    char tmp[MAX_SPRINTF]; // resulting string limited to XXX chars
    va_list args;
    va_start (args, fmt );
    vsnprintf(tmp, MAX_SPRINTF, fmt, args);
    va_end (args);
    Serial.print(tmp);
}


/*
 * Float to ascii
 * Since the sprintf() of the Arduino doesn't support floating point
 * converstion, #include <stdlib.h> for itoa() and then use this function
 * to do the conversion manually
 */
char 
*ftoa(char *a, double f, int precision)
{
  long p[] = {
    0,10,100,1000,10000,100000,1000000,10000000,100000000  };

  char *ret = a;
  long heiltal = (long)f;
  itoa(heiltal, a, 10);
  while (*a != '\0') a++;
  *a++ = '.';
  long desimal = abs((long)((f - heiltal) * p[precision]));
  itoa(desimal, a, 10);
  return ret;
}

