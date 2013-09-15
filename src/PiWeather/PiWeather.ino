
/**
 * Temperature data logger.
 *
 * Main module
 *
 * Gérard Chevalier, Jan 2011
 * Nov 2011, changed to integrate La Crosse IT+ protocol
 */
// After moving from Arduino 18 to 23, had to add this include here because when compiling, include order seems
// to have changed. Strange!
//#include <EtherCard.h>

#include "DataloggerDefs.h"
#include <avr/pgmspace.h>
//#include "dnslkup.h"
#include <avr/wdt.h>

extern void RF12Init();
extern void NetworkInitialize();
extern void TX433Init();
extern void WebSend();
extern void DecodeFrame();
extern void Get1820Tmp();
extern void CheckRF12Recept();
extern void switchON();
extern void switchOFF();
extern void DebugPrint_P(const char *);
extern void DebugPrintln_P(const char *);
extern void CheckProcessBrowserRequest();
extern void LoadConfig();
extern void ITPlusRXSetup();

extern byte CentralTempSignBit, CentralTempWhole, CentralTempFract;
extern Type_Channel ITPlusChannels[];
extern Type_Discovered DiscoveredITPlus[];
extern Type_Config Config;
extern word LastServerSendOK;
extern byte buf[];
extern byte DNSState;

boolean Acquire1820 = true;  // True to trigger a measure upon reset, and not wait first mn elapsed
boolean ANewMinute = false;
unsigned long previousMillis = 0;
// Most of time calculation done in mn with 8 bits, having so a roll-over of about 4 h
// But total nb of mn stored as 16 bits (~1092 h, ~45.5 days)
byte LastWebSend = 0;
word Minutes = 0;

// For seconds, 1 byte also used as we just want to check within 1 minute
byte Seconds = 0;

// xx comments
byte justSent = 0;
byte badPeriodNb = 0;
byte boxRebootCount = 0;
byte boxRebootFlag = BOX_REBOOT_IDLE;
boolean plugTestRequest = false;

// "0,-tt.dNL1,-tt.dNL2,-tt.dNL3,-tt.dNL0" xxxxxxxxxxxxxxxx 0,-tt.dNL1,-tt.dNL2,-tt.dNL3,-tt.dNL4,-tt.dNL5,-tt.dNL6,-tt.dNL0
char CommonStrBuff[50], *PtData;

// SignalError tells if an error has to be signaled on LED, 0=No, 1&2=yes, 2 values for blinking
byte SignalError = 1;
boolean ErrorCondition = false;


/* main Initialization */
/* ------------------- */
void setup() {
  Serial.begin(57600);
  DDRC |= _BV(DDC3);  // LED Pin = output
  LoadConfig();
  // Found this comment into network library: "init ENC28J60, must be done after SPI has been properly set up!"
  // So taking care of calling RF12 initialization prior ethernet initialization
  RF12Init();
//  NetworkInitialize();
  ITPlusRXSetup();
//  DS1820Init();
//  TX433Init();

  DebugPrintln_P(PSTR("Ready"));
/*
  for (byte i = 0; i < 3; i++) {  // Signal Init OK with 3 LED pulses
    RX_LED_ON();
    delay(150);
    RX_LED_OFF();
    delay(400);
  }
*/
  wdt_enable(WDTO_4S);
  // Send ON in case the switch is in OFF state
//  switchON();
}

void loop() {
  // Check if a new second elapsed
  if (millis() - previousMillis > 1000L) {
    previousMillis = millis();
    Seconds++;
    if (Seconds == 60) {
      Seconds = 0;
      Minutes++;
      ANewMinute = true;
    }

  // If one minute elapsed, check what we have to do
  if (ANewMinute) {
    ANewMinute = false;
    // Decrement LastReceiveTimer for all channels every mn...
    for (byte Channel = 0; Channel < ITPLUS_MAX_SENSORS; Channel++) {
      if (ITPlusChannels[Channel].LastReceiveTimer != 0) ITPlusChannels[Channel].LastReceiveTimer--;
    }
    for (byte Channel = 0; Channel < ITPLUS_MAX_DISCOVER; Channel++) {
      if (DiscoveredITPlus[Channel].LastReceiveTimer != 0) DiscoveredITPlus[Channel].LastReceiveTimer--;
    }

      PtData = CommonStrBuff;



    // DataStream 1 to ITPLUS_MAX_SENSORS are IT+ Sensors
      for (byte Channel = 0; Channel < ITPLUS_MAX_SENSORS; Channel++) {
        if (ITPlusChannels[Channel].SensorID != 0xff) {  // Send only if registered
          if (ITPlusChannels[Channel].LastReceiveTimer != 0) {  // Send only if valid temp received
            //                        "0,-tt.dNL1,-tt.dNL2,-tt.dNL3,-tt.dNL0"
            PtData += sprintf(PtData, "%d,", Channel + 1);
            if (ITPlusChannels[Channel].Temp & 0x80)
              *PtData++ = '-';
            PtData += sprintf(PtData, "%d.%d\r\n", ITPlusChannels[Channel].Temp & 0x7f, ITPlusChannels[Channel].DeciTemp);
          }
        }
      }

      // Remove last CR/LF
      *(PtData - 2) = 0;
  }
//  CheckProcessBrowserRequest();
  CheckRF12Recept();

  // Check error condition for signaling through LED
  ErrorCondition = false;
  for (byte Channel = 0; Channel < ITPLUS_MAX_SENSORS; Channel++) {
    if (ITPlusChannels[Channel].SensorID != 0xff &&  // La Crosse receive OK check, only if registered
    ITPlusChannels[Channel].LastReceiveTimer == 0) {
      ErrorCondition = true;
      break;
    }
  }
  /* xx Check removed as RF12 "enabling" was removed, always on error condition
   if (!ErrorCondition) {
   for (byte Channel = 0; Channel < MAX_JEENODE; Channel++) {
   if (RF12Channels[Channel].LastReceiveTimer == 0) {  // RF12 receive OK check
   ErrorCondition = true;
   break;
   }
   }
   }
   */

  }
  // Finally, keek the node alive by patting the dog
  wdt_reset();
}

