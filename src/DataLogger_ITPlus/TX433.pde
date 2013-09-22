/**
 * Temperature data logger.
 *
 * xx
 *
 * Gérard Chevalier, Nov 2011
 * Nov 2011, xxxxxxxxx
 */

#include "DataloggerDefs.h"

#define NB_BITS 52

#define TX_ON()   ((PORTD |=  (1<<PORTD7)))
#define TX_OFF()  ((PORTD &= ~(1<<PORTD7)))

byte onFrame[] = {0xfe, 1, 0xbf, 0xf8, 1, 0xe1, 0xb0};
byte offFrame[] = {0xfe, 1, 0xbf, 0xf8, 0x1d, 0xa5, 0xb0};

void TX433Init() {
  // PD7/AIN1 (pin 13) = DIO port 4 on Jeenode xx
  DDRD |= _BV(DDD7);
}

// Compensation blabla xx OK for 5V
#define COMPENSATE 100

void sendBit(byte currentBit) {
  if (currentBit == 1) {
    delayMicroseconds(500-COMPENSATE);
    TX_ON();
    delayMicroseconds(1200 -20 - 500+COMPENSATE);
  } else {
    delayMicroseconds(900-COMPENSATE);
    TX_ON();
    delayMicroseconds(1200-20 - 900+COMPENSATE);
  }
  TX_OFF();
}

void sendPrehamble() {
  TX_ON();
  delayMicroseconds(2600);
  TX_OFF();
}

void sendON() {
  byte bitNb, bitNbToSend;
    sendPrehamble();
    for (bitNb = 0; bitNb < NB_BITS; bitNb++) {
      bitNbToSend = 7 - (bitNb % 8);
      sendBit((onFrame[bitNb / 8] >> bitNbToSend) & 1);
    }
}

void sendOFF() {
  byte bitNb, bitNbToSend;
    sendPrehamble();
    for (bitNb = 0; bitNb < NB_BITS; bitNb++) {
      bitNbToSend = 7 - (bitNb % 8);
      sendBit((offFrame[bitNb / 8] >> bitNbToSend) & 1);
    }
}

void switchON() {
  for (byte i = 0; i < 5; i++) {
    sendON();
    delay(23); delayMicroseconds(800);
  }
}

void switchOFF() {
  for (byte i = 0; i < 5; i++) {
    sendOFF();
    delay(23); delayMicroseconds(800);
  }
}


