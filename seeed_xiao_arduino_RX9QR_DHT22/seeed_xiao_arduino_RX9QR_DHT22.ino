/* Seeed XIAO LED */
#define LED_pin 13 // PA17_W13 pin

/* DHT22 Temperature/Humidity Sensor */
#include "DHT.h"
#define DHTPIN 2
#define DHTTYPE DHT22
//create an instance of DHT sensor
DHT dht(DHTPIN, DHTTYPE);

/* ========== CO2 Sensor RX-9 (Begin) ========== */
/* https://github.com/EXSEN/RX-9 */
/* Utilizing RX-9 QR Sample Code
 *  date: 2020.03.04
 *  Carbon Dioxide Gas sensor(RX-9) with
 *  ATMEGA328p, 16Mhz, 5V
 *  file name: RX9SampleCodeQR_RX9
 *  
 *  RX-9 have 4 pin
 *  E: EMF
 *  T: Thermistor for sensor
 *  G: GND
 *  V: 3.3V > 200 mA
 */
#include "RX9QR.h"
#define EMF_pin 5   // RX-9 E with PA5
#define THER_pin 6  // RX-9 T with PA6
#define ADCvolt 3.3
#define ADCResol 1024
#define Base_line 432
#define meti 60  
#define mein 120 //Automotive: 120, Home or indoor: 1440

//CO2 calibrated number
float cal_A = 409.1; // you can take the data from RX-9 bottom side QR data #### of first 4 digits. you type the data to cal_A as ###.#
float cal_B = 61.28; // following 4 digits after cal_A is cal_B, type the data to cal_B as ##.##

//CO2 Step range
#define cr1  700      // Base_line ~ cr1
#define cr2  1000     // cr1 ~ cr2
#define cr3  2000     // cr2 ~ cr3
#define cr4  4000     // cr3 ~ cr4 and over cr4

// Thermister constant
// RX-9 have thermistor inside of sensor package. this thermistor check the temperature of sensor to compensate the data
// don't edit the number
#define C1 0.00230088
#define C2 0.000224
#define C3 0.00000002113323296
float Resist_0 = 15;

RX9QR RX9(cal_A, cal_B, Base_line, meti, mein, cr1, cr2, cr3, cr4);
/* ========== CO2 Sensor RX-9 (End) ========== */

//Timing
unsigned int time_now = 0;
unsigned int time_prev = 0;
unsigned int interval = 1;

bool getCO2(unsigned int *val) {
  int status_sensor = 0;
  unsigned int co2_ppm = 0;
  unsigned int co2_step = 0;
  float EMF = 0;
  float THER = 0;

  //read EMF data from RX-9, RX-9 Simple START-->
  EMF = analogRead(EMF_pin);
  delay(1);
  EMF = EMF / (ADCResol - 1);
  EMF = EMF * ADCvolt;
  EMF = EMF / 6;
  EMF = EMF * 1000;
  // <-- read EMF data from RX-9, RX-9 Simple END 
  
  //read THER data from RX-9, RX-9 Simple START-->
  THER = analogRead(THER_pin);
  delay(1);
  THER = 1/(C1+C2*log((Resist_0*THER)/(ADCResol-THER))+C3*pow(log((Resist_0*THER)/(ADCResol-THER)),3))-273.15;
  // <-- read THER data from RX-9, RX-9 Simple END
  
  status_sensor = RX9.status_co2();   //read status_sensor, status_sensor = 0 means warming up, = 1 means stable
  co2_ppm = RX9.cal_co2(EMF,THER);    //calculation carbon dioxide gas concentration. 
  co2_step = RX9.step_co2();          //read steps of carbon dioixde gas concentration. you can edit the step range with cr1~cr4 above.
  *val = co2_ppm;
  return (status_sensor == 1);
}

bool getTemperature(float *val) {
  float t = dht.readTemperature();
  *val = t;
  return !isnan(t);
}

bool getHumidity(float *val) {
  float h = dht.readHumidity();
  *val = h;
  return !isnan(h);
}

void setup() {
  // LED
  pinMode(LED_pin, OUTPUT);
  //digitalWrite(LED_pin, LOW);
  // CO2 Sensor Pin Setting
  pinMode(EMF_pin, INPUT);
  pinMode(THER_pin, INPUT);
  // DHT22 (Temp/Humidity) Sensor Setting
  pinMode(DHTPIN, INPUT);
  dht.begin();
  // Serial COM
  SerialUSB.begin(115200);
}

void loop() {
  // put your main code here, to run repeatedly:
  time_now = millis();
  if(time_now - time_prev >= interval*1000){
    //every 1 sec
    time_prev += interval*1000;
    digitalWrite(LED_pin, LOW); // LED On

    bool co2_valid, t_valid, h_valid;
    unsigned int co2_ppm;
    float t, h;
    co2_valid = getCO2(&co2_ppm);
    t_valid = getTemperature(&t);
    h_valid = getHumidity(&h);
    SerialUSB.print("C:");
    if (co2_valid) {
      SerialUSB.print(co2_ppm);
    } else {
      SerialUSB.print("xxxx");      
    }
    SerialUSB.print(" T:");
    if (t_valid) {
      SerialUSB.print(t);
    } else {
      SerialUSB.print("xxxx");
    }
    SerialUSB.print(" H:");
    if (h_valid) {
      SerialUSB.print(h);
    } else {
      SerialUSB.print("xxxx");      
    }
    SerialUSB.println(""); //CR LF
  } else if (time_now - time_prev >= interval*1000/8) {
    digitalWrite(LED_pin, HIGH); // LED Off
  }
}
