/**
 * Temperature data logger.
 *
 * Misc. functions module.
 *
 * Gérard Chevalier, Jan 2011
 * Nov 2011, changed to integrate La Crosse IT+ protocol
 */

#include <avr/eeprom.h>

// Nb of milliseconds in day, hour, min, sec
#define DAY     86400000
#define HOUR    3600000
#define MINUTE  60000
#define SECOND  1000

// Print functions using Flash memory to avoid copying string constants to RAM at initialization.
void DebugPrint_P(const char *addr) {
  char c;

  while ((c = pgm_read_byte(addr++)))
    Serial.write(c);
}

void DebugPrintln_P(const char *addr) {
  DebugPrint_P(addr);
  Serial.println();
}

#if (defined DEBUG_BOX_REBOOT || defined DEBUG_DNS)
void printDigits(byte digits) {
  // Function for digital clock display: prints colon and leading 0
  Serial.write(':');
  if(digits < 10)
    Serial.write('0');
  Serial.print(digits,DEC);  
} 

// Formated Time Printing
void printTime(){
  long timeNow = millis();
  
  int days = timeNow / DAY ;
  int hours = (timeNow % DAY) / HOUR;
  int minutes = ((timeNow % DAY) % HOUR) / MINUTE ;
  int seconds = (((timeNow % DAY) % HOUR) % MINUTE) / SECOND;

  Serial.print(days,DEC);  
  printDigits(hours);  
  printDigits(minutes);
  printDigits(seconds);
  Serial.write(' ');
}
#endif


/**********************************************************************
 *  Configuration functions
 **********************************************************************/
Type_Config Config;  // Holds all configuration parameters

// The default configuration values NodeIP, Gateway, serverIP, WebSendPeriod
Type_Config DefaultConfig PROGMEM = {{ 192,168,1,5 }, { 192,168,1,1 }, {0,0,0,0}, 15};

// The same into the EEPROM
Type_Config CONFIG_STRUCT_EEPROM EEMEM;

// Some configuration parameters are too long to be copied into RAM, they will be maintained only into EEPROM
char SRV_HOST_EEPROM[30] EEMEM;
char SRV_URL_EEPROM[50] EEMEM;
char SRV_HDR_EEPROM[90] EEMEM;
/**** Next one MUST BE THE LAST! ****/
byte CONFIG_CKS_EEPROM EEMEM;

// Initial Checksum "seed". To be set to something <> 0 as a blank EEPROM will has all 0. For each change in EEPROM
// structure, change this to invalidate content and force re-init.
#define CKS_INIT_SEED  33

extern Type_Channel ITPlusChannels[];  // Live table of IT+ Sensors

// Compute all configuration parameters CKS and write it into EEP
static void WriteEEPCKS() {
  byte CKS;

  CKS = CKS_INIT_SEED;
  for (int i = 0; i < (int)&CONFIG_CKS_EEPROM; i++)
    CKS += eeprom_read_byte((byte *)i);
  eeprom_write_byte(&CONFIG_CKS_EEPROM, CKS);
}

// Writes the configuration parameters stored in config struct into EEPROM & Update CKS
static void SaveConfig() {
  byte *ptConfig, *ptEEPROM;
  ptConfig = (byte *) &Config;
  ptEEPROM = (byte *) &CONFIG_STRUCT_EEPROM;
  for (byte i = 0; i < sizeof(Config); i++) eeprom_write_byte(ptEEPROM++, *ptConfig++);
  // Update CKS into EEP
  WriteEEPCKS();
}

// Resets configuration parameters stored in config struct to default and other strings to null
// Save also into EEPROM
static void ResetConfig() {
  // First part with memcopy
  memcpy_P(&Config, &DefaultConfig, sizeof(Config));
  // ITPlusID size vary on ITPLUS_MAX_SENSORS: cannot use memcpy
  for (byte i = 0; i < ITPLUS_MAX_SENSORS; i++)
    ITPlusChannels[i].SensorID = Config.ITPlusID[i] = 0xff;  // Initialize also live IT+ table

  // Init other stings to null
  eeprom_write_byte((byte *)&SRV_HOST_EEPROM[0], 0);
  eeprom_write_byte((byte *)&SRV_URL_EEPROM[0], 0);
  eeprom_write_byte((byte *)&SRV_HDR_EEPROM[0], 0);
  
  // Write config struct to EEP, this will also compute and update CKS on all saved parameters
  SaveConfig();
}

// Initial loading of configuration parameters from EEPROM
static void LoadConfig() {
  byte CKS;

  // Set pull-up on pin used to reset config in order to check correctly
  // On POR, all DDR = 0 ==> pin = input, but no pull-up beacause:
  // When input, if PORTxn is 1, pull-up activated, 0 on POR ==> no pull-up
  PARAM_RESET_DATA_PORT |= (1 << PARAM_RESET_PIN_NB);

//  DebugPrint_P(PSTR("Load Config "));
  // First check if EEPROM has valid data
  CKS = CKS_INIT_SEED;
  for (int i = 0; i < (int)&CONFIG_CKS_EEPROM; i++)
    CKS += eeprom_read_byte((byte *) i);

  // If invalid CKS, initialize all parameters in EEPROM
  if (CKS != eeprom_read_byte(&CONFIG_CKS_EEPROM)) {
//    DebugPrintln_P(PSTR("CKS KO"));

    // Copy initial values to config struct
    ResetConfig();
  } else {  // Checksum OK, Load the valid config if not reset requested
//    DebugPrintln_P(PSTR("CKS OK"));
    
    // Check if a HARD RESET config is requested (PARAM_RESET_PIN grounded to low)
    if ((PARAM_RESET_PIN_PORT & (1 << PARAM_RESET_PIN_NB)) == 0) {
      // We only reset network parameters stored into config structure because others do not prevent from running
      // the web interface, that is LocalIP[4], RouterIP[4] & ServerIP[4]
//      DebugPrintln_P(PSTR("Reset Conf"));
      memcpy_P(&Config, &DefaultConfig, sizeof(Config));
      SaveConfig();
      
      // Enter an infinite loop with fast flashing LED to signal param reset and that user must remove jumper
      while (true) {
        RX_LED_ON();
        delay(150);
        RX_LED_OFF();
        delay(400);
      }
    }
    
    // Otherwise, load config structure from EEPROM
    byte *ptConfig, *ptEEPROM;
    ptConfig = (byte *) &Config;
    ptEEPROM = (byte *) &CONFIG_STRUCT_EEPROM;
    for (byte i = 0; i < sizeof(Config); i++) *ptConfig++ = eeprom_read_byte(ptEEPROM++);

    // Load registered IT+ sensors IDs
    for (byte i = 0; i < ITPLUS_MAX_SENSORS; i++)
      ITPlusChannels[i].SensorID = Config.ITPlusID[i];
  }
}


