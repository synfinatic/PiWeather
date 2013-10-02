/*
 * PiWeather Weather station data logger.  
 * Can be used with either JeeLink or any Arduino + RF12 
 * module.
 * 
 * Copyright 2013, Aaron Turner 
 */

#include <avr/pgmspace.h>
#include "PiWeather.h"
#include "RF12_IT_ext.h"
#include "Misc.h"
#include "ITPlusRX_ext.h"

/***********************************************
 * Globals 
 ***********************************************/
// SignalError tells if an error has to be signaled on LED, 0=No, 1&2=yes, 2 values for blinking
byte SignalError = 1;
boolean ErrorCondition = false;
unsigned long previousMillis = 0;

uint8_t Seconds = 0;
word Minutes = 0;
boolean ANewMinute = false;

/* Forward declare */
void RF12Init();


char CommonStrBuff[50], *PtData;

/***********************************************
 * setup() 
 ***********************************************/
void 
setup() {
    Serial.begin(57600);
    RF12Init();
    ITPlusRXSetup();
}

/***********************************************
 * loop() 
 ***********************************************/
void 
loop() {
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
        CheckRF12Recv();

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
}

/***********************************************
 * Other Code
 ***********************************************/

/*
 * Init our RF12 module 
 */
void
RF12Init() {
#ifdef USE_915Mhz 
    rf12_initialize(1, RF12_915MHZ, 0xd4);
    rf12_initialize_overide_ITP(915);
    DebugPrintln_P(PSTR("915Mhz radio init"));
#elif defined USE_868Mhz 
    rf12_initialize(1, RF12_868MHZ, 0xd4);
    rf12_initialize_overide_ITP(868);
    DebugPrintln_P(PSTR("868Mhz radio init"));
#else 
#error "Please define USE_915Mhz or USE_868Mhz in PiWeather.h"
#endif
}


void 
CheckRF12Recv() {
    if (rf12_recvDone()) {
        // If a "Receive Done" condition is signaled, we can safely use the RF12 library buffer up to the next call to
        // rf12_recvDone: RF12 tranceiver is held in idle state up to the next call.
        // Is it IT+ or Jeenode frame ?
        if (ITPlusFrame) {
            ProcessITPlusFrame();  // Keep IT+ logic outside this source files
        } else {
            if (rf12_crc == 0) {  // Valid RF12 Jeenode frame received
#ifdef RF12_DEBUG
                DebugPrint_P(PSTR("RF12 rcv: "));
                for (byte i = 0; i < rf12_len; ++i) {
                    Serial.print(rf12_data[i], HEX); Serial.print(' ');
                }
                Serial.println();
#endif
            }
        }
    }
}
