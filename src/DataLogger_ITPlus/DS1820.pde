/**
 * Temperature data logger.
 *
 * This module is in charge of temperature measure locally for central node
 * Old 1820 algorithm is used for conversion here (as a 1820 was attached).
 * See JeetempSensor for 18S20 & 18B20 algorithms
 *
 * Gérard Chevalier, Jan 2011
 * March 2011, added DS18B20 / DS18S20 logic, 18S20 code is the same as old 1820.
 */
#include "DataloggerDefs.h"
#include <OneWire.h>

extern char CommonStrBuff[];
extern void DebugPrint_P(const char *);
extern void DebugPrintln_P(const char *);

// if B_MODEL defined, temp reading will use 18B20 model scheme, otherwise 18S20/1820 is assumed
#define B_MODEL

OneWire  ds(4);

byte HighByte, LowByte, TReading, CentralTempSignBit, CentralTempWhole, CentralTempFract;
byte TempRead, CountRemain;
word Tc_100;

void DS1820Init() {
}

void Get1820Tmp() {
  byte i;
  byte present = 0;
  byte OneWData[12];
  
  ds.reset();
  ds.skip();
  ds.write(0x44, 1);         // start conversion, with parasite power on at the end
  
  delay(1000);     // maybe 750ms is enough, maybe not
  // we might do a ds.depower() here, but the reset will take care of it.
  present = ds.reset();
  ds.skip();
  ds.write(0xBE);         // Read Scratchpad

  for ( i = 0; i < 9; i++) {           // we need 9 bytes
#ifdef DS1820_DEBUG_LOW
    Serial.print(" SP_"); Serial.print(i, DEC);
#endif
    OneWData[i] = ds.read();
  }

#ifdef DS1820_DEBUG_LOW
  Serial.print("\nP=");
  Serial.print(present,HEX);
  Serial.print(", ");

  DebugPrint_P(PSTR("FRAME: "));
  for ( i = 0; i < 9; i++) {
    Serial.print(OneWData[i], HEX);
    Serial.write(' ');
  }

  DebugPrintln(PSTR(" CRC="));
  Serial.print(OneWire::crc8(OneWData, 8), HEX);
  Serial.print(" (");
  if (ds.crc8(OneWData, 8) == OneWData[8]) {  // vérification validité code CRC des valeurs reçues
    Serial.println ("OK)"); 
  }
  else {
    Serial.println ("KO)"); 
  }
#endif
  // Check if CRC OK, otherwise return without changing t° values: will wait next period to sample again
  if (ds.crc8(OneWData, 8) != OneWData[8])
    return;

#ifdef B_MODEL
  // 18B20 default to 12 bits resolution at power up
  LowByte = OneWData[0];
  HighByte = OneWData[1];
  CentralTempWhole = (HighByte << 4) | (LowByte >> 4);
  CentralTempFract = ((LowByte & 0b1111) * 10) / 16;
  // A little bit to heavy to go through a bollean for sign in that case...
  // but keeped as is for compatibility with 18S20 code.
  CentralTempSignBit = (CentralTempWhole & 0b10000000) != 0;
  CentralTempWhole &= 0b01111111;
#else
// TEMPERATURE = TEMP_READ -0.25 + (COUNT_PER_C - COUNT_REMAIN) / COUNT_PER_C
// X 100 ==>
// 100 * TEMP_READ -25 + (100 * COUNT_PER_C - 100*COUNT_REMAIN) / 100 * COUNT_PER_C
// From datasheet: Note that the COUNT PER °C register is hard-wired to 16 (10h).
// 100 * TEMP_READ -25 + (1600 - 100*COUNT_REMAIN) / 16
  LowByte = OneWData[0];
  HighByte = OneWData[1];
  TempRead = LowByte;  // Only 8 significant bits (-55 .. +85)
  CountRemain = OneWData[6];
  
  CentralTempSignBit = HighByte != 0;
  if (CentralTempSignBit != 0)
    TReading = -TReading;

  Tc_100 = ((word)(TempRead >> 1)) * 100 - 25 + ((((word)(16 - CountRemain)) * 100) / 16);
  CentralTempWhole = Tc_100 / 100;  // separate off the whole and fractional portions
  CentralTempFract = Tc_100 % 100;
  if (CentralTempFract % 10 >= 5)
    CentralTempFract = CentralTempFract / 10 + 1;
  else
    CentralTempFract = CentralTempFract / 10;

#endif
#ifdef DS1820_DEBUG
  sprintf(CommonStrBuff, "1Wire: %c%d.%d", CentralTempSignBit != 0 ? '-' : '+', CentralTempWhole, CentralTempFract);
  Serial.println(CommonStrBuff);
#endif
}

