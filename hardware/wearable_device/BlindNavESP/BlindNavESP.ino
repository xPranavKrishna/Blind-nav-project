#include <BLEDevice.h>
#include <BLEServer.h>
#include <BLEUtils.h>
#include <BLE2902.h>

// -------- BLE DETAILS --------
#define SERVICE_UUID "4fafc201-1fb5-459e-8fcc-c5c9c331914b"
#define DISTANCE_UUID "beb5483e-36e1-4688-b7f5-ea07361b26a8"
#define DETECTED_UUID "1c95d5e3-d8f7-413a-bf3d-7d3d14a81bf0"
#define TIMESTAMP_UUID "d8f7125f-b267-4e20-bee0-1a951a1ac307"

// -------- PIN DEFINITIONS --------
#define TRIG_PIN 5
#define ECHO_PIN 18
#define BUZZER_PIN 23

// -------- CONSTANTS --------
#define MAX_VALID_DISTANCE 200   // cm
#define OBSTACLE_THRESHOLD 60    // cm

BLEServer *pServer = NULL;
BLECharacteristic *pDistanceChar = NULL;
BLECharacteristic *pDetectedChar = NULL;
BLECharacteristic *pTimestampChar = NULL;

bool deviceConnected = false;

class MyServerCallbacks: public BLEServerCallbacks {
  void onConnect(BLEServer* pServer) {
    deviceConnected = true;
    Serial.println("Device connected");
  };
  void onDisconnect(BLEServer* pServer) {
    deviceConnected = false;
    Serial.println("Device disconnected");
    delay(500);
    pServer->startAdvertising();
    Serial.println("Advertising restarted");
  }
};

long duration;
int distance;

void setup() {
  Serial.begin(115200);

  pinMode(TRIG_PIN, OUTPUT);
  pinMode(ECHO_PIN, INPUT);
  pinMode(BUZZER_PIN, OUTPUT);

  // Initialize BLE
  BLEDevice::init("BlindNavESP");
  pServer = BLEDevice::createServer();
  pServer->setCallbacks(new MyServerCallbacks());

  BLEService *pService = pServer->createService(SERVICE_UUID);

  pDistanceChar = pService->createCharacteristic(DISTANCE_UUID, BLECharacteristic::PROPERTY_NOTIFY | BLECharacteristic::PROPERTY_READ);
  pDetectedChar = pService->createCharacteristic(DETECTED_UUID, BLECharacteristic::PROPERTY_NOTIFY | BLECharacteristic::PROPERTY_READ);
  pTimestampChar = pService->createCharacteristic(TIMESTAMP_UUID, BLECharacteristic::PROPERTY_NOTIFY | BLECharacteristic::PROPERTY_READ);

  pDistanceChar->addDescriptor(new BLE2902());
  pDetectedChar->addDescriptor(new BLE2902());
  pTimestampChar->addDescriptor(new BLE2902());

  pService->start();

  // Security
  BLESecurity *pSecurity = new BLESecurity();
  pSecurity->setAuthenticationMode(ESP_LE_AUTH_REQ_SC_BOND);
  pSecurity->setCapability(ESP_IO_CAP_NONE);

  // Start Advertising
  BLEAdvertising *pAdvertising = BLEDevice::getAdvertising();
  pAdvertising->addServiceUUID(SERVICE_UUID);
  pAdvertising->setScanResponse(false);
  pAdvertising->setMinPreferred(0x06);
  BLEDevice::startAdvertising();

  Serial.println("BLE advertising started - BlindNavESP Ready");
}

void loop() {
  // Ultrasonic Sensor Reading
  digitalWrite(TRIG_PIN, LOW);
  delayMicroseconds(2);
  digitalWrite(TRIG_PIN, HIGH);
  delayMicroseconds(10);
  digitalWrite(TRIG_PIN, LOW);

  duration = pulseIn(ECHO_PIN, HIGH, 60000);
  distance = (duration * 0.034) / 2;

  Serial.print("Distance: ");
  Serial.print(distance);
  Serial.println(" cm");

  bool obstacleDetected = false;
  int sendDistance = distance;

  if (distance <= 0 || distance > MAX_VALID_DISTANCE) {
    sendDistance = -1;
    obstacleDetected = false;
    digitalWrite(BUZZER_PIN, LOW);
  } else if (distance <= OBSTACLE_THRESHOLD) {
    obstacleDetected = true;
    digitalWrite(BUZZER_PIN, HIGH);
  } else {
    digitalWrite(BUZZER_PIN, LOW);
  }

  // Send data to App via BLE
  if (deviceConnected) {
    uint8_t distanceData[4];
    memcpy(distanceData, &sendDistance, 4);
    pDistanceChar->setValue(distanceData, 4);
    pDistanceChar->notify();

    uint8_t timestampData[4];
    int timestamp = (int)millis();
    memcpy(timestampData, &timestamp, 4);
    pTimestampChar->setValue(timestampData, 4);
    pTimestampChar->notify();

    uint8_t detectedData[1];
    detectedData[0] = obstacleDetected ? 1 : 0;
    pDetectedChar->setValue(detectedData, 1);
    pDetectedChar->notify();

    Serial.println("Data notified to app");
  }

  delay(300);
}
