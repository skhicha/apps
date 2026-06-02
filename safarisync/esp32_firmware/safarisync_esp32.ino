// =============================================================================
// SafariSync ESP32 Motor Controller — HTTP Web Server
// Controls two DC motors via TB6612/L298N driver over local WiFi.
// Web Admin sends GET requests → ESP32 moves motors in real time.
//
// ⚡ FLASH INSTRUCTIONS:
//   1. Open this file in Arduino IDE
//   2. Fill in YOUR_WIFI_NAME and YOUR_WIFI_PASSWORD below
//   3. Set Board → ESP32 Dev Module (or WROOM-32)
//   4. Upload at 115200 baud
//   5. Open Serial Monitor → note the IP address printed
//   6. Enter that IP in the SafariSync Web Admin → Vehicle Control tab
// =============================================================================

#include <WiFi.h>
#include <WebServer.h>

// ─── WiFi Credentials ────────────────────────────────────────────────────────
const char* ssid     = "YOUR_WIFI_NAME";
const char* password = "YOUR_WIFI_PASSWORD";

// ─── HTTP Server on port 80 ──────────────────────────────────────────────────
WebServer server(80);

// ─── Motor Pins (matches your existing wiring) ───────────────────────────────
#define PWMA  25    // Motor A speed (PWM)
#define AIN1  27    // Motor A direction pin 1
#define AIN2  26    // Motor A direction pin 2

#define PWMB  14    // Motor B speed (PWM)
#define BIN1  13    // Motor B direction pin 1
#define BIN2  12    // Motor B direction pin 2

#define STBY  33    // Motor driver standby (HIGH = active)

// ─── PWM Configuration ───────────────────────────────────────────────────────
#define PWM_FREQ   1000   // 1 kHz PWM frequency
#define PWM_RES    8      // 8-bit resolution → values 0–255
#define CH_A       0      // LEDC channel for Motor A
#define CH_B       1      // LEDC channel for Motor B

// ─── Runtime State ───────────────────────────────────────────────────────────
int    currentSpeedPWM = 180;   // 0–255, default ~70% duty cycle
String currentMode     = "stopped";
String currentDir      = "none";

// ─────────────────────────────────────────────────────────────────────────────
// CORS HELPERS — required so browser can call ESP32 from a different origin
// ─────────────────────────────────────────────────────────────────────────────
void addCORSHeaders() {
  server.sendHeader("Access-Control-Allow-Origin",  "*");
  server.sendHeader("Access-Control-Allow-Methods", "GET, OPTIONS");
  server.sendHeader("Access-Control-Allow-Headers", "Content-Type, Origin");
  server.sendHeader("Cache-Control",                "no-cache");
}

void sendOK(const String& body) {
  addCORSHeaders();
  server.send(200, "text/plain", body);
}

void handlePreflight() {   // OPTIONS preflight for CORS
  addCORSHeaders();
  server.send(204, "text/plain", "");
}

// ─────────────────────────────────────────────────────────────────────────────
// /status  →  JSON telemetry for the web app to display
// ─────────────────────────────────────────────────────────────────────────────
void handleStatus() {
  addCORSHeaders();
  int speedPct = map(currentSpeedPWM, 0, 255, 0, 100);
  String json = "{";
  json += "\"mode\":\""      + currentMode + "\",";
  json += "\"direction\":\"" + currentDir  + "\",";
  json += "\"speed\":"       + String(speedPct) + ",";
  json += "\"ip\":\""        + WiFi.localIP().toString() + "\",";
  json += "\"wifi_rssi\":"   + String(WiFi.RSSI()) + ",";
  json += "\"uptime_s\":"    + String(millis() / 1000);
  json += "}";
  server.send(200, "application/json", json);
}

// ─────────────────────────────────────────────────────────────────────────────
// Root page — a minimal HTML remote (useful for quick testing without the app)
// ─────────────────────────────────────────────────────────────────────────────
void handleRoot() {
  addCORSHeaders();
  String html = R"(<!DOCTYPE html>
<html><head><meta charset='UTF-8'><title>SafariSync ESP32</title>
<style>
  body{background:#0B1810;color:#E8F5EB;font-family:sans-serif;text-align:center;padding:20px;}
  h1{color:#6EDB75;}
  button{background:#162A1C;color:#6EDB75;border:1px solid #4BB855;padding:14px 28px;
         font-size:16px;border-radius:10px;cursor:pointer;margin:6px;}
  button:hover{background:#1D3820;}
  .stop{color:#F5A623;border-color:#F5A623;}
  .estop{color:#E84040;border-color:#E84040;font-weight:900;}
  #status{margin-top:20px;font-family:monospace;color:#7A9E82;font-size:12px;}
</style></head>
<body>
  <h1>🌿 SafariSync Motor Controller</h1>
  <p style='color:#7A9E82'>IP: )";
  html += WiFi.localIP().toString();
  html += R"( &nbsp;|&nbsp; Mode: <span id='m'>)" + currentMode + R"(</span></p>
  <div>
    <button onclick="cmd('forward')">▲ FORWARD</button>
  </div>
  <div>
    <button onclick="cmd('left')">◄ LEFT</button>
    <button class='stop' onclick="cmd('stop')">■ STOP</button>
    <button onclick="cmd('right')">RIGHT ►</button>
  </div>
  <div>
    <button onclick="cmd('back')">▼ BACK</button>
  </div>
  <div style='margin-top:16px'>
    <button class='estop' onclick="cmd('estop')">🆘 EMERGENCY STOP</button>
  </div>
  <div id='status'></div>
  <script>
    async function cmd(ep) {
      try {
        const r = await fetch('/'+ep);
        const t = await r.text();
        document.getElementById('status').textContent = '→ ' + t;
      } catch(e) { document.getElementById('status').textContent = '✗ Error: '+e; }
    }
  </script>
</body></html>)";
  server.send(200, "text/html", html);
}

// ─────────────────────────────────────────────────────────────────────────────
// Speed helper — reads optional ?speed=XX query param (0–100 %)
// Returns PWM value (0–255), falls back to currentSpeedPWM if no param given
// ─────────────────────────────────────────────────────────────────────────────
int getSpeedFromParam() {
  if (server.hasArg("speed")) {
    int pct = constrain(server.arg("speed").toInt(), 0, 100);
    return map(pct, 0, 100, 0, 255);
  }
  return currentSpeedPWM;
}

// ─────────────────────────────────────────────────────────────────────────────
// MOTOR FUNCTIONS (low-level)
// ─────────────────────────────────────────────────────────────────────────────
void motorDrive(int speedA, bool fwdA, int speedB, bool fwdB) {
  digitalWrite(STBY, HIGH);
  ledcWrite(CH_A, speedA);
  ledcWrite(CH_B, speedB);
  digitalWrite(AIN1, fwdA ? HIGH : LOW);
  digitalWrite(AIN2, fwdA ? LOW  : HIGH);
  digitalWrite(BIN1, fwdB ? HIGH : LOW);
  digitalWrite(BIN2, fwdB ? LOW  : HIGH);
}

void forward(int spd) {
  motorDrive(spd, true,  spd, true);
}

void backward(int spd) {
  motorDrive(spd, false, spd, false);
}

void turnLeft(int spd) {
  // Left motor slows/reverses, right motor full forward → pivots left
  motorDrive(spd / 3, false, spd, true);
}

void turnRight(int spd) {
  // Right motor slows/reverses, left motor full forward → pivots right
  motorDrive(spd, true, spd / 3, false);
}

void stopBot() {
  ledcWrite(CH_A, 0);
  ledcWrite(CH_B, 0);
  digitalWrite(AIN1, LOW); digitalWrite(AIN2, LOW);
  digitalWrite(BIN1, LOW); digitalWrite(BIN2, LOW);
}

void emergencyStop() {
  digitalWrite(STBY, LOW);   // kill motor driver power
  ledcWrite(CH_A, 0);
  ledcWrite(CH_B, 0);
  digitalWrite(AIN1, LOW); digitalWrite(AIN2, LOW);
  digitalWrite(BIN1, LOW); digitalWrite(BIN2, LOW);
  delay(80);
  digitalWrite(STBY, HIGH);  // re-enable so future commands still work
}

// ─────────────────────────────────────────────────────────────────────────────
// SETUP
// ─────────────────────────────────────────────────────────────────────────────
void setup() {
  Serial.begin(115200);
  delay(800);
  Serial.println("\n\n╔══════════════════════════════════════╗");
  Serial.println("║   SafariSync ESP32 Motor Controller  ║");
  Serial.println("╚══════════════════════════════════════╝");

  // ── Motor driver GPIO setup ──
  pinMode(AIN1, OUTPUT); pinMode(AIN2, OUTPUT);
  pinMode(BIN1, OUTPUT); pinMode(BIN2, OUTPUT);
  pinMode(STBY, OUTPUT);
  digitalWrite(STBY, HIGH);   // driver active

  // ── PWM channels (LEDC) ──
  ledcSetup(CH_A, PWM_FREQ, PWM_RES);
  ledcSetup(CH_B, PWM_FREQ, PWM_RES);
  ledcAttachPin(PWMA, CH_A);
  ledcAttachPin(PWMB, CH_B);
  ledcWrite(CH_A, 0);
  ledcWrite(CH_B, 0);

  // ── WiFi ──
  Serial.printf("Connecting to WiFi: %s\n", ssid);
  WiFi.begin(ssid, password);
  int attempts = 0;
  while (WiFi.status() != WL_CONNECTED) {
    delay(500);
    Serial.print(".");
    if (++attempts > 40) {
      Serial.println("\n⚠ WiFi timeout — restarting…");
      ESP.restart();
    }
  }
  Serial.println("\n✅ WiFi Connected!");
  Serial.printf("🌐 ESP32 IP Address: %s\n", WiFi.localIP().toString().c_str());
  Serial.println("📋 Enter this IP in SafariSync Web Admin → Vehicle Control → ESP32 WiFi");
  Serial.println("──────────────────────────────────────────");

  // ── HTTP Routes ──

  // Preflight (OPTIONS) for every route
  server.on("/",        HTTP_OPTIONS, handlePreflight);
  server.on("/status",  HTTP_OPTIONS, handlePreflight);
  server.on("/forward", HTTP_OPTIONS, handlePreflight);
  server.on("/back",    HTTP_OPTIONS, handlePreflight);
  server.on("/left",    HTTP_OPTIONS, handlePreflight);
  server.on("/right",   HTTP_OPTIONS, handlePreflight);
  server.on("/stop",    HTTP_OPTIONS, handlePreflight);
  server.on("/estop",   HTTP_OPTIONS, handlePreflight);
  server.on("/speed",   HTTP_OPTIONS, handlePreflight);

  // Root + status
  server.on("/",        HTTP_GET, handleRoot);
  server.on("/status",  HTTP_GET, handleStatus);

  // Movement commands
  server.on("/forward", HTTP_GET, []() {
    int spd = getSpeedFromParam();
    forward(spd);
    currentDir = "forward"; currentMode = "manual";
    Serial.printf("▲ FORWARD  spd=%d\n", spd);
    sendOK("forward");
  });

  server.on("/back", HTTP_GET, []() {
    int spd = getSpeedFromParam();
    backward(spd);
    currentDir = "backward"; currentMode = "manual";
    Serial.printf("▼ BACKWARD spd=%d\n", spd);
    sendOK("backward");
  });

  server.on("/left", HTTP_GET, []() {
    int spd = getSpeedFromParam();
    turnLeft(spd);
    currentDir = "left"; currentMode = "manual";
    Serial.printf("◄ LEFT     spd=%d\n", spd);
    sendOK("left");
  });

  server.on("/right", HTTP_GET, []() {
    int spd = getSpeedFromParam();
    turnRight(spd);
    currentDir = "right"; currentMode = "manual";
    Serial.printf("► RIGHT    spd=%d\n", spd);
    sendOK("right");
  });

  server.on("/stop", HTTP_GET, []() {
    stopBot();
    currentDir = "none"; currentMode = "stopped";
    Serial.println("■ STOP");
    sendOK("stop");
  });

  server.on("/estop", HTTP_GET, []() {
    emergencyStop();
    currentDir = "none"; currentMode = "emergency_stop";
    Serial.println("🆘 EMERGENCY STOP");
    sendOK("emergency_stop");
  });

  server.on("/speed", HTTP_GET, []() {
    if (server.hasArg("v")) {
      int pct = constrain(server.arg("v").toInt(), 0, 100);
      currentSpeedPWM = map(pct, 0, 100, 0, 255);
      Serial.printf("⚡ SPEED → %d%% (PWM=%d)\n", pct, currentSpeedPWM);
    }
    sendOK("speed=" + String(map(currentSpeedPWM, 0, 255, 0, 100)));
  });

  server.onNotFound([]() {
    addCORSHeaders();
    server.send(404, "text/plain", "Not found — SafariSync ESP32");
  });

  server.begin();
  Serial.println("🚀 HTTP Server started on port 80");
  Serial.println("══════════════════════════════════════════");
  Serial.println("  Endpoints:");
  Serial.println("  GET /forward?speed=70");
  Serial.println("  GET /back?speed=70");
  Serial.println("  GET /left?speed=70");
  Serial.println("  GET /right?speed=70");
  Serial.println("  GET /stop");
  Serial.println("  GET /estop");
  Serial.println("  GET /speed?v=70  (set global speed %)");
  Serial.println("  GET /status      (JSON telemetry)");
  Serial.println("══════════════════════════════════════════\n");
}

// ─────────────────────────────────────────────────────────────────────────────
// LOOP — just handle incoming HTTP clients
// ─────────────────────────────────────────────────────────────────────────────
void loop() {
  server.handleClient();

  // ── Optional safety: auto-stop if WiFi drops ──
  static unsigned long lastWifiCheck = 0;
  if (millis() - lastWifiCheck > 5000) {
    lastWifiCheck = millis();
    if (WiFi.status() != WL_CONNECTED) {
      Serial.println("⚠ WiFi lost — reconnecting…");
      stopBot();
      currentMode = "stopped";
      WiFi.reconnect();
    }
  }
}
