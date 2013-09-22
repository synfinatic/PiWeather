#ifndef PiWeather_H
#define PiWeather_H 

#include "RF12_IT_ext.h"
#include <Arduino.h>

/* Only define 915 or 868 below depending on 
 * what version of hardware you have
 */
#define USE_915Mhz
// #define USE_868Mhz

#define DEBUG
#define RF12_DEBUG  // General RF12 radio debug 
#define RF12_FRAME_DEBUG // Debug RF12 frames 
#define DEBUG_CRC

#define ITPLUS_DEBUG 
#define ITPLUS_DEBUG_FRAME
#define ITPLUS_MAX_SENSORS 15 
#define ITPLUS_MAX_DISCOVER  ITPLUS_MAX_SENSORS
#define ITPLUS_DISCOVERY_PERIOD 255
#define ITPLUS_ID_MASK	0b00111111

#define SENSORS_RX_TIMEOUT 5



// Radio Sensor structure (both RF12 & IT+)
typedef struct {
  char SensorID;
  char LastReceiveTimer;
  char Temp, DeciTemp;
} Type_Channel;

// Radio Sensor structure for IT+ Sensors discovery process
typedef struct {
  char SensorID;
  char LastReceiveTimer;
  char Temp, DeciTemp;
} Type_Discovered;

#endif
