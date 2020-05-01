/*
Flash total size: 256KB
number of page 4096
page size 64Bytes
Use 0x0003FFC0 ~ 0x0003FFFF (64Bytes) as config area
*/
#include "FlashStorage.h" // Atmel SAMD Native Library
FlashClass flash((const void *) 0x00000000, 256*1024);
#define CONFIG_AREA_BASE    ((const volatile void *) 0x0003FFC0)
#define CONFIG_AREA_SIZE    64
#define CONFIG_USED_SIZE    0x10
#define CONFIG_BOOT_COUNT   ((const volatile void *) (CONFIG_AREA_BASE + 0x00))
#define CONFIG_CALIB_COUNT ((const volatile void *) (CONFIG_AREA_BASE + 0x04))
#define CONFIG_CAL_A        ((const volatile void *) (CONFIG_AREA_BASE + 0x08))
#define CONFIG_CAL_B        ((const volatile void *) (CONFIG_AREA_BASE + 0x0C))
uint32_t boot_count, calib_count;

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
float cal_A = 372.1; // you can take the data from RX-9 bottom side QR data #### of first 4 digits. you type the data to cal_A as ###.#
float cal_B = 63.27; // following 4 digits after cal_A is cal_B, type the data to cal_B as ##.##

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

// Serial Read
char rcv_msg[32] = {};
int rcv_msg_pos = 0;
bool rcv_end = false;
bool enable_monitor = true;
bool enable_echoback = false;

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

void updateFlashConfig() {
  uint32_t *data = (uint32_t *) malloc(CONFIG_AREA_SIZE);
  for (int i = 0; i < CONFIG_AREA_SIZE/4; i++) {
    flash.read(CONFIG_AREA_BASE + i*4, &data[i], sizeof(data[i]));
  }
  flash.erase(CONFIG_AREA_BASE, CONFIG_AREA_SIZE);
  flash.write(CONFIG_BOOT_COUNT, &boot_count, sizeof(boot_count));
  flash.write(CONFIG_CALIB_COUNT, &calib_count, sizeof(calib_count));
  flash.write(CONFIG_CAL_A, &cal_A, sizeof(cal_A));
  flash.write(CONFIG_CAL_B, &cal_B, sizeof(cal_B));
  for (int i = CONFIG_USED_SIZE/4; i < CONFIG_AREA_SIZE/4; i++) {
    flash.write(CONFIG_AREA_BASE + i*4, &data[i], sizeof(data[i]));
  }
  free(data);
}

void setup() {
  // Serial COM
  SerialUSB.begin(115200);
  delay(1000);

  // Load Config Parameters from flash
  flash.read(CONFIG_BOOT_COUNT, &boot_count, sizeof(boot_count));
  flash.read(CONFIG_CALIB_COUNT, &calib_count, sizeof(calib_count));
  if (boot_count == 0xffffffff) {
    // Config Area Initialize
    boot_count = 0;
    calib_count = 0;
    flash.erase(CONFIG_AREA_BASE, CONFIG_AREA_SIZE);
    flash.write(CONFIG_BOOT_COUNT, &boot_count, sizeof(boot_count));
    flash.write(CONFIG_CALIB_COUNT, &calib_count, sizeof(calib_count));
    flash.write(CONFIG_CAL_A, &cal_A, sizeof(cal_A));
    flash.write(CONFIG_CAL_B, &cal_B, sizeof(cal_B));
  } else {
    if (boot_count < 0xfffffffe) boot_count++;
    // Load Calibration data
    flash.read(CONFIG_CALIB_COUNT, &calib_count, sizeof(calib_count));
    flash.read(CONFIG_CAL_A, &cal_A, sizeof(cal_A));
    flash.read(CONFIG_CAL_B, &cal_B, sizeof(cal_B));
    // update boot_count
    updateFlashConfig();
  }
  SerialUSB.println("");
  SerialUSB.println("Seeed XIAO CO2/Temp/Humidity Monitor ver 1.00");
  SerialUSB.print("Boot count: ");
  SerialUSB.print(boot_count);
  SerialUSB.print(" Calibration count: ");
  SerialUSB.println(calib_count);
  SerialUSB.print("cal_A: ");
  SerialUSB.print(cal_A);
  SerialUSB.print(" cal_B: ");
  SerialUSB.println(cal_B);

  // LED
  pinMode(LED_pin, OUTPUT);
  //digitalWrite(LED_pin, LOW);
  // CO2 Sensor Pin Setting
  pinMode(EMF_pin, INPUT);
  pinMode(THER_pin, INPUT);
  // DHT22 (Temp/Humidity) Sensor Setting
  pinMode(DHTPIN, INPUT);
  dht.begin();
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
    if (enable_monitor) {
      SerialUSB.print("# C:");
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
    }
  } else if (time_now - time_prev >= interval*1000/8) {
    digitalWrite(LED_pin, HIGH); // LED Off
  }
  // Serial Read
  while (SerialUSB.available()) {
    int inByte = SerialUSB.read();
    if (inByte == '\r' || inByte == '\n' || rcv_msg_pos >= 31) {
      rcv_msg[rcv_msg_pos] = '\0';
      rcv_end = true;
      break;
    } else {
      rcv_msg[rcv_msg_pos++] = inByte;
    }
  }
  if (rcv_end && rcv_msg_pos > 0) {
    //SerialUSB.println(rcv_msg);
    rcv_msg_pos = 0;
    rcv_end = false;
    String rcvMsg = rcv_msg;
    if (rcvMsg.equalsIgnoreCase("enable_monitor")) {
      enable_monitor = true;
    } else if (rcvMsg.equalsIgnoreCase("disable_monitor")) {
      enable_monitor = false;
    } else if (rcvMsg.equalsIgnoreCase("enable_echoback")) {
      enable_echoback = true;
    } else if (rcvMsg.equalsIgnoreCase("disable_echoback")) {
      enable_echoback = false;
    } else if (rcvMsg.equalsIgnoreCase("reset") || rcvMsg.equalsIgnoreCase("reboot")) {
      NVIC_SystemReset();
    } else if (rcvMsg.substring(0, 6).equalsIgnoreCase("calib ")) {
      if (rcvMsg.length() == 6+21 || rcvMsg.length() == 6+22) {
        // QR-code example "calib 15742214167K0544CAB07A"
        String factor_A = rcvMsg.substring(6, 10);
        String factor_B = rcvMsg.substring(10, 14);
        String comp_factor = rcvMsg.substring(14, 17);
        String serial_number = rcvMsg.substring(17, 28); // Officially it's 22 char. but there are modules which have 21 char.
        SerialUSB.print("cal_A: ");
        SerialUSB.println(factor_A);
        SerialUSB.print("cal_B: ");
        SerialUSB.println(factor_B);
        SerialUSB.print("Temp comp: ");
        SerialUSB.println(comp_factor);
        SerialUSB.print("Serial Number: ");
        SerialUSB.println(serial_number);
        if (comp_factor.equals("167") && serial_number.charAt(0) == 'K') {
          // Update Calibration parameter in flash
          cal_A = factor_A.toFloat() / 10.0;
          cal_B = factor_B.toFloat() / 100.0;
          calib_count++;
          updateFlashConfig();
          SerialUSB.println("Calibration OK");
        } else {
          SerialUSB.println("Calibration Value Error");
        }
      } else {
        SerialUSB.println("Calibration Format Error");
      }
    }
    if (enable_echoback) {
      SerialUSB.println(rcvMsg);
    }
  }
  delay(10);
}
