# PiWeather #

PiWeather is a [Raspberry Pi](http://www.raspberrypi.org) based weather base 
station.   The basic goal is to provide a graphing, reporting and alerting 
solution for wireless weather sensors (temperature, humidity, rain, wind)
sold by companies like [La Cross Technology](http://www.lacrossetechnology.com/).

## Why? ##

So for about a year I've been using the La Crosse Alerts system to track the 
temperature and humidity of my wine cellar.  While the La Crosse Alerts system 
works, it is a very basic system and I wanted something with better reporting 
funcationality and not be locked into La Crosse's expensive sensors + yearly 
fee.  I'd also like to integrate other sensors for inside and outside of my home.

After looking around at the market, I couldn't find anything which met my requirements:

 1. Inexpensive
 1. Support for temperature, humidity, wind and rain sensors
 1. No yearly service fee
 1. Ability to store at least 1 years worth of historical data, preferably 5+ years
 1. Easy access to both the raw data and graphs
 1. Ability to send alerts via email
 
Hence, PiWeather was born.  

## What? ##

PiWeather will be a combination software & hardware project.

 1. Web based software which can run on any Linux computer for all the reporting & alerting.
 1. And a RaspberryPi daughter board[*] providing the wireless RF connectivity to the sensors 
 
RaspberryPi is a low cost and low power Linux computer which will make running 
PiWeather 24/7 inexpensive (prices start at $25) to get started with and 
cost-effective to run due to it's low power requirements.  

[\*] Of course, if you already have a Linux computer with a free USB port at 
home running 24/7 you will be able to use that instead of the RaspberryPi via a 
[JeeLink](http://jeelabs.net/projects/hardware/wiki/JeeLink) which will 
provide the necessary wireless interface to talk to the weather sensors.

## Sensors ##

Right now my goal is to support La Cross Technology IT+ (868/915Mhz) temperature 
& humidity sensors.  Then I hope to add support for wind and rain sensors as 
well.  Other vendor and wireless technologies (433Mhz).

## Credits ##
 
Note, that the software running on the JeeLink/Atmega is heavily based on the code written by: 
 * Jean-Claude Wippler [JeeLabs - JeeLink RF12](http://jeelabs.net/pub/docs/jeelib/)
 * Gerard Chevalier [GcrNet](http://gcrnet.net/node/32)

