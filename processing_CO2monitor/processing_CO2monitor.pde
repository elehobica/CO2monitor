import java.util.*;
import java.util.regex.*;
import java.text.*;
import processing.serial.*;
import controlP5.*;
import grafica.*;
 
Serial Port;
ControlP5 cp5;

String comPorts[];
String comSpeeds[] = {"9600", "19200", "38400", "57600", "115200"};
String intevals[] = {"1sec(1hour)", "3sec(3hour)", "6sec(6hour)", "12sec(12hour)", "24sec(24hour)", "60sec(60hour)", "168sec(7days)", "4min(10days)", "336sec(14days)", "12min(30days)", "60min(150days)"};
int interval_vals[] = {1, 3, 6, 12, 24, 60, 168, 60*4, 336, 60*12, 60*60};

final int pSize = 3600;
int lastSampleTime = 0;
int accum_val = 0;
int accum_count = 0;

int co2ppm = 0;
float temp = 0.0;
float humi = 0.0;
boolean co2ppm_valid = false;
boolean temp_valid = false;
boolean humi_valid = false;

GPlot plot;
GPointsArray queue;
GPointsArray points;

String csvDumpFileName;
PrintWriter csv;
boolean csvIsWritten = false;
boolean plotUpdated = false;
Date baseDate;

int rx_time = -300;
   
void setup() {
  ControllerStyle st;
  
  // long getTime() cannot be handled by float which is supported GPlot
  // Threfore this sketch handles the offset time
  baseDate = new Date();

  size(640, 480);
  cp5 = new ControlP5(this);
  ControlFont cf0 = new ControlFont(createFont("Arial", 12));

  // ====================
  // CO2 Graph
  // ====================
  queue = new GPointsArray(3);
  points = new GPointsArray(pSize);

  plot = new GPlot(this);
  plot.setPos(40, 60);
  plot.setOuterDim(560, 120);
  plot.setDim(500, 120);
  plot.setPoints(points);
  plot.setPointSize(2.0);
  plot.setTitleText("CO2 (ppm)");
  //plot.getXAxis().setAxisLabelText("x axis");
  // Activate the zooming and panning
  //plot.activateZooming();
  //plot.activatePanning();
  plot.setMar(50, 40, 30, 20);
  plot.getYAxis().setRotateTickLabels(false);

  // ====================
  // File Menu
  // ====================
  Group grp0 = cp5.addGroup("File")
                  .setBackgroundColor(color(0, 64))
                  .setBarHeight(20)
                  .hideArrow() 
                  //.activateEvent(true)
                  ;
  grp0.getCaptionLabel()
      .setFont(cf0)
      .setHeight(20)
      .toUpperCase(false)
      ;
      
  cp5.addButton("load_csv")
      .setFont(cf0)
      .setPosition(0,0)
      .setSize(120,20)
      .moveTo(grp0)
      // Label
      .getCaptionLabel()
      .setText("Load CSV")
      .alignX(LEFT)
      .toUpperCase(false)
      ;

  cp5.addButton("exit")
      .setFont(cf0)
      .setPosition(0,20)
      .setSize(120,20)
      .moveTo(grp0)
      // Label
      .getCaptionLabel()
      .setText("Exit")
      .alignX(LEFT)
      .toUpperCase(false)
      ;

  cp5.addAccordion("acc_file")
      .setPosition(0,0)
      .setWidth(120)
      .addItem(grp0)
      .setItemHeight(40)
      //.activateEvent(true)
      ;
    
  // ====================
  // Option Menu
  // ====================
  Group grp1 = cp5.addGroup("Option")
                  .setBackgroundColor(color(0, 192))
                  .setBarHeight(20)
                  .hideArrow() 
                  //.activateEvent(true)
                  ;
  grp1.getCaptionLabel()
      .setFont(cf0)
      .setHeight(20)
      .toUpperCase(false)
      ;

  cp5.addTextlabel("lbl_interval").setFont(cf0).setText("Graph tick(Total)").setPosition(10,0).moveTo(grp1);

  cp5.addScrollableList("interval")
      .setFont(cf0)
      .setPosition(10, 20)
      .setSize(100, 60)
      .setBarHeight(20)
      .setItemHeight(20)
      .addItems(intevals)
      .setOpen(false)
      .moveTo(grp1)
      // Label
      .getCaptionLabel()
      .setText("select Interval")
      .toUpperCase(false)
      ;
      // Label
  cp5.get(ScrollableList.class, "interval")
      .getValueLabel()
      .toUpperCase(false)
      ;
      
  cp5.addToggle("dump_csv")
      .setFont(cf0)
      .setPosition(10, 90)
      .setSize(10,10)
      .moveTo(grp1)
      // Label
      .getCaptionLabel()
      .setText("Dump CSV")
      .toUpperCase(false)
      ;
  st = cp5.get(Toggle.class, "dump_csv").getCaptionLabel().getStyle();
  st.marginLeft = 20;
  st.marginTop = -20;

  cp5.addButton("clear_graph")
      .setFont(cf0)
      .setPosition(10,110)
      .setSize(100, 20)
      .moveTo(grp1)
      // Label
      .getCaptionLabel()
      .setText("Clear Graph")
      .toUpperCase(false)
      ;

  cp5.addRange("range_co2")
      .setFont(cf0)
      // disable broadcasting since setRange and setRangeValues will trigger an event
      .setBroadcast(false) 
      .setPosition(10, 170)
      .setSize(100, 20)
      .setHandleSize(10)
      .setRange(400, 2000)
      .setRangeValues(400, 1000)
      // after the initialization we turn broadcast back on again
      .setBroadcast(true)
      .setColorForeground(color(255, 40))
      .setColorBackground(color(255, 40))  
      .moveTo(grp1)
      ;
  cp5.get(Range.class, "range_co2")
      .getCaptionLabel()
      .setText("CO2 Green Zone")
      .toUpperCase(false)
      ;
  st = cp5.get(Range.class, "range_co2").getCaptionLabel().getStyle();
  st.marginLeft = -100;
  st.marginTop = -20;

  cp5.addRange("range_temp")
      .setFont(cf0)
      // disable broadcasting since setRange and setRangeValues will trigger an event
      .setBroadcast(false) 
      .setPosition(10, 210)
      .setSize(100, 20)
      .setHandleSize(10)
      .setRange(-40, 60)
      .setRangeValues(0, 30)
      // after the initialization we turn broadcast back on again
      .setBroadcast(true)
      .setColorForeground(color(255, 40))
      .setColorBackground(color(255, 40))  
      .moveTo(grp1)
      ;
  cp5.get(Range.class, "range_temp")
      .getCaptionLabel()
      .setText("T. Green Zone")
      .toUpperCase(false)
      ;
  st = cp5.get(Range.class, "range_temp").getCaptionLabel().getStyle();
  st.marginLeft = -100;
  st.marginTop = -20;

  cp5.addRange("range_humi")
      .setFont(cf0)
      // disable broadcasting since setRange and setRangeValues will trigger an event
      .setBroadcast(false) 
      .setPosition(10, 250)
      .setSize(100,20)
      .setHandleSize(10)
      .setRange(0, 100)
      .setRangeValues(20, 60)
      // after the initialization we turn broadcast back on again
      .setBroadcast(true)
      .setColorForeground(color(255, 40))
      .setColorBackground(color(255, 40))  
      .moveTo(grp1)
      ;
  cp5.get(Range.class, "range_humi")
      .getCaptionLabel()
      .setText("H. Green Zone")
      .toUpperCase(false)
      ;
  st = cp5.get(Range.class, "range_humi").getCaptionLabel().getStyle();
  st.marginLeft = -100;
  st.marginTop = -20;
  cp5.addAccordion("acc_option")
     .setPosition(120,0)
     .setWidth(120)
     .addItem(grp1)
     .setItemHeight(300)
     //.activateEvent(true)
     ;

  // ====================
  // Com Menu
  // ====================
  comPorts = Serial.list();

  Group grp2 = cp5.addGroup("COM")
                  .setBackgroundColor(color(0, 192))
                  .setBarHeight(20)
                  .hideArrow() 
                  //.activateEvent(true)
                  ;
  grp2.getCaptionLabel()
      .setFont(cf0)
      .setHeight(20)
      .toUpperCase(false)
      ;

  //cp5.addTextlabel("lbl_comPort").setFont(cf0).setText("COM Port").setPosition(10,10).moveTo(grp0).removeProperty("stringValue");
  cp5.addTextlabel("lbl_comPort", "COM Port", 10, 10).setFont(cf0).moveTo(grp2);
  cp5.addTextlabel("lbl_comSpeed").setFont(cf0).setText("COM Speed").setPosition(10,80).moveTo(grp2);
                    
  cp5.addScrollableList("comPort")
      .setFont(cf0)
      .setPosition(10, 30)
      .setSize(100, 60)
      .setBarHeight(20)
      .setItemHeight(20)
      .addItems(comPorts)
      .setOpen(false)
      .moveTo(grp2)
      .addCallback(
        new CallbackListener() {
          public void controlEvent(CallbackEvent theEvent) {
            if (theEvent.getAction() == ControlP5.ACTION_PRESS) {
              ScrollableList comPort = (ScrollableList) theEvent.getController();
              comPorts = Serial.list();
              comPort.setItems(comPorts);
            }
          }
        }
      )
      // Label
      .getCaptionLabel()
      .setText("select Port")
      .toUpperCase(false)
      ;
  
  cp5.addScrollableList("comSpeed")
      .setFont(cf0)
      .setPosition(10, 100)
      .setSize(100, 60)
      .setBarHeight(20)
      .setItemHeight(20)
      .addItems(comSpeeds)
      .setOpen(false)
      .moveTo(grp2)
      // Label
      .getCaptionLabel()
      .setText("select Speed")
      .toUpperCase(false)
      ;

  cp5.addAccordion("acc_com")
     .setPosition(240,0)
     .setWidth(120)
     .addItem(grp2)
     .setItemHeight(180)
     //.activateEvent(true)
     ;

  // ====================
  // Rest of Tool Bar
  // ====================
  cp5.addButtonBar("bar")
    .setPosition(360, 0)
    .setSize(280, 20)
    ;

  // ====================
  // Chart Start / Stop
  // ====================
  cp5.addIcon("capture", 10)
      .setPosition(600, 24)
      .setSize(30, 30)              // this determins mouse sensitive area
      //.setRoundedCorners(20)
      .setFont(createFont("fontawesome-webfont.ttf", 30)) // 30 determines the size
      .setFontIcons(#00f201, #00f201) // Play: #00f144, Stop:#00f28d, Pause: #00f28b
      .setSwitch(true)
      .setOn()
      .setColorForeground(color(64))
      .setColorActive(color(224, 192, 0))
      //.hideBackground()
      ;
     
  // ====================
  // Load Properties
  // ====================
  // === Remove All unused properties ===
  for (Textlabel textLabel: cp5.getAll(Textlabel.class)) {
    cp5.removeProperty(textLabel);
  }
  // === Load Properties ===
  cp5.loadProperties(("sensor.properties"));

  // ====================
  // CSV Dump
  // ====================
  csvDumpFileName = nf(year(), 4) + "_" + nf(month(), 2) + nf(day(), 2) +"_"+ nf(hour(), 2) + nf(minute(), 2) + nf(second(), 2) + ".csv";
  csv = createWriter(csvDumpFileName);
  csv.println("date,CO2");
  
}

void disp_meter(int x, int y, int w, int h, String captionStr, boolean isValid, float val, String valFmt, String unitStr, String rangeName) {
  Range range = cp5.get(Range.class, rangeName);
  boolean withinRange = (val >= range.getLowValue() && val <= range.getHighValue());
  if (withinRange) {
    fill(256, 256, 256);
  } else {
    fill(192, 24, 24);
  }
  rect(x, y, w, h, 4);
  textAlign(RIGHT);
  fill(256, 256, 256);
  textSize(20);
  text(captionStr, x+w/2-58, y+h/2+8);  
  textAlign(CENTER);
  if (withinRange) {
    fill(0, 102, 153);
  } else {
    fill(255, 255, 255);
  }
  textSize(20);
  if (isValid) {
    text(String.format(valFmt, val), x+w/2-4, y+h/2+8);
  } else {
    text("---", x+w/2-4, y+h/2+8);
  }
  textSize(12);
  text(unitStr, x+w/2+34, y+h/2+8);
}

void draw() {
  background(128);
  // Meters
  disp_meter(100+180*0, 24, 100, 30, "CO2:", co2ppm_valid, co2ppm, "%.0f", "ppm", "range_co2");
  disp_meter(100+180*1, 24, 100, 30, "T:", temp_valid, temp, "%.1f", "°C", "range_temp");
  disp_meter(100+180*2, 24, 100, 30, "H:", humi_valid, humi, "%.1f", "%", "range_humi");
  
  // Rx Indicator
  if (millis() - rx_time < 300) {
    fill(24, 192, 24);
  } else {
    fill(24, 24, 24);
  }
  circle(20, 40, 8);
  
  // Graph tick process
  if (queue.getNPoints() >= 1) {
    GPoint gp = queue.get(0);
    while (queue.getNPoints() > 0) {
      gp = queue.get(0);
      if (gp.getLabel().equals("CO2")) {
        accum_val += gp.getY();
        accum_count++;
      }
      queue.remove(0);
    }
    int sampleTime = millis();
    int interval = interval_vals[(int) cp5.get(ScrollableList.class, "interval").getValue()];
    if (sampleTime - lastSampleTime >= interval*1000) {
      lastSampleTime += interval*1000;
      if (accum_count > 0) {
        float value = (float) accum_val / accum_count;
        if (points.getNPoints() >= pSize) {
          points.remove(0);
        }
        points.add(gp.getX(), value);
        //points.add(gp.getX(), value, gp.getLabel());
        //points.add(gp);
        if (Objects.nonNull(csv) && cp5.get(Toggle.class, "dump_csv").getValue() == 1) {
          Date date = new Date((long) gp.getX()*1000 + + baseDate.getTime());
          SimpleDateFormat sdf = new SimpleDateFormat("yyyy/MM/dd HH:mm:ss");
          csv.println("\"" + sdf.format(date) + "\"," + String.valueOf(value));
          csv.flush();
          csvIsWritten = true;
        }
        accum_val = 0;
        accum_count = 0;
        plot.setPoints(points);
        plotUpdated = true;
      }
    }
  }

  // Graph Update
  if (plotUpdated) {
    plotUpdated = false;
    plot.getXAxis().setNTicks(6);
    int tickSize = plot.getXAxis().getTicks().length;
    String tickLabels[] = new String[tickSize];
    //int tickIdx = 0;
    String prvDateStr = "";
    for (int i = 0; i < tickSize; i++) {
      float tickX = plot.getXAxis().getTicks()[i];
      Date tickDate = new Date((long) tickX*1000 + + baseDate.getTime());
      SimpleDateFormat sdf = new SimpleDateFormat("yyyy/MM/dd HH:mm:ss");
      String tickDateStr = sdf.format(tickDate);
      String dateStr = tickDateStr.substring(5, 10);
      String timeStr = tickDateStr.substring(11, 16);
      if (prvDateStr.equals(dateStr)) {
        tickLabels[i] = timeStr;
      } else {
        tickLabels[i] = timeStr + "\n" + dateStr;
        prvDateStr = dateStr;
      }
    }
    plot.getXAxis().setTickLabels(tickLabels);
  }
  plot.defaultDraw();
}

// ====================
// Callback Functions
// ====================
// === GUI Callback Functions ===
public void exit() {
  if (Objects.nonNull(csv)) {
    csv.flush();
    csv.close();
  }
  if (!csvIsWritten) {
    File f = new File(sketchPath() + "/" + csvDumpFileName);
    if (f.exists()) {
      f.delete();
    }
  }
  println("exit");
  super.exit();
}

public void load_csv(int theValue) {
  selectInput("Select a file to process:", "csvFileSelected", new File(dataPath("")));
}

public void csvFileSelected(File selection) {
  if (selection != null) {
    noLoop(); // stop draw() to avoid plot conflicting
    println("User selected " + selection.getAbsolutePath());
    Table table = loadTable(selection.getAbsolutePath(), "header");
    println(table.getRowCount() + " total rows in table");
    for (TableRow row : table.rows()) {
      try {
        String dateStr = row.getString("date");
        SimpleDateFormat sdf = new SimpleDateFormat("yyyy/MM/dd HH:mm:ss");
        Date date = sdf.parse(dateStr);
        float co2ppm = row.getFloat("CO2");
        if (points.getNPoints() >= pSize) {
          points.remove(0);
        }
        points.add((float) (date.getTime() - baseDate.getTime())/1000, co2ppm);
        //queue.add((float) (date.getTime() - baseDate.getTime())/1000, co2ppm);
      } catch (ParseException e) {
        println("illegal format");
        //e.printStackTrace();
      }
    }
    plot.setPoints(points);
    println("Done");
    plotUpdated = true;
    loop(); // restart draw()
  }
  //cp5.get(Accordion.class, "acc_file").close(); // this causes something wrong with event handling
}

private void configCom() {
  //String comPort = cp5.get(ScrollableList.class, "comPort").getValueLabel().getText(); // this works, but got '-' at initial
  //int comSpeed = Integer.parseInt(cp5.get(ScrollableList.class, "comSpeed").getValueLabel().getText()); // this doesn't work correctly
  if (comPorts.length > 0) {
    String comPort = comPorts[(int) cp5.get(ScrollableList.class, "comPort").getValue()];
    int comSpeed = Integer.parseInt(comSpeeds[(int) cp5.get(ScrollableList.class, "comSpeed").getValue()]);
    println("COM Port: " + comPort + " Speed: " + comSpeed);
    if (Objects.nonNull(Port)) {
      Port.stop();
    }
    if (comPort != "" || comPort != "-") {
      Port = new Serial(this, comPort, comSpeed);
      Port.bufferUntil(10);
    }
    // === Save Properties ===
    cp5.saveProperties("sensor.properties");
  }
}

public void comPort(int theValue) {
  configCom();
}

public void comSpeed(int theValue) {
  configCom();
}

public void interval(int theValue) {
  // === Save Properties ===
  cp5.saveProperties("sensor.properties");
}

public void dump_csv(int theValue) {
  // === Save Properties ===
  cp5.saveProperties("sensor.properties");
}

public void clear_graph(int theValue) {
  noLoop(); // stop draw() to avoid plot conflicting
  points.removeInvalidPoints();
  points.removeRange(0, points.getNPoints()); // remove 0 ~ N-1
  plot.setPoints(points);
  lastSampleTime = millis();
  plotUpdated = true;
  loop(); // restart draw()  
}

// === Serial Callback Function ===
private static boolean isFloat(String str) {
  String regex = "^\\-?\\d+(\\.\\d+)?$";
  Pattern p = Pattern.compile(regex);
  Matcher m = p.matcher(str);
  return m.find();
}

private static boolean isDigit(String str) {
  String regex = "^\\-?\\d+$";
  Pattern p = Pattern.compile(regex);
  Matcher m = p.matcher(str);
  return m.find();
}
    
public void serialEvent(Serial Port) {
  int idx0, idx1, idx2;
  String str;
  String comText;
  
  rx_time = millis();
  comText = Port.readStringUntil(10);
  print(comText);
  
  //format example
  // # C:xxxx T:-2.50 H:52.80
  // # C:444 T:26.70 H:52.70

  idx0 = comText.indexOf("# C:");
  idx1 = comText.indexOf(" T:");
  idx2 = comText.indexOf(" H:");

  str = comText.substring(idx0+4, idx1);
  if (isDigit(str)) {
    co2ppm = Integer.parseInt(str);
    co2ppm_valid = true;
  } else {
    co2ppm_valid = false;
  }
  str = comText.substring(idx1+3, idx2);
  if (isFloat(str)) {
    temp = Float.parseFloat(str);
    temp_valid = true;
  } else {
    temp_valid = false;
  }
  str = comText.substring(idx2+3, comText.length());
  if (isFloat(str)) {
    humi = Float.parseFloat(str);
    humi_valid = true;
  } else {
    humi_valid = false;
  }
  
  noLoop(); // stop draw() to avoid plot conflicting
  if (queue.getNPoints() == 0 && cp5.get(Icon.class, "capture").getBooleanValue()) {
    if (co2ppm_valid) {
      queue.add((float) (new Date().getTime() - baseDate.getTime())/1000, co2ppm, "CO2");
    }
    if (temp_valid) {
      queue.add((float) (new Date().getTime() - baseDate.getTime())/1000, temp, "T");
    }
    if (humi_valid) {
      queue.add((float) (new Date().getTime() - baseDate.getTime())/1000, humi, "H");
    }
  }
  loop(); // restart draw()
    
}

public void mouseReleased() {
  if (
    cp5.getMouseOverList().contains(cp5.get(Range.class, "range_co2")) ||
    cp5.getMouseOverList().contains(cp5.get(Range.class, "range_temp")) ||
    cp5.getMouseOverList().contains(cp5.get(Range.class, "range_humi"))
  ) {
    // === Save Properties ===
    cp5.saveProperties("sensor.properties");    
  }
}
