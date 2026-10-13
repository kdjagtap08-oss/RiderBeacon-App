/*
 * SmartKavach — ESP32 + MPU6050 Helmet Unit Firmware
 * 
 * Hardware Wiring:
 *   ESP32 3V3  --> MPU6050 VCC
 *   ESP32 GND  --> MPU6050 GND
 *   ESP32 G21  --> MPU6050 SDA (I2C Data)
 *   ESP32 G22  --> MPU6050 SCL (I2C Clock)
 *   MPU6050 AD0 -> GND (Sets I2C address to 0x68)
 * 
 * BLE Specifications:
 *   Device Name: "SmartKavach Helmet"
 *   Service UUID:        4fafc201-1fb5-459e-8fcc-c5c9c331914b
 *   Characteristic UUID: beb5483e-36e1-4688-b7f5-ea07361b26a8 (NOTIFY)
 *   Packet Format:       ASCII CSV "gx,gy,gz\n" (angular velocity in °/s)
 *   Streaming Frequency: 25 Hz (every 40ms)
 */

#include <Wire.h>
#include <BLEDevice.h>
#include <BLEServer.h>
#include <BLEUtils.h>
#include <BLE2902.h>

// BLE UUID definitions (Must match Flutter app constants)
#define SERVICE_UUID        "4fafc201-1fb5-459e-8fcc-c5c9c331914b"
#define CHARACTERISTIC_UUID "beb5483e-36e1-4688-b7f5-ea07361b26a8"
#define DEVICE_NAME         "SmartKavach Helmet"

// MPU6050 I2C Configuration
#define MPU_ADDR 0x68
#define SDA_PIN  21
#define SCL_PIN  22

// Sampling & Transmission Rates
const unsigned long SAMPLE_INTERVAL_MS = 40; // 25 Hz update rate
unsigned long lastSampleTime = 0;

// BLE Server & Characteristic pointers
BLEServer* pServer = nullptr;
BLECharacteristic* pCharacteristic = nullptr;
bool deviceConnected = false;
bool oldDeviceConnected = false;

// Calibration Offsets (deg/sec)
float gyroOffsetX = 0.0;
float gyroOffsetY = 0.0;
float gyroOffsetZ = 0.0;

// Power saving & inactivity tracking
unsigned long lastMotionTime = 0;
const unsigned long INACTIVITY_SLEEP_MS = 600000; // 10 minutes of complete standstill -> light sleep

// BLE Connection Callbacks
class HelmetServerCallbacks: public BLEServerCallbacks {
    void onConnect(BLEServer* pServer) {
        deviceConnected = true;
        Serial.println("[BLE] Phone connected to helmet unit.");
    };

    void onDisconnect(BLEServer* pServer) {
        deviceConnected = false;
        Serial.println("[BLE] Phone disconnected from helmet unit.");
    }
};

void initMPU6050() {
    Wire.begin(SDA_PIN, SCL_PIN);
    
    // Wake up MPU6050 (default is sleep mode)
    Wire.beginTransmission(MPU_ADDR);
    Wire.write(0x6B); // PWR_MGMT_1 register
    Wire.write(0x00); // Set to 0 to wake up sensor
    Wire.endTransmission(true);

    // Configure Gyroscope Full Scale Range: ±1000 deg/s (FS_SEL = 2)
    // Register 0x1B, Bits [4:3] = 0b10 (0x10)
    Wire.beginTransmission(MPU_ADDR);
    Wire.write(0x1B); // GYRO_CONFIG register
    Wire.write(0x10); // ±1000 °/s (Sensitivity = 32.8 LSB / °/s)
    Wire.endTransmission(true);

    // Configure Low Pass Filter (DLPF_CFG = 3 -> 44Hz bandwidth)
    Wire.beginTransmission(MPU_ADDR);
    Wire.write(0x1A); // CONFIG register
    Wire.write(0x03); 
    Wire.endTransmission(true);

    Serial.println("[MPU] MPU6050 initialized successfully.");
}

void calibrateGyro() {
    Serial.println("[CALIB] Calibrating gyroscope offsets... Keep helmet stationary.");
    const int SAMPLES = 100;
    long sumX = 0, sumY = 0, sumZ = 0;

    for (int i = 0; i < SAMPLES; i++) {
        Wire.beginTransmission(MPU_ADDR);
        Wire.write(0x43); // Start at GYRO_XOUT_H
        Wire.endTransmission(false);
        Wire.requestFrom(MPU_ADDR, 6, true);

        if (Wire.available() >= 6) {
            int16_t rawX = (Wire.read() << 8) | Wire.read();
            int16_t rawY = (Wire.read() << 8) | Wire.read();
            int16_t rawZ = (Wire.read() << 8) | Wire.read();
            sumX += rawX;
            sumY += rawY;
            sumZ += rawZ;
        }
        delay(10);
    }

    // ±1000 °/s scale: 32.8 LSB per °/s
    gyroOffsetX = (sumX / (float)SAMPLES) / 32.8;
    gyroOffsetY = (sumY / (float)SAMPLES) / 32.8;
    gyroOffsetZ = (sumZ / (float)SAMPLES) / 32.8;

    Serial.printf("[CALIB] Offsets -> X: %.2f, Y: %.2f, Z: %.2f °/s\n", 
                  gyroOffsetX, gyroOffsetY, gyroOffsetZ);
}

void readGyro(float &gx, float &gy, float &gz) {
    Wire.beginTransmission(MPU_ADDR);
    Wire.write(0x43); // GYRO_XOUT_H register
    Wire.endTransmission(false);
    Wire.requestFrom(MPU_ADDR, 6, true);

    if (Wire.available() >= 6) {
        int16_t rawX = (Wire.read() << 8) | Wire.read();
        int16_t rawY = (Wire.read() << 8) | Wire.read();
        int16_t rawZ = (Wire.read() << 8) | Wire.read();

        // Convert raw values to °/s and subtract calibrated zero-offset
        gx = (rawX / 32.8) - gyroOffsetX;
        gy = (rawY / 32.8) - gyroOffsetY;
        gz = (rawZ / 32.8) - gyroOffsetZ;
    } else {
        gx = 0.0; gy = 0.0; gz = 0.0;
    }
}

void initBLE() {
    Serial.println("[BLE] Starting BLE GATT Server...");
    BLEDevice::init(DEVICE_NAME);

    pServer = BLEDevice::createServer();
    pServer->setCallbacks(new HelmetServerCallbacks());

    BLEService *pService = pServer->createService(SERVICE_UUID);

    pCharacteristic = pService->createCharacteristic(
        CHARACTERISTIC_UUID,
        BLECharacteristic::PROPERTY_READ   |
        BLECharacteristic::PROPERTY_NOTIFY
    );

    // Client Characteristic Configuration Descriptor (CCCD) required for notify
    pCharacteristic->addDescriptor(new BLE2902());

    pService->start();

    // Start Advertising
    BLEAdvertising *pAdvertising = BLEDevice::getAdvertising();
    pAdvertising->addServiceUUID(SERVICE_UUID);
    pAdvertising->setScanResponse(true);
    pAdvertising->setMinPreferred(0x06); // Helps iPhone & Android connection latency
    pAdvertising->setMinPreferred(0x12);
    BLEDevice::startAdvertising();

    Serial.println("[BLE] Advertising as 'SmartKavach Helmet'. Ready to connect.");
}

void setup() {
    Serial.begin(115200);
    delay(500);

    Serial.println("\n=================================");
    Serial.println("  SmartKavach Helmet Unit v1.0   ");
    Serial.println("=================================");

    initMPU6050();
    calibrateGyro();
    initBLE();

    lastMotionTime = millis();
}

void loop() {
    unsigned long now = millis();

    // Re-advertising handling if phone disconnects
    if (!deviceConnected && oldDeviceConnected) {
        delay(500); // Give the Bluetooth stack a moment
        pServer->startAdvertising();
        Serial.println("[BLE] Disconnected. Restarted advertising.");
        oldDeviceConnected = deviceConnected;
    }
    if (deviceConnected && !oldDeviceConnected) {
        oldDeviceConnected = deviceConnected;
    }

    // Periodic sensor read and BLE notify at 25 Hz
    if (now - lastSampleTime >= SAMPLE_INTERVAL_MS) {
        lastSampleTime = now;

        float gx = 0.0, gy = 0.0, gz = 0.0;
        readGyro(gx, gy, gz);

        // Check motion activity (for power saving)
        float motionMag = abs(gx) + abs(gy) + abs(gz);
        if (motionMag > 15.0) { // Moving
            lastMotionTime = now;
        }

        // Send over BLE if connected
        if (deviceConnected) {
            char buffer[48];
            // Format as standard CSV: "gx,gy,gz" (e.g. "12.4,-3.2,0.5")
            snprintf(buffer, sizeof(buffer), "%.1f,%.1f,%.1f", gx, gy, gz);

            pCharacteristic->setValue(buffer);
            pCharacteristic->notify();
        }

        // Inactivity timeout -> Deep sleep saving helmet battery
        if (now - lastMotionTime > INACTIVITY_SLEEP_MS) {
            Serial.println("[POWER] No motion detected for 10 minutes. Entering light sleep...");
            esp_sleep_enable_timer_wakeup(5000000); // Wake every 5s to check motion
            esp_light_sleep_start();
            lastMotionTime = millis();
        }
    }
}
