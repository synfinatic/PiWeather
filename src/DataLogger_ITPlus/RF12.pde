/**
 * Temperature data logger.
 *
 * This module is in charge of receiving other Jeenodes measures through RF12
 *
 * Gérard Chevalier, Jan 2011
 * Nov 2011, changed to integrate La Crosse IT+ protocol
 */

#include "DataloggerDefs.h"
#include <RF12.h>
#include <Ports.h>

// After IT+ addition into central node, added 2 preamble bytes to identify clearly the "Home Made Sensor" over RF12
#define CHECK1  0x10
#define CHECK2  0x01

extern void DebugPrint_P(const char *);
extern void DebugPrintln_P(const char *);
extern void ProcessITPlusFrame();

extern void rf12_initialize_overide_ITP ();
extern boolean ITPlusFrame;

Type_Channel RF12Channels[MAX_JEENODE];

void RF12Init() {
  rf12_initialize(1, RF12_868MHZ, 0xd4);
    
  // Overide settings for RFM01/IT+ compliance
  rf12_initialize_overide_ITP();
  
  DebugPrintln_P(PSTR("RF12Init"));
}

void CheckRF12Recept() {
  byte Channel;

  if (rf12_recvDone()) {
    // If a "Receive Done" condition is signaled, we can safely use the RF12 library buffer up to the next call to
    // rf12_recvDone: RF12 tranceiver is held in idle state up to the next call.
    // Is it IT+ or Jeenode frame ?
    if (ITPlusFrame)
      ProcessITPlusFrame();  // Keep IT+ logic outside this source files
    else {
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
   
   
