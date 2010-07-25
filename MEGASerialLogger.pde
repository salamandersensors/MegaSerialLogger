#include <SdFat.h>
#include <Wire.h>
#include "RTClib.h"
#include "WString.h"


//Adafruit light and Temp logger code modified by Cindy to accept serial input, TelosB board
// A simple data logger for the Arduino 
//Cindy: Use Arduino MEGA serial port 1 RX ( MEGA pin19) for Telosb, regular Serial for computer SerialMonitor
#define ECHO_TO_SERIAL   1 // echo data to serial port
#define WAIT_TO_START    0 // Wait for serial input in setup()
#define SYNC_INTERVAL 1000 // mills between calls to sync()
uint32_t syncTime = 0;     // time of last sync()

int incomingByte = 0; //For incoming serial data --Cindy

// the digital pins that connect to the LEDs -currently don't have pin 2 hookedup
#define redLEDpin 2
#define greenLEDpin 3

RTC_DS1307 RTC; // define the Real Time Clock object

// The objects to talk to the SD card
Sd2Card card;
SdVolume volume;
SdFile root;
SdFile file;

void error(char *str)
{
  Serial.print("error: ");
  Serial.println(str);
  while(1);
}

void setup(void)
{
  Serial.begin(9600); //for computer
  Serial1.begin(57600);  //works? others use 9600. if so remember to compile TelosB listener for 9600 -Cindy
  Serial.println();

  
#if WAIT_TO_START
  Serial.println("Type any character to start");
  while (!Serial.available());
#endif //WAIT_TO_START

  // initialize the SD card
  if (!card.init()) error("card.init");
  
  // initialize a FAT volume
  if (!volume.init(card)) error("volume.init");
  
  // open root directory
  if (!root.openRoot(volume)) error("openRoot");
  
  // create a new file
  char name[] = "LOGGER00.CSV";
  for (uint8_t i = 0; i < 100; i++) {
    name[6] = i/10 + '0';
    name[7] = i%10 + '0';
    if (file.open(root, name, O_CREAT | O_EXCL | O_WRITE)) break;
  }
  if (!file.isOpen()) error ("file.create");
  Serial.print("Logging to: ");
  Serial.println(name);

  // write header
  file.writeError = 0;

  Wire.begin();  
  RTC.begin();  //Had to change this to resemble ds1307 which worked on the MEGA. Otherwise clock doesn't seem to start. 
  //Need jumper connecting MEGA SDA pin to logger shield SDA, and MEGA SCL pin to logger shield SCL.
  
  if (!RTC.isrunning()) {
    file.println("RTC failed");
    //RTC.adjust(DateTime(__DATE__, __TIME__));
#if ECHO_TO_SERIAL
    Serial.println("RTC failed");
#endif  //ECHO_TO_SERIAL
  }
  

  file.println("data, millis,stamp,datetime");    
#if ECHO_TO_SERIAL
  Serial.println("data, millis,stamp,datetime");
#endif //ECHO_TO_SERIAL

  // attempt to write out the header to the file
  if (file.writeError || !file.sync()) {
    error("write header");
  }
  
  pinMode(redLEDpin, OUTPUT);
  pinMode(greenLEDpin, OUTPUT);
 
}

byte prevByte=0;
void loop(void)
{


  if (Serial1.available()>0){ //I got this from http://arduino.cc/en/Serial/Read  -Cindy
      incomingByte = Serial1.read(); //read one byte--nowhere else do we read bytes in previous code
      file.print (Nib1toString(incomingByte));  //instead should I save up bytes and print an array?
      file.print (Nib2toString(incomingByte));
      file.print (" ");
      #if ECHO_TO_SERIAL
         Serial.print (Nib1toString(incomingByte));
         Serial.print (Nib2toString(incomingByte));
         Serial.print (" ");
         #endif
  //Detect the end of line pattern 7E 7E, exit loop and write the byte array, THEN DO timestamp
  }
 

  if ( prevByte==126 and incomingByte==126 )//end of line has a pattern of two 7Es in a row (0x7E=126)
  {     
        incomingByte=0; //reset so we don't always get stuck here
 	file.print (",");
  	DateTime now;
  
 	 // clear print error
 	 file.writeError = 0;
 	 // log milliseconds since starting
  	uint32_t m = millis();
  	file.print(m);           // milliseconds since start
  	file.print(", ");    
	#if ECHO_TO_SERIAL
	 Serial.print(m);         // milliseconds since start
 	 Serial.print(", ");  
	#endif

  	// fetch the time
  	now = RTC.now();
  	// log time
  	file.print(now.unixtime()); // seconds since 1/1/1970
  	file.print(", ");
  	file.print('"');
  	file.print(now.year(), DEC);
 	 file.print("/");
  	file.print(now.month(), DEC);
  	file.print("/");
 	file.print(now.day(), DEC);
 	 file.print(" ");
 	file.print(now.hour(), DEC);
 	 file.print(":");
  	file.print(now.minute(), DEC);
 	 file.print(":");
 	 file.print(now.second(), DEC);
 	 file.print('"');
	#if ECHO_TO_SERIAL
 	 Serial.print(now.unixtime()); // seconds since 1/1/1970
 	 Serial.print(", ");
  	 Serial.print('"');
  	 Serial.print(now.year(), DEC);
 	 Serial.print("/");
 	 Serial.print(now.month(), DEC);
 	 Serial.print("/");
 	 Serial.print(now.day(), DEC);
 	 Serial.print(" ");
 	 Serial.print(now.hour(), DEC);
 	 Serial.print(":");
 	 Serial.print(now.minute(), DEC);
 	 Serial.print(":");
 	 Serial.print(now.second(), DEC);
 	 Serial.print('"');
	#endif //ECHO_TO_SERIAL
 

 	 file.println();
	#if ECHO_TO_SERIAL
 	 Serial.println();
	#endif // ECHO_TO_SERIAL

  	if (file.writeError) error("write data");
 	 digitalWrite(redLEDpin, LOW);
  
  	//don't sync too often - requires 2048 bytes of I/O to SD card
  	if ((millis() - syncTime) <  SYNC_INTERVAL) return;
  	syncTime = millis();
  
  	// blink LED to show we are syncing data to the card & updating FAT!
 	 digitalWrite(greenLEDpin, HIGH);
 	 if (!file.sync()) error("sync");
 	 digitalWrite(greenLEDpin, LOW);
    }
    prevByte=incomingByte;
}

char Nib1toString (byte mybyte){  // try make and save ascii strings on the sd card and serial terminal
    char tempstring;  //so a fool can read it with their bare eyes
    int x=0;
    int y=0;
    y=mybyte;
    if (y<0) y=256+y; //convert to unsigned
    x = y>>4; //Upper nibble
    if((x-9) <=0) tempstring=char(x+48);
    else tempstring=char(x+55);
    return tempstring;
}

char Nib2toString (byte mybyte){  // try make and save ascii strings on the sd card and serial terminal
    char tempstring;  //so a fool can read it with their bare eyes
    int x=0;
    int y=0;
    y=mybyte;
    if (y<0) y=256+y; //convert to unsigned
    x = y>>4; //Upper nibble
    x= (y-16*x);//lower nibble
    if((x-9) <=0) tempstring=char(x+48);
    else tempstring=char(x+55);
    return tempstring;
}

