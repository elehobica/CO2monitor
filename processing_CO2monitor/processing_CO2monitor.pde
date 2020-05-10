import java.util.*;
import java.util.regex.*;
import java.text.*;
import java.lang.Math;
import processing.serial.*;
import controlP5.*;
import grafica.*;
 
ControlP5 cp5;

Serial Port;
int lastRxTime = -300; // for Rx Indicator

// COM configuration parameters
String comPorts[];
String comSpeeds[] = {"9600", "19200", "38400", "57600", "115200"};
String intevals[] = {"1sec(1hour)", "3sec(3hour)", "6sec(6hour)", "12sec(12hour)", "24sec(24hour)", "60sec(60hour)", "168sec(7days)", "4min(10days)", "336sec(14days)", "12min(30days)", "60min(150days)"};
int interval_vals[] = {1, 3, 6, 12, 24, 60, 168, 60*4, 336, 60*12, 60*60};

// Raw Items
int co2ppm = 0;
float temp = 0.0;
float humi = 0.0;
boolean co2ppm_valid = false;
boolean temp_valid = false;
boolean humi_valid = false;

// Graphs
final int nGraphs = 3;
final int pSize = 3600;
GPointsArray queue;
AccumGraph[] graphs;
boolean plotUpdated = false;
int lastSampleTime = 0;
Date baseDate; // for handling Date in float value

// CSV Dump File
String csvDumpFileName;
PrintWriter csv;
int csvNumItems = 0;
   
//===============================================
// Class for accumulating value & plotting graph
//===============================================
public class AccumGraph {
  private int size;
  private GPlot plot;
  private GPointsArray points;
  private float accumVal;
  private int accumCount;
  private float roundUnit;
  private boolean isPlotted;
  // Constructor
  public AccumGraph(PApplet parent, int size, String title, int plotColor, float roundUnit, boolean drawXTicksLabels) {
    this.size = size;
    plot = new GPlot(parent);
    points = new GPointsArray(size);
    //plot.setPoints(points);
    this.roundUnit = roundUnit;
    accumVal = 0.0;
    accumCount = 0;
    isPlotted = false;
    plot.setOuterDim(520, 120);
    plot.setDim(520, 120);
    plot.setPointSize(2.0);
    plot.setPointColor(plotColor);
    plot.setLineColor(plotColor);
    plot.setAxesOffset(0);
    plot.setTicksLength(-4);
    plot.setTitleText(title);
    plot.getTitle().setRelativePos(0.05);
    //plot.getYAxis().setAxisLabelText(title);
    // Activate the zooming and panning
    //plot.activateZooming();
    //plot.activatePanning();
    plot.getYAxis().setRotateTickLabels(false);
    plot.getXAxis().setDrawTickLabels(drawXTicksLabels);
    if (drawXTicksLabels) {
      plot.setMar(50, 40, 40, 20);
    } else {
      plot.setMar(0, 40, 40, 20);
    }
  }
  void setPlotPos(float x, float y) {
    plot.setPos(x, y);
  }
  void accum(float y) {
    accumVal += y;
    accumCount++;
  }
  void put(float x, float y) {
    if (points.getNPoints() >= size) {
      points.remove(0);
    }
    points.add(x, y);
  }
  void reflect() {
    plot.setPoints(points);
  }
  // plotAccum: if accumulated, plot accumVal and return true otherwise return false
  boolean plotAccum(float x) {
    if (accumCount > 0) {
      float value = (float) Math.round(accumVal / accumCount * ((int) (1.0 / roundUnit))) / ((int) (1.0 / roundUnit));
      //float value = Math.round(accumVal / accumCount * 10.0) / 10.0;
      put(x, value);
      reflect();
      accumVal = 0.0;
      accumCount = 0;
      isPlotted = true;
    } else {
      isPlotted = false;
    }
    return isPlotted;
  }
  boolean isPlotted() {
    return isPlotted;
  }
  float getLastAccumY() {
    return points.getLastPoint().getY();
  }
  void setXTickLabels(String[] newTickLabels) {
    plot.getXAxis().setTickLabels(newTickLabels);
  }
  // convertXTickLabelsToDate: convert XTicks in float to those in Date String
  String[] convertXTickLabelsToDate(Date baseDate) {
    int tickSize = plot.getXAxis().getTicks().length; // get actual number of ticks
    String tickLabels[] = new String[tickSize];
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
    setXTickLabels(tickLabels); // the number of tickLabels must be as same as the number of ticks, otherwise ignored
    return tickLabels;
  }
  float[] getXLim() {
    return plot.getXLim();
  }
  void setXLim(float[] newXLim) {
    plot.setXLim(newXLim);
  }
  void draw() {
    plot.beginDraw();
    plot.drawBackground();
    plot.drawBox();
    plot.drawGridLines(GPlot.VERTICAL);
    plot.drawXAxis();
    plot.drawYAxis();
    plot.drawTitle();
    plot.drawPoints();
    plot.drawLines();
    plot.endDraw();
  }
  void clear() {
    accumVal = 0.0;
    accumCount = 0;
    points.removeInvalidPoints();
    points.removeRange(0, points.getNPoints()); // remove 0 ~ N-1
    reflect();
  }
  void setXNTicks(int newNTicks) {
    plot.getXAxis().setNTicks(newNTicks);
  }
}

void setup() {
  ControllerStyle st;
  
  // long getTime() cannot be handled by float which is supported GPlot
  // Threfore this sketch handles the offset time
  baseDate = new Date();

  size(640, 620);
  surface.setTitle("CO2 Monitor");
  cp5 = new ControlP5(this);
  ControlFont cf0 = new ControlFont(createFont("Arial", 12));

  // ====================
  // Queue
  // ====================
  queue = new GPointsArray(nGraphs);

  // ====================
  // Graphs
  // ====================
  graphs = new AccumGraph[nGraphs];
  graphs[0] = new AccumGraph(this, pSize, "CO2 (ppm)", 0xffee0000, 0.1, false);
  graphs[1] = new AccumGraph(this, pSize, "Temperature (°C)", 0xff00cc00, 0.01, false);
  graphs[2] = new AccumGraph(this, pSize, "Humidity (%)", 0xff0000cc, 0.1, true);
  for (int i = 0; i < nGraphs; i++) {
    graphs[i].setPlotPos(30, 70+160*i);
  }

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

  cp5.addTextlabel("lbl_interval").setFont(cf0).setText("Graph tick(Total)").setPosition(10,10).moveTo(grp1);

  cp5.addScrollableList("interval")
      .setFont(cf0)
      .setPosition(10, 30)
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

  cp5.addButton("clear_graph")
      .setFont(cf0)
      .setPosition(10, 100)
      .setSize(100, 20)
      .moveTo(grp1)
      // Label
      .getCaptionLabel()
      .setText("Clear Graph")
      .toUpperCase(false)
      ;
     
  cp5.addToggle("dump_csv")
      .setFont(cf0)
      .setPosition(10, 140)
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

  cp5.addRange("range_co2")
      .setFont(cf0)
      // disable broadcasting since setRange and setRangeValues will trigger an event
      .setBroadcast(false) 
      .setPosition(10, 180)
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
      .setText("CO2 Normal Zone")
      .toUpperCase(false)
      ;
  st = cp5.get(Range.class, "range_co2").getCaptionLabel().getStyle();
  st.marginLeft = -100;
  st.marginTop = -20;

  cp5.addRange("range_temp")
      .setFont(cf0)
      // disable broadcasting since setRange and setRangeValues will trigger an event
      .setBroadcast(false) 
      .setPosition(10, 220)
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
      .setText("T. Normal Zone")
      .toUpperCase(false)
      ;
  st = cp5.get(Range.class, "range_temp").getCaptionLabel().getStyle();
  st.marginLeft = -100;
  st.marginTop = -20;

  cp5.addRange("range_humi")
      .setFont(cf0)
      // disable broadcasting since setRange and setRangeValues will trigger an event
      .setBroadcast(false) 
      .setPosition(10, 260)
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
      .setText("H. Normal Zone")
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
      .setFont(createFont("fontawesome-webfont.ttf", 30)) // Font, Size
      .setFontIcons(#00f201, #00f201) // Play: #00f144, Stop:#00f28d, Pause: #00f28b, Chart: #00f201
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
  // CSV Dump File
  // ====================
  csvDumpFileName = nf(year(), 4) + "_" + nf(month(), 2) + nf(day(), 2) +"_"+ nf(hour(), 2) + nf(minute(), 2) + nf(second(), 2) + ".csv";
  csv = createWriter(dataPath("") + "/" + csvDumpFileName);
  //csv = createWriter(sketchPath() + "/" + csvDumpFileName);
  csv.println("date,CO2,Temperature,Humidity");
  csvNumItems = 0;
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
  if (millis() - lastRxTime < 300) {
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
      for (int i = 0; i < nGraphs; i++) {
        if (gp.getLabel().equals(String.valueOf(i))) {
          graphs[i].accum(gp.getY());
        }
      }
      queue.remove(0);
    }
    int sampleTime = millis();
    int interval = interval_vals[(int) cp5.get(ScrollableList.class, "interval").getValue()];
    if (sampleTime - lastSampleTime >= interval*1000) {
      lastSampleTime += interval*1000;
      for (int i = 0; i < nGraphs; i++) {
        plotUpdated |= graphs[i].plotAccum(gp.getX());
      }
      if (Objects.nonNull(csv) && cp5.get(Toggle.class, "dump_csv").getValue() == 1) {
        if (csvNumItems >= pSize) {
          // renew (close & reopen) CSV File
          csv.flush();
          csv.close();
          csvDumpFileName = nf(year(), 4) + "_" + nf(month(), 2) + nf(day(), 2) +"_"+ nf(hour(), 2) + nf(minute(), 2) + nf(second(), 2) + ".csv";
          csv = createWriter(dataPath("") + "/" + csvDumpFileName);
          //csv = createWriter(sketchPath() + "/" + csvDumpFileName);
          csv.println("date,CO2,Temperature,Humidity");
          csvNumItems = 0;
        }
        Date date = new Date((long) gp.getX()*1000 + + baseDate.getTime());
        SimpleDateFormat sdf = new SimpleDateFormat("yyyy/MM/dd HH:mm:ss");
        csv.print("\"" + sdf.format(date) + "\"");
        for (int i = 0; i < nGraphs; i++) {
          csv.print(",");
          if (graphs[i].isPlotted()) {
            csv.print(String.valueOf(graphs[i].getLastAccumY()));
          }
        }
        csv.println("");
        csv.flush();
        csvNumItems++;
      }
    }
  }

  // Graph Update
  if (plotUpdated) {
    plotUpdated = false;
    for (int i = 0; i < nGraphs; i++) {
      graphs[i].setXNTicks(6); // number of ticks is just the guideline (can be differ from actual number)
    }
    // The Reference is graphs[1] (Temperature) because graphs[0] (CO2) has warming-up period after power-on
    String tickLabels[] = graphs[1].convertXTickLabelsToDate(baseDate);
    float xLims[] = graphs[1].getXLim();
    // Copy reference XAxis Limits and XAxis Tick Labels to other graphs
    for (int i = 0; i < nGraphs; i++) {
      if (i == 1) { continue; }
      graphs[i].setXLim(xLims);
      graphs[i].setXTickLabels(tickLabels);
    }
  }
  // Draw Graphs from Lower to Upper to show XAxis line
  for (int i = nGraphs-1; i >= 0; i--) {
    graphs[i].draw();
  }
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
  if (csvNumItems == 0) {
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
  if (selection == null) { return; }
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
      float f_date = (date.getTime() - baseDate.getTime()) / 1000.0;
      graphs[0].put(f_date, row.getFloat("CO2"));
      graphs[1].put(f_date, row.getFloat("Temperature"));
      graphs[2].put(f_date, row.getFloat("Humidity"));
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
  for (int i = 0; i < nGraphs; i++) {
    graphs[i].reflect();
  }
  println("Done");
  plotUpdated = true;
  loop(); // restart draw()
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
      try {
        Port = new Serial(this, comPort, comSpeed);
        Port.bufferUntil(10);
      } catch (RuntimeException e) {
        println("ERROR: Serial Port \"" + comPort + "\" is busy");
      }
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
  for (int i = 0; i < nGraphs; i++) {
    graphs[i].clear();
  }
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
  int idx;
  int idx0, idx1, idx2;
  String str;
  String comText;
  
  lastRxTime = millis();
  comText = Port.readStringUntil(10);
  print(comText);
  
  //format example
  // # C:xxxx T:-2.50 H:52.80
  // # C:444 T:26.70 H:52.70

  idx = comText.indexOf("#");
  idx0 = comText.indexOf(" C:");
  idx1 = comText.indexOf(" T:");
  idx2 = comText.indexOf(" H:");

  if (idx != 0) { return; }

  str = comText.substring(idx0+3, idx1);
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
  float f_date = (new Date().getTime() - baseDate.getTime()) / 1000.0;
  if (queue.getNPoints() == 0 && cp5.get(Icon.class, "capture").getBooleanValue()) {
    if (co2ppm_valid) {
      queue.add(f_date, co2ppm, "0");
    }
    if (temp_valid) {
      queue.add(f_date, temp, "1");
    }
    if (humi_valid) {
      queue.add(f_date, humi, "2");
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
