#ifndef ITPlusRX_H
#define ITPlusRX_H 

// Note: Don't include this file, include ITPlusRX_ext.h instead

void ITPlusRXSetup();
boolean CheckITPlusCRC();
void ProcessITPlusFrame();
byte CheckITPlusRegistration(byte id, byte Temp, byte DeciTemp);

#endif
