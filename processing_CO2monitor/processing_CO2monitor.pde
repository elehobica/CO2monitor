import java.util.*;
import java.text.*;
import processing.serial.*;
import controlP5.*;
import grafica.*;
 
Serial Port;
ControlP5 cp5;

String comPorts[];
String comSpeeds[] = {"9600", "19200", "38400", "57600", "115200"};
String intevals[] = {"1sec/1hour", "3sec/3hour", "6sec/6hour", "12sec/12hour", "24sec/24hour", "60sec/60hour", "168sec/7days", "4min/10days", "336sec/14days", "12min/30days", "60min/150days"};
int interval_vals[] = {1, 3, 6, 12, 24, 60, 168, 60*4, 336, 60*12, 60*60};

final int pSize = 3600;
int lastSampleTime = 0;
int accum_val = 0;
int accum_count = 0;

String comText = "";

GPlot plot;
GPointsArray queue;
GPointsArray points;

String csvDumpFileName;
PrintWriter csv;
boolean csvIsWritten = false;
boolean plotUpdated = false;
Date baseDate;
 
void setup() {
  // long getTime() cannot be handled by float which is supported GPlot
  // Threfore this sketch handles the offset time
  baseDate = new Date();

  size(640, 480);
  cp5 = new ControlP5(this);
  ControlFont cf0 = new ControlFont(createFont("Arial", 12));

  // ====================
  // CO2 Graph
  // ====================
  queue = new GPointsArray(1);
  points = new GPointsArray(pSize);

  plot = new GPlot(this);
  plot.setPos(40, 50);
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
  // CSV Load
  // ====================
  cp5.addButton("csv")
       .setFont(cf0)
       .setPosition(440,0)
       .setSize(55,20)
       ;
       
  // ====================
  // Configuration Menu
  // ====================
  comPorts = Serial.list();

  Group grp0 = cp5.addGroup("Configuration")
                  .setBackgroundColor(color(0, 64))
                  .setBarHeight(20)
                  ;
  grp0.getCaptionLabel()
      .setFont(cf0)
      .setHeight(20)
      .toUpperCase(false)
      ;

  //cp5.addTextlabel("lbl_comPort").setFont(cf0).setText("COM Port").setPosition(10,10).moveTo(grp0).removeProperty("stringValue");
  cp5.addTextlabel("lbl_comPort", "COM Port", 10, 10).setFont(cf0).moveTo(grp0);
  cp5.addTextlabel("lbl_comSpeed").setFont(cf0).setText("COM Speed").setPosition(10,80).moveTo(grp0);
  cp5.addTextlabel("lbl_interval").setFont(cf0).setText("Interval/History").setPosition(10,150).moveTo(grp0);
                    
  ScrollableList sll0 = cp5.addScrollableList("comPort")
                           .setFont(cf0)
                           .setPosition(10, 30)
                           .setSize(120, 60)
                           .setBarHeight(20)
                           .setItemHeight(20)
                           .addItems(comPorts)
                           .setOpen(false)
                           .moveTo(grp0)
                           ;
  sll0.getCaptionLabel()
      .setText("select Port")
      .toUpperCase(false)
      ;
  sll0.addCallback(
    new CallbackListener() {
      public void controlEvent(CallbackEvent theEvent) {
        if (theEvent.getAction() == ControlP5.ACTION_PRESS) {
          ScrollableList comPort = (ScrollableList) theEvent.getController();
          comPorts = Serial.list();
          comPort.setItems(comPorts);
        }
      }
    }
  );
  ScrollableList sll1 = cp5.addScrollableList("comSpeed")
                           .setFont(cf0)
                           .setPosition(10, 100)
                           .setSize(120, 60)
                           .setBarHeight(20)
                           .setItemHeight(20)
                           .addItems(comSpeeds)
                           .setOpen(false)
                           .moveTo(grp0)
                         ;
  sll1.getCaptionLabel()
      .setText("select Speed")
      .toUpperCase(false)
      ;
  ScrollableList sll2 = cp5.addScrollableList("interval")
                           .setFont(cf0)
                           .setPosition(10, 170)
                           .setSize(120, 60)
                           .setBarHeight(20)
                           .setItemHeight(20)
                           .addItems(intevals)
                           .setOpen(false)
                           .moveTo(grp0)
                         ;
  sll2.getCaptionLabel()
      .setText("select Interval")
      .toUpperCase(false)
      ;
  sll2.getValueLabel()
      .toUpperCase(false)
      ;
      
  Toggle tgl0 = cp5.addToggle("csvdump")
                    .setFont(cf0)
                    .setPosition(10, 240)
                    .setSize(10,10)
                    .moveTo(grp0)
                    ;
  tgl0.getCaptionLabel()
      .setText("CSV Dump")
      .toUpperCase(false)
      ;
    
  cp5.addAccordion("acc_config")
     .setPosition(500,0)
     .setWidth(140)
     .addItem(grp0)
     .setItemHeight(400)
     .activateEvent(true)
     ;
     
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

void draw() {
  background(128);
  fill(256, 256, 256);
  rect(10, 10, 100, 30, 4);
  fill(0, 102, 153);
  textAlign(CENTER);
  text(comText, 10+100/2, 10+40/2);
  textSize(20);

  if (queue.getNPoints() >= 1) {
    if (points.getNPoints() >= pSize) {
      points.remove(0);
    }
    GPoint gp = queue.get(0);
    accum_val += gp.getY();
    accum_count++;
    queue.remove(0);
    int sampleTime = millis();
    int interval = interval_vals[(int) cp5.get(ScrollableList.class, "interval").getValue()];
    if (sampleTime - lastSampleTime >= interval*1000) {
      lastSampleTime += interval*1000;
      float value = (float) accum_val / accum_count;
      points.add(gp.getX(), value);
      //points.add(gp.getX(), value, gp.getLabel());
      //points.add(gp);
      if (Objects.nonNull(csv) && cp5.get(Toggle.class, "csvdump").getValue() == 1) {
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

public void csv(int theValue) {
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

public void csvdump(int theValue) {
  // === Save Properties ===
  cp5.saveProperties("sensor.properties");
}

// === Serial Callback Function ===
public void serialEvent(Serial Port) {
  comText = Port.readStringUntil(10);
  print(comText);
  int co2ppm = Integer.parseInt(comText.substring(2, 6));

  noLoop(); // stop draw() to avoid plot conflicting
  if (queue.getNPoints() == 0) {
    queue.add((float) (new Date().getTime() - baseDate.getTime())/1000, co2ppm);
  }
  loop(); // restart draw()
}
