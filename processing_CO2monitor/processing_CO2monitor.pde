import java.util.*;
import java.util.regex.*;
import java.text.*;
import java.lang.Math;
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
float co2_accum_val = 0;
int co2_accum_count = 0;
float temp_accum_val = 0;
int temp_accum_count = 0;
float humi_accum_val = 0;
int humi_accum_count = 0;

int co2ppm = 0;
float temp = 0.0;
float humi = 0.0;
boolean co2ppm_valid = false;
boolean temp_valid = false;
boolean humi_valid = false;

GPlot plot;
GPlot plot1;
GPlot plot2;
GPointsArray queue;
GPointsArray points;
GPointsArray points1;
GPointsArray points2;

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

  size(640, 620);
  cp5 = new ControlP5(this);
  ControlFont cf0 = new ControlFont(createFont("Arial", 12));

  // ====================
  // Graphs
  // ====================
  queue = new GPointsArray(3);
  points = new GPointsArray(pSize);
  points1 = new GPointsArray(pSize);
  points2 = new GPointsArray(pSize);

  plot = new GPlot(this);
  plot.setPos(30, 70);
  plot.setOuterDim(520, 120);
  plot.setDim(520, 120);
  plot.setPoints(points);
  plot.setPointSize(2.0);
  plot.setAxesOffset(0);
  plot.setTicksLength(-4);
  plot.setTitleText("CO2 (ppm)");
  plot.getTitle().setRelativePos(0.05);
  //plot.getYAxis().setAxisLabelText("CO2 (ppm)");
  // Activate the zooming and panning
  //plot.activateZooming();
  //plot.activatePanning();
  plot.setMar(0, 40, 40, 20);
  plot.getYAxis().setRotateTickLabels(false);
  plot.getXAxis().setDrawTickLabels(false);
  
  plot1 = new GPlot(this);
  plot1.setPos(30, 230);
  plot1.setOuterDim(520, 120);
  plot1.setDim(520, 120);
  plot1.setPoints(points);
  plot1.setPointSize(2.0);
  plot1.setAxesOffset(0);
  plot1.setTicksLength(-4);
  plot1.setTitleText("Temperature (°C)");
  plot1.getTitle().setRelativePos(0.05);
  //plot1.getYAxis().setAxisLabelText("CO2 (ppm)");
  // Activate the zooming and panning
  //plot1.activateZooming();
  //plot1.activatePanning();
  plot1.setMar(0, 40, 40, 20);
  plot1.getYAxis().setRotateTickLabels(false);
  plot1.getXAxis().setDrawTickLabels(false);

  plot2 = new GPlot(this);
  plot2.setPos(30, 390);
  plot2.setOuterDim(520, 120);
  plot2.setDim(520, 120);
  plot2.setPoints(points);
  plot2.setPointSize(2.0);
  plot2.setAxesOffset(0);
  plot2.setTicksLength(-4);
  plot2.setTitleText("Humidity (%)");
  plot2.getTitle().setRelativePos(0.05);
  //plot2.getYAxis().setAxisLabelText("CO2 (ppm)");
  // Activate the zooming and panning
  //plot2.activateZooming();
  //plot2.activatePanning();
  plot2.setMar(50, 40, 40, 20);
  plot2.getYAxis().setRotateTickLabels(false);
  //plot2.getXAxis().setDrawTickLabels(false);

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
      .setRange(-5, 35)
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
      .setRange(10, 90)
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
  csv = createWriter(dataPath("") + "/" + csvDumpFileName);
  //csv = createWriter(sketchPath() + "/" + csvDumpFileName);
  csv.println("date,CO2,Temperature,Humidity");
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
        co2_accum_val += gp.getY();
        co2_accum_count++;
      } else if (gp.getLabel().equals("T")) {
        temp_accum_val += gp.getY();
        temp_accum_count++;
      } else if (gp.getLabel().equals("H")) {
        humi_accum_val += gp.getY();
        humi_accum_count++;
      }
      queue.remove(0);
    }
    int sampleTime = millis();
    int interval = interval_vals[(int) cp5.get(ScrollableList.class, "interval").getValue()];
    if (sampleTime - lastSampleTime >= interval*1000) {
      lastSampleTime += interval*1000;
      if (co2_accum_count > 0) {
        float value = Math.round(co2_accum_val / co2_accum_count * 10.0) / 10.0;
        if (points.getNPoints() >= pSize) {
          points.remove(0);
        }
        points.add(gp.getX(), value);

        plot.setPoints(points);
        plotUpdated = true;
      }
      if (temp_accum_count > 0) {
        float value = Math.round(temp_accum_val / temp_accum_count * 10.0) / 10.0;
        if (points1.getNPoints() >= pSize) {
          points1.remove(0);
        }
        points1.add(gp.getX(), value);
        plot1.setPoints(points1);
        plotUpdated = true;
      }
      if (humi_accum_count > 0) {
        float value = Math.round(humi_accum_val / humi_accum_count * 10.0) / 10.0;
        if (points2.getNPoints() >= pSize) {
          points2.remove(0);
        }
        points2.add(gp.getX(), value);
        plot2.setPoints(points2);
        plotUpdated = true;
      }
      if (Objects.nonNull(csv) && cp5.get(Toggle.class, "dump_csv").getValue() == 1) {
        Date date = new Date((long) gp.getX()*1000 + + baseDate.getTime());
        SimpleDateFormat sdf = new SimpleDateFormat("yyyy/MM/dd HH:mm:ss");
        csv.print("\"" + sdf.format(date) + "\",");
        if (co2_accum_count > 0) {
          csv.print(String.valueOf(points.getLastPoint().getY()));
        }
        csv.print(",");
        if (temp_accum_count > 0) {
          csv.print(String.valueOf(points1.getLastPoint().getY()));
        }
        csv.print(",");
        if (humi_accum_count > 0) {
          csv.print(String.valueOf(points2.getLastPoint().getY()));
        }
        csv.println("");
        csv.flush();
        csvIsWritten = true;
      }
      co2_accum_val = 0;
      co2_accum_count = 0;
      temp_accum_val = 0;
      temp_accum_count = 0;
      humi_accum_val = 0;
      humi_accum_count = 0;
    }
  }

  // Graph Update
  if (plotUpdated) {
    plotUpdated = false;
    
    plot.getXAxis().setNTicks(6);
    plot1.getXAxis().setNTicks(6);
    plot2.getXAxis().setNTicks(6);
    
    // Reference Tick is plot1 (Temp.)
    int tickSize = plot1.getXAxis().getTicks().length;
    String tickLabels[] = new String[tickSize];
    //int tickIdx = 0;
    String prvDateStr = "";
    for (int i = 0; i < tickSize; i++) {
      float tickX = plot1.getXAxis().getTicks()[i];
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
    plot1.getXAxis().setTickLabels(tickLabels);
        
    // Copy XAxis Limit of the reference to the others
    plot.setXLim(plot1.getXLim());
    plot2.setXLim(plot1.getXLim());
    // Copy XAxis Tick Labels
    plot.getXAxis().setTickLabels(tickLabels);
    plot2.getXAxis().setTickLabels(tickLabels);
  }
  // Draw Graphs from Lower to Upper to show XAxis line
  plot2.defaultDraw();
  plot1.defaultDraw();
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
    File f = new File(dataPath("") + "/" + csvDumpFileName);
    //File f = new File(sketchPath() + "/" + csvDumpFileName);
    if (f.exists()) {
      f.delete();
    }
  }
  println("exit");
  super.exit();
}

public void load_csv(int theValue) {
  selectInput("Select a file to process:", "csvFileSelected", new File(dataPath("data/")));
}

public void csvFileSelected(File selection) {
  if (selection != null) {
    noLoop(); // stop draw() to avoid plot conflicting
    println("User selected " + selection.getAbsolutePath());
    Table table = loadTable(selection.getAbsolutePath(), "header");
    println(table.getRowCount() + " total rows in table");
    for (TableRow row : table.rows()) {
      try {
        float value;
        String dateStr = row.getString("date");
        SimpleDateFormat sdf = new SimpleDateFormat("yyyy/MM/dd HH:mm:ss");
        Date date = sdf.parse(dateStr);
        value = row.getFloat("CO2");
        if (points.getNPoints() >= pSize) {
          points.remove(0);
        }
        points.add((float) (date.getTime() - baseDate.getTime())/1000, value);
        value = row.getFloat("Temperature");
        if (points1.getNPoints() >= pSize) {
          points1.remove(0);
        }
        points1.add((float) (date.getTime() - baseDate.getTime())/1000, value);
        value = row.getFloat("Humidity");
        if (points2.getNPoints() >= pSize) {
          points2.remove(0);
        }
        points2.add((float) (date.getTime() - baseDate.getTime())/1000, value);        
      } catch (ParseException e) {
        println("ERROR: illegal format");
        //e.printStackTrace();
        break;
      } catch (IllegalArgumentException e) {
        println("ERROR: illegal format");
        //e.printStackTrace();
        break;
      }
    }
    plot.setPoints(points);
    plot1.setPoints(points1);
    plot2.setPoints(points2);
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
  points1.removeInvalidPoints();
  points1.removeRange(0, points1.getNPoints()); // remove 0 ~ N-1
  plot1.setPoints(points1);
  points2.removeInvalidPoints();
  points2.removeRange(0, points2.getNPoints()); // remove 0 ~ N-1
  plot2.setPoints(points);
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
