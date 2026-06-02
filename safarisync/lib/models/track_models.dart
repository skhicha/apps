// ─────────────────────────────────────────────────────────────────────────────
// SafariSync v3.0 — New Models & Track Data
// ─────────────────────────────────────────────────────────────────────────────
import 'dart:math';

// ─────────────────────────────────────────────────────────────────────────────
// AQI DATA MODEL
// Data from AQI sensor module on the ESP32 rover
// ─────────────────────────────────────────────────────────────────────────────
class AqiData {
  final double temperature;  // °C
  final double humidity;     // %
  final int aqiIndex;        // 0-500 AQI scale
  final double pm25;         // µg/m³
  final double co2;          // ppm
  final String status;       // "Good" | "Moderate" | "Unhealthy" etc.
  final DateTime timestamp;

  AqiData({
    required this.temperature,
    required this.humidity,
    required this.aqiIndex,
    required this.pm25,
    required this.co2,
    required this.status,
    required this.timestamp,
  });

  factory AqiData.simulated() {
    final rng = Random();
    final temp = 28.0 + rng.nextDouble() * 12;
    final hum = 45.0 + rng.nextDouble() * 35;
    final aqi = 20 + rng.nextInt(80);
    return AqiData(
      temperature: temp,
      humidity: hum,
      aqiIndex: aqi,
      pm25: 5.0 + rng.nextDouble() * 30,
      co2: 400.0 + rng.nextDouble() * 200,
      status: _aqiStatus(aqi),
      timestamp: DateTime.now(),
    );
  }

  factory AqiData.fromMap(Map<dynamic, dynamic> d) {
    final aqi = (d['aqi_index'] as num?)?.toInt() ?? 50;
    return AqiData(
      temperature: (d['temperature'] as num?)?.toDouble() ?? 30.0,
      humidity: (d['humidity'] as num?)?.toDouble() ?? 60.0,
      aqiIndex: aqi,
      pm25: (d['pm25'] as num?)?.toDouble() ?? 10.0,
      co2: (d['co2'] as num?)?.toDouble() ?? 420.0,
      status: (d['status'] as String?) ?? _aqiStatus(aqi),
      timestamp: DateTime.now(),
    );
  }

  static String _aqiStatus(int idx) {
    if (idx <= 50) return 'Good';
    if (idx <= 100) return 'Moderate';
    if (idx <= 150) return 'Sensitive Groups';
    if (idx <= 200) return 'Unhealthy';
    if (idx <= 300) return 'Very Unhealthy';
    return 'Hazardous';
  }

  String get aqiColor => _aqiColorHex(aqiIndex);
  static String _aqiColorHex(int idx) {
    if (idx <= 50) return '#6EDB75';
    if (idx <= 100) return '#F5D042';
    if (idx <= 150) return '#F5A623';
    if (idx <= 200) return '#E84040';
    if (idx <= 300) return '#9B7FEF';
    return '#7E0023';
  }

  String get weatherDescription {
    if (temperature > 40) return 'Extreme Heat';
    if (temperature > 35) return 'Hot & Sunny';
    if (temperature > 28) return 'Warm & Clear';
    if (temperature > 22) return 'Pleasant';
    return 'Cool';
  }

  String get weatherEmoji {
    if (humidity > 80 && temperature > 30) return '⛈';
    if (humidity > 70) return '🌦';
    if (temperature > 38) return '🔥';
    if (temperature > 30) return '☀️';
    if (temperature > 22) return '🌤';
    return '🌙';
  }

  String get forecastText {
    if (humidity > 80 && temperature > 30) return 'Possible thunderstorms in 2–3 hrs';
    if (humidity > 70) return 'Partly cloudy, light rain possible';
    if (humidity < 30 && temperature > 35) return 'Dry, hot conditions through evening';
    if (temperature > 32) return 'Clear and hot throughout the day';
    return 'Clear skies expected all day';
  }

  AqiData copyWithSimStep(Random rng) => AqiData(
    temperature: (temperature + (rng.nextDouble() - 0.5) * 0.4).clamp(20, 48),
    humidity: (humidity + (rng.nextDouble() - 0.5) * 1.0).clamp(20, 100),
    aqiIndex: (aqiIndex + rng.nextInt(5) - 2).clamp(0, 300),
    pm25: (pm25 + (rng.nextDouble() - 0.5) * 1.2).clamp(0, 150),
    co2: (co2 + (rng.nextDouble() - 0.5) * 10).clamp(380, 1000),
    status: _aqiStatus(aqiIndex),
    timestamp: DateTime.now(),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// RFID EVENT MODEL
// Triggered when vehicle passes a checkpoint reader
// ─────────────────────────────────────────────────────────────────────────────
class RfidEvent {
  final String tagId;
  final String checkpointName;
  final String checkpointId;
  final DateTime timestamp;
  final int lapNumber;
  final int? lapTimeMs;

  RfidEvent({
    required this.tagId,
    required this.checkpointName,
    required this.checkpointId,
    required this.timestamp,
    required this.lapNumber,
    this.lapTimeMs,
  });

  factory RfidEvent.fromMap(Map<dynamic, dynamic> d, int lap) => RfidEvent(
        tagId: (d['last_tag'] as String?) ?? 'UNKNOWN',
        checkpointName: (d['checkpoint'] as String?) ?? 'CP0',
        checkpointId: (d['checkpoint'] as String?) ?? 'CP0',
        timestamp: DateTime.now(),
        lapNumber: lap,
        lapTimeMs: (d['last_lap_ms'] as num?)?.toInt(),
      );

  String get formattedLapTime {
    if (lapTimeMs == null) return '--';
    final s = lapTimeMs! ~/ 1000;
    final ms = lapTimeMs! % 1000;
    return '${s.toString().padLeft(2, '0')}.${ms.toString().padLeft(3, '0')}s';
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// DETECTED OBJECT MODEL
// From ESP32-CAM vision system (YOLO/TFLite on edge)
// ─────────────────────────────────────────────────────────────────────────────
class DetectedObject {
  final String id;
  final String label;
  final double confidence;
  final DateTime timestamp;
  final double? trackX;
  final double? trackY;
  final String emoji;

  DetectedObject({
    required this.id,
    required this.label,
    required this.confidence,
    required this.timestamp,
    this.trackX,
    this.trackY,
    String? emoji,
  }) : emoji = emoji ?? _emojiFor(label);

  factory DetectedObject.fromMap(Map<dynamic, dynamic> d) {
    final label = (d['label'] as String?) ?? 'Unknown';
    return DetectedObject(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      label: label,
      confidence: (d['confidence'] as num?)?.toDouble() ?? 0.8,
      timestamp: DateTime.now(),
      trackX: (d['x'] as num?)?.toDouble(),
      trackY: (d['y'] as num?)?.toDouble(),
    );
  }

  static String _emojiFor(String label) {
    final l = label.toLowerCase();
    if (l.contains('camel')) return '🐪';
    if (l.contains('tiger')) return '🐅';
    if (l.contains('lion')) return '🦁';
    if (l.contains('bull')) return '🐂';
    if (l.contains('polar bear') || l.contains('bear')) return '🐻‍❄️';
    if (l.contains('giraffe')) return '🦒';
    if (l.contains('elephant')) return '🐘';
    if (l.contains('zebra')) return '🦓';
    if (l.contains('rhino')) return '🦏';
    if (l.contains('hippo')) return '🦛';
    if (l.contains('leopard') || l.contains('cheetah')) return '🐆';
    if (l.contains('buffalo')) return '🐃';
    if (l.contains('deer')) return '🦌';
    if (l.contains('bird') || l.contains('parrot') || l.contains('toucan')) return '🦜';
    if (l.contains('person') || l.contains('human')) return '👤';
    return '🐾';
  }

  String get confidenceLabel {
    if (confidence >= 0.90) return 'HIGH';
    if (confidence >= 0.70) return 'MED';
    return 'LOW';
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// TRACK VEHICLE STATE
// Real-time position and status of the line-follower car
// ─────────────────────────────────────────────────────────────────────────────
class TrackVehicleState {
  final double x;          // 0.0-1.0 normalized on track canvas
  final double y;          // 0.0-1.0 normalized
  final int pathIndex;     // current segment index on track path
  final double pathProgress; // 0.0-1.0 within segment
  final String segmentId;
  final bool onTrack;
  final double speed;      // 0-100 %
  final int battery;       // 0-100 %
  final String mode;       // autonomous | manual | stopped | brake
  final int irLeft;        // 0 = off line, 1 = on line
  final int irCenter;
  final int irRight;
  final double deviationMm;
  final double lap;
  final int elapsedMs;

  TrackVehicleState({
    required this.x,
    required this.y,
    this.pathIndex = 0,
    this.pathProgress = 0.0,
    this.segmentId = 'START',
    this.onTrack = true,
    this.speed = 0,
    this.battery = 100,
    this.mode = 'stopped',
    this.irLeft = 0,
    this.irCenter = 1,
    this.irRight = 0,
    this.deviationMm = 0,
    this.lap = 0,
    this.elapsedMs = 0,
  });

  factory TrackVehicleState.initial() => TrackVehicleState(
        x: LineFollowerTrack.path[0][0],
        y: LineFollowerTrack.path[0][1],
      );

  factory TrackVehicleState.fromMap(Map<dynamic, dynamic> d) {
    final pos = d['position'] as Map? ?? {};
    final status = d['status'] as Map? ?? {};
    final sensors = d['sensors'] as Map? ?? {};
    return TrackVehicleState(
      x: (pos['x'] as num?)?.toDouble() ?? LineFollowerTrack.path[0][0],
      y: (pos['y'] as num?)?.toDouble() ?? LineFollowerTrack.path[0][1],
      pathIndex: (pos['pathIndex'] as num?)?.toInt() ?? 0,
      pathProgress: (pos['pathProgress'] as num?)?.toDouble() ?? 0.0,
      segmentId: (pos['segmentId'] as String?) ?? 'START',
      onTrack: (sensors['on_track'] as bool?) ?? true,
      speed: (status['speed'] as num?)?.toDouble() ?? 0.0,
      battery: (status['battery'] as num?)?.toInt() ?? 100,
      mode: (status['mode'] as String?) ?? 'stopped',
      irLeft: (sensors['ir_left'] as num?)?.toInt() ?? 0,
      irCenter: (sensors['ir_center'] as num?)?.toInt() ?? 1,
      irRight: (sensors['ir_right'] as num?)?.toInt() ?? 0,
      deviationMm: (sensors['deviation_mm'] as num?)?.toDouble() ?? 0,
      elapsedMs: (d['elapsed_ms'] as num?)?.toInt() ?? 0,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// LINE FOLLOWER TRACK PATH
//
// Pixel-accurate coordinates traced from the 1277×819 hackathon image.
// All coordinates are normalized: x/1277, y/819.
//
// Path: P39 (start) → P40 → … → P93 (end), indices 0–54.
// Dashed return segment closes the loop: P93 → P39, indices 54–58.
// START marker = P39 = index 0   (left side of dashed bridge)
// END   marker = P93 = index 54  (right side of dashed bridge)
// ─────────────────────────────────────────────────────────────────────────────
class LineFollowerTrack {

  // ── The continuous path — normalized (0–1) ──────────────────────────────
  // Indices 0–54  : main track P39→P93
  // Indices 54–58 : dashed closing bridge P93→P39 (drawn dashed)
  static const List<List<double>> path = [

    // ── MAIN PATH — pixel (x,y) / (1277 × 819) — strictly from provided coords ──
    // P71 is inserted between P66 & P67 (bottom horizontal run y≈799)
    [0.39468, 0.39926],  //  0  P39 (504,327) START
    [0.33908, 0.41978],  //  1  P40 (433,344)
    [0.30774, 0.47131],  //  2  P41 (393,386)
    [0.29210, 0.54578],  //  3  P42 (373,447)  ← left S bottom
    [0.30774, 0.61661],  //  4  P43 (393,505)
    [0.33908, 0.66545],  //  5  P44 (433,545)
    [0.38449, 0.69231],  //  6  P45 (491,567)
    [0.46280, 0.68742],  //  7  P46 (591,563)
    [0.52076, 0.68742],  //  8  P47 (665,563)
    [0.59202, 0.68986],  //  9  P48 (756,565)
    [0.64683, 0.72894],  // 10  P49 (826,597)
    [0.68285, 0.77900],  // 11  P50 (872,638)
    [0.71417, 0.83150],  // 12  P51 (912,681)
    [0.74863, 0.88523],  // 13  P52 (956,725)
    [0.78700, 0.94139],  // 14  P53(1005,771)
    [0.83477, 0.97557],  // 15  P54(1066,799)
    [0.88488, 0.96459],  // 16  P55(1130,790)
    [0.92092, 0.91087],  // 17  P56(1176,746)
    [0.94128, 0.83760],  // 18  P57(1202,686)
    [0.89741, 0.71184],  // 19  P58(1146,583)
    [0.84651, 0.68131],  // 20  P59(1081,558)
    [0.79718, 0.70330],  // 21  P60(1018,576)
    [0.76351, 0.75580],  // 22  P61 (975,619)
    [0.68051, 0.89011],  // 23  P62 (869,729)
    [0.63977, 0.94506],  // 24  P63 (817,774)
    [0.58731, 0.97680],  // 25  P64 (750,800)
    [0.51371, 0.97680],  // 26  P65 (656,800)
    [0.39389, 0.98047],  // 27  P66 (503,803)
    [0.25528, 0.97557],  // 28  P71 (326,799) ← between P66 & P67 (bottom straight)
    [0.10415, 0.97557],  // 29  P67 (133,799)
    [0.03837, 0.89499],  // 30  P68  (49,733)
    [0.04228, 0.76067],  // 31  P69  (54,623)
    [0.10571, 0.68498],  // 32  P70 (135,561)  ← left S bottom of return
    [0.17932, 0.66057],  // 33  P72 (229,541)
    [0.20752, 0.59706],  // 34  P73 (265,489)
    [0.20438, 0.48230],  // 35  P74 (261,395)  ← left S inflection going up
    [0.15975, 0.41880],  // 36  P75 (204,343)
    [0.09866, 0.39682],  // 37  P76 (126,325)
    [0.04307, 0.33211],  // 38  P77  (55,272)
    [0.03289, 0.22100],  // 39  P78  (42,181)
    [0.07049, 0.13553],  // 40  P79  (90,111)
    [0.12451, 0.10989],  // 41  P80 (159, 90)
    [0.18168, 0.11477],  // 42  P81 (232, 94)
    [0.26000, 0.10989],  // 43  P82 (332, 90)
    [0.32889, 0.10745],  // 44  P83 (420, 88)
    [0.44949, 0.10989],  // 45  P84 (574, 90)
    [0.57399, 0.10745],  // 46  P85 (733, 88)
    [0.70399, 0.11234],  // 47  P86 (899, 92)
    [0.83242, 0.11234],  // 48  P87(1063, 92)
    [0.89351, 0.13431],  // 49  P88(1141,110)
    [0.92795, 0.20147],  // 50  P89(1185,165)
    [0.93109, 0.29426],  // 51  P90(1189,241)
    [0.89820, 0.37240],  // 52  P91(1147,305)
    [0.84494, 0.40293],  // 53  P92(1079,330)
    [0.76038, 0.39804],  // 54  P93 (971,326) END — vehicle stops here

    // ── DASHED CLOSING BRIDGE — P93 → P39 (drawn dashed, car never travels) ──
    [0.66016, 0.39804],  // 55  bridge pt 1
    [0.55000, 0.39865],  // 56  bridge pt 2
    [0.46744, 0.39926],  // 57  bridge pt 3
    [0.39468, 0.39926],  // 58  P39 — closes the loop (same as index 0)
  ];

  // ── Dashed segment range (inclusive path indices) ──
  // path[54]→path[58] = the horizontal closing bridge (END → START)
  static const int dashedStart = 54;  // P93 (END marker) — vehicle stops here
  static const int dashedEnd   = 58;  // back at P39 (START marker)

  // ── START marker: P39 (index 0) — exact pixel (504,327)/(1277×819) ──
  static const double startX = 0.39468;
  static const double startY = 0.39926;

  // ── END marker: P93 (index 54) — exact pixel (971,326)/(1277×819) ──
  static const double endX = 0.76038;
  static const double endY = 0.39804;

  // ── RFID checkpoints ──
  static const List<Map<String, dynamic>> checkpoints = [
    {'id': 'CP0', 'name': 'START',         'pathIndex':  0,  'x': 0.39468, 'y': 0.39926},
    {'id': 'CP1', 'name': 'Small Oval Bot','pathIndex':  3,  'x': 0.29210, 'y': 0.54578},
    {'id': 'CP2', 'name': 'Bottom Right',  'pathIndex': 14,  'x': 0.78700, 'y': 0.94139},
    {'id': 'CP3', 'name': 'Figure-8 Top',  'pathIndex': 19,  'x': 0.89741, 'y': 0.71184},
    {'id': 'CP4', 'name': 'Bottom Left',   'pathIndex': 29,  'x': 0.10415, 'y': 0.97557},
    {'id': 'CP5', 'name': 'Top Center',    'pathIndex': 45,  'x': 0.44949, 'y': 0.10989},
    {'id': 'CP6', 'name': 'END',           'pathIndex': 54,  'x': 0.76038, 'y': 0.39804},
  ];

  // ── Animal positions A1–A17 — full track perimeter ──────────────────────────
  // Image: 1277 × 819 px.  Normalization: x/1277, y/819.
  // A1 =(500,379)  A2 =(491,506)  A3 =(740,498)  A4 =(865,557)  A5 =(1035,732)
  // A6 =(1031,629) A7 =(866,800)  A8 =(157,749)  A9 =(157,622)  A10=(151,509)
  // A11=(164,382)  A12=(161,272)  A13=(155,38)   A14=(410,143)  A15=(795,143)
  // A16=(1076,32)  A17=(1075,383)
  static const List<Map<String, dynamic>> trackAnimals = [
    {'label': 'Camel',      'emoji': '🐪', 'pathIndex':  1, 'x': 0.39154, 'y': 0.46276},  // A1  (500,379)
    {'label': 'Tiger',      'emoji': '🐅', 'pathIndex':  4, 'x': 0.38450, 'y': 0.61782},  // A2  (491,506)
    {'label': 'Lion',       'emoji': '🦁', 'pathIndex':  8, 'x': 0.57962, 'y': 0.60806},  // A3  (740,498)
    {'label': 'Bull',       'emoji': '🐂', 'pathIndex': 10, 'x': 0.67737, 'y': 0.67985},  // A4  (865,557)
    {'label': 'Polar Bear', 'emoji': '🐻‍❄️', 'pathIndex': 13, 'x': 0.81050, 'y': 0.89377},  // A5 (1035,732)
    {'label': 'Giraffe',    'emoji': '🦒', 'pathIndex': 22, 'x': 0.80736, 'y': 0.76800},  // A6 (1031,629)
    {'label': 'Camel',      'emoji': '🐪', 'pathIndex': 23, 'x': 0.67815, 'y': 0.97680},  // A7  (866,800)
    {'label': 'Tiger',      'emoji': '🐅', 'pathIndex': 29, 'x': 0.12295, 'y': 0.91453},  // A8  (157,749)
    {'label': 'Lion',       'emoji': '🦁', 'pathIndex': 31, 'x': 0.12295, 'y': 0.75946},  // A9  (157,622)
    {'label': 'Bull',       'emoji': '🐂', 'pathIndex': 32, 'x': 0.11825, 'y': 0.62149},  // A10 (151,509)
    {'label': 'Polar Bear', 'emoji': '🐻‍❄️', 'pathIndex': 35, 'x': 0.12842, 'y': 0.46642},  // A11 (164,382)
    {'label': 'Giraffe',    'emoji': '🦒', 'pathIndex': 38, 'x': 0.12607, 'y': 0.33211},  // A12 (161,272)
    {'label': 'Camel',      'emoji': '🐪', 'pathIndex': 41, 'x': 0.12139, 'y': 0.04640},  // A13 (155, 38)
    {'label': 'Tiger',      'emoji': '🐅', 'pathIndex': 44, 'x': 0.32107, 'y': 0.17460},  // A14 (410,143)
    {'label': 'Lion',       'emoji': '🦁', 'pathIndex': 46, 'x': 0.62254, 'y': 0.17460},  // A15 (795,143)
    {'label': 'Bull',       'emoji': '🐂', 'pathIndex': 48, 'x': 0.84260, 'y': 0.03907},  // A16(1076, 32)
    {'label': 'Polar Bear', 'emoji': '🐻‍❄️', 'pathIndex': 52, 'x': 0.84182, 'y': 0.46764},  // A17(1075,383)
  ];

  // Get interpolated position along path
  static List<double> interpolate(int segIndex, double t) {
    final p = path;
    final i = segIndex.clamp(0, p.length - 2);
    final x = p[i][0] + (p[i + 1][0] - p[i][0]) * t.clamp(0.0, 1.0);
    final y = p[i][1] + (p[i + 1][1] - p[i][1]) * t.clamp(0.0, 1.0);
    return [x, y];
  }

  // Get heading (angle in degrees) for a given segment
  static double heading(int segIndex) {
    final p = path;
    final i = segIndex.clamp(0, p.length - 2);
    final dx = p[i + 1][0] - p[i][0];
    final dy = p[i + 1][1] - p[i][1];
    return atan2(dy, dx) * 180 / pi + 90;
  }

  // Smoothed heading: interpolates between current and next segment directions
  // within the segment, removing the abrupt snap at waypoints (left S-turn fix).
  // nextI is capped at dashedStart-1 so the car never rotates toward the bridge.
  static double smoothHeading(int segIndex, double t) {
    final p = path;
    final i = segIndex.clamp(0, p.length - 2);

    // Direction of current segment
    final dx0 = p[i + 1][0] - p[i][0];
    final dy0 = p[i + 1][1] - p[i][1];
    final double angle0 = atan2(dy0, dx0) * 180 / pi + 90;

    // Direction of next segment (capped so we never rotate toward the bridge)
    final nextI = (i + 1).clamp(0, dashedStart - 1);
    final dx1 = p[nextI + 1][0] - p[nextI][0];
    final dy1 = p[nextI + 1][1] - p[nextI][1];
    final double angle1 = atan2(dy1, dx1) * 180 / pi + 90;

    // Shortest-path angle interpolation
    double diff = ((angle1 - angle0) % 360 + 540) % 360 - 180;
    return angle0 + diff * t.clamp(0.0, 1.0);
  }

  // Returns true if the given path index is within the dashed segment
  static bool isDashed(int pathIndex) {
    return pathIndex >= dashedStart && pathIndex <= dashedEnd;
  }
}

