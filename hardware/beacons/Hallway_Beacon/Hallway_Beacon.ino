#include <BLEDevice.h>
#include <BLEAdvertising.h>

#define BEACON_NAME "Hallway-Beacon"

void setup() {
  Serial.begin(115200);
  BLEDevice::init(BEACON_NAME);
  BLEAdvertising *pAdvertising = BLEDevice::getAdvertising();
  pAdvertising->setScanResponse(true);
  pAdvertising->setMinPreferred(0x06);
  BLEDevice::startAdvertising();
  Serial.println("Advertising started as: " + String(BEACON_NAME));
}

void loop() {
  delay(5000);
}
