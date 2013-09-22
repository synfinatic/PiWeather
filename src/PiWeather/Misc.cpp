#include "Arduino.h"
#include <avr/pgmspace.h>
#include "PiWeather.h"

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

