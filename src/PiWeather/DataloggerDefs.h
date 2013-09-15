/**
 * Temperature data logger.
 *
 * Global Includes
 *
 * Gérard Chevalier, Jan 2011
 * Nov 2011, changed to integrate La Crosse IT+ protocol
 */
 #ifndef DATALOGGER_DEFS_H
 #define DATALOGGER_DEFS_H
 #include <Arduino.h>
//#include "Arduino.h"
// Central Node DS1820 sensor debug flags
//#define DS1820_DEBUG
//#define DS1820_DEBUG_LOW
//#define DEBUG_BOX_REBOOT


// RF12 transmissions debuging flag (Only jeenode not TX29)
//#define RF12_DEBUG

// IT+ Decoding debug flags
#define ITPLUS_DEBUG_FRAME
#define ITPLUS_DEBUG
//#define DEBUG_CRC

// Network debuging flag
//#define DEBUG_ETH 1 // set to 1 to show incoming requests on serial port
//#define DEBUG_DNS 1
//#define DEBUG_HTTP 1

#ifdef DS1820_DEBUG_LOW
  #define DS1820_DEBUG
#endif

// Total number of tries for sending measures over the Web
#define MAX_WEB_RETRY		3
// xx comments
#define MAX_WEB_BAD_PERIOD	2
#define BOX_REBOOT_IDLE		0
#define BOX_REBOOT_INIT		1
#define BOX_REBOOT_DOWN		2

#define SENSORS_RX_TIMEOUT 5

#ifndef DATALOGGERDEFS

#define ITPLUS_MAX_SENSORS  15
//#define ITPLUS_MAX_DISCOVER  5
#define ITPLUS_MAX_DISCOVER  ITPLUS_MAX_SENSORS
#define ITPLUS_DISCOVERY_PERIOD 255

#define FIRST_JEENODE  10
#define MAX_JEENODE    3

// Structure in RAM holding configuration, as stored in EEPROM
typedef struct {
    byte LocalIP[4];    // Keep those 3 parameters at the begining
    byte RouterIP[4];   // for the hard reset config
    byte ServerIP[4];   // working
    byte WebSendPeriod;
    byte ITPlusID[ITPLUS_MAX_SENSORS];  // IT+ Sensors ID for Registered sensors
} Type_Config;

#define DNS_INIT	0
#define DNS_WAIT_ANSWER	1
#define DNS_GOT_ANSWER	2
#define DNS_NO_HOST	3

// Radio Sensor structure (both RF12 & IT+)
typedef struct {
  byte SensorID;
  byte LastReceiveTimer;
  byte Temp, DeciTemp;
} Type_Channel;

// Radio Sensor structure for IT+ Sensors discovery process
typedef struct {
  byte SensorID;
  byte LastReceiveTimer;
  byte Temp, DeciTemp;
} Type_Discovered;

#define RX_LED_ON()   ((PORTC |=  (1<<PORTC3)))
#define RX_LED_OFF()  ((PORTC &= ~(1<<PORTC3)))

#define PARAM_RESET_DATA_PORT  PORTD
#define PARAM_RESET_PIN_PORT   PIND
#define PARAM_RESET_PIN_NB     6

#define DATALOGGERDEFS
#endif
#endif //DATALOGGER_DEFS_H

