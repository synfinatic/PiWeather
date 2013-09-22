/**
 * Temperature data logger.
 *
 * This module is in charge of all networking processing.
 *
 * Gérard Chevalier, Jan 2011
 * Nov 2011, changed to integrate La Crosse IT+ protocol
 */

// As this project uses Jeenode that is using enc28j60 ethernet chip, the library used is the one from Guido Socher.
// (See copyrights in source files).
// Has been slightly adapted by Jean-Claude Wippler to work with Jeenode,
// and by me to change parameters location from Flash to EEPROM (see bellow).
// Some explanation can also be found here: http://www.tuxgraphics.org/electronics/200905/embedded-tcp-ip-stack.shtml
#include "DataloggerDefs.h"
#include <EtherCard.h>
#include <Ports.h>
#include <RF12.h>
#include "dnslkup.h"

/********************/
/* IMPORTANT NOTICE */
/********************/
// The following function 
// void client_browse_url(prog_char *urlbuf, char *urlbuf_varpart, prog_char *hoststr,void (*callback)(byte,uint16_t,uint16_t))
// void client_http_post(prog_char *urlbuf, prog_char *hoststr, prog_char *additionalheaderline,char *postval,void (*callback)(byte,uint16_t,uint16_t))
// into ip_arp_udp_tcp.cpp has been modified.
// This was for changing parameters urlbuf, hoststr & additionalheaderline from being processed as
// laying into EEPROM instead of flash (no more prog_char *) into client_browse_url & client_http_post functions,
// we changed processing of client_urlbuf, client_hoststr & client_additionalheaderline parameters.
// Those variables are copied into internal buffers using fill_tcp_data_p.
// We had to change the call to fill_tcp_data_p by a call to fill_tcp_data_e and implement fill_tcp_data_e
// A #define USE_EEP_INSTEADOF_FLASH placed into ip_arp_udp_tcp.cpp is driving the change.

// IP @ settings
// The beginning of address is hardcoded to 192.168 and cannot be changed
// Then the node address will be 192.168.A.B where A & B can be set via the WEB interface
// A & B will be stored within EEPROM and myip[2&3] upon startup
// We consider the network mask to be 255.255.255.0 (not managed in the Ethernet library), and hence,
// the Gateway will be 192.168.A.G, G can be set via the WEB interface, and is stored into EEPROM
// 192.168 is hard coded via the DefaultConfig struct bellow.

// Reference to temperature data that will be sent over HTTP.
extern byte CentralTempSignBit, CentralTempWhole, CentralTempFract;
extern Type_Channel ITPlusChannels[];
extern Type_Discovered DiscoveredITPlus[];
extern Type_Config Config;
extern void SaveConfig();

extern Type_Config CONFIG_STRUCT_EEPROM EEMEM;
extern char SRV_HOST_EEPROM[] EEMEM;
extern char SRV_URL_EEPROM[] EEMEM;
extern char SRV_HDR_EEPROM[] EEMEM;
extern byte CONFIG_CKS_EEPROM EEMEM;
extern byte justSent;
extern byte boxRebootCount;
extern boolean plugTestRequest;

// ethernet interface mac address - must be unique on your network
byte mymac[6] = { 0x54,0x55,0x58,0x10,0x00,0x26 };  // Not configurable

// IP address of the web server to contact for posting data.
// If WEB Server is on internet, this address is asked via DNS lookup from Server Host Name.
// If WEB Server is on local network where host is not defined in DNS, the convention is that if the server address
// is defined via the WEB interface (!0), it is used "as is", adding the host name into the request.
uint8_t websrvip[4];  // So will be either config defined or comming from DNS request answer.

byte DNSState;

word SentCount;

// TCP PORT for send / receive NOT configurable via WEB interface
#define HTTP_PORT 80

byte buf[800];      // tcp/ip send and receive buffer
static BufferFiller bfill;  // used as cursor while filling the buffer

word LastServerSendOK;

boolean LNKUP=false;//xxgg

EtherCard eth;

byte LastRemovedSensorID, LastRemovedSensorIndex;

/**********************************************************************
 *  Initialization and configuration functions
 **********************************************************************/

/* Initialization of this module */
/* ----------------------------- */
void NetworkInitialize() {
  LastServerSendOK = 0; SentCount = 0;
  LastRemovedSensorID = 0xff;

#if DEBUG_ETH
  DebugPrintln_P(PSTR("Init NW"));
#endif
  // Init ENC28J60, must be done after SPI has been properly set up! (means RF12Init must be called before)
  eth.initialize(mymac);
  
  // Initialize TCP stuff
  eth.initIp(mymac, (byte *)Config.LocalIP, HTTP_PORT);
  client_set_gwip((byte *)Config.RouterIP);

  // DNS Lookup: if no server IP set in config (e.g. first byte = 0), asks to DNS
  if (Config.ServerIP[0] == 0) {
    // But Only if Server name set
    if (eeprom_read_byte((byte *)&SRV_HOST_EEPROM[0]) != 0)
      DNSState = DNS_INIT;  // Signal to send DNS request
    else
      DNSState = DNS_NO_HOST;  // Will not send DNS request & not signal misconfiguration
  } else {
    for (byte i = 0; i < 4; i++) websrvip[i] = Config.ServerIP[i];
    client_set_wwwip(websrvip);
    DNSState = DNS_GOT_ANSWER;  // This state used also to signal "IP Got from config", no need to ask DNS again
  }
}

/**********************************************************************
 *  WEB pages functions
 *
 * Pages structure & addresses are the following:
 * 
 * Home   /
 * Status /s
 * Config /c
 *  Sensors /d [IT+ Sensors registering page]
 *   Remove  /k [Remove a sensor from registered table]
 *   Cancel  /z [Cancel last remove processing]
 *   Add     /j [Add Sensors page]
 *    Clear  /C [Clear the discovery table]
 *    Regis   /r [Register Sensor Processing]
 *  Srv @   /e
 *   Submit Name /h [Host Name Setting]
 *   Submit IP   /i [Host IP Setting]
 *  API     /a
 *   Submit URL  /u [API URL Setting]
 *   Submit Head /x [API Extra Header Setting]
 *  Local @ /l
 *   Submit      /m [A, B & G values Setting]
 *  Misc    /o
 *   Submit Per  /p [Sending Period Setting]
 *   WDT & Plug Test /w
 *  Err   /E
 *
 **********************************************************************/
static char okHeader[] PROGMEM = 
    "HTTP/1.0 200 OK\r\n"
    "Content-Type: text/html\r\n"
    "Pragma: no-cache\r\n";
static char redirHeader[] PROGMEM = 
    "HTTP/1.0 302 found\r\nLocation: ";
static char BreakAndCRLF[] PROGMEM = "<br/>\r\n";
static char BackToC[] PROGMEM = "<input type=button value=\"Back\" onclick=\"location.replace('/c');\">";

// HOME
// ----
static void homePage(BufferFiller& buf) {
  buf.emit_p(PSTR("$F\r\n"
    "<title>DataLogger</title><H1>DataLogger</H1>"
    "<a href='s'>Status</a><br/><a href='c'>Configure</a>"), okHeader);
}

// STATUS
// ------
static void StatusPage(BufferFiller& buf) {
  buf.emit_p(PSTR("$F\r\n"
    "<meta http-equiv='refresh' content='$D'/>"
    "<title>Status</title>" 
    "<a href='/'>Home</a>"), okHeader, 5);  // Set fixed refresh time.
  buf.emit_p(PSTR(
    "<H1>Status</H1>"));

  // Print DNS status    
  switch (DNSState) {
    case DNS_WAIT_ANSWER:
      buf.emit_p(PSTR(
        "<H2>Resolving DNS</H2>")); break;
    case DNS_NO_HOST:
      buf.emit_p(PSTR(
        "<H2>No SrvName for DNS</H2>")); break;
  }

  // Print UpTime
  buf.emit_p(PSTR(
    "<H3>Datalogger</H3>Uptime: "));

  // Print uptime HH:MM:SS (roll over every 100 h, need to be enhanced)
  unsigned long t = millis() / 1000;
  word h = t / 3600;
  byte m = (t / 60) % 60;
  byte s = t % 60;
  buf.emit_p(PSTR(
    "$D$D:$D$D:$D$D"), h/10, h%10, m/10, m%10, s/10, s%10);

  // Print elapsed time since last send (in mn)
  buf.emit_p(PSTR("<br/>Last POST: "));
  if (SentCount != 0) {
    h = (Minutes - LastServerSendOK);  // 'h' variable reused because it's a word, but NOT holding hours here.
    m = h % 60;
    h = h / 60;
    buf.emit_p(PSTR("$D$D:$D$D ($D POST)"), h/10, h%10, m/10, m%10, SentCount);
  } else
    buf.emit_p(PSTR("None"));
  
  // Print number of ADSL Box reboot
  buf.emit_p(PSTR("<br/>Box Reboot: "));
  buf.emit_p(PSTR("$D"), boxRebootCount);
  
  // Print central node temp
  buf.emit_p(PSTR("<br/>Temp: "));
  if (CentralTempSignBit != 0)
    buf.emit_raw("-", 1);
  buf.emit_p(PSTR("$D$D.$D"), CentralTempWhole/10, CentralTempWhole%10, CentralTempFract);

  // Print IT+ sensors temps
  buf.emit_p(PSTR("<H3>Sensors</H3>"));

  for (byte Channel = 0; Channel < ITPLUS_MAX_SENSORS; Channel++) {
    if (Channel != 0) buf.emit_p(PSTR("<br/>"));
    buf.emit_p(PSTR("Ch$D: "), Channel + 1);
    if (ITPlusChannels[Channel].SensorID != 0xff) {
      if (ITPlusChannels[Channel].LastReceiveTimer != 0) {
        if ((ITPlusChannels[Channel].Temp & 0x80) != 0)
          buf.emit_raw("-", 1);
        buf.emit_p(PSTR("$D.$D"), ITPlusChannels[Channel].Temp & 0x7f, ITPlusChannels[Channel].DeciTemp);
      } else {
        buf.emit_p(PSTR("Stalled"));
      }
    } else
      buf.emit_p(PSTR("Not Reg"));
  }
}

// Global configuration
// --------------------
static void ConfigPage(BufferFiller& buf) {
  buf.emit_p(PSTR("$F\r\n"
    "<title>Config</title><H1>Config</H1>"
    "<a href='/'>Home</a><br/>"
    "<a href='d'>Sensors</a><br/>"
    "<a href='e'>Server @</a><br/>"
    "<a href='a'>API</a><br/>"
    "<a href='l'>Local @</a><br/>"
    "<a href='o'>Misc</a><br/>"), okHeader);
}

static int getIntArg(const char* data, const char* key, int value =-1) {
    char temp[10];
    if (find_key_val(data + 7, temp, sizeof(temp), key) > 0)
        value = atoi(temp);
    return value;
}

// On all config pages, there are as many HTML forms as parameters to simplify decoding and having
// shorter data length (ethernet buffer size limitation).

// Sensors configuration: displays registered IT+ sensors
// ------------------------------------------------------
static void SensorsConfigPage(BufferFiller& buf) {
  // xx to do add t° display as in discovery mode
  buf.emit_p(PSTR("$F\r\n<title>Config</title>"
    "<a href='/'>Home</a>"
    "<h1>Registered Sensors</h1>"
    "<table border=\"1\"><tr><th>Id</th><th>Chan</th><th>Remove</th></tr>"), okHeader);

  for (byte i = 0; i < ITPLUS_MAX_SENSORS; i++) {
    if (ITPlusChannels[i].SensorID != 0xff) {
      buf.emit_p(PSTR("<tr><td>$D</td><td>$D</td><td><a href='/k?i=$D'>R</a></td></tr>\r\n"),
        ITPlusChannels[i].SensorID, i + 1, i + 1);
    }
  }
  buf.emit_p(PSTR("</table><br/>\r\n"
    "<a href='/z'>Cancel last remove</a><br/><a href='/j'>Add Sensors</a><br/><br/>\r\n"
    "$F"), BackToC);
}

// Processing functions & data for registered sensors display
// ----------------------------------------------------------
static void ProcessRemoveSensor(const char* data, BufferFiller& buf) {
  if (data[6] == '?') {  // Query has the form: ?i=i [i = index]
    byte ChannelIndex;
    
    // Get channel index to remove
    ChannelIndex = getIntArg(data, "i", 1) - 1;
    
    // Remember last removed channel for future rollback
    LastRemovedSensorID = ITPlusChannels[ChannelIndex].SensorID;
    LastRemovedSensorIndex = ChannelIndex;
    
    // Unregister the channel
    ITPlusChannels[ChannelIndex].SensorID = 0xff;

    // Write back into config and then to EEP
    Config.ITPlusID[ChannelIndex] = 0xff;
    SaveConfig();
    
    // Redirect to sensors config page when done. This will display updated channels data
    buf.emit_p(PSTR(
      "$F/d\r\n\r\n"), redirHeader);
  }
}

static void ProcessCancelLastRemove(BufferFiller& buf) {
  // First, cjeck if there is a possible roll back
  if (LastRemovedSensorID != 0xff) {
    // Re-enable last removed sensor
    ITPlusChannels[LastRemovedSensorIndex].SensorID = LastRemovedSensorID;
    
    // Write back into config and then to EEP
    Config.ITPlusID[LastRemovedSensorIndex] = LastRemovedSensorID;
    SaveConfig();
    
    // Finally, as the sensor may have come up meanwhile into the discovered table, remove it.
    for (byte i = 0; i < ITPLUS_MAX_DISCOVER; i++) {
      if ((DiscoveredITPlus[i].SensorID & ITPLUS_ID_MASK) == LastRemovedSensorID) {
        // Found! Then remove...
        DiscoveredITPlus[i].SensorID = 0xff;
        break;
      }
    }

    // Makes a further roll back not possible
    LastRemovedSensorID = 0xff;
  }
    
  // Redirect to sensors config page when done. This will display updated channels data
  buf.emit_p(PSTR(
    "$F/d\r\n\r\n"), redirHeader);
}

// Sensors discovering / adding page
// ---------------------------------
// This page displays senors that can be registered: received & not yet registered
// To help indentify them, temperature is also shown if refreshed within the last 10 mn.
static void SensorsAddPage(BufferFiller& buf) {
  char bufStr[5], *ptBuff, c;
  
  buf.emit_p(PSTR("$F\r\n<title>Config</title>"
    "<a href='/'>Home</a>"
    "<h1>Sensors Add</h1>"
    "IDs With RESET<br/>"), okHeader);

  // Display sensors still in reset state
  for (byte i = 0; i < ITPLUS_MAX_DISCOVER; i++) {
    if ((DiscoveredITPlus[i].SensorID != 0xff) && ((DiscoveredITPlus[i].SensorID & ~ITPLUS_ID_MASK)) != 0) {

      buf.emit_p(PSTR("$D "), DiscoveredITPlus[i].SensorID & ITPLUS_ID_MASK);
      if (DiscoveredITPlus[i].LastReceiveTimer > ITPLUS_DISCOVERY_PERIOD - 10) {
        if (DiscoveredITPlus[i].Temp & 0x80)
          buf.write('-');
        buf.emit_p(PSTR("($D.$D&deg;)"), DiscoveredITPlus[i].Temp & 0x7f, DiscoveredITPlus[i].DeciTemp);
      } else {
        buf.emit_p(PSTR("NoRX"));
      }
      buf.emit_p(PSTR("<br/>"));
    }
  }

  // Display sensors in normal state
  buf.emit_p(PSTR("Normal IDs<br/>"));
  for (byte i = 0; i < ITPLUS_MAX_DISCOVER; i++) {
    if ((DiscoveredITPlus[i].SensorID != 0xff) && ((DiscoveredITPlus[i].SensorID & ~ITPLUS_ID_MASK)) == 0) {
      buf.emit_p(PSTR("$D "), DiscoveredITPlus[i].SensorID & ITPLUS_ID_MASK);
      if (DiscoveredITPlus[i].LastReceiveTimer > ITPLUS_DISCOVERY_PERIOD - 10) {
        if (DiscoveredITPlus[i].Temp & 0x80)
          buf.write('-');
        buf.emit_p(PSTR("($D.$D&deg;)"), DiscoveredITPlus[i].Temp & 0x7f, DiscoveredITPlus[i].DeciTemp);
      } else {
        buf.emit_p(PSTR("NoRX"));
      }
      buf.emit_p(PSTR("<br/>"));
    }
  }

  buf.emit_p(PSTR("<form action=\"r\">"
    "<br/>Id:<input type=text name=\"i\" size=2> Chan:<input type=text name=\"c\" size=2>"
    "<input type=submit value=\"Add\"></form>"));
  buf.emit_p(PSTR("<a href='/C'>Clear List</a>$F"), BreakAndCRLF);
  buf.emit_p(PSTR("<input type=button value=\"Cancel\" onclick=\"location.replace('/d');\">"));
}

// Processing functions & data for sensors add page
// ------------------------------------------------
// Registering a new sensor
static void ProcessRegisterIPPlusSensor(const char* data, BufferFiller& buf) {
  int sensorID, channel;
  byte i;
  // Not very nice error processing done here, but remember: Arduino resources are tight...

  // Check Sensor ID validity (should have been better not to let user fill that value into page...
  sensorID = getIntArg(data, "i");
  if (sensorID < 0 || sensorID > 64) {
    // Redirect to error page with error code #1
    buf.emit_p(PSTR("$F/E?e=1\r\n\r\n"), redirHeader);
    return;
  }
  // Check if sensor known
  for (i = 0; i < ITPLUS_MAX_DISCOVER; i++) {
    if ((DiscoveredITPlus[i].SensorID & ITPLUS_ID_MASK) == sensorID)
      break;
  }
  if (i == ITPLUS_MAX_DISCOVER) {
    // Redirect to error page with error code #2
    buf.emit_p(PSTR("$F/E?e=2\r\n\r\n"), redirHeader);
    return;
  }
  // Here i < ITPLUS_MAX_DISCOVER records the index where sensor was into the table, remember it for later remove
  // Check if channel OK
  channel = getIntArg(data, "c");
  if (channel < 1 || channel > ITPLUS_MAX_SENSORS) {
    // Redirect to error page with error code #3
    buf.emit_p(PSTR("$F/E?e=3\r\n\r\n"), redirHeader);
    return;
  }
  if (Config.ITPlusID[channel - 1] != 0xff) {
    // Redirect to error page with error code #4
    buf.emit_p(PSTR("$F/E?e=4\r\n\r\n"), redirHeader);
    return;
  }
  
  // All check OK: register the sensor
  ITPlusChannels[channel - 1].SensorID = sensorID;
  // Sensor should not be anymore in discovery table
  DiscoveredITPlus[i].SensorID = 0xff;

  // Write back into config and then to EEP
  Config.ITPlusID[channel - 1] = sensorID;
  SaveConfig();
    
  // Redirect to sensors config page when done. This will display updated channels data
  buf.emit_p(PSTR(
    "$F/d\r\n\r\n"), redirHeader);
}

static void SensorRegisterErrorPage(const char* data, BufferFiller& buf) {
  int errorID;

  errorID = getIntArg(data, "e");
  buf.emit_p(PSTR("$F\r\n"
    "<title>Error</title>"
    "<h1>Sensor register ERROR</h1>\r\n"), okHeader);
  buf.emit_p(PSTR("1 ID must < 64$F"), BreakAndCRLF);
  buf.emit_p(PSTR("2 ID must be detected$F"), BreakAndCRLF);
  buf.emit_p(PSTR("3 Channel = 1..$D$F"), ITPLUS_MAX_SENSORS, BreakAndCRLF);
  buf.emit_p(PSTR("4 Channel not in use$F"), BreakAndCRLF);
  buf.emit_p(PSTR("Rule #$D not met$F"), errorID, BreakAndCRLF);
  // Finally, the OK button
  buf.emit_p(PSTR("<input type=button value=\"OK\" onclick=\"location.replace('/j');\">"));

}

// Clearing the discovery table
static void ClearDiscoveryTable(BufferFiller& buf) {
  for (byte i = 0; i < ITPLUS_MAX_DISCOVER; i++) {
    DiscoveredITPlus[i].SensorID = 0xff;
  }

  // Redirect to Sensors discovering / adding page when done.
  buf.emit_p(PSTR(
    "$F/j\r\n\r\n"), redirHeader);
}

// Server configuration page: displays configuration
// -------------------------------------------------
static char TextInputHTMLPart1[] PROGMEM = "<br/><input type=text name=\"i\" size=70 value=\"";
static char TextInputHTMLPart2[] PROGMEM = "\"><input type=submit value=\"Set\"></form>\r\n";
static void ServerAddressConfigPage(BufferFiller& buf) {
  byte b, *EEAddr;
  char serverIPString[16];
  
  buf.emit_p(PSTR("$F\r\n"
    "<title>Config</title>"
    "<a href='/'>Home</a>"
    "<h1>Server Config</h1>\r\n"), okHeader);

  // Host name form
  buf.emit_p(PSTR(
    "<form action=\"/h\">"	// method defaults to GET
    "Host Name$F"), TextInputHTMLPart1);
  EEAddr = (byte *)&SRV_HOST_EEPROM[0];
  while (b = eeprom_read_byte(EEAddr++))
    buf.write(b);
  buf.emit_p(TextInputHTMLPart2);

  // Host address form, first, we build the @ into a string
  if (Config.ServerIP[0] != 0) {
    sprintf_P(serverIPString, PSTR("%d.%d.%d.%d"), Config.ServerIP[0], Config.ServerIP[1], Config.ServerIP[2], Config.ServerIP[3]);
  } else
    serverIPString[0] = 0;
  buf.emit_p(PSTR(
    "<form action=\"/i\">"	// method defaults to GET
    "Host @$F"), TextInputHTMLPart1);
  EEAddr = (byte *)serverIPString;
  while (b = *EEAddr++)
    buf.write(b);
  buf.emit_p(TextInputHTMLPart2);
  
  // Finally, the back button
  buf.emit_p(BackToC);
}

static void ServerAPIConfigPage(BufferFiller& buf) {
  byte b, *EEAddr;
  
  buf.emit_p(PSTR("$F\r\n"
    "<title>Config</title>"
    "<a href='/'>Home</a>"
    "<h1>API Config</h1>\r\n"), okHeader);

  // URL form
  buf.emit_p(PSTR(
    "<form action=\"/u\">"	// method defaults to GET
    "URL$F"), TextInputHTMLPart1);
  EEAddr = (byte *)&SRV_URL_EEPROM[0];
  while (b = eeprom_read_byte(EEAddr++))
    buf.write(b);
  buf.emit_p(TextInputHTMLPart2);

  // Extra header form
  buf.emit_p(PSTR(
    "<form action=\"/x\">"	// method defaults to GET
    "Extra Header$F"), TextInputHTMLPart1);
  EEAddr = (byte *)&SRV_HDR_EEPROM[0];
  while (b = eeprom_read_byte(EEAddr++))
    buf.write(b);
  buf.emit_p(TextInputHTMLPart2);

  // Finally, the back button
  //buf.emit_p(PSTR("<input type=button value=\"Cancel\" onclick=\"location.replace('/c');\">"));
  buf.emit_p(BackToC);
}

// Display local IP configuration
static void LocalConfigPage(BufferFiller& buf) {
  char bufStr[5], *ptBuff, c;

  buf.emit_p(PSTR("$F\r\n"
    "<title>Config</title>"
    "<a href='/'>Home</a>"
    "<h1>Local Config</h1>\r\n"), okHeader);

  buf.emit_p(PSTR(
    "Node@ 192.168.A.B<br/>GW 192.168.A.G<br/>\r\n"
    "<form action=\"m\">"
    "A <input type=text name=\"a\" size=4 value=\""));
  sprintf_P(bufStr, PSTR("%d"), Config.LocalIP[2]);
  ptBuff = bufStr;
  while (c = *ptBuff++)
    buf.write(c);
  buf.emit_p(PSTR(
    "\">"));
    
  buf.emit_p(PSTR(
    "B <input type=text name=\"b\" size=4 value=\""));
  sprintf_P(bufStr, PSTR("%d"), Config.LocalIP[3]);
  ptBuff = bufStr;
  while (c = *ptBuff++)
    buf.write(c);
  buf.emit_p(PSTR(
    "\">"));

  buf.emit_p(PSTR(
    "G <input type=text name=\"g\" size=4 value=\""));
  sprintf_P(bufStr, PSTR("%d"), Config.RouterIP[3]);
  ptBuff = bufStr;
  while (c = *ptBuff++)
    buf.write(c);
  buf.emit_p(PSTR(
    "\"><input type=submit value=\"Set\"></form>\r\n"));

  // Finally, the back button
  //buf.emit_p(PSTR("<input type=button value=\"Cancel\" onclick=\"location.replace('/c');\">"));
  buf.emit_p(BackToC);
}

// Display Miscelaneous data
static void MiscConfigPage(BufferFiller& buf) {
  char bufStr[5], *ptBuff, c;

  buf.emit_p(PSTR("$F\r\n"
    "<title>Config</title>"
    "<a href='/'>Home</a>"
    "<h1>Misc Config</h1>\r\n"), okHeader);

  buf.emit_p(PSTR(
    "Send Period<br/>\r\n"
    "<form action=\"p\">"
    "A <input type=text name=\"p\" size=4 value=\""));
  sprintf_P(bufStr, PSTR("%d"), Config.WebSendPeriod);
  ptBuff = bufStr;
  while (c = *ptBuff++)
    buf.write(c);
  buf.emit_p(PSTR(
    "\"><input type=submit value=\"Set\"></form>\r\n"));

  // Link to Remote Plug & WatchDog test
  buf.emit_p(PSTR("<a href='/w'>Plug Test</a><br/>\r\n"));
  // Finally, the back button
  //buf.emit_p(PSTR("<input type=button value=\"Cancel\" onclick=\"location.replace('/c');\">"));
  buf.emit_p(BackToC);
}

// Page for testing WatchDog & ADSL Box Reboot
// -------------------------------------------
static void WDTPlugTestPage(BufferFiller& buf) {

  buf.emit_p(PSTR("$F\r\n"
    "<title>Plug Test</title>"
    "<h1>Remote Plug Test</h1>\r\n"), okHeader);

  buf.emit_p(PSTR(
    "Remote Plug Test<br/>\r\n"
    "Will reboot in 1mn<br/>\r\n"));

  plugTestRequest = true;
}

// Processing functions & data for server set parameters
// -----------------------------------------------------
static char ErrorResp[] PROGMEM = "HTTP/1.0 401 Unauthorized\r\nContent-Type: text/html\r\n"
                           "\r\n<h1>401 Unauthorized</h1>";  

// Set Hostname
static void ProcessSetHostName(char* data, BufferFiller& buf) {
  byte i;
  char *pt;
  
  // All requests have ?i= followed by the value up to a blank. The value is "URL encoded"
  // Check we have ?i= (after "GET /x)
  if (strncmp("?i=", data + 6, 3) == 0) {
    // Search the first space that follow, replaces it by 0 to terminate the string
    for (pt = data + 6 + 3; *pt != ' '; pt++) ;
    *pt = 0;
    // Decode
    urldecode(data + 6 + 3);

    // Write the string into EEPROM
    for (i = 0, pt = data + 6 + 3; *pt != 0 && i < sizeof(SRV_HOST_EEPROM) - 1; i++, pt++)
      eeprom_write_byte((byte *)&SRV_HOST_EEPROM[i], (byte)*pt);
    
    // Write terminating 0, string truncated to sizef() if too long
    eeprom_write_byte((byte *)&SRV_HOST_EEPROM[i], 0);
    // Update CKS into EEP
    WriteEEPCKS();

    // Initiate DNS lookup for new host if needed
    if (Config.ServerIP[0] == 0) {
    // But Only if Server name just set is not empty
      if (eeprom_read_byte((byte *)&SRV_HOST_EEPROM[0]) != 0)
        DNSState = DNS_INIT;
      else
        DNSState = DNS_NO_HOST;
    }
  
    // Redirect to server config page when done. This will display updated data  
    buf.emit_p(PSTR("$F/e\r\n\r\n"), redirHeader);
  } else {  // Send and error response.
    bfill.emit_p(ErrorResp);  
  }
}

// Set Host @
static void ProcessSetHostAddr(char* data, BufferFiller& buf) {
  byte i;
  char *pt;
  
  // All requests have ?i= followed by the value up to a blank. The value is "URL encoded"
  // Check we have ?i= (after "GET /x)
  if (strncmp("?i=", data + 6, 3) == 0) {
    // Search the first space that follow, replaces it by . to make strtok working
    for (pt = data + 6 + 3; *pt != ' '; pt++) ;
    *pt = '.';
    // Decode
    urldecode(data + 6 + 3);

    // Decode the address as 4 numbers '.' separated
    Config.ServerIP[0] = atoi(strtok(data + 6 + 3, "."));
    Config.ServerIP[1] = atoi(strtok(NULL, "."));
    Config.ServerIP[2] = atoi(strtok(NULL, "."));
    Config.ServerIP[3] = atoi(strtok(NULL, "."));

    // Write new config into EEPROM
    SaveConfig();    // Will also update CKS into EEP
  
    // Redirect to server config page when done. This will display updated data  
    buf.emit_p(PSTR("$F/e\r\n\r\n"), redirHeader);
  } else {  // Send and error response.
    bfill.emit_p(ErrorResp);  
  }
}

// Set URL
static void ProcessSetURL(char* data, BufferFiller& buf) {
  byte i;
  char *pt;
  
  // All requests have ?i= followed by the value up to a blank. The value is "URL encoded"
  // Check we have ?i= (after "GET /x)
  if (strncmp("?i=", data + 6, 3) == 0) {
    // Search the first space that follow, replaces it by 0 to terminate the string
    for (pt = data + 6 + 3; *pt != ' '; pt++) ;
    *pt = 0;
    // Decode
    urldecode(data + 6 + 3);

    // Write the string into EEPROM
    for (i = 0, pt = data + 6 + 3; *pt != 0 && i < sizeof(SRV_URL_EEPROM) - 1; i++, pt++)
      eeprom_write_byte((byte *)&SRV_URL_EEPROM[i], (byte)*pt);
    
    // Write terminating 0, string truncated to sizef() if too long
    eeprom_write_byte((byte *)&SRV_URL_EEPROM[i], 0);
    // Update CKS into EEP
    WriteEEPCKS();
  
    // Redirect to server config page when done. This will display updated data  
    buf.emit_p(PSTR("$F/a\r\n\r\n"), redirHeader);
  } else {  // Send and error response.
    bfill.emit_p(ErrorResp);  
  }
}

// Set Extra Header
static void ProcessSetExtraHeader(char* data, BufferFiller& buf) {
  byte i;
  char *pt;
  
  // All requests have ?i= followed by the value up to a blank. The value is "URL encoded"
  // Check we have ?i= (after "GET /x)
  if (strncmp("?i=", data + 6, 3) == 0) {
    // Search the first space that follow, replaces it by 0 to terminate the string
    for (pt = data + 6 + 3; *pt != ' '; pt++) ;
    *pt = 0;
    // Decode
    urldecode(data + 6 + 3);

    // Write the string into EEPROM
    for (i = 0, pt = data + 6 + 3; *pt != 0 && i < sizeof(SRV_HDR_EEPROM) - 1; i++, pt++)
      eeprom_write_byte((byte *)&SRV_HDR_EEPROM[i], (byte)*pt);
    
    // Write terminating 0, string truncated to sizef() if too long
    eeprom_write_byte((byte *)&SRV_HDR_EEPROM[i], 0);
    // Update CKS into EEP
    WriteEEPCKS();
  
    // Redirect to server config page when done. This will display updated data  
    buf.emit_p(PSTR("$F/a\r\n\r\n"), redirHeader);
  } else {  // Send and error response.
    bfill.emit_p(ErrorResp);  
  }
}

// Set local network values
static void ProcessSetLocal(char* data, BufferFiller& buf) {
  byte valA, valB, valG;
  
  // Requests have the form ?a=val&b=val&g=val followed by a blank.
  // Values are "URL encoded", normally, no need to decode in that case.
  valA = getIntArg(data, "a", 0);
  valB = getIntArg(data, "b", 0);
  valG = getIntArg(data, "g", 0);
  
  Config.LocalIP[2] = valA;
  Config.LocalIP[3] = valB;
  Config.RouterIP[2] = valA;
  Config.RouterIP[3] = valG;

  SaveConfig();

  // Redirect to local network values config page when done. This will display updated data
  buf.emit_p(PSTR(
    "$F/l\r\n\r\n"), redirHeader);
}

// Set WEB sending period
static void ProcessSetPeriod(char* data, BufferFiller& buf) {
  byte valPeriod;

  // Requests have the form ?p=period followed by a blank.
  // Values are "URL encoded", normally, no need to decode in that case.
  valPeriod = getIntArg(data, "p", 0);
  
  Config.WebSendPeriod = valPeriod;
  SaveConfig();

  // Redirect to set misc values config page when done. This will display updated data
  buf.emit_p(PSTR(
    "$F/o\r\n\r\n"), redirHeader);
}

/**********************************************************************
 *
 *  WEB Requests from browser check and dispatcher
 *
 **********************************************************************/
void CheckProcessBrowserRequest() {
    word len = eth.packetReceive(buf, sizeof(buf));


//xx
if (enc28j60linkup()) {
  if (!LNKUP) {
    DebugPrintln_P(PSTR("ETHUP"));
    LNKUP = true;
  }
} else if (LNKUP) {
  DebugPrintln_P(PSTR("ETHDOWN"));
  LNKUP = false;
}



    // ENC28J60 loop runner: handle ping and wait for a tcp packet
    word pos = eth.packetLoop(buf,len);
    if (len == 0) {
      if (DNSState == DNS_INIT) {
        eth.dnsRequest(buf, SRV_HOST_EEPROM);  // We are sure that hostname is not empty when DNS_STATE == DNS_INIT
#ifdef DEBUG_DNS
        printTime(); DebugPrintln_P(PSTR("DNS Req"));
#endif
        DNSState = DNS_WAIT_ANSWER;
        return;
      }
      
      if (DNSState == DNS_WAIT_ANSWER && eth.dnsHaveAnswer()) {
        DNSState = DNS_GOT_ANSWER;
        byte* pt = eth.dnsGetIp();
        for (byte i = 0; i < 4; i++) websrvip[i] = *pt++;
        client_set_wwwip(websrvip);
#ifdef DEBUG_DNS
        printTime(); DebugPrintln_P(PSTR("DNS Resp"));
        pt = eth.dnsGetIp();
        Serial.print(*pt++,DEC); Serial.print('.'); Serial.print(*pt++,DEC); Serial.print('.');
        Serial.print(*pt++,DEC); Serial.print('.'); Serial.print(*pt++,DEC); Serial.print('.');
        Serial.println("");
#endif
      }
      return;
    }

    if (pos == 0) { // But len != 0 here
      // Check for incomming messages not processed as part of packetloop_icmp_tcp, e.g udp messages for DNS
      eth.checkForDnsAnswer(buf, len);
      return;
    }

    // check if valid tcp data is received
    if (pos) {
        bfill = eth.tcpOffset(buf);
        char* data = (char *) buf + pos;
#if DEBUG_ETH
        Serial.println(data);
#endif
        // Check if we have a valid "GET /"
        if (strncmp("GET /", data, 5) == 0) {
          switch (data[5]) {  // Command dispatcher
            case ' ' : homePage(bfill); break;
            case 's' : StatusPage(bfill); break;
            case 'c' : ConfigPage(bfill); break;

            case 'd' : SensorsConfigPage(bfill); break;
            case 'k' : ProcessRemoveSensor(data, bfill); break;
            case 'z' : ProcessCancelLastRemove(bfill); break;

            case 'j' : SensorsAddPage(bfill); break;
            case 'r' : ProcessRegisterIPPlusSensor(data, bfill); break;
            case 'C' : ClearDiscoveryTable(bfill); break;

            case 'e' : ServerAddressConfigPage(bfill); break;
            case 'h' : ProcessSetHostName(data, bfill); break;
            case 'i' : ProcessSetHostAddr(data, bfill); break;

            case 'a' : ServerAPIConfigPage(bfill); break;
            case 'u' : ProcessSetURL(data, bfill); break;
            case 'x' : ProcessSetExtraHeader(data, bfill); break;

            case 'l' : LocalConfigPage(bfill); break;
            case 'm' : ProcessSetLocal(data, bfill); break;

            case 'o' : MiscConfigPage(bfill); break;
            case 'p' : ProcessSetPeriod(data, bfill); break;

            case 'w' : WDTPlugTestPage(bfill); break;
            case 'E' : SensorRegisterErrorPage(data, bfill); break;

            default : bfill.emit_p(ErrorResp);
          }
        } else
            bfill.emit_p(ErrorResp);

        eth.httpServerReply(buf,bfill.position()); // send web page data
#if DEBUG_ETH
          DebugPrintln_P(PSTR("Resp sent"));
#endif
    }
}

// Some documentation:

// extern void client_browse_url(prog_char *urlbuf, char *urlbuf_varpart, prog_char *hoststr,void (*callback)(uint8_t,uint16_t));
// The callback is a reference to a function which must look like this:
// void browserresult_callback(uint8_t statuscode,uint16_t datapos)
// statuscode=0 means a good webpage was received, with http code 200 OK
// statuscode=1 an http error was received
// statuscode=2 means the other side in not a web server and in this case datapos is also zero

// http post
// client web browser using http POST operation:
// additionalheaderline must be set to NULL if not used.
// postval is a string buffer which can only be de-allocated by the caller 
// when the post operation was really done (e.g when callback was executed).
// postval must be urlencoded.

// extern void client_http_post(prog_char *urlbuf, prog_char *hoststr, prog_char *additionalheaderline, prog_char *method, char *postval,void (*callback)(uint8_t,uint16_t));
// The callback is a reference to a function which must look like this:
// void browserresult_callback(uint8_t statuscode,uint16_t datapos)
// statuscode=0 means a good webpage was received, with http code 200 OK
// statuscode=1 an http error was received
// statuscode=2 means the other side in not a web server and in this case datapos is also zero

void browserresult_callback(uint8_t statuscode, uint16_t datapos, uint16_t len) {
  // Status is set to: strncmp("200",(char *)&(bufptr[datapos+9]),3) != 0;
  // Callback not called if client_browse_url cannot send the request (network cable disconnected for instance)
#if DEBUG_HTTP
  DebugPrint_P(PSTR("Resp ")); Serial.println(statuscode, DEC);
#endif
#ifdef DEBUG_BOX_REBOOT
  printTime(); DebugPrintln_P(PSTR("GotResp"));
#endif
  // Signallling we received an answer from server to prevent retries.
  // Retry mechanism is there to cope with transmission errors (mostly WEB time-outs), not negative answers,
  // so any type of response mean communication is OK.
  justSent = 0;
  switch (statuscode) {
    case 0:
      LastServerSendOK = Minutes;  // For Status Page & Error Signaling
      SentCount++;
      break;

    case 1:
#if DEBUG_HTTP
      DebugPrintln_P(PSTR("Resp "));
      Serial.println((char *)&buf[datapos]);
#endif

    case 2:
    default:
      break;
  }
}

void WebSend(char *StrBuff) {
#ifdef DEBUG_BOX_REBOOT
  printTime(); Serial.println("POST");//xxgg
#endif

  client_http_post(SRV_URL_EEPROM, SRV_HOST_EEPROM, SRV_HDR_EEPROM, StrBuff, &browserresult_callback);
}

