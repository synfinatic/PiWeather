/**
 * Temperature data logger.
 *
 * This module is in charge of receiving and decoding La Crosse technology IT+
 * protocol frames.
 *
 * Gérard Chevalier, Nov 2011
 * IT+ decoding was possible thank to
 *   - The great job done by fred, see here: http://fredboboss.free.fr/tx29/tx29_1.php?lang=en
 *   - And stuff found here: http://forum.jeelabs.net/node/110
 */

#include "Arduino.h"
#include "RF12_IT_ext.h"
#include <avr/pgmspace.h>
#include "Misc.h"
#include "PiWeather.h"

extern byte SignalError; // From PiWeather.ino

byte CheckITPlusRegistration(byte, byte, byte);
Type_Discovered DiscoveredITPlus[ITPLUS_MAX_DISCOVER];
Type_Channel ITPlusChannels[ITPLUS_MAX_SENSORS];

/* Initialization of this module */
/* ----------------------------- */
void 
ITPlusRXSetup() {
    DebugPrintln_P(PSTR("Init IT+"));

    for (byte i = 0; i < ITPLUS_MAX_SENSORS; i++)
        ITPlusChannels[i].LastReceiveTimer = 0;

    for (byte i = 0; i < ITPLUS_MAX_DISCOVER; i++)
        DiscoveredITPlus[i].SensorID = 0xff;
}

#define CRC_POLY 0x31
boolean 
CheckITPlusCRC(byte *msge, byte nbBytes) {
    byte reg = 0;
    short int i;
    byte curByte, curbit, bitmask;
    byte do_xor;

    while (nbBytes-- != 0) {
        curByte = *msge++; bitmask = 0b10000000;
        while (bitmask != 0) {
            curbit = ((curByte & bitmask) == 0) ? 0 : 1;
            bitmask >>= 1;
#ifdef DEBUG_CRC
            sprintf("byte %02x", curByte);
#endif
            do_xor = (reg & 0x80);

            reg <<=1;
            reg |= curbit;
#ifdef DEBUG_CRC
            sprintf(" b=%d ", curbit);
#endif

            if (do_xor)
            {
#ifdef DEBUG_CRC
                sprintf(" Xoring %02x", reg);
#endif
                reg ^= CRC_POLY;
#ifdef DEBUG_CRC
                sprintf(" > %02x", reg);
#endif
            }

#ifdef DEBUG_CRC
            sprintf(" reg %02x\n", reg);
#endif
        }
    }
    return (reg == 0);
}

void 
ProcessITPlusFrame() {
    byte Temp, DeciTemp, SensorId, ResetFlag, Channel, Hygro,lcSensorId;
#ifdef ITPLUS_DEBUG
    float TempF;
    char FloatBuff[6];
#endif 

    // Here, there are chance that the frame just received is an IT+ one (flag ITPlusFrame set), but not sure.
    // So, check CRC, and decode if OK.
#ifdef ITPLUS_DEBUG_FRAME
    sprintf("GotIT+: %02x %02x %02x %02x %02x\n", 
            rf12_buf[0], rf12_buf[1], rf12_buf[2], rf12_buf[3], rf12_buf[4]);
#endif

    if (CheckITPlusCRC((byte *)rf12_buf, 5)) {
        // OK, CRC is valid, we do have an IT+ valid frame
        // Signal reception on LED. tbd: enhance this code as it actively take CPU cycle, and with IT+ 4 / 8 s frame pace
        // it's not a good idea...
//        if (SignalError == 0) {  // Otherwise don't touch LED
            //      RX_LED_ON(); delay(150);  // xx tbd: set new algorythm
            //      RX_LED_OFF(); delay(50);
            //RX_LED_ON(); delay(150);
            //RX_LED_OFF();
//        }

        // Extract the Sensor and lcSensorId values
        SensorId = ((rf12_buf[0] & 0x0f) << 4) + ((rf12_buf[1] & 0xf0) >> 4) >> 2;
        lcSensorId = (((rf12_buf[0] & 0x0f) << 4) + ((rf12_buf[1] & 0xf0) >> 4)) & 0xfc;
 
        // Reset flag is stored as bit #6 in sensorID.
        ResetFlag = (rf12_buf[1] & 0b00100000) << 1;

        // Sign bit is stored into bit #7 of temperature. IT+ add a 40° offset to temp, so < 40 means negative
        Temp = (((rf12_buf[1] & 0x0f) * 10) + ((rf12_buf[2] & 0xf0) >> 4));
        DeciTemp = rf12_buf[2] & 0x0f;
        if (Temp >= 40) {
            Temp -= 40;
        } else {
            if (DeciTemp == 0) {
                Temp = 40 - Temp;
            } else {
                Temp = 39 - Temp;
                DeciTemp = 10 - DeciTemp;
            }
            Temp |= 0b10000000;
        }

        Hygro = rf12_buf[3] & 0x7f;

#ifdef ITPLUS_DEBUG
        //Serial.print("Id: "); printHex(SensorId);
        //Serial.print(" - lcId: "); printHex(lcSensorId);
        if (ResetFlag) {
            Serial.print("RESET!  ");
        }

        sprintf("Id: 0x%02x - lcId: 0x%02x Temp: ", SensorId, lcSensorId);


        // is value negative?
        if (Temp & 0b10000000)
            Serial.print("-");

        // calc temp in Farenhiet
        TempF = (((float)Temp + ((float)DeciTemp * 0.1)) * 1.8) + 32;

        // we don't store it as a float!
        sprintf("%02d.%dC (%sF)", Temp & 0x7F, DeciTemp, ftoa(FloatBuff, TempF, 1));

        // Apparently 106 is invalid, but we are seeing 125 for bogus????
        if (Hygro != 106) {
            sprintf(" Hygro: %02d%%\n", Hygro);
        } else {
            Serial.println();
        }
#endif

        // Process received measures (only if sensor is registered)
        if ((Channel = CheckITPlusRegistration((SensorId | ResetFlag), Temp, DeciTemp)) != 0xff) {
            ITPlusChannels[Channel].Temp = Temp;
            ITPlusChannels[Channel].DeciTemp = DeciTemp;
        }
    } else {
#ifdef ITPLUS_DEBUG_FRAME
        DebugPrintln_P(PSTR("BadCRC"));
#endif
    }
}

// Find an IT+ ID into the registered IDs table. If found, return the index in table
// Bit 6 of ID is the "Sensor Reseted" indicator, meaning the battery was replaced and a new
// ID was generated. This flag is held on for about 4h30mn, enabling sensor / receiver peering.
// This function should be passed the "raw ID", including the flag (in bit #6) in order to store it
// into the discovered table with the sensor id to distinguish lists in display later on.
// If the ID is not found, the sensor is added to the discovered IDs table (if not already there).
// When ID not found, return 0xff
byte 
CheckITPlusRegistration(byte id, byte Temp, byte DeciTemp) {
    byte i, FreeIndex;
    unsigned int MaxTime;

#ifdef ITPLUS_DEBUG 
    sprintf("Checking IT+ Registration: id:%02x, temp:%d, decitemp:%d\n", id, Temp, DeciTemp);
#endif 

    for (i = 0; i < ITPLUS_MAX_SENSORS; i++) {
        if (ITPlusChannels[i].SensorID == (id & ITPLUS_ID_MASK)) {  // Do the search without reset flag
            // OK Found, reset receive timer & return channel = index
            ITPlusChannels[i].LastReceiveTimer = SENSORS_RX_TIMEOUT;
#ifdef ITPLUS_DEBUG 
            sprintf("Found sensor in ITPlusChannels slot: %d\n", i);
#endif
            return i;
        }
    }

    // The sensor is not registered, try to find it into discovered table
    for (i = 0; i < ITPLUS_MAX_DISCOVER; i++) {
        if ((DiscoveredITPlus[i].SensorID & ITPLUS_ID_MASK) == (id & ITPLUS_ID_MASK)) {
            // Found! Update the last receive timer
            DiscoveredITPlus[i].LastReceiveTimer = ITPLUS_DISCOVERY_PERIOD;
            DiscoveredITPlus[i].Temp = Temp;
            DiscoveredITPlus[i].DeciTemp = DeciTemp;

#ifdef ITPLUS_DEBUG 
            sprintf("Sensor isn't registred, updating DiscoveredITPlus slot: %d\n", i);
#endif
            // And return "NOT Found"
            return 0xff;
        }
    }

    // Not found: insert into a free slot, including the reset flag.
    for (i = 0; i < ITPLUS_MAX_DISCOVER; i++) {	// Find a free slot
        if (DiscoveredITPlus[i].SensorID == 0xff) {
            DiscoveredITPlus[i].SensorID = id;
            DiscoveredITPlus[i].LastReceiveTimer = ITPLUS_DISCOVERY_PERIOD;
            DiscoveredITPlus[i].Temp = Temp;
            DiscoveredITPlus[i].DeciTemp = DeciTemp;
#ifdef ITPLUS_DEBUG 
            sprintf("Sensor isn't known, adding it into DiscoveredITPlus slot: %d\n", i);
#endif
            return 0xff;
        }
    }

    // No free slot found. Use the one with oldest receiving time.
    MaxTime = ITPLUS_DISCOVERY_PERIOD;
    FreeIndex = 0;
    for (i = 0; i < ITPLUS_DISCOVERY_PERIOD; i++) {
        if (DiscoveredITPlus[i].LastReceiveTimer < MaxTime) {
            MaxTime = DiscoveredITPlus[i].LastReceiveTimer;
            FreeIndex = i;
        }
    }
    DiscoveredITPlus[FreeIndex].SensorID = id;
    DiscoveredITPlus[FreeIndex].LastReceiveTimer = ITPLUS_DISCOVERY_PERIOD;
    DiscoveredITPlus[FreeIndex].Temp = Temp;
    DiscoveredITPlus[FreeIndex].DeciTemp = DeciTemp;
#ifdef ITPLUS_DEBUG 
            sprintf("Sensor overload! Re-using DiscoveredITPlus slot: %d\n", FreeIndex);
#endif
    return 0xff;
}

