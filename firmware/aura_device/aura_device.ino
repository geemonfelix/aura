// --- AURA Firmware v5.2: Custom GPS Pins ---
// This version configures the GPS module to use custom pins D26 (RX) and D25 (TX).

// -----------------------------------------------------------------
// 1. INCLUDE LIBRARIES
// -----------------------------------------------------------------
#include <Wire.h>
#include <oled.h>
#include <AccelAndGyro.h>
#include <DHT.h>
#include <TinyGPS++.h>
#include <MQ135.h>
#include <WiFi.h>
#include <time.h>

// Firebase Libraries - Firestore is part of the main client library
#include <Firebase_ESP_Client.h>
#include "addons/TokenHelper.h"

// Disable unused Firebase features for faster compilation
#define FIREBASE_DISABLE_ONBOARD_WIFI
#define FIREBASE_DISABLE_ONBOARD_BLE

// -----------------------------------------------------------------
// 2. WIFI & FIREBASE CREDENTIALS
// -----------------------------------------------------------------
#define WIFI_SSID "Geemon Vettiyadan"
#define WIFI_PASSWORD "password"

#define API_KEY "AIzaSyDvV3dyiZ18SKuHWSrP7u-7rM2cIWR7liE"
#define FIREBASE_PROJECT_ID "aura-project-8dc5b"
#define USER_EMAIL "********"
#define USER_PASSWORD "*********"

// -----------------------------------------------------------------
// 3. PIN DEFINITIONS & CONSTANTS
// -----------------------------------------------------------------
#define DHT_PIN     27
#define MQ135_PIN   34
#define GUVA_PIN    35
#define BUZZER_PIN  14
#define DHT_TYPE    DHT22
#define SCREEN_WIDTH 128
#define SCREEN_HEIGHT 64
#define MIN_FREE_HEAP 80000 // Minimum required memory for a stable Firebase connection

// -----------------------------------------------------------------
// 4. OBJECT INITIALIZATION
// -----------------------------------------------------------------
oLed display(SCREEN_WIDTH, SCREEN_HEIGHT);
AccelAndGyro accel;
DHT dht(DHT_PIN, DHT_TYPE);
MQ135 mq135_sensor(MQ135_PIN);
TinyGPSPlus gps;

FirebaseData fbdo;
FirebaseAuth auth;
FirebaseConfig config;
String deviceId = "";

// -----------------------------------------------------------------
// 5. GLOBAL VARIABLES
// -----------------------------------------------------------------
float temperatureC, humidity;
float accelX, accelY, accelZ;
float uvIndex;
float airQualityPPM;
double gpsLat = 0.0, gpsLng = 0.0;
int gpsSatellites = 0;
int auraRiskScore = 0;

int displayPage = 0;
const int NUM_PAGES = 3;

unsigned long previousMillis = 0;
const long interval = 30000; // Update every 30 seconds

bool firebaseReady = false;
unsigned long lastFirebaseAttempt = 0;
const unsigned long FIREBASE_RETRY_INTERVAL = 30000;
unsigned long lastWiFiAttempt = 0;

// -----------------------------------------------------------------
// 6. SETUP FUNCTION
// -----------------------------------------------------------------
void setup() {
  Serial.begin(115200);
  Serial.println("\nAURA Firmware v5.2 (Custom GPS Pins) Initializing...");

  deviceId = WiFi.macAddress();
  deviceId.replace(":", "");

  Wire.begin();
  dht.begin();
  
  // UPDATED: Initialize Serial2 for the GPS module on your specific pins.
  Serial2.begin(9600, SERIAL_8N1, 26, 25); // RX=D26, TX=D25
  
  pinMode(BUZZER_PIN, OUTPUT);

  display.begin();
  display.clearDisplay();
  display.setTextSize(1);
  display.setTextColor(SSD1306_WHITE);
  display.setCursor(0, 0);
  display.println("AURA System Check:");
  display.display();
  
  connectToWiFi();
  
  if(WiFi.status() == WL_CONNECTED) {
    syncTimeWithNTP();
    setupFirebase();
  }

  display.print(" MPU6050: ");
  if (accel.begin()) { display.println("OK"); } else { display.println("FAIL"); }
  display.display();
  delay(500);
  
  display.println("Check Complete.");
  display.display();
  delay(2000);
}

// -----------------------------------------------------------------
// 7. MAIN LOOP
// -----------------------------------------------------------------
void loop() {
  unsigned long currentMillis = millis();
  
  if (currentMillis - previousMillis >= interval) {
    previousMillis = currentMillis;

    readMyosaSensors();
    readStandardSensors();
    readGPS();
    
    auraRiskScore = calculateRiskScore(airQualityPPM, uvIndex, humidity, temperatureC);
    
    if (auraRiskScore < 25) {
      tone(BUZZER_PIN, 1500, 100);
    }
    
    updateOLED();
    printToSerial();
    
    if (WiFi.status() == WL_CONNECTED) {
      if (!Firebase.ready()) {
        if (currentMillis - lastFirebaseAttempt > FIREBASE_RETRY_INTERVAL) {
          Serial.println("Reinitializing Firebase due to connection issues...");
          Firebase.reset(&config);
          delay(1000);
          setupFirebase();
          lastFirebaseAttempt = currentMillis;
        }
      } else {
        sendDataToFirestore();
      }
    } else {
      if (currentMillis - lastWiFiAttempt > 30000) {
        Serial.println("Attempting WiFi reconnection...");
        connectToWiFi();
        if (WiFi.status() == WL_CONNECTED) {
          syncTimeWithNTP();
          setupFirebase();
        }
        lastWiFiAttempt = currentMillis;
      }
    }
    
    displayPage++;
    if (displayPage >= NUM_PAGES) {
      displayPage = 0;
    }
  }
}

// -----------------------------------------------------------------
// 8. CONNECTION & SETUP FUNCTIONS
// -----------------------------------------------------------------

void connectToWiFi() {
  display.print(" WiFi: Connecting...\n");
  display.display();
  Serial.print("Connecting to " + String(WIFI_SSID));
  
  WiFi.disconnect(true);
  delay(1000);
  WiFi.mode(WIFI_STA);
  WiFi.setAutoReconnect(true);
  WiFi.persistent(true);
  WiFi.begin(WIFI_SSID, WIFI_PASSWORD);

  int attempts = 0;
  while (WiFi.status() != WL_CONNECTED && attempts < 20) {
    delay(500);
    Serial.print(".");
    attempts++;
  }

  if (WiFi.status() == WL_CONNECTED) {
    Serial.println("\nWiFi Connected!");
    display.print(" WiFi: OK\n");
  } else {
    Serial.println("\nWiFi Failed!");
    display.print(" WiFi: FAIL\n");
  }
  display.display();
}

void syncTimeWithNTP() {
  Serial.println("Syncing time with NTP servers...");
  display.print(" Time Sync...\n");
  display.display();
  
  configTime(0, 0, "asia.pool.ntp.org", "in.pool.ntp.org");
  
  time_t now = time(nullptr);
  int retries = 0;
  while (now < 1672531200 && retries < 20) {
      delay(500);
      Serial.print(".");
      now = time(nullptr);
      retries++;
  }

  if (retries < 20) {
      Serial.println("\nTime successfully synced");
      display.print(" Time Sync: OK\n");
  } else {
      Serial.println("\nFailed to obtain time");
      display.print(" Time Sync: FAIL\n");
  }
  display.display();
}

void setupFirebase() {
  Serial.println("Configuring Firebase for Firestore...");
  
  config.api_key = API_KEY;
  
  auth.user.email = USER_EMAIL;
  auth.user.password = USER_PASSWORD;
  
  config.timeout.serverResponse = 10 * 1000;
  
  Firebase.reconnectNetwork(true);
  fbdo.setResponseSize(2048);
  
  Serial.println("Initializing Firebase...");
  Firebase.begin(&config, &auth);
}

// -----------------------------------------------------------------
// 9. FIRESTORE DATABASE FUNCTION
// -----------------------------------------------------------------

void sendDataToFirestore() {
  if (!Firebase.ready() || WiFi.status() != WL_CONNECTED) {
    Serial.println("Firebase not ready or WiFi disconnected. Skipping update.");
    firebaseReady = false;
    return;
  }

  if (ESP.getFreeHeap() < MIN_FREE_HEAP) {
    Serial.println("!!! WARNING: Low memory. Skipping Firebase update to prevent SSL failure.");
    return;
  }

  String documentPath = "devices/" + deviceId;
  FirebaseJson content;
  
  time_t now = time(nullptr);
  char timeStr[30];
  strftime(timeStr, sizeof(timeStr), "%Y-%m-%dT%H:%M:%SZ", gmtime(&now));
  
  content.set("fields/aura_score/integerValue", String(auraRiskScore));
  content.set("fields/temperature/doubleValue", String(temperatureC));
  content.set("fields/humidity/doubleValue", String(humidity));
  content.set("fields/uv_index/doubleValue", String(uvIndex));
  content.set("fields/air_quality_ppm/doubleValue", String(airQualityPPM));
  content.set("fields/timestamp/timestampValue", timeStr);
  
  content.set("fields/accelerometer/mapValue/fields/x/doubleValue", String(accelX));
  content.set("fields/accelerometer/mapValue/fields/y/doubleValue", String(accelY));
  content.set("fields/accelerometer/mapValue/fields/z/doubleValue", String(accelZ));

  if (gpsLat != 0.0 && gpsLng != 0.0) {
    content.set("fields/location/geoPointValue/latitude", String(gpsLat));
    content.set("fields/location/geoPointValue/longitude", String(gpsLng));
    content.set("fields/satellites/integerValue", String(gpsSatellites));
  }
  
  if (Firebase.Firestore.patchDocument(&fbdo, FIREBASE_PROJECT_ID, "", documentPath.c_str(), content.raw(), "")) {
    firebaseReady = true;
  } else {
    Serial.println("<-- Main document update failed: " + fbdo.errorReason());
    firebaseReady = false;
    return;
  }

  String historyDocumentId = String(now);
  String historyPath = "devices/" + deviceId + "/history/" + historyDocumentId;
  FirebaseJson historyContent;

  historyContent.set("fields/aura_score/integerValue", String(auraRiskScore));
  historyContent.set("fields/timestamp/timestampValue", timeStr);

  if (gpsLat != 0.0 && gpsLng != 0.0) {
    historyContent.set("fields/location/geoPointValue/latitude", String(gpsLat));
    historyContent.set("fields/location/geoPointValue/longitude", String(gpsLng));
  }

  Serial.println("--> Adding new history document: " + historyPath);
  if (!Firebase.Firestore.patchDocument(&fbdo, FIREBASE_PROJECT_ID, "", historyPath.c_str(), historyContent.raw(), "")) {
    Serial.println("<-- History document creation failed: " + fbdo.errorReason());
  }
}


// -----------------------------------------------------------------
// 10. SENSOR FUNCTIONS
// -----------------------------------------------------------------

void readMyosaSensors() {
  accelX = accel.getAccelX(false);
  accelY = accel.getAccelY(false);
  accelZ = accel.getAccelZ(false);
}

void readStandardSensors() {
  temperatureC = dht.readTemperature();
  humidity = dht.readHumidity();
  
  if (isnan(temperatureC) || isnan(humidity)) {
    Serial.println("Failed to read from DHT sensor!");
    return;
  }

  int uv_analog = analogRead(GUVA_PIN);
  float uv_voltage = uv_analog * (3.3 / 4095.0);
  uvIndex = uv_voltage / 0.1;

  float ppm_reading = mq135_sensor.getPPM();
  if (ppm_reading > 0 && ppm_reading < 10000) {
    airQualityPPM = ppm_reading;
  } else {
    Serial.println("Invalid MQ135 reading. Using default PPM value.");
    airQualityPPM = 400;
  }
}

void readGPS() {
  while (Serial2.available() > 0) {
    gps.encode(Serial2.read());
  }
  
  if (gps.location.isUpdated() && gps.location.isValid()) {
    gpsLat = gps.location.lat();
    gpsLng = gps.location.lng();
  }
  if (gps.satellites.isUpdated() && gps.satellites.isValid()) {
    gpsSatellites = gps.satellites.value();
  }
}

// -----------------------------------------------------------------
// 11. UTILITY FUNCTIONS
// -----------------------------------------------------------------

int calculateRiskScore(float ppm, float uv, float hum, float temp) {
  int air_score;

  if (ppm <= 1000) {
    air_score = map(constrain(ppm, 400, 1000), 400, 1000, 100, 75);
  } else if (ppm <= 2000) {
    air_score = map(ppm, 1001, 2000, 74, 50);
  } else if (ppm <= 5000) {
    air_score = map(ppm, 2001, 5000, 49, 0);
  } else {
    air_score = 0;
  }
  
  int uv_score = map(constrain(uv, 0, 11), 0, 11, 100, 0);
  
  float heat_humidity_factor = 1.0;
  if (hum > 75 && temp > 30) {
    heat_humidity_factor = 0.8; 
  }
  
  float total_score = (air_score * 0.6) + (uv_score * 0.4);
  total_score *= heat_humidity_factor;
  
  return constrain((int)total_score, 0, 100);
}

void updateOLED() {
  display.clearDisplay();
  display.setTextSize(2);
  display.setCursor(0, 0);
  display.print("AURA: ");
  display.print(auraRiskScore);
  display.drawLine(0, 18, SCREEN_WIDTH, 18, SSD1306_WHITE);

  display.setTextSize(1);
  display.setCursor(0, 22);

  switch(displayPage) {
    case 0:
      display.print("PPM: ");
      display.print(airQualityPPM, 0);
      display.print(" UV: ");
      display.println(uvIndex, 1);
      break;
    case 1:
      display.print("Temp: ");
      display.print(temperatureC, 1);
      display.println("C");
      display.print("Humidity: ");
      display.print((int)humidity);
      display.println("%");
      display.print("Sats: ");
      display.println(gpsSatellites);
      break;
    case 2:
      display.println("Motion (Accel X,Y,Z)");
      display.print("X: ");
      display.println(accelX, 2);
      display.print("Y: ");
      display.println(accelY, 2);
      display.print("Z: ");
      display.println(accelZ, 2);
      break;
  }
  
  display.setCursor(80, 56);
  if (WiFi.status() == WL_CONNECTED && firebaseReady) {
    display.print("FSTORE:OK");
  } else if (WiFi.status() == WL_CONNECTED) {
    display.print("WIFI:OK");
  } else {
    display.print("OFFLINE");
  }
  display.display();
}

void printToSerial() {
  Serial.println("\n--- AURA DATA ---");
  Serial.print("Risk Score: "); Serial.println(auraRiskScore);
  Serial.print("Air Quality (PPM): "); Serial.println(airQualityPPM);
  Serial.print("WiFi RSSI: "); Serial.println(WiFi.RSSI());
  Serial.print("Free Heap: "); Serial.println(ESP.getFreeHeap());
  Serial.println("--------------------");
}
