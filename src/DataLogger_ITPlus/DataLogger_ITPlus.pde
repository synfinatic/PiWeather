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
#include <EtherCard.h>

#include "DataloggerDefs.h"
#include <avr/pgmspace.h>
#include "dnslkup.h"
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
  Serial.begin(115200);
  DDRC |= _BV(DDC3);  // LED Pin = output
  LoadConfig();
  // Found this comment into network library: "init ENC28J60, must be done after SPI has been properly set up!"
  // So taking care of calling RF12 initialization prior ethernet initialization
  RF12Init();
  NetworkInitialize();
  ITPlusRXSetup();
  DS1820Init();
  TX433Init();

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
  switchON();
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
    // Error signaling code : must be run once per second.
    if (SignalError != 0) {
      if (SignalError == 1) {
        RX_LED_ON(); 
        SignalError = 2;
      } 
      else {
        RX_LED_OFF(); 
        SignalError = 1;
      }
    }
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

    // To simplify, a new DS1820 measure is triggered every minute
    Acquire1820 = true;

    // Reset DNS Lookup State Machine every mn if got no answer to force retry
    if (DNSState == DNS_WAIT_ANSWER)
      DNSState = DNS_INIT;

    // Check if we had max retries sending over MAX_WEB_BAD_PERIOD to trigger ADSL BOX reboot.
    // Here, one mn elapsed since last send request, letting enough margin to test if it was OK.
    if (justSent == MAX_WEB_RETRY) {
      if (badPeriodNb == MAX_WEB_BAD_PERIOD - 1) {  // Is the nb of period with all retries failed above the limit?
        // YES: request a reboot
        boxRebootFlag = BOX_REBOOT_INIT;
        justSent = 0;  // No need to try again...
#ifdef DEBUG_BOX_REBOOT
        printTime(); 
        DebugPrintln_P(PSTR("REBOOT REQ"));
#endif
      } 
      else {
        badPeriodNb++;
        justSent = 0;  // Prepare a new cycle
#ifdef DEBUG_BOX_REBOOT
        printTime(); 
        DebugPrintln_P(PSTR("BAD Period"));
#endif
      }
    }

    // ADSL BOX Reboot management. Will transition state every minute.
    switch (boxRebootFlag) {
    case BOX_REBOOT_IDLE:
      break;
    case BOX_REBOOT_INIT:
#ifdef DEBUG_BOX_REBOOT
      printTime(); DebugPrintln_P(PSTR("BoxOFF"));
#endif
      switchOFF();  // Would be nice to signal on LED too xx
      boxRebootFlag = BOX_REBOOT_DOWN;
      break;
    case BOX_REBOOT_DOWN:
#ifdef DEBUG_BOX_REBOOT
      printTime(); DebugPrintln_P(PSTR("BoxON"));
#endif
      switchON();
      boxRebootFlag = BOX_REBOOT_IDLE;
      boxRebootCount++;
      badPeriodNb = 0;
      break;
    }

    /*
Watchdog:
     #include <avr/wdt.h>
     wdt_enable(WDTO_1S);
     wdt_reset();
     */

    // Check if we have to send to WEB server (and send only if DNS lookup was OK or not needed)
    // We send every "WebSendPeriod" mn. If a send fails, there will be MAX_WEB_RETRY attempts (at one mn interval) within the
    // current period, but the next sed period will be still calculated from the fisrt attempt (not the last good try) to keep
    // a constant sending period on avearage.
    if ((((byte)((byte)Minutes - LastWebSend) >= Config.WebSendPeriod) && DNSState == DNS_GOT_ANSWER) ||
      (justSent != 0)) {
      if (justSent == 0) {  // First try for current period
        LastWebSend = (byte)Minutes;
        justSent = 1;
#ifdef DEBUG_BOX_REBOOT
        printTime(); 
        DebugPrintln_P(PSTR("NewPer"));
#endif
      } 
      else {
        justSent++;  // Counting tries for current period
#ifdef DEBUG_BOX_REBOOT
        printTime(); 
        DebugPrintln_P(PSTR("Retry"));
#endif
      }

      PtData = CommonStrBuff;

      // DataStream 0 is local DS1820 temp
      PtData += sprintf(PtData, "0,");
      if (CentralTempSignBit)
        *PtData++ = '-';
      PtData += sprintf(PtData, "%d.%d\r\n", CentralTempWhole, CentralTempFract);

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
#if DEBUG_HTTP
      DebugPrint_P(PSTR("POST ")); 
      Serial.println(CommonStrBuff);
#endif
      WebSend(CommonStrBuff);
    }
  }

  if (Acquire1820) {
    Get1820Tmp();
    Acquire1820 = false;
  }

  CheckProcessBrowserRequest();
  CheckRF12Recept();

  // Process remote Plug & WatchDog test request
  if (plugTestRequest) {
    for (byte i = 0; i < 15; i++) {
      // Send ON
      switchON();
      // Wait 2 s between ON/OFF
      delay(2000);wdt_reset();
      // Send OFF
      switchOFF();
      // Wait 2 s between ON/OFF
      delay(2000);wdt_reset();
    }
    while (true) ;
  }
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
  if (!ErrorCondition) {  // WEB Server send OK check
    if ((byte)((byte)Minutes - (byte)LastServerSendOK) >=  3 * Config.WebSendPeriod)
      ErrorCondition = true;
    // In a next release, trigger also a new DNS lookup in case Server IP changed, for now, assume a reset will do the job.
  }
  if (ErrorCondition) {
    if (SignalError == 0) SignalError = 1;  // Else, meaning that already signaled
  } 
  else
    SignalError = 0;

  // Finally, keek the node alive by patting the dog
  wdt_reset();
}

