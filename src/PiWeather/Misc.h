#ifndef Misc_H
#define Misc_h
#include "Arduino.h"

void DebugPrint_P(const char *addr);
void DebugPrintln_P(const char *addr);
void printHex(byte data);
void serial_printf(char *fmt, ... );
char *ftoa(char *a, double f, int precision);


#endif

