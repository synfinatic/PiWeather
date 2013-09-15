PiWeather ========= 
Raspberry Pi Weather Base Station

PiWeather is a [Raspberry Pi](http://www.raspberrypi.org) based weather base 
station.   The basic goal is to provide a graphing, reporting and alerting 
solution for wireless weather (temperature, humidity, rain, wind) sensors 
sold by companies like [La Cross Technology](http://www.lacrossetechnology.com/) or 
anything supporting the [WSTEP](https://code.google.com/p/wfrog/wiki/WeatherStationEventProtocol "Weather Station Event Protocol").

PiWeather will be comprised of two parts:

1. Software which can run on any Linux computer 
2a. A RaspberryPi daughter board providing the wireless RF connectivity to the sensors OR
2b. A Linux computer with a USB port and a [JeeLink](http://jeelabs.net/projects/hardware/wiki/JeeLink)

Note, that the software running on the JeeLink/Atmega is heavily based on the code written by 
Gerard Chevalier and available at [GcrNet](http://gcrnet.net/node/32).

