import 'dart:async';
import 'dart:math';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:webview_flutter/webview_flutter.dart';

// Firebase
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

// SafariSync v3.0 — new screens & models
import 'models/track_models.dart';
import 'screens/line_follower_screen.dart';
import 'screens/aqi_weather_screen.dart';

import 'screens/rfid_report_screen.dart';
import 'screens/vehicle_control_screen.dart';

// ─────────────────────────────────────────────────────────────────────────────
// FIREBASE CONFIG — paste from google-services.json
// ─────────────────────────────────────────────────────────────────────────────
const _kFirebaseApiKey =
    'AIzaSyDEytSdddrjirQ-7sP7G1BTGJXVVTj-1us'; // from google-services.json
const _kFirebaseAppId = 'Y1:1026628634662:android:7238427b33a4fdfde83ee7';
const _kFirebaseMessagingSenderId = '1026628634662';
const _kFirebaseProjectId = 'safarisync-b887b';
const _kFirebaseDatabaseUrl =
    'https://safarisync-b887b-default-rtdb.firebaseio.com'; // Realtime DB URL
const _kFirebaseStorageBucket = 'safarisync-b887b.appspot.com';

bool get _firebaseConfigured => !_kFirebaseApiKey.startsWith('YOUR_');

// ─────────────────────────────────────────────────────────────────────────────
// MAP CONFIGURATION — calibrated to safari_map.png (1473×971 px)
// All coords are fractions (0.0–1.0) of image width/height
// ─────────────────────────────────────────────────────────────────────────────
const _kUseAssetMap = true;           // ← changed from false
const _kMapAssetPath = 'assets/safari_map.png';

/// Animals visible in the map image at their approximate positions
class MapAnimals {
  static const List<Map<String, dynamic>> all = [
    // ── Updated animal roster per hackathon spec ──
    {'id':'ma1',  'name':'Camel',       'emoji':'🐪', 'x':0.08,'y':0.18,'zone':'A'},
    {'id':'ma2',  'name':'Tiger',       'emoji':'🐅', 'x':0.22,'y':0.28,'zone':'B'},
    {'id':'ma3',  'name':'Lion',        'emoji':'🦁', 'x':0.48,'y':0.38,'zone':'B'},
    {'id':'ma4',  'name':'Bull',        'emoji':'🐂', 'x':0.35,'y':0.55,'zone':'C'},
    {'id':'ma5',  'name':'Polar Bear',  'emoji':'🐻‍❄️', 'x':0.62,'y':0.22,'zone':'F'},
    {'id':'ma6',  'name':'Giraffe',     'emoji':'🦒', 'x':0.78,'y':0.15,'zone':'F'},
    // Secondary positions for hotspot variety
    {'id':'ma7',  'name':'Camel',       'emoji':'🐪', 'x':0.18,'y':0.72,'zone':'D'},
    {'id':'ma8',  'name':'Tiger',       'emoji':'🐅', 'x':0.55,'y':0.62,'zone':'E'},
    {'id':'ma9',  'name':'Giraffe',     'emoji':'🦒', 'x':0.88,'y':0.45,'zone':'F'},
    {'id':'ma10', 'name':'Lion',        'emoji':'🦁', 'x':0.30,'y':0.42,'zone':'B'},
    {'id':'ma11', 'name':'Bull',        'emoji':'🐂', 'x':0.70,'y':0.72,'zone':'D'},
    {'id':'ma12', 'name':'Polar Bear',  'emoji':'🐻‍❄️', 'x':0.45,'y':0.15,'zone':'A'},
  ];
}

class MapPaths {
  // ── UNPLUGGED ROUND III — LINE FOLLOWER TRACK (normalized 0–1)
  // Left ≈ black mat, right ≈ tan mat; dashed telemetry zone on horizontal bridge.
  // ESP32 should publish x,y in this same normalized frame (see RTDB `vehicles/car_1`).
  static List<List<double>>? _lfTrack;
  static List<List<double>> get lineFollowerTrack =>
      _lfTrack ??= _buildUnpluggedLineFollowerTrack();

  /// Waypoint indices [inclusive, exclusive) along `lineFollowerTrack` drawn dashed (telemetry uplink zone).
  static const lineFollowerDashedRange = [28, 44];

  /// RFID / IR checkpoint markers on the track (normalized positions).
  static const List<Map<String, dynamic>> lineFollowerCheckpoints = [
    {'id': 'cp_start', 'label': 'START', 'x': 0.08, 'y': 0.90},
    {'id': 'cp_mid', 'label': 'DATA ZONE', 'x': 0.46, 'y': 0.50},
    {'id': 'cp_rfid', 'label': 'RFID FINISH', 'x': 0.88, 'y': 0.82},
  ];

  static List<List<double>> _buildUnpluggedLineFollowerTrack() {
    final p = <List<double>>[];
    void add(double x, double y) {
      if (p.isEmpty || p.last[0] != x || p.last[1] != y) p.add([x, y]);
    }
    void line(double x1, double y1, double x2, double y2, int n) {
      for (int i = 0; i <= n; i++) {
        final t = i / n;
        add(x1 + (x2 - x1) * t, y1 + (y2 - y1) * t);
      }
    }
    // Bottom loop (opens east)
    for (int i = 0; i <= 24; i++) {
      final t = i / 24.0;
      final a = pi * 0.5 + pi * t;
      add(0.14 + 0.10 * cos(a), 0.86 + 0.06 * sin(a));
    }
    // Middle loop
    for (int i = 0; i <= 24; i++) {
      final t = i / 24.0;
      final a = pi * 0.5 + pi * t;
      add(0.14 + 0.10 * cos(a), 0.66 + 0.06 * sin(a));
    }
    // Top loop on black side
    for (int i = 0; i <= 24; i++) {
      final t = i / 24.0;
      final a = pi * 0.5 + pi * t;
      add(0.14 + 0.10 * cos(a), 0.46 + 0.06 * sin(a));
    }
    // Exit to horizontal bridge toward tan field
    line(0.24, 0.46, 0.36, 0.48, 8);
    line(0.36, 0.48, 0.52, 0.50, 10); // dashed section middle
    line(0.52, 0.50, 0.62, 0.48, 6);
    // Large upper arc on tan side
    for (int i = 0; i <= 30; i++) {
      final t = i / 30.0;
      final a = -pi * 0.85 + pi * 0.95 * t;
      add(0.72 + 0.16 * cos(a), 0.22 + 0.14 * sin(a));
    }
    // Figure-eight crossover (simplified twin lobes)
    for (int i = 0; i <= 18; i++) {
      final t = i / 18.0;
      final a = pi * 0.2 + pi * 1.6 * t;
      add(0.74 + 0.09 * cos(a), 0.52 + 0.07 * sin(a));
    }
    for (int i = 0; i <= 18; i++) {
      final t = i / 18.0;
      final a = -pi * 0.4 + pi * 1.6 * t;
      add(0.78 + 0.08 * cos(a), 0.58 + 0.06 * sin(a));
    }
    // Bottom small loop + return toward bridge
    for (int i = 0; i <= 20; i++) {
      final t = i / 20.0;
      final a = pi * 0.5 + pi * 1.2 * t;
      add(0.84 + 0.06 * cos(a), 0.78 + 0.05 * sin(a));
    }
    line(0.82, 0.74, 0.62, 0.55, 10);
    line(0.62, 0.55, 0.48, 0.52, 8);
    line(0.48, 0.52, 0.30, 0.50, 10);
    // Close back into left stack bottom
    line(0.30, 0.50, 0.20, 0.58, 6);
    line(0.20, 0.58, 0.10, 0.78, 10);
    line(0.10, 0.78, 0.08, 0.90, 6);
    return p;
  }

  // ── MAIN OUTER ROAD LOOP (clockwise from gate bottom-right) ──
  // Traced from the winding cream/beige road in safari_map.png
  static const mainLoop = [
    [0.90, 0.92], // Gate entrance (bottom-right)
    [0.78, 0.88], // Bottom road heading left
    [0.62, 0.82], // Bottom-center
    [0.48, 0.80], // Bottom-center-left (waterhole south)
    [0.34, 0.75], // Lower-left curve
    [0.20, 0.72], // West lower
    [0.10, 0.65], // West side heading north (rhino/hippo area)
    [0.08, 0.52], // West mid
    [0.10, 0.40], // West-upper near parrot zone
    [0.12, 0.28], // Upper-left near giraffe zone
    [0.22, 0.18], // Top-left corner
    [0.36, 0.08], // Top road heading right (penguin dome)
    [0.50, 0.06], // Top-center
    [0.64, 0.08], // Top-right
    [0.76, 0.12], // Northeast (elephant territory)
    [0.88, 0.18], // Far right upper
    [0.92, 0.32], // Right side heading south
    [0.92, 0.50], // Right mid (elephant/giraffe east)
    [0.90, 0.68], // Right lower
    [0.90, 0.92], // Back to gate
  ];

  // ── INNER NORTH-SOUTH CONNECTOR ──
  static const innerNS = [
    [0.50, 0.06],
    [0.50, 0.20],
    [0.50, 0.35],
    [0.48, 0.50], // Center junction
    [0.46, 0.65],
    [0.46, 0.80],
  ];

  // ── INNER EAST-WEST CONNECTOR ──
  static const innerEW = [
    [0.10, 0.40],
    [0.25, 0.42],
    [0.48, 0.50], // Center junction
    [0.65, 0.50],
    [0.82, 0.45],
    [0.92, 0.50],
  ];

  // ── WATERHOLE SPUR ──
  static const waterholeRoad = [
    [0.46, 0.65],
    [0.52, 0.68],
    [0.60, 0.72],
  ];

  // ── ALL ROADS (for drawing) ──
  static const allRoads = [mainLoop, innerNS, innerEW, waterholeRoad];

  // ── ON-ROAD ANIMAL POSITIONS (triggers jeep detour) — aligned to line follower + safari
  static List<Map<String, dynamic>> get onRoadAnimals {
    final t = lineFollowerTrack;
    List<double> at(int i) => t[i.clamp(0, t.length - 1)];
    return [
      {'pos': [at(12)[0], at(12)[1]], 'animal': 'Giraffe', 'emoji': '🦒'},
      {'pos': [at(35)[0], at(35)[1]], 'animal': 'Lion', 'emoji': '🦁'},
      {'pos': [at(55)[0], at(55)[1]], 'animal': 'Polar Bear', 'emoji': '🐻\u200d❄️'},
      {'pos': [at(80)[0], at(80)[1]], 'animal': 'Camel', 'emoji': '🐪'},
      {'pos': [at(5)[0], at(5)[1]], 'animal': 'Bull', 'emoji': '🐂'},
    ];
  }

  // ── JEEP ROUTES (safari map). Hardware autonomous car → RTDB `vehicles/car_1` uses `lineFollowerTrack`.
  static Map<String, List<List<double>>>? _jeepRoutes;
  static Map<String, List<List<double>>> get jeepRoutes =>
      _jeepRoutes ??= {
        'j1': [
          [0.90, 0.92],
          [0.78, 0.88],
          [0.62, 0.82],
          [0.48, 0.80],
          [0.34, 0.75],
          [0.20, 0.72],
          [0.10, 0.65],
          [0.08, 0.52],
          [0.10, 0.40],
          [0.12, 0.28],
          [0.22, 0.18],
          [0.36, 0.08],
          [0.50, 0.06],
          [0.64, 0.08],
          [0.76, 0.12],
          [0.88, 0.18],
          [0.92, 0.32],
          [0.92, 0.50],
          [0.90, 0.68],
          [0.90, 0.92],
        ],
        'j2': [
          [0.10, 0.40],
          [0.25, 0.42],
          [0.48, 0.50],
          [0.46, 0.65],
          [0.52, 0.68],
          [0.60, 0.72],
          [0.62, 0.82],
          [0.48, 0.80],
          [0.46, 0.65],
          [0.48, 0.50],
          [0.10, 0.40],
        ],
        'j3': [
          [0.48, 0.50],
          [0.65, 0.50],
          [0.82, 0.45],
          [0.92, 0.50],
          [0.92, 0.32],
          [0.88, 0.18],
          [0.76, 0.12],
          [0.64, 0.08],
          [0.50, 0.06],
          [0.50, 0.20],
          [0.50, 0.35],
          [0.48, 0.50],
        ],
        'j4': [
          [0.50, 0.06],
          [0.50, 0.20],
          [0.50, 0.35],
          [0.48, 0.50],
          [0.46, 0.65],
          [0.46, 0.80],
          [0.48, 0.80],
          [0.62, 0.82],
          [0.78, 0.88],
          [0.90, 0.92],
          [0.90, 0.68],
          [0.92, 0.50],
        ],
        'j5': [
          [0.28, 0.42],
          [0.48, 0.50],
          [0.65, 0.50],
          [0.88, 0.18],
          [0.76, 0.12],
          [0.64, 0.08],
          [0.50, 0.06],
          [0.36, 0.08],
          [0.22, 0.18],
          [0.12, 0.28],
          [0.10, 0.40],
          [0.25, 0.42],
          [0.28, 0.42],
        ],
        'j6': [
          [0.90, 0.92],
          [0.90, 0.68],
          [0.90, 0.92],
        ],
      };

  // ── ANIMAL ZONE BOUNDING BOXES [xMin,yMin,xMax,yMax] ──
  static const animalZones = {
    'ma1': [0.04,0.14,0.18,0.32], 'ma2': [0.10,0.28,0.24,0.42],
    'ma3': [0.18,0.22,0.30,0.38], 'ma4': [0.22,0.36,0.36,0.50],
    'ma5': [0.16,0.48,0.30,0.62], 'ma6': [0.08,0.58,0.22,0.72],
    'ma7': [0.68,0.12,0.82,0.28], 'ma8': [0.76,0.24,0.90,0.38],
    'ma9': [0.42,0.34,0.56,0.48], 'ma10':[0.32,0.38,0.46,0.52],
    'ma11':[0.46,0.46,0.60,0.60], 'ma12':[0.52,0.54,0.66,0.68],
    'ma13':[0.82,0.44,0.96,0.60], 'ma14':[0.72,0.40,0.86,0.56],
    'ma15':[0.56,0.66,0.70,0.80], 'ma16':[0.38,0.66,0.52,0.80],
    'ma17':[0.30,0.04,0.44,0.18], 'ma18':[0.40,0.10,0.54,0.22],
    'ma19':[0.02,0.34,0.12,0.46], 'ma20':[0.06,0.48,0.16,0.62],
  };
}

// ─────────────────────────────────────────────────────────────────────────────
// THEME
// ─────────────────────────────────────────────────────────────────────────────
class ST {
  static const Color bg = Color(0xFF0B1810);
  static const Color bgDeep = Color(0xFF0F1F14);
  static const Color panel = Color(0xFF162A1C);
  static const Color card = Color(0xFF1D3324);
  static const Color overlay = Color(0xFF0A160D);
  static const Color g0 = Color(0xFF6EDB75);
  static const Color g1 = Color(0xFF4DB855);
  static const Color g2 = Color(0xFF2E8C36);
  static const Color gGlow = Color(0x1A4DB855);
  static const Color gBorder = Color(0x2E4DB855);
  static const Color gBorderBright = Color(0x554DB855);
  static const Color amber = Color(0xFFF5A623);
  static const Color amberL = Color(0xFFFDD07A);
  static const Color red = Color(0xFFE84040);
  static const Color redL = Color(0xFFFFAAAA);
  static const Color blue = Color(0xFF4A9EF5);
  static const Color blueL = Color(0xFF9DCEFF);
  static const Color teal = Color(0xFF26C6B0);
  static const Color tealL = Color(0xFF7EEADB);
  static const Color purple = Color(0xFF9B7FEF);
  static const Color purpleL = Color(0xFFC4AAFF);
  static const Color pink = Color(0xFFEA6A9B);
  static const Color t1 = Color(0xFFE8F5E9);
  static const Color t2 = Color(0x99E8F5E9);
  static const Color t3 = Color(0x55E8F5E9);
  static const Color t4 = Color(0x33E8F5E9);

  static TextStyle bebas(double sz, {Color color = g0}) => TextStyle(
    fontFamily: 'Anton',
    fontSize: sz,
    color: color,
    letterSpacing: sz * 0.08,
    height: 1.0,
  );
  static TextStyle mono(double sz, {Color color = t2}) =>
      GoogleFonts.jetBrainsMono(fontSize: sz, color: color);
  static TextStyle label(double sz, {Color color = t3}) => GoogleFonts.dmSans(
    fontSize: sz,
    color: color,
    fontWeight: FontWeight.w600,
    letterSpacing: 1.0,
  );
  static TextStyle body(double sz, {Color color = t1}) =>
      GoogleFonts.dmSans(fontSize: sz, color: color);

  static BoxDecoration panelBox({
    Color? border,
    double radius = 10,
    Color? bg,
  }) => BoxDecoration(
    color: bg ?? panel,
    borderRadius: BorderRadius.circular(radius),
    border: Border.all(color: border ?? gBorder, width: 1),
  );
  static BoxDecoration cardBox({
    Color? border,
    double radius = 10,
    Color? bg,
  }) => BoxDecoration(
    color: bg ?? card,
    borderRadius: BorderRadius.circular(radius),
    border: Border.all(color: border ?? gBorder, width: 1),
  );
  static BoxDecoration glowBox(Color color) => BoxDecoration(
    color: color.withOpacity(0.08),
    borderRadius: BorderRadius.circular(10),
    border: Border.all(color: color.withOpacity(0.35), width: 1),
    boxShadow: [
      BoxShadow(
        color: color.withOpacity(0.12),
        blurRadius: 12,
        spreadRadius: 2,
      ),
    ],
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// MODELS
// ─────────────────────────────────────────────────────────────────────────────
enum UserRole { tourist, driver, admin }

enum VehicleStatus { active, parked, alert, offline }

enum AlertType { critical, warning, info }

enum DangerLevel { low, medium, high }

// Jeep detour state machine
enum JeepDetourState { onPath, stopping, detouringAround, returning }

class AnimalModel {
  final String id, name, species, emoji;
  final Color color;
  final String zone, status, detectedBy;
  double x, y;
  // Target position for smooth movement within zone
  double targetX, targetY;
  final double confidence;
  final DateTime lastSeen;
  int sightingCount;

  AnimalModel({
    required this.id,
    required this.name,
    required this.species,
    required this.emoji,
    required this.color,
    required this.zone,
    required this.status,
    required this.detectedBy,
    required this.x,
    required this.y,
    required this.confidence,
    required this.lastSeen,
    this.sightingCount = 0,
  }) : targetX = x,
        targetY = y;

  AnimalModel copyWith({
    double? x,
    double? y,
    double? targetX,
    double? targetY,
    String? status,
    int? sightingCount,
  }) =>
      AnimalModel(
        id: id,
        name: name,
        species: species,
        emoji: emoji,
        color: color,
        zone: zone,
        status: status ?? this.status,
        detectedBy: detectedBy,
        x: x ?? this.x,
        y: y ?? this.y,
        confidence: confidence,
        lastSeen: lastSeen,
        sightingCount: sightingCount ?? this.sightingCount,
      )
        ..targetX = targetX ?? this.targetX
        ..targetY = targetY ?? this.targetY;
}

class VehicleModel {
  final String id, name, driverName, zone;
  double x, y, direction, speed, batteryLevel, fuelLevel;
  int passengers;
  VehicleStatus status;
  bool pirTriggered;
  int pathIndex;
  double pathProgress;
  // Detour state for on-road animal avoidance
  JeepDetourState detourState;
  double detourTimer;
  double detourOffsetX, detourOffsetY;
  String? blockedByAnimal;

  VehicleModel({
    required this.id,
    required this.name,
    required this.driverName,
    required this.zone,
    required this.x,
    required this.y,
    required this.direction,
    required this.speed,
    required this.batteryLevel,
    required this.fuelLevel,
    required this.passengers,
    required this.status,
    this.pirTriggered = false, this.pathIndex = 0, this.pathProgress = 0.0,
    this.detourState = JeepDetourState.onPath, this.detourTimer = 0,
    this.detourOffsetX = 0, this.detourOffsetY = 0, this.blockedByAnimal
  });
}

class ZoneModel {
  final String id, name, description;
  final Color color, borderColor;
  final DangerLevel danger;
  final List<String> animalIds;
  final double cx, cy, w, h;
  int vehicleCount;
  final int maxVehicles;

  ZoneModel({
    required this.id,
    required this.name,
    required this.description,
    required this.color,
    required this.borderColor,
    required this.danger,
    required this.animalIds,
    required this.cx,
    required this.cy,
    required this.w,
    required this.h,
    this.vehicleCount = 0,
    this.maxVehicles = 6,
  });
}

class AlertModel {
  final String id, emoji, title, message;
  final AlertType type;
  final DateTime time;
  bool isRead;
  // SOS fields
  final bool isSOS;
  final double? sosLat, sosLng;
  final String? sosVehicleId, sosVehicleName, sosTriggerBy;

  AlertModel({required this.id, required this.emoji, required this.title,
    required this.message, required this.type, required this.time,
    this.isRead = false, this.isSOS = false,
    this.sosLat, this.sosLng, this.sosVehicleId, this.sosVehicleName, this.sosTriggerBy
  });
}

class ImuData {
  final double ax, ay, az, gx, gy, gz, mx, my, mz;
  final double temperature, pressure, heading, altitude;
  final DateTime timestamp;
  ImuData({
    required this.ax,
    required this.ay,
    required this.az,
    required this.gx,
    required this.gy,
    required this.gz,
    required this.mx,
    required this.my,
    required this.mz,
    required this.temperature,
    required this.pressure,
    required this.heading,
    required this.altitude,
    required this.timestamp,
  });
}

/// UNPLUGGED line-follower car pose in normalized track coordinates (see `MapPaths.lineFollowerTrack`).
class TrackCarTelemetry {
  final double x, y, direction, speed;
  final int pathIndex;
  final double pathProgress;
  final bool inTelemetryDashedZone;
  TrackCarTelemetry({
    required this.x,
    required this.y,
    required this.direction,
    required this.speed,
    required this.pathIndex,
    required this.pathProgress,
    required this.inTelemetryDashedZone,
  });
}

/// AQI module + simple heuristic forecast (ESP32 publishes same shape to RTDB `env/aqi`).
class AqiReading {
  final double pm25, pm10, aqi;
  final double temperature, humidity;
  final int rainChance4h;
  final String forecastSummary;
  final DateTime timestamp;
  AqiReading({
    required this.pm25,
    required this.pm10,
    required this.aqi,
    required this.temperature,
    required this.humidity,
    required this.rainChance4h,
    required this.forecastSummary,
    required this.timestamp,
  });
}

class LiveDetection {
  final String id, label, emoji;
  final double x, y, confidence;
  final DateTime time;
  LiveDetection({
    required this.id,
    required this.label,
    required this.emoji,
    required this.x,
    required this.y,
    required this.confidence,
    required this.time,
  });
}

class TicketModel {
  final String id, type, timeSlot, description;
  final double price;
  final List<String> features;
  final Color accentColor;
  TicketModel({
    required this.id,
    required this.type,
    required this.timeSlot,
    required this.description,
    required this.price,
    required this.features,
    required this.accentColor,
  });
}

// ── SLOT MODEL — a bookable date+time combination ──
class SlotModel {
  final String id, ticketTypeId, date, timeLabel;
  final int maxCapacity, bookedCount;
  bool get isFull => bookedCount >= maxCapacity;
  bool get isAlmostFull => (maxCapacity - bookedCount) <= 5 && !isFull;
  SlotModel({required this.id, required this.ticketTypeId, required this.date,
    required this.timeLabel, required this.maxCapacity, required this.bookedCount});
}

// ── BOOKING MODEL — a completed booking record ──
class BookingModel {
  final String bookingId, ticketType, ticketTypeId, date, timeSlot;
  final String userId, userName, userEmail, userPhone;
  final double price;
  final String qrData;
  final DateTime bookedAt;
  BookingModel({required this.bookingId, required this.ticketType,
    required this.ticketTypeId, required this.date, required this.timeSlot,
    required this.userId, required this.userName, required this.userEmail,
    required this.userPhone, required this.price,
    required this.qrData, required this.bookedAt});
}

class SafariRoute {
  final String id, name, note, scoreLabel;
  final Color color, scoreColor;
  final double distanceKm;
  final int durationMinutes, estimatedSightings;
  final List<String> waypoints;
  SafariRoute({
    required this.id,
    required this.name,
    required this.note,
    required this.scoreLabel,
    required this.color,
    required this.scoreColor,
    required this.distanceKm,
    required this.durationMinutes,
    required this.estimatedSightings,
    required this.waypoints,
  });
}

// ─────────────────────────────────────────────────────────────────────────────
// STATIC DATA
// ─────────────────────────────────────────────────────────────────────────────
class SD {
  // Animals are now built from the actual map image
  static List<AnimalModel> buildMapAnimals() {
    final speciesInfo = {
      'Camel':      ['Camelus bactrianus',        0xFFD9A848, 'Grazing'],
      'Tiger':      ['Panthera tigris',           0xFFE84040, 'Stalking'],
      'Lion':       ['Panthera leo',              0xFFF5A623, 'Hunting'],
      'Bull':       ['Bos taurus',                0xFF92400E, 'Alert'],
      'Polar Bear': ['Ursus maritimus',           0xFFE2E8F0, 'Foraging'],
      'Giraffe':    ['Giraffa camelopardalis',    0xFFFDD07A, 'Grazing'],
    };
    final cams = List.generate(20, (i) => 'ESP32-CAM-${(i+1).toString().padLeft(2,'0')}');
    final rng = Random(42);
    return MapAnimals.all.asMap().entries.map((e) {
      final i = e.key; final ma = e.value;
      final name = ma['name'] as String;
      final info = speciesInfo[name] ?? ['Unknown', 0xFF6EDB75, 'Active'];
      return AnimalModel(
        id: ma['id'] as String, name: name,
        species: info[0] as String, emoji: ma['emoji'] as String,
        color: Color(info[1] as int), zone: ma['zone'] as String,
        status: info[2] as String, detectedBy: cams[i % cams.length],
        x: ma['x'] as double, y: ma['y'] as double,
        confidence: 0.75 + rng.nextDouble() * 0.22,
        lastSeen: DateTime.now(),
        sightingCount: 3 + rng.nextInt(28),
      );
    }).toList();
  }

  // Keep backward-compatible getter
  static List<AnimalModel> get animals => buildMapAnimals();

  static List<VehicleModel> buildVehicles() => [
    VehicleModel(
      id: 'j1',
      name: 'Jeep Alpha-01',
      driverName: 'Kamba J.',
      zone: 'A',
      x: 0.10,
      y: 0.15,
      direction: 30,
      speed: 12,
      batteryLevel: 88,
      fuelLevel: 72,
      passengers: 6,
      status: VehicleStatus.active,
      pathIndex: 0,
    ),
    VehicleModel(
      id: 'j2',
      name: 'Jeep Beta-02',
      driverName: 'Osei M.',
      zone: 'D',
      x: 0.25,
      y: 0.48,
      direction: 90,
      speed: 8,
      batteryLevel: 94,
      fuelLevel: 58,
      passengers: 4,
      status: VehicleStatus.active,
      pathIndex: 0,
    ),
    VehicleModel(
      id: 'j3',
      name: 'Jeep Gamma-03',
      driverName: 'Amara B.',
      zone: 'C',
      x: 0.50,
      y: 0.50,
      direction: 0,
      speed: 0,
      batteryLevel: 100,
      fuelLevel: 90,
      passengers: 6,
      status: VehicleStatus.parked,
      pathIndex: 0,
    ),
    VehicleModel(
      id: 'j4',
      name: 'Jeep Delta-04',
      driverName: 'Nuru K.',
      zone: 'E',
      x: 0.50,
      y: 0.28,
      direction: 270,
      speed: 10,
      batteryLevel: 67,
      fuelLevel: 45,
      passengers: 5,
      status: VehicleStatus.active,
      pathIndex: 0,
    ),
    VehicleModel(
      id: 'j5',
      name: 'Ranger Rover-01',
      driverName: 'Zuri P.',
      zone: 'B',
      x: 0.72,
      y: 0.52,
      direction: 315,
      speed: 15,
      batteryLevel: 45,
      fuelLevel: 38,
      passengers: 2,
      status: VehicleStatus.alert,
      pathIndex: 0,
    ),
    VehicleModel(
      id: 'j6',
      name: 'Medical Unit',
      driverName: 'Dr. Akin',
      zone: 'Base',
      x: 0.50,
      y: 0.90,
      direction: 0,
      speed: 0,
      batteryLevel: 100,
      fuelLevel: 95,
      passengers: 3,
      status: VehicleStatus.parked,
      pathIndex: 0,
    ),
  ];

  static final List<ZoneModel> zones = [
    ZoneModel(id:'A', name:'Zone Alpha', description:'Giraffe, Deer, Birds territory',
        color:const Color(0x2E4A9EF5), borderColor:const Color(0xFF4A9EF5),
        danger:DangerLevel.low,
        animalIds:['ma1','ma2','ma3','ma17','ma18','ma19'],
        cx:0.15, cy:0.26, w:0.28, h:0.30, maxVehicles:8),
    ZoneModel(id:'B', name:'Zone Beta', description:'Predator zone — HIGH ALERT',
        color:const Color(0x2EE84040), borderColor:const Color(0xFFE84040),
        danger:DangerLevel.high,
        animalIds:['ma4','ma9'],
        cx:0.38, cy:0.43, w:0.20, h:0.16, maxVehicles:4),
    ZoneModel(id:'C', name:'Zone Charlie', description:'Buffalo plains',
        color:const Color(0x2EF5A623), borderColor:const Color(0xFFF5A623),
        danger:DangerLevel.medium,
        animalIds:['ma10'],
        cx:0.38, cy:0.44, w:0.13, h:0.12, maxVehicles:6),
    ZoneModel(id:'D', name:'Zone Delta', description:'Waterhole, Hippo & Zebra',
        color:const Color(0x2E26C6B0), borderColor:const Color(0xFF26C6B0),
        danger:DangerLevel.low,
        animalIds:['ma5','ma6','ma15','ma16','ma20'],
        cx:0.35, cy:0.70, w:0.30, h:0.22, maxVehicles:8),
    ZoneModel(id:'E', name:'Zone Echo', description:'Bear & Capybara enclosure',
        color:const Color(0x2E9B7FEF), borderColor:const Color(0xFF9B7FEF),
        danger:DangerLevel.medium,
        animalIds:['ma11','ma12'],
        cx:0.54, cy:0.56, w:0.15, h:0.14, maxVehicles:5),
    ZoneModel(id:'F', name:'Zone Foxtrot', description:'Elephant & East savannah',
        color:const Color(0x1A4DB855), borderColor:const Color(0xFF4DB855),
        danger:DangerLevel.low,
        animalIds:['ma7','ma8','ma13','ma14'],
        cx:0.82, cy:0.36, w:0.22, h:0.26, maxVehicles:6),
  ];

  static final List<AlertModel> alerts = [
    AlertModel(
      id: '1',
      emoji: '🚨',
      title: 'Lion pride near Jeep Alpha-01',
      message: 'Lion detected 80m away. Immediate alert issued.',
      type: AlertType.critical,
      time: DateTime.now().subtract(const Duration(minutes: 2)),
    ),
    AlertModel(
      id: '2',
      emoji: '⚠️',
      title: 'Zone B overcrowded',
      message: 'Maximum capacity exceeded. Reroute vehicles.',
      type: AlertType.critical,
      time: DateTime.now().subtract(const Duration(minutes: 5)),
    ),
    AlertModel(
      id: '3',
      emoji: '🌡️',
      title: 'High temp in Zone C: 42°C',
      message: 'Heat advisory for tourists in Zone C.',
      type: AlertType.warning,
      time: DateTime.now().subtract(const Duration(minutes: 12)),
    ),
    AlertModel(
      id: '4',
      emoji: '💧',
      title: 'West waterhole low: 22%',
      message: 'Animal migration expected toward Zone D.',
      type: AlertType.warning,
      time: DateTime.now().subtract(const Duration(minutes: 18)),
    ),
    AlertModel(
      id: '5',
      emoji: '📡',
      title: 'ESP32 Node #07 reconnected',
      message: 'Node 07 back online. All sensors nominal.',
      type: AlertType.info,
      time: DateTime.now().subtract(const Duration(minutes: 22)),
    ),
    AlertModel(
      id: '6',
      emoji: '🐘',
      title: 'New elephant sighting in Zone A',
      message: 'Bull elephant detected. Confidence: 94%.',
      type: AlertType.info,
      time: DateTime.now().subtract(const Duration(minutes: 28)),
    ),
    AlertModel(
      id: '7',
      emoji: '⚡',
      title: 'Node-09 battery critical: 12%',
      message: 'Replace Node-09 within 2 hours.',
      type: AlertType.warning,
      time: DateTime.now().subtract(const Duration(minutes: 35)),
    ),
  ];

  static final List<TicketModel> tickets = [
    TicketModel(
      id: 't1',
      type: 'Morning Safari',
      timeSlot: '06:00 – 12:00',
      description: '6AM–12PM · 4 zones · Sunrise wildlife',
      price: 2499,
      accentColor: ST.amberL,
      features: [
        'Guided jeep tour',
        'Wildlife expert onboard',
        'Photo stops included',
        'Breakfast pack',
        'Emergency kit',
      ],
    ),
    TicketModel(
      id: 't2',
      type: 'Full Day Pass',
      timeSlot: '06:00 – 18:00',
      description: '6AM–6PM · All zones · Full access',
      price: 4999,
      accentColor: ST.g0,
      features: [
        'Unlimited zone access',
        'Professional guide',
        'Lunch & dinner included',
        'Priority animal sightings',
        'Emergency kit + SOS',
      ],
    ),
    TicketModel(
      id: 't3',
      type: 'Sunset Special',
      timeSlot: '15:00 – 19:00',
      description: '3PM–7PM · Peak wildlife hours',
      price: 3299,
      accentColor: ST.pink,
      features: [
        'Peak wildlife window',
        'Sunset photography',
        'Bonfire evening',
        'Hot beverages',
        'Star-gazing session',
      ],
    ),
  ];

  static final List<SafariRoute> routes = [
    SafariRoute(
      id: 'r1',
      name: 'Alpha Trail',
      note: 'High elephant & giraffe activity on east corridor',
      scoreLabel: 'OPTIMAL',
      color: ST.g0,
      scoreColor: ST.g0,
      distanceKm: 14.2,
      durationMinutes: 135,
      estimatedSightings: 12,
      waypoints: ['Gate', 'Zone A', 'Zone D', 'Zone C', 'Gate'],
    ),
    SafariRoute(
      id: 'r2',
      name: 'Beta Circuit',
      note: 'Zone B (predator) active — extra caution required',
      scoreLabel: 'MODERATE',
      color: ST.amber,
      scoreColor: ST.amber,
      distanceKm: 11.8,
      durationMinutes: 110,
      estimatedSightings: 9,
      waypoints: ['Gate', 'Zone F', 'Zone B', 'Zone C', 'Gate'],
    ),
    SafariRoute(
      id: 'r3',
      name: 'Gamma Loop',
      note: 'Zone B overcrowded + lion hunting — avoid today',
      scoreLabel: 'AVOID',
      color: ST.red,
      scoreColor: ST.red,
      distanceKm: 16.5,
      durationMinutes: 165,
      estimatedSightings: 15,
      waypoints: ['Gate', 'Zone A', 'Zone B', 'Zone E', 'Zone D', 'Gate'],
    ),
  ];

  static final List<Map<String, dynamic>> predictions = [
    {
      'icon': '🦁',
      'title': 'High lion activity in Zone B',
      'conf': 87,
      'tag': 'DANGER',
      'tagBg': 0x26E84040,
      'tagFg': 0xFFE84040,
      'desc': 'Based on prey movement & time-of-day patterns',
    },
    {
      'icon': '🐘',
      'title': 'Elephant herd moving to waterhole',
      'conf': 92,
      'tag': 'MOVEMENT',
      'tagBg': 0x264A9EF5,
      'tagFg': 0xFF4A9EF5,
      'desc': 'GY-91 IMU patterns suggest westward migration in Zone A',
    },
    {
      'icon': '🌅',
      'title': 'Peak sighting window: 17:00–18:30',
      'conf': 78,
      'tag': 'OPTIMAL',
      'tagBg': 0x264DB855,
      'tagFg': 0xFF6EDB75,
      'desc': 'Historical data shows 3× animal activity at dusk',
    },
    {
      'icon': '🦒',
      'title': 'Giraffe pod near east acacia grove',
      'conf': 71,
      'tag': 'LOCATION',
      'tagBg': 0x269B7FEF,
      'tagFg': 0xFF9B7FEF,
      'desc': 'Drone imagery + PIR sensor correlation confirms eastside',
    },
    {
      'icon': '🌧️',
      'title': 'Rain event in 4 hours (Zone D)',
      'conf': 84,
      'tag': 'WEATHER',
      'tagBg': 0x2626C6B0,
      'tagFg': 0xFF26C6B0,
      'desc': 'BMP280 pressure drop detected on 3 nodes.',
    },
  ];
}

// ─────────────────────────────────────────────────────────────────────────────
// PATH INTERPOLATION — smooth movement along waypoints
// ─────────────────────────────────────────────────────────────────────────────
class PathInterpolator {
  // Get interpolated position along a path at t (0.0 = start, 1.0 = end of segment)
  static Offset lerp(List<List<double>> path, int segIndex, double t) {
    if (path.isEmpty) return const Offset(0.5, 0.5);
    final i = segIndex.clamp(0, path.length - 2);
    final p0 = Offset(path[i][0], path[i][1]);
    final p1 = Offset(path[i + 1][0], path[i + 1][1]);
    return Offset.lerp(p0, p1, t.clamp(0, 1))!;
  }

  // Get heading angle between two consecutive waypoints
  static double heading(List<List<double>> path, int segIndex) {
    if (path.length < 2) return 0;
    final i = segIndex.clamp(0, path.length - 2);
    final dx = path[i + 1][0] - path[i][0];
    final dy = path[i + 1][1] - path[i][1];
    return atan2(dy, dx) * 180 / pi + 90; // Convert to compass bearing
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SIMULATION SERVICE — path-constrained movement
// ─────────────────────────────────────────────────────────────────────────────
class SimService {
  static final SimService _i = SimService._();
  factory SimService() => _i;
  SimService._();

  final _rng = Random();
  final _animalCtrl = StreamController<List<AnimalModel>>.broadcast();
  final _vehicleCtrl = StreamController<List<VehicleModel>>.broadcast();
  final _imuCtrl = StreamController<ImuData>.broadcast();
  final _alertCtrl = StreamController<AlertModel>.broadcast();
  final _trackCtrl = StreamController<TrackCarTelemetry>.broadcast();
  final _aqiCtrl = StreamController<AqiReading>.broadcast();
  final _detCtrl = StreamController<List<LiveDetection>>.broadcast();

  List<AnimalModel> _animals = SD.animals.map((a) => a.copyWith()).toList();
  List<VehicleModel> _vehicles = SD.buildVehicles();
  final List<LiveDetection> _liveDetections = [];

  Timer? _at, _vt, _it, _alt, _tt, _aqt, _dt;
  // Per-animal: timer countdown to next target change
  final Map<String, int> _animalTargetCountdown = {};
  double _heading = 87;
  int _trackSeg = 0;
  double _trackProg = 0;

  Stream<List<AnimalModel>> get animals => _animalCtrl.stream;
  Stream<List<VehicleModel>> get vehicles => _vehicleCtrl.stream;
  Stream<ImuData> get imu => _imuCtrl.stream;
  Stream<AlertModel> get alert => _alertCtrl.stream;
  Stream<TrackCarTelemetry> get trackCar => _trackCtrl.stream;
  Stream<AqiReading> get aqi => _aqiCtrl.stream;
  Stream<List<LiveDetection>> get detections => _detCtrl.stream;
  List<AnimalModel> get currentAnimals => _animals;
  List<VehicleModel> get currentVehicles => _vehicles;

  void start() {
    // Initialize animal target countdowns
    for (final a in _animals) _animalTargetCountdown[a.id] = 0;

    _at = Timer.periodic(
      const Duration(milliseconds: 200),
          (_) => _tickAnimals(),
    );
    _vt = Timer.periodic(
      const Duration(milliseconds: 80),
          (_) => _tickVehicles(),
    );
    _it = Timer.periodic(const Duration(milliseconds: 80), (_) => _tickImu());
    _alt = Timer.periodic(const Duration(seconds: 40), (_) => _tickAlert());
    _tt = Timer.periodic(const Duration(milliseconds: 80), (_) => _tickTrackCar());
    _aqt = Timer.periodic(const Duration(seconds: 3), (_) => _tickAqi());
    _dt = Timer.periodic(const Duration(seconds: 5), (_) => _tickDetections());
  }

  void stop() {
    _at?.cancel();
    _vt?.cancel();
    _it?.cancel();
    _alt?.cancel();
    _tt?.cancel();
    _aqt?.cancel();
    _dt?.cancel();
  }

  static const _detPool = [
    ('🦁', 'Lion', 'lion'),
    ('🐘', 'Elephant', 'elephant'),
    ('🦓', 'Zebra', 'zebra'),
    ('🦒', 'Giraffe', 'giraffe'),
    ('🦛', 'Hippo', 'hippo'),
  ];

  void _tickDetections() {
    final route = MapPaths.lineFollowerTrack;
    if (route.isEmpty) return;
    final pick = _detPool[_rng.nextInt(_detPool.length)];
    final ip = _rng.nextInt(route.length - 1);
    final pt = route[ip];
    final id = 'd_${DateTime.now().millisecondsSinceEpoch}';
    _liveDetections.insert(
      0,
      LiveDetection(
        id: id,
        label: pick.$2,
        emoji: pick.$1,
        x: (pt[0] + (_rng.nextDouble() - 0.5) * 0.04).clamp(0.02, 0.98),
        y: (pt[1] + (_rng.nextDouble() - 0.5) * 0.04).clamp(0.02, 0.98),
        confidence: 0.72 + _rng.nextDouble() * 0.26,
        time: DateTime.now(),
      ),
    );
    while (_liveDetections.length > 30) _liveDetections.removeLast();
    if (!_detCtrl.isClosed) _detCtrl.add(List.from(_liveDetections));
  }

  void _tickTrackCar() {
    final route = MapPaths.lineFollowerTrack;
    if (route.length < 2) return;
    const spd = 0.0022;
    var np = _trackProg + spd;
    var ni = _trackSeg;
    while (np >= 1.0) {
      np -= 1.0;
      ni = (ni + 1) % (route.length - 1);
    }
    _trackProg = np;
    _trackSeg = ni;
    final pos = PathInterpolator.lerp(route, ni, np);
    final hdg = PathInterpolator.heading(route, ni);
    final dz = ni >= MapPaths.lineFollowerDashedRange[0] &&
        ni < MapPaths.lineFollowerDashedRange[1];
    if (!_trackCtrl.isClosed) {
      _trackCtrl.add(TrackCarTelemetry(
        x: pos.dx,
        y: pos.dy,
        direction: hdg,
        speed: 10 + _rng.nextDouble() * 4,
        pathIndex: ni,
        pathProgress: np,
        inTelemetryDashedZone: dz,
      ));
    }
  }

  void _tickAqi() {
    final pm25 = 18 + _rng.nextDouble() * 35;
    final pm10 = pm25 + 8 + _rng.nextDouble() * 12;
    final aqi = (pm25 * 1.4 + pm10 * 0.3).clamp(20, 220);
    final temp = 26 + _rng.nextDouble() * 10;
    final hum = 45 + _rng.nextInt(35);
    final pressureHint = _rng.nextDouble();
    final rain = pressureHint < 0.25 ? 55 + _rng.nextInt(35) : 8 + _rng.nextInt(25);
    final summary = rain > 40
        ? 'AQI + pressure trend: possible showers in ~4h'
        : 'Stable conditions; good visibility for vision stack';
    if (!_aqiCtrl.isClosed) {
      _aqiCtrl.add(AqiReading(
        pm25: pm25,
        pm10: pm10,
        aqi: aqi.toDouble(),
        temperature: temp,
        humidity: hum.toDouble(),
        rainChance4h: rain,
        forecastSummary: summary,
        timestamp: DateTime.now(),
      ));
    }
  }

  // Animals move smoothly within their defined zone bounds
  void _tickAnimals() {
    _animals =
        _animals.map((a) {
          final bounds = MapPaths.animalZones[a.id];
          if (bounds == null) return a;

          final countdown = _animalTargetCountdown[a.id] ?? 0;

          // Pick new target every ~3 seconds (15 ticks * 200ms = 3s)
          if (countdown <= 0) {
            final tx = bounds[0] + _rng.nextDouble() * (bounds[2] - bounds[0]);
            final ty = bounds[1] + _rng.nextDouble() * (bounds[3] - bounds[1]);
            _animalTargetCountdown[a.id] = 10 + _rng.nextInt(20);
            final updated = a.copyWith(targetX: tx, targetY: ty);
            return _moveAnimalTowardTarget(updated);
          } else {
            _animalTargetCountdown[a.id] = countdown - 1;
            return _moveAnimalTowardTarget(a);
          }
        }).toList();
    if (!_animalCtrl.isClosed) _animalCtrl.add(_animals);
  }

  AnimalModel _moveAnimalTowardTarget(AnimalModel a) {
    const speed = 0.0018; // movement per tick
    final dx = a.targetX - a.x;
    final dy = a.targetY - a.y;
    final dist = sqrt(dx * dx + dy * dy);
    if (dist < 0.002) return a;
    final nx = a.x + (dx / dist) * speed;
    final ny = a.y + (dy / dist) * speed;
    return a.copyWith(x: nx, y: ny);
  }

  // Vehicles move along their defined road paths
  void _tickVehicles() {
    for (int i = 0; i < _vehicles.length; i++) {
      final v = _vehicles[i];
      if (v.status == VehicleStatus.parked) continue;
      final route = MapPaths.jeepRoutes[v.id];
      if (route == null || route.length < 2) continue;

      switch (v.detourState) {
        case JeepDetourState.stopping:
          _vehicles[i].speed = (_vehicles[i].speed * 0.82).clamp(0.5, 20);
          _vehicles[i].detourTimer -= 0.08;
          if (_vehicles[i].detourTimer <= 0) {
            _vehicles[i].detourState = JeepDetourState.detouringAround;
            _vehicles[i].detourTimer = 2.8;
            final ang = PathInterpolator.heading(route, _vehicles[i].pathIndex) * pi / 180;
            _vehicles[i].detourOffsetX = -sin(ang) * 0.038;
            _vehicles[i].detourOffsetY = cos(ang) * 0.038;
          }
          break;

        case JeepDetourState.detouringAround:
          _vehicles[i].detourTimer -= 0.08;
          var np = v.pathProgress + 0.001;
          var ni = v.pathIndex;
          while (np >= 1.0) { np -= 1.0; ni = (ni + 1) % (route.length - 1); }
          final pos = PathInterpolator.lerp(route, ni, np);
          _vehicles[i].x = (pos.dx + _vehicles[i].detourOffsetX).clamp(0.02, 0.98);
          _vehicles[i].y = (pos.dy + _vehicles[i].detourOffsetY).clamp(0.02, 0.98);
          _vehicles[i].pathIndex = ni;
          _vehicles[i].pathProgress = np;
          _vehicles[i].speed = 4;
          if (_vehicles[i].detourTimer <= 0) {
            _vehicles[i].detourState = JeepDetourState.returning;
            _vehicles[i].detourTimer = 1.2;
          }
          break;

        case JeepDetourState.returning:
          _vehicles[i].detourTimer -= 0.08;
          _vehicles[i].detourOffsetX *= 0.88;
          _vehicles[i].detourOffsetY *= 0.88;
          if (_vehicles[i].detourTimer <= 0) {
            _vehicles[i].detourState = JeepDetourState.onPath;
            _vehicles[i].detourOffsetX = 0;
            _vehicles[i].detourOffsetY = 0;
            _vehicles[i].blockedByAnimal = null;
          }
          break;

        case JeepDetourState.onPath:
          final spd = v.status == VehicleStatus.alert ? 0.0026 : 0.0015;
          var np2 = v.pathProgress + spd;
          var ni2 = v.pathIndex;
          while (np2 >= 1.0) { np2 -= 1.0; ni2 = (ni2 + 1) % (route.length - 1); }
          final pos2 = PathInterpolator.lerp(route, ni2, np2);
          final hdg = PathInterpolator.heading(route, ni2);
          // Check for on-road animal encounter
          if (v.blockedByAnimal == null) {
            for (final oa in MapPaths.onRoadAnimals) {
              final ap = oa['pos'] as List<dynamic>;
              final dx = pos2.dx - (ap[0] as double);
              final dy = pos2.dy - (ap[1] as double);
              if (sqrt(dx*dx + dy*dy) < 0.04) {
                _vehicles[i].detourState = JeepDetourState.stopping;
                _vehicles[i].detourTimer = 1.5;
                _vehicles[i].blockedByAnimal = oa['animal'] as String;
                break;
              }
            }
          }
          if (_vehicles[i].detourState == JeepDetourState.onPath) {
            _vehicles[i].x = pos2.dx;
            _vehicles[i].y = pos2.dy;
            _vehicles[i].direction = hdg;
            _vehicles[i].speed = (_vehicles[i].speed + (_rng.nextDouble()-0.5)*0.3).clamp(2, 20);
            _vehicles[i].pathIndex = ni2;
            _vehicles[i].pathProgress = np2;
            _vehicles[i].pirTriggered = _rng.nextDouble() < 0.025;
          }
          break;
      }
    }
    if (!_vehicleCtrl.isClosed) _vehicleCtrl.add(List.from(_vehicles));
  }

  void _tickImu() {
    _heading = (_heading + _rng.nextDouble() * 0.4) % 360;
    final imu = ImuData(
      ax: (_rng.nextDouble() - 0.5) * 0.9,
      ay: (_rng.nextDouble() - 0.5) * 0.9,
      az: 9.81 + (_rng.nextDouble() - 0.5) * 0.08,
      gx: (_rng.nextDouble() - 0.5) * 9,
      gy: (_rng.nextDouble() - 0.5) * 9,
      gz: (_rng.nextDouble() - 0.5) * 4,
      mx: (_rng.nextDouble() - 0.5) * 48,
      my: (_rng.nextDouble() - 0.5) * 48,
      mz: (_rng.nextDouble() - 0.5) * 48,
      temperature: 28 + _rng.nextDouble() * 7,
      pressure: 1013 + _rng.nextDouble() * 4,
      heading: _heading,
      altitude: 820 + _rng.nextDouble() * 10,
      timestamp: DateTime.now(),
    );
    if (!_imuCtrl.isClosed) _imuCtrl.add(imu);
  }

  void _tickAlert() {
    final msgs = [
      AlertModel(
        id: _rng.nextInt(999999).toString(),
        emoji: '🦁',
        title: 'Lion movement detected',
        message: 'PIR sensor triggered in Zone B sector 2',
        type: AlertType.critical,
        time: DateTime.now(),
      ),
      AlertModel(
        id: _rng.nextInt(999999).toString(),
        emoji: '⚡',
        title: 'Node battery critical',
        message:
        'Node-${_rng.nextInt(14) + 1} at ${_rng.nextInt(15) + 5}% battery.',
        type: AlertType.warning,
        time: DateTime.now(),
      ),
      AlertModel(
        id: _rng.nextInt(999999).toString(),
        emoji: '🐘',
        title: 'Elephant herd crossing road',
        message: '5 elephants crossing Zone A service road.',
        type: AlertType.info,
        time: DateTime.now(),
      ),
      AlertModel(
        id: _rng.nextInt(999999).toString(),
        emoji: '🚙',
        title: 'Vehicle speeding detected',
        message: 'Jeep exceeded 15km/h safety limit.',
        type: AlertType.warning,
        time: DateTime.now(),
      ),
    ];
    if (!_alertCtrl.isClosed) _alertCtrl.add(msgs[_rng.nextInt(msgs.length)]);
  }

  void triggerSOS(VehicleModel v, String triggeredBy) {
    final sos = AlertModel(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      emoji: '🆘',
      title: 'SOS ALERT — ${v.name}',
      message: 'Emergency triggered by $triggeredBy at Zone ${v.zone}. '
          'Location: (${(v.x*100).toStringAsFixed(1)}%, ${(v.y*100).toStringAsFixed(1)}%)',
      type: AlertType.critical,
      time: DateTime.now(),
      isSOS: true,
      sosLat: -2.3124 + v.y * 0.05,
      sosLng: 36.8219 + v.x * 0.05,
      sosVehicleId: v.id,
      sosVehicleName: v.name,
      sosTriggerBy: triggeredBy,
    );
    if (!_alertCtrl.isClosed) _alertCtrl.add(sos);
  }

  void dispose() {
    stop();
    _animalCtrl.close();
    _vehicleCtrl.close();
    _imuCtrl.close();
    _alertCtrl.close();
    _trackCtrl.close();
    _aqiCtrl.close();
    _detCtrl.close();
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// PROVIDER — role-aware state
// ─────────────────────────────────────────────────────────────────────────────
class SProvider extends ChangeNotifier {
  final _sim = SimService();
  final _rng = Random();

  FirebaseFirestore? _fs;
  FirebaseDatabase? _rtdb;

  StreamSubscription<QuerySnapshot>? _animalSub, _alertSub;
  StreamSubscription<DatabaseEvent>? _vehicleSub, _imuSub, _car1Sub, _aqiRtdbSub, _cmdSub;
  StreamSubscription<TrackCarTelemetry>? _trackSimSub;
  StreamSubscription<AqiReading>? _aqiSimSub;
  StreamSubscription<List<LiveDetection>>? _detSimSub;

  UserRole role = UserRole.tourist;
  String userName = '', uid = '', userPhone = '', userEmail = '';
  String? assignedVehicleId; // for driver role

  List<AnimalModel> animals = [];
  List<VehicleModel> vehicles = [];
  List<AlertModel> alerts = List.from(SD.alerts);
  ImuData? imuData;

  bool isOnline = true,
      showHeatmap = false,
      replayMode = false,
      fbConnected = false;

  List<BookingModel> myBookings = [];
  Map<String, int> slotBookedCounts = {};
  StreamSubscription<QuerySnapshot>? _slotSub;

  String? selectedAnimalId, focusedVehicleId;
  Map<String, bool> layers = {
    'animals': true,
    'vehicles': true,
    'zones': true,
    'paths': true,
    'hotspots': false,
    'hackathonTrack': false,
    'checkpoints': true,
  };

  double wsLatency = 18, jeepSpeed = 12, lat = -2.3124, lng = 36.8219;
  String heading = '087°';
  int espNodes = 12;
  String weather = '34°C ☀';
  int humidity = 62;

  // UNPLUGGED / hardware fusion
  AqiReading? aqiData;
  List<LiveDetection> liveDetections = [];
  String? lastAdminCommand;
  DateTime? lastAdminCommandAt;
  Duration trackRunElapsed = Duration.zero;
  DateTime? _trackRunStartedAt;
  bool rfidFinishSeen = false;
  int missionDetectionCount = 0;
  TrackCarTelemetry? _simTrackTelemetry, _hwTrackTelemetry;
  TrackCarTelemetry? get trackTelemetry =>
      _hwTrackTelemetry ?? _simTrackTelemetry;

  // Role-based feature gates
  bool get canSeeAnalytics => role == UserRole.admin;
  bool get canSeeFleet => role == UserRole.admin || role == UserRole.driver;
  bool get canSeeImu => role == UserRole.admin || role == UserRole.driver;
  bool get canSeeTickets => role == UserRole.tourist || role == UserRole.admin;
  bool get canSeeRoutes => true;
  bool get canSeeMap => true;
  bool get canSeeLineFollower =>
      role == UserRole.driver || role == UserRole.admin || role == UserRole.tourist;
  bool get isAdmin => role == UserRole.admin;
  bool get isDriver => role == UserRole.driver;
  bool get isTourist => role == UserRole.tourist;

  // v3.0 — convenience getter that maps AqiReading to AqiData for new screens
  AqiData? get aqiDataV3 {
    final a = aqiData;
    if (a == null) return null;
    return AqiData(
      temperature: a.temperature,
      humidity: a.humidity,
      aqiIndex: a.aqi.toInt(),
      pm25: a.pm25,
      co2: 420, // default — update when sensor sends CO2
      status: a.aqi <= 50 ? 'Good' : a.aqi <= 100 ? 'Moderate' : 'Unhealthy',
      timestamp: a.timestamp,
    );
  }

  int get unreadAlerts =>
      alerts.where((a) => !a.isRead && a.type == AlertType.critical).length;

  int get activeVehicles => vehicles.where((v) => v.status == VehicleStatus.active || v.status == VehicleStatus.alert).length;
  List<AlertModel> get sosAlerts => alerts.where((a) => a.isSOS && !a.isRead).toList();

  // Get next 7 days of slots for a ticket type
  List<SlotModel> getSlotsForTicket(String ticketTypeId) {
    final now = DateTime.now();
    final timeMap = {'t1':'06:00 – 12:00', 't2':'06:00 – 18:00', 't3':'15:00 – 19:00'};
    return List.generate(7, (d) {
      final date = now.add(Duration(days: d));
      final dateStr = '${date.year}-${date.month.toString().padLeft(2,'0')}-${date.day.toString().padLeft(2,'0')}';
      final slotId = '${ticketTypeId}_$dateStr';
      return SlotModel(
        id: slotId, ticketTypeId: ticketTypeId, date: dateStr,
        timeLabel: timeMap[ticketTypeId] ?? '06:00 – 18:00',
        maxCapacity: 20, bookedCount: slotBookedCounts[slotId] ?? 0,
      );
    });
  }

  // Get role-appropriate alerts (tourists see simplified versions)
  List<AlertModel> get visibleAlerts {
    if (isTourist)
      return alerts
          .where((a) => a.type != AlertType.info || a.emoji == '🐘')
          .take(5)
          .toList();
    return alerts;
  }

  void init(
      UserRole r,
      String name, {
        String phone = '',
        String email = '',
        String? vehicleId,
      }) {
    role = r;
    userName = name;
    userPhone = phone;
    userEmail = email;
    assignedVehicleId = vehicleId;

    if (_firebaseConfigured) {
      try {
        uid = FirebaseAuth.instance.currentUser?.uid ?? 'anon';
        _fs = FirebaseFirestore.instance;
        _rtdb = FirebaseDatabase.instance;
      } catch (_) {}
    }

    animals = List.from(SD.animals);
    vehicles = SD.buildVehicles();

    _sim.start();
    _sim.imu.listen((d) {
      imuData = d;
      heading = '${d.heading.toStringAsFixed(0).padLeft(3, '0')}°';
      _pushImuToRtdb(d);
      notifyListeners();
    });
    _sim.alert.listen((a) {
      _pushAlertToFirestore(a);
      alerts.insert(0, a);
      if (alerts.length > 40) alerts.removeLast();
      notifyListeners();
    });
    _sim.animals.listen((list) {
      animals = list;
      notifyListeners();
    });
    _sim.vehicles.listen((list) {
      vehicles = list;
      _updateStats();
      notifyListeners();
    });

    _trackRunStartedAt = DateTime.now();
    _trackSimSub = _sim.trackCar.listen((t) {
      _simTrackTelemetry = t;
      trackRunElapsed = DateTime.now().difference(_trackRunStartedAt!);
      notifyListeners();
    });
    _aqiSimSub = _sim.aqi.listen((a) {
      aqiData = a;
      weather = '${a.temperature.toStringAsFixed(0)}°C ${_weatherEmoji(a)}';
      humidity = a.humidity.round();
      if (_firebaseConfigured) _pushAqiToRtdb(a);
      notifyListeners();
    });
    _detSimSub = _sim.detections.listen((d) {
      liveDetections = d;
      missionDetectionCount = d.length;
      notifyListeners();
    });

    if (_firebaseConfigured) {
      _subscribeFirestore();
      _subscribeRtdb();
      _subscribeRtdbMission();
      _subscribeSlots();
      _loadMyBookings();
      _seedFirestoreIfEmpty();
    }
    if (isDriver) {
      layers['hackathonTrack'] = true;
    }
  }

  String _weatherEmoji(AqiReading a) {
    if (a.rainChance4h > 45) return '🌧';
    if (a.aqi > 150) return '😷';
    if (a.temperature > 33) return '☀';
    return '⛅';
  }

  /// Admin / web — remote control payload consumed by ESP32 (see `admin/commands/car_1`).
  Future<void> sendAdminVehicleCommand(String action,
      {double speed = 0, String mode = 'auto'}) async {
    lastAdminCommand = '$action · ${speed.toStringAsFixed(0)} · $mode';
    lastAdminCommandAt = DateTime.now();
    if (!_firebaseConfigured || _rtdb == null) {
      notifyListeners();
      return;
    }
    await _rtdb!.ref('admin/commands/car_1').set({
      'action': action,
      'speed': speed,
      'mode': mode,
      'issuedBy': userName,
      'ts': ServerValue.timestamp,
    }).catchError((_) {});
    notifyListeners();
  }

  void _subscribeRtdbMission() {
    if (!_firebaseConfigured || _rtdb == null) return;
    _rtdb!.ref('missions/current').onValue.listen((ev) {
      final raw = ev.snapshot.value;
      if (raw is! Map) return;
      final m = Map<String, dynamic>.from(raw);
      rfidFinishSeen = m['rfidFinished'] == true;
      notifyListeners();
    });
  }

  void _pushAqiToRtdb(AqiReading a) {
    if (!_firebaseConfigured || _rtdb == null) return;
    _rtdb!.ref('env/aqi').set({
      'pm25': a.pm25,
      'pm10': a.pm10,
      'aqi': a.aqi,
      'temp': a.temperature,
      'humidity': a.humidity,
      'rainChance4h': a.rainChance4h,
      'forecast': a.forecastSummary,
      'ts': ServerValue.timestamp,
    }).catchError((_) {});
  }

  void _subscribeFirestore() {
    _animalSub = _fs!.collection('animals').snapshots().listen((snap) {
      if (snap.docs.isEmpty) return;
      fbConnected = true;
      animals =
          snap.docs.map((d) {
            final data = d.data();
            return AnimalModel(
              id: d.id,
              name: data['name'] ?? 'Unknown',
              species: data['species'] ?? '',
              emoji: data['emoji'] ?? '🐾',
              color: Color(
                int.tryParse(data['colorHex'] ?? '0xFF6EDB75') ?? 0xFF6EDB75,
              ),
              zone: data['zone'] ?? 'A',
              status: data['status'] ?? 'Active',
              detectedBy: data['detectedBy'] ?? 'ESP32-CAM',
              x: (data['x'] ?? 0.5).toDouble(),
              y: (data['y'] ?? 0.5).toDouble(),
              confidence: (data['confidence'] ?? 0.8).toDouble(),
              lastSeen:
              (data['lastSeen'] as Timestamp?)?.toDate() ?? DateTime.now(),
              sightingCount: data['sightingCount'] ?? 0,
            );
          }).toList();
      notifyListeners();
    }, onError: (_) => fbConnected = false);

    _alertSub = _fs!
        .collection('alerts')
        .orderBy('time', descending: true)
        .limit(20)
        .snapshots()
        .listen((snap) {
      if (snap.docs.isEmpty) return;
      alerts =
          snap.docs.map((d) {
            final data = d.data();
            return AlertModel(
              id: d.id,
              emoji: data['emoji'] ?? '📡',
              title: data['title'] ?? '',
              message: data['message'] ?? '',
              type:AlertType.values.firstWhere((t)=>t.name==(data['type']??'info'), orElse:()=>AlertType.info),
              time:(data['time'] as Timestamp?)?.toDate()??DateTime.now(),
              isRead:data['isRead']??false,
              isSOS:data['isSOS']??false,
              sosLat:(data['sosLat'] as num?)?.toDouble(),
              sosLng:(data['sosLng'] as num?)?.toDouble(),
              sosVehicleId:data['sosVehicleId'],
              sosVehicleName:data['sosVehicleName'],
              sosTriggerBy:data['sosTriggerBy'],
            );
          }).toList();
      notifyListeners();
    }, onError: (_) {});
  }

  void _subscribeSlots() {
    if (!_firebaseConfigured || _fs == null) return;
    _slotSub = _fs!.collection('slots').snapshots().listen((snap) {
      for (final doc in snap.docs) {
        slotBookedCounts[doc.id] = (doc.data()['bookedCount'] as num?)?.toInt() ?? 0;
      }
      notifyListeners();
    });
  }

  Future<void> _loadMyBookings() async {
    if (!_firebaseConfigured || _fs == null || uid.isEmpty) return;
    try {
      final snap = await _fs!.collection('bookings')
          .where('userId', isEqualTo: uid)
          .orderBy('bookedAt', descending: true)
          .get();
      myBookings = snap.docs.map((d) {
        final data = d.data();
        return BookingModel(
          bookingId: data['bookingId'] ?? d.id,
          ticketType: data['type'] ?? '',
          ticketTypeId: data['ticketTypeId'] ?? '',
          date: data['date'] ?? '',
          timeSlot: data['timeSlot'] ?? '',
          userId: uid,
          userName: data['userName'] ?? '',
          userEmail: data['userEmail'] ?? '',
          userPhone: data['userPhone'] ?? '',
          price: (data['price'] as num?)?.toDouble() ?? 0,
          qrData: data['qrData'] ?? '',
          bookedAt: (data['bookedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
        );
      }).toList();
      notifyListeners();
    } catch (_) {}
  }

  /// Books a slot atomically — returns bookingId on success, null if slot is full
  Future<String?> bookSlot(String slotId, String ticketTypeId, String date,
      String timeSlot, double price, String type) async {
    final bookingId = _generateBookingId();
    final qrData = generateQrData(bookingId, ticketTypeId);

    if (_firebaseConfigured && _fs != null) {
      try {
        await _fs!.runTransaction((tx) async {
          final slotRef = _fs!.collection('slots').doc(slotId);
          final slotDoc = await tx.get(slotRef);
          final current = slotDoc.exists
              ? (slotDoc.data()?['bookedCount'] as num?)?.toInt() ?? 0
              : 0;
          if (current >= 20) throw Exception('SLOT_FULL');
          tx.set(slotRef, {
            'ticketTypeId': ticketTypeId, 'date': date,
            'bookedCount': current + 1, 'maxCapacity': 20,
          }, SetOptions(merge: true));
          final bookRef = _fs!.collection('bookings').doc();
          tx.set(bookRef, {
            'bookingId': bookingId, 'userId': uid, 'userName': userName,
            'userEmail': userEmail, 'userPhone': userPhone,
            'type': type, 'ticketTypeId': ticketTypeId,
            'slotId': slotId, 'date': date, 'timeSlot': timeSlot,
            'price': price, 'qrData': qrData,
            'bookedAt': FieldValue.serverTimestamp(), 'status': 'confirmed',
          });
        });
        slotBookedCounts[slotId] = (slotBookedCounts[slotId] ?? 0) + 1;
        // Add locally immediately so UI updates even if _loadMyBookings is slow
        myBookings.insert(0, BookingModel(
          bookingId: bookingId, ticketType: type, ticketTypeId: ticketTypeId,
          date: date, timeSlot: timeSlot, userId: uid, userName: userName,
          userEmail: userEmail, userPhone: userPhone, price: price,
          qrData: qrData, bookedAt: DateTime.now(),
        ));
        _sendConfirmation(bookingId, type, date, timeSlot, price, qrData);
        notifyListeners();
        // Also try to refresh from Firestore (non-blocking)
        _loadMyBookings().catchError((_) {});
        return bookingId;
      } catch (e) {
        if (e.toString().contains('SLOT_FULL')) return null;
        // Firebase write failed — fall back to local demo mode
        slotBookedCounts[slotId] = (slotBookedCounts[slotId] ?? 0) + 1;
        myBookings.insert(0, BookingModel(
          bookingId: bookingId, ticketType: type, ticketTypeId: ticketTypeId,
          date: date, timeSlot: timeSlot, userId: 'local', userName: userName,
          userEmail: userEmail, userPhone: userPhone, price: price,
          qrData: qrData, bookedAt: DateTime.now(),
        ));
        _sendConfirmation(bookingId, type, date, timeSlot, price, qrData);
        notifyListeners();
        return bookingId;
      }
    } else {
      // ── Demo / simulation mode ──
      slotBookedCounts[slotId] = (slotBookedCounts[slotId] ?? 0) + 1;
      myBookings.insert(0, BookingModel(
        bookingId: bookingId, ticketType: type, ticketTypeId: ticketTypeId,
        date: date, timeSlot: timeSlot, userId: 'demo', userName: userName,
        userEmail: userEmail, userPhone: userPhone, price: price,
        qrData: qrData, bookedAt: DateTime.now(),
      ));
      _sendConfirmation(bookingId, type, date, timeSlot, price, qrData);
      notifyListeners();
      return bookingId;
    }
  }

  Future<String?> adminBookForTourist({
    required String touristName,
    required String touristEmail,
    required String touristPhone,
    required String ticketTypeId,
    required String date,
    required String timeSlot,
    required double price,
    required String type,
  }) async {
    final bookingId = _generateBookingId();
    // Use tourist UID if Firebase, else 'tourist_offline'
    final touristUid = _firebaseConfigured
        ? 'offline_${DateTime.now().millisecondsSinceEpoch}'
        : 'tourist_offline';
    final qrData = 'SAFARISYNC|BID:$bookingId|TID:$ticketTypeId|UID:$touristUid'
        '|NAME:$touristName|TS:${DateTime.now().toIso8601String()}|VER:2.2';
    final slotId = '${ticketTypeId}_$date';

    if (_firebaseConfigured && _fs != null) {
      try {
        await _fs!.runTransaction((tx) async {
          final slotRef = _fs!.collection('slots').doc(slotId);
          final slotDoc = await tx.get(slotRef);
          final current = slotDoc.exists
              ? (slotDoc.data()?['bookedCount'] as num?)?.toInt() ?? 0
              : 0;
          if (current >= 20) throw Exception('SLOT_FULL');
          tx.set(slotRef, {
            'ticketTypeId': ticketTypeId,
            'date': date,
            'bookedCount': current + 1,
            'maxCapacity': 20,
          }, SetOptions(merge: true));
          final bookRef = _fs!.collection('bookings').doc();
          tx.set(bookRef, {
            'bookingId': bookingId,
            'userId': touristUid,
            'userName': touristName,
            'userEmail': touristEmail,
            'userPhone': touristPhone,
            'type': type,
            'ticketTypeId': ticketTypeId,
            'slotId': slotId,
            'date': date,
            'timeSlot': timeSlot,
            'price': price,
            'qrData': qrData,
            'bookedAt': FieldValue.serverTimestamp(),
            'status': 'confirmed',
            'bookedByAdmin': true,
            'adminName': userName,
          });
        });
      } catch (_) {
        return null;
      }
    }

    slotBookedCounts[slotId] = (slotBookedCounts[slotId] ?? 0) + 1;

    // Add to local myBookings so admin can see it immediately
    myBookings.insert(
        0,
        BookingModel(
          bookingId: bookingId,
          ticketType: type,
          ticketTypeId: ticketTypeId,
          date: date,
          timeSlot: timeSlot,
          userId: touristUid,
          userName: touristName,
          userEmail: touristEmail,
          userPhone: touristPhone,
          price: price,
          qrData: qrData,
          bookedAt: DateTime.now(),
        ));

    // Simulated notifications to tourist
    debugPrint('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
    debugPrint('📧 EMAIL → $touristEmail');
    debugPrint('   Subject: Your SafariSync Booking Confirmation');
    debugPrint('   Hi $touristName! Your booking has been confirmed.');
    debugPrint('   Booking ID: $bookingId');
    debugPrint('   Package: $type');
    debugPrint('   Date: $date  Slot: $timeSlot');
    debugPrint('   Amount Paid: ₹${price.toStringAsFixed(0)}');
    debugPrint('   Show the QR code below at the entry gate.');
    debugPrint('   QR Data: $qrData');
    debugPrint('📱 SMS → $touristPhone');
    debugPrint(
        '   SafariSync: Hi $touristName, booking $bookingId confirmed for $type on $date ($timeSlot). Show QR at gate. -SafariSync');
    debugPrint('🔔 PUSH → $touristPhone: Your safari is booked! Tap to see QR.');
    debugPrint('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');

    notifyListeners();
    return bookingId;
  }

  void _sendConfirmation(String bookingId, String type, String date,
      String timeSlot, double price, String qrData) {
    // ── Production: call Firebase Cloud Function / Twilio / SendGrid ──
    // For simulation, just log:
    debugPrint('📧 EMAIL → $userEmail | Booking $bookingId | $type $date $timeSlot | ₹$price');
    debugPrint('📱 SMS → $userPhone | SafariSync: Your $type on $date ($timeSlot) is confirmed. ID: $bookingId');
  }

  void triggerSOS() {
    VehicleModel? v;
    if (assignedVehicleId != null)
      v = vehicles.cast<VehicleModel?>().firstWhere((vv) => vv?.id == assignedVehicleId, orElse: () => null);
    v ??= vehicles.isNotEmpty ? vehicles.first : null;
    if (v == null) return;
    _sim.triggerSOS(v, userName);
    final idx = vehicles.indexWhere((vv) => vv.id == v!.id);
    if (idx >= 0) vehicles[idx].status = VehicleStatus.alert;
    if (_firebaseConfigured && _fs != null) {
      _fs!.collection('sos_events').add({
        'triggeredBy': userName, 'userId': uid, 'role': role.name,
        'vehicleId': v.id, 'vehicleName': v.name, 'zone': v.zone,
        'x': v.x, 'y': v.y,
        'lat': -2.3124 + v.y * 0.05, 'lng': 36.8219 + v.x * 0.05,
        'timestamp': FieldValue.serverTimestamp(),
      }).catchError((_){});
    }
    notifyListeners();
  }

  void _subscribeRtdb() {
    _vehicleSub = _rtdb!.ref('vehicles').onValue.listen((event) {
      final raw = event.snapshot.value;
      if (raw == null) return;
      final map = Map<String, dynamic>.from(raw as Map);
      vehicles =
          map.entries
              .where((e) => e.key != 'car_1')
              .map((e) {
            final d = Map<String, dynamic>.from(e.value as Map);
            return VehicleModel(
              id: e.key,
              name: d['name'] ?? e.key,
              driverName: d['driverName'] ?? 'Driver',
              zone: d['zone'] ?? 'Base',
              x: (d['x'] ?? 0.5).toDouble(),
              y: (d['y'] ?? 0.5).toDouble(),
              direction: (d['direction'] ?? 0).toDouble(),
              speed: (d['speed'] ?? 0).toDouble(),
              batteryLevel: (d['batteryLevel'] ?? 100).toDouble(),
              fuelLevel: (d['fuelLevel'] ?? 100).toDouble(),
              passengers: d['passengers'] ?? 0,
              status: VehicleStatus.values.firstWhere(
                    (s) => s.name == (d['status'] ?? 'parked'),
                orElse: () => VehicleStatus.parked,
              ),
              pirTriggered: d['pirTriggered'] ?? false,
            );
          }).toList();
      _updateStats();
      notifyListeners();
    }, onError: (_) {});

    _imuSub = _rtdb!.ref('imu/jeep_1').onValue.listen((event) {
      final raw = event.snapshot.value;
      if (raw == null) return;
      final d = Map<String, dynamic>.from(raw as Map);
      final accel = Map<String, dynamic>.from(d['accel'] ?? {});
      final gyro = Map<String, dynamic>.from(d['gyro'] ?? {});
      final mag = Map<String, dynamic>.from(d['mag'] ?? {});
      final bmp = Map<String, dynamic>.from(d['bmp'] ?? {});
      imuData = ImuData(
        ax: (accel['x'] ?? 0).toDouble(),
        ay: (accel['y'] ?? 0).toDouble(),
        az: (accel['z'] ?? 9.81).toDouble(),
        gx: (gyro['x'] ?? 0).toDouble(),
        gy: (gyro['y'] ?? 0).toDouble(),
        gz: (gyro['z'] ?? 0).toDouble(),
        mx: (mag['x'] ?? 0).toDouble(),
        my: (mag['y'] ?? 0).toDouble(),
        mz: (mag['z'] ?? 0).toDouble(),
        temperature: (bmp['temp'] ?? 28).toDouble(),
        pressure: (bmp['pressure'] ?? 1013).toDouble(),
        altitude: (bmp['alt'] ?? 820).toDouble(),
        heading: (d['heading'] ?? 0).toDouble(),
        timestamp: DateTime.now(),
      );
      heading = '${imuData!.heading.toStringAsFixed(0).padLeft(3, '0')}°';
      notifyListeners();
    }, onError: (_) {});

    _car1Sub = _rtdb!.ref('vehicles/car_1').onValue.listen((event) {
      final raw = event.snapshot.value;
      if (raw is! Map) {
        _hwTrackTelemetry = null;
        notifyListeners();
        return;
      }
      final d = Map<String, dynamic>.from(raw);
      _hwTrackTelemetry = TrackCarTelemetry(
        x: (d['x'] ?? 0.5).toDouble(),
        y: (d['y'] ?? 0.5).toDouble(),
        direction: (d['direction'] ?? 0).toDouble(),
        speed: (d['speed'] ?? 0).toDouble(),
        pathIndex: (d['pathIndex'] as num?)?.toInt() ?? 0,
        pathProgress: (d['pathProgress'] as num?)?.toDouble() ?? 0,
        inTelemetryDashedZone: d['inDataZone'] == true,
      );
      notifyListeners();
    }, onError: (_) {});

    _aqiRtdbSub = _rtdb!.ref('env/aqi').onValue.listen((event) {
      final raw = event.snapshot.value;
      if (raw is! Map) return;
      final m = Map<String, dynamic>.from(raw);
      aqiData = AqiReading(
        pm25: (m['pm25'] as num?)?.toDouble() ?? 0,
        pm10: (m['pm10'] as num?)?.toDouble() ?? 0,
        aqi: (m['aqi'] as num?)?.toDouble() ?? 0,
        temperature: (m['temp'] as num?)?.toDouble() ?? 28,
        humidity: (m['humidity'] as num?)?.toDouble() ?? 50,
        rainChance4h: (m['rainChance4h'] as num?)?.toInt() ?? 0,
        forecastSummary: m['forecast']?.toString() ?? '—',
        timestamp: DateTime.now(),
      );
      weather =
          '${aqiData!.temperature.toStringAsFixed(0)}°C ${_weatherEmoji(aqiData!)}';
      humidity = aqiData!.humidity.round();
      notifyListeners();
    }, onError: (_) {});

    _cmdSub = _rtdb!.ref('admin/commands/car_1').onValue.listen((event) {
      final raw = event.snapshot.value;
      if (raw is! Map) return;
      final d = Map<String, dynamic>.from(raw);
      final a = d['action']?.toString();
      if (a == null || a.isEmpty) return;
      lastAdminCommand =
          '$a · spd ${(d['speed'] as num?)?.toString() ?? '0'} · ${d['mode'] ?? ''}';
      lastAdminCommandAt = DateTime.now();
      notifyListeners();
    }, onError: (_) {});
  }

  void _pushAlertToFirestore(AlertModel a) {
    if (!_firebaseConfigured || _fs == null) return;
    _fs!.collection('alerts').add({
      'emoji': a.emoji, 'title': a.title, 'message': a.message,
      'type': a.type.name, 'time': FieldValue.serverTimestamp(), 'isRead': false,
      'isSOS': a.isSOS, 'sosLat': a.sosLat, 'sosLng': a.sosLng,
      'sosVehicleId': a.sosVehicleId, 'sosVehicleName': a.sosVehicleName,
      'sosTriggerBy': a.sosTriggerBy,
    }).catchError((_){});
  }

  void _pushImuToRtdb(ImuData d) {
    if (!_firebaseConfigured || _rtdb == null) return;
    _rtdb!
        .ref('imu/jeep_1')
        .update({
      'accel': {'x': d.ax, 'y': d.ay, 'z': d.az},
      'gyro': {'x': d.gx, 'y': d.gy, 'z': d.gz},
      'mag': {'x': d.mx, 'y': d.my, 'z': d.mz},
      'bmp': {
        'temp': d.temperature,
        'pressure': d.pressure,
        'alt': d.altitude,
      },
      'heading': d.heading,
      'ts': ServerValue.timestamp,
    })
        .catchError((_) {});
  }

  String _generateBookingId() {
    final ts = DateTime.now().millisecondsSinceEpoch;
    final rand = _rng.nextInt(9999).toString().padLeft(4, '0');
    return 'SS-${ts.toString().substring(7)}$rand';
  }

  String generateQrData(String bookingId, String ticketId) {
    final ts = DateTime.now().toIso8601String();
    final nonce = _rng.nextInt(999999).toString().padLeft(6, '0');
    return 'SAFARISYNC|BID:$bookingId|TID:$ticketId|UID:$uid|TS:$ts|NONCE:$nonce|VER:2.2';
  }

  Future<String> bookTicket(
      String ticketId,
      String type,
      double price,
      String slot,
      ) async {
    final bookingId = _generateBookingId();
    if (_firebaseConfigured && _fs != null) {
      try {
        await _fs!.collection('bookings').add({
          'userId': uid,
          'ticketId': ticketId,
          'type': type,
          'price': price,
          'timeSlot': slot,
          'bookingId': bookingId,
          'bookedAt': FieldValue.serverTimestamp(),
          'status': 'confirmed',
          'qrData': generateQrData(bookingId, ticketId),
          'userName': userName,
          'userPhone': userPhone,
        });
      } catch (_) {}
    }
    return bookingId;
  }

  Future<void> _seedFirestoreIfEmpty() async {
    if (!_firebaseConfigured || _fs == null) return;
    try {
      final snap = await _fs!.collection('animals').limit(1).get();
      if (snap.docs.isNotEmpty) return;
      final batch = _fs!.batch();
      for (final a in SD.animals) {
        batch.set(_fs!.collection('animals').doc(a.id), {
          'name': a.name,
          'species': a.species,
          'emoji': a.emoji,
          'colorHex':
          '0xFF${a.color.value.toRadixString(16).padLeft(8, '0').substring(2)}',
          'zone': a.zone,
          'status': a.status,
          'detectedBy': a.detectedBy,
          'x': a.x,
          'y': a.y,
          'confidence': a.confidence,
          'sightingCount': a.sightingCount,
          'lastSeen': FieldValue.serverTimestamp(),
        });
      }
      await batch.commit();
      for (final v in SD.buildVehicles()) {
        await _rtdb!.ref('vehicles/${v.id}').set({
          'name': v.name,
          'driverName': v.driverName,
          'zone': v.zone,
          'x': v.x,
          'y': v.y,
          'direction': v.direction,
          'speed': v.speed,
          'batteryLevel': v.batteryLevel,
          'fuelLevel': v.fuelLevel,
          'passengers': v.passengers,
          'status': v.status.name,
          'pirTriggered': false,
        });
      }
    } catch (_) {}
  }

  void _updateStats() {
    wsLatency = 8 + _rng.nextDouble() * 22;
    jeepSpeed =
        vehicles
            .where((v) => v.status == VehicleStatus.active)
            .fold(0.0, (s, v) => s + v.speed) /
            max(1, vehicles.where((v) => v.status == VehicleStatus.active).length);
    lat += (_rng.nextDouble() - 0.5) * 0.00008;
    lng += (_rng.nextDouble() - 0.5) * 0.00008;
    espNodes = 11 + _rng.nextInt(3);
  }

  void toggleLayer(String k) {
    layers[k] = !(layers[k] ?? true);
    notifyListeners();
  }

  void toggleHeatmap() {
    showHeatmap = !showHeatmap;
    notifyListeners();
  }

  void toggleReplay() {
    replayMode = !replayMode;
    notifyListeners();
  }

  void toggleOnline() {
    isOnline = !isOnline;
    notifyListeners();
  }

  void selectAnimal(String? id) {
    selectedAnimalId = id;
    notifyListeners();
  }

  void focusVehicle(String id) {
    focusedVehicleId = id;
    notifyListeners();
  }

  void markRead(String id) {
    final i = alerts.indexWhere((a) => a.id == id);
    if (i != -1) {
      alerts[i].isRead = true;
      if (_firebaseConfigured && _fs != null)
        _fs!
            .collection('alerts')
            .doc(id)
            .update({'isRead': true})
            .catchError((_) {});
      notifyListeners();
    }
  }

  AnimalModel? getAnimal(String id) => animals.cast<AnimalModel?>().firstWhere(
        (a) => a?.id == id,
    orElse: () => null,
  );
  VehicleModel? getVehicle(String id) => vehicles
      .cast<VehicleModel?>()
      .firstWhere((v) => v?.id == id, orElse: () => null);

  @override
  void dispose() {
    _animalSub?.cancel();
    _alertSub?.cancel();
    _vehicleSub?.cancel();
    _imuSub?.cancel();
    _car1Sub?.cancel();
    _aqiRtdbSub?.cancel();
    _cmdSub?.cancel();
    _trackSimSub?.cancel();
    _aqiSimSub?.cancel();
    _detSimSub?.cancel();
    _slotSub?.cancel();
    _sim.dispose();
    super.dispose();
  }
}

class AdminOfflineBookingScreen extends StatefulWidget {
  const AdminOfflineBookingScreen({super.key});
  @override
  State<AdminOfflineBookingScreen> createState() =>
      _AdminOfflineBookingState();
}

class _AdminOfflineBookingState extends State<AdminOfflineBookingScreen> {
  final _nameC = TextEditingController();
  final _emailC = TextEditingController();
  final _phoneC = TextEditingController();
  String? _selectedTicketId;
  String? _selectedDate;
  bool _loading = false;
  String? _doneBookingId, _doneQr, _doneType;

  String _fmtDate(DateTime d) {
    const m = ['','Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    const w = ['Mon','Tue','Wed','Thu','Fri','Sat','Sun'];
    return '${w[d.weekday-1]}, ${d.day} ${m[d.month]}';
  }

  Future<void> _submit() async {
    if (_nameC.text.isEmpty || _emailC.text.isEmpty || _phoneC.text.isEmpty ||
        _selectedTicketId == null || _selectedDate == null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          backgroundColor: ST.red.withOpacity(0.9),
          content: Text('Please fill all fields and select a date.',
              style: ST.body(12, color: Colors.white))));
      return;
    }
    final tt = SD.tickets.firstWhere((t) => t.id == _selectedTicketId);
    setState(() => _loading = true);
    final prov = context.read<SProvider>();
    final id = await prov.adminBookForTourist(
      touristName: _nameC.text.trim(),
      touristEmail: _emailC.text.trim(),
      touristPhone: _phoneC.text.trim(),
      ticketTypeId: tt.id,
      date: _selectedDate!,
      timeSlot: tt.timeSlot,
      price: tt.price,
      type: tt.type,
    );
    if (mounted) {
      setState(() {
        _loading = false;
        if (id != null) {
          _doneBookingId = id;
          _doneQr = prov.generateQrData(id, tt.id);
          _doneType = tt.type;
        }
      });
      if (id == null) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            backgroundColor: ST.red.withOpacity(0.9),
            content: Text('Slot full or error. Try another date.',
                style: ST.body(12, color: Colors.white))));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_doneBookingId != null) {
      return Scaffold(
        backgroundColor: ST.bg,
        body: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Text('✅', style: TextStyle(fontSize: 56)),
              const SizedBox(height: 12),
              Text('BOOKING REGISTERED', style: ST.bebas(26)),
              Text(_doneType ?? '', style: ST.body(13, color: ST.t2)),
              Text(_nameC.text, style: ST.body(12, color: ST.t3)),
              const SizedBox(height: 16),
              Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12)),
                  child: QrImageView(
                      data: _doneQr!,
                      version: QrVersions.auto,
                      size: 180,
                      eyeStyle: const QrEyeStyle(
                          eyeShape: QrEyeShape.square, color: Colors.black),
                      dataModuleStyle: const QrDataModuleStyle(
                          dataModuleShape: QrDataModuleShape.square,
                          color: Colors.black))),
              const SizedBox(height: 10),
              Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 8),
                  decoration: ST.glowBox(ST.g1),
                  child: Text(_doneBookingId!,
                      style: ST
                          .mono(12, color: ST.g0)
                          .copyWith(letterSpacing: 1.5))),
              const SizedBox(height: 10),
              Container(
                  padding: const EdgeInsets.all(11),
                  decoration: ST.glowBox(ST.g1),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      const Icon(Icons.email, color: ST.g0, size: 13),
                      const SizedBox(width: 6),
                      Expanded(child: Text('Email sent to ${_emailC.text}', style: ST.body(10, color: ST.t2))),
                    ]),
                    const SizedBox(height: 4),
                    Row(children: [
                      const Icon(Icons.sms, color: ST.g0, size: 13),
                      const SizedBox(width: 6),
                      Expanded(child: Text('SMS sent to ${_phoneC.text}', style: ST.body(10, color: ST.t2))),
                    ]),
                  ])),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                    onPressed: () => setState(() {
                      _doneBookingId = null;
                      _doneQr = null;
                      _doneType = null;
                      _nameC.clear();
                      _emailC.clear();
                      _phoneC.clear();
                      _selectedTicketId = null;
                      _selectedDate = null;
                    }),
                    style: ElevatedButton.styleFrom(
                        backgroundColor: ST.g1,
                        foregroundColor: ST.bg,
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
                        elevation: 0),
                    child: Text('Register Another Tourist',
                        style: ST
                            .body(13, color: ST.bg)
                            .copyWith(fontWeight: FontWeight.w800))),
              ),
            ]),
          ),
        ),
      );
    }

    final now = DateTime.now();
    final dates = List.generate(
        7, (i) => now.add(Duration(days: i)));

    return Scaffold(
      backgroundColor: ST.bg,
      body: Stack(children: [
        SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _RoleBanner('🛡 Admin · Offline Booking',
                  'Register tourist & issue ticket on-site', ST.amber),
              Text('REGISTER TOURIST', style: ST.bebas(28)),
              Text('Tourist details · Select ticket · Confirm',
                  style: ST.body(11, color: ST.t3)),
              const SizedBox(height: 16),
              Text('TOURIST INFORMATION', style: ST.label(9, color: ST.t3)),
              const SizedBox(height: 8),
              _Field('Full name *', _nameC, icon: Icons.person_outline),
              const SizedBox(height: 8),
              _Field('Email address *', _emailC,
                  icon: Icons.email_outlined,
                  keyboard: TextInputType.emailAddress),
              const SizedBox(height: 8),
              _Field('Mobile number *', _phoneC,
                  icon: Icons.phone_outlined,
                  keyboard: TextInputType.phone),
              const SizedBox(height: 16),
              Text('SELECT TICKET PACKAGE', style: ST.label(9, color: ST.t3)),
              const SizedBox(height: 8),
              ...SD.tickets.map((tt) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: GestureDetector(
                  onTap: () =>
                      setState(() => _selectedTicketId = tt.id),
                  child: AnimatedContainer(
                    duration: 180.ms,
                    padding: const EdgeInsets.all(12),
                    decoration: ST.cardBox(
                        border: _selectedTicketId == tt.id
                            ? tt.accentColor
                            : null),
                    child: Row(children: [
                      Expanded(
                          child: Column(
                              crossAxisAlignment:
                              CrossAxisAlignment.start,
                              children: [
                                Text(tt.type,
                                    style: ST
                                        .body(13, color: ST.t1)
                                        .copyWith(
                                        fontWeight:
                                        FontWeight.w700)),
                                Text(tt.timeSlot,
                                    style:
                                    ST.mono(10, color: ST.t3)),
                              ])),
                      Text('₹${tt.price.toStringAsFixed(0)}',
                          style:
                          ST.bebas(22, color: tt.accentColor)),
                      const SizedBox(width: 10),
                      Container(
                          width: 20,
                          height: 20,
                          decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: _selectedTicketId == tt.id
                                  ? tt.accentColor
                                  : Colors.transparent,
                              border: Border.all(
                                  color: tt.accentColor)),
                          child: _selectedTicketId == tt.id
                              ? const Icon(Icons.check,
                              size: 13, color: Colors.white)
                              : null),
                    ]),
                  ),
                ),
              )),
              const SizedBox(height: 16),
              Text('SELECT DATE', style: ST.label(9, color: ST.t3)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: dates.map((d) {
                  final ds =
                      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
                  final sel = _selectedDate == ds;
                  return GestureDetector(
                    onTap: () => setState(() => _selectedDate = ds),
                    child: AnimatedContainer(
                      duration: 160.ms,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                          color: sel
                              ? ST.g1.withOpacity(0.15)
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                              color: sel ? ST.g1 : ST.gBorder)),
                      child: Text(_fmtDate(d),
                          style: ST.body(11,
                              color: sel ? ST.g0 : ST.t2)),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                    onPressed: _loading ? null : _submit,
                    style: ElevatedButton.styleFrom(
                        backgroundColor: ST.amber,
                        foregroundColor: ST.bg,
                        padding:
                        const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
                        elevation: 0),
                    child: Text(
                        _loading
                            ? 'Registering...'
                            : 'Register & Issue Ticket →',
                        style: ST
                            .body(14, color: ST.bg)
                            .copyWith(
                            fontWeight: FontWeight.w800))),
              ),
              const SizedBox(height: 60),
            ],
          ),
        ),
        if (_loading)
          Container(
              color: Colors.black.withOpacity(0.65),
              child: const Center(
                  child: CircularProgressIndicator(color: ST.g1))),
      ]),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// MAP PAINTER — image-based with overlay elements
// ─────────────────────────────────────────────────────────────────────────────
class MapPainter extends CustomPainter {
  // NOTE: 'animals' removed — the map image already shows them visually
  final List<VehicleModel> vehicles;
  final List<ZoneModel>    zones;
  final Map<String,bool>   layers;
  final bool showHeatmap;
  final String? selectedAnimalId;
  final double tick;
  final ui.Image? mapImage;
  final List<AlertModel> sosAlerts;
  final TrackCarTelemetry? trackTelemetry;
  final List<LiveDetection>? liveDetections;

  MapPainter({required this.vehicles, required this.zones,
    required this.layers, required this.showHeatmap, required this.tick,
    this.selectedAnimalId, this.mapImage, this.sosAlerts = const [],
    this.trackTelemetry, this.liveDetections});

  @override
  void paint(Canvas canvas, Size size) {
    final W = size.width, H = size.height;

    if (mapImage != null) {
      // Draw uploaded/asset map image
      final src = Rect.fromLTWH(
        0,
        0,
        mapImage!.width.toDouble(),
        mapImage!.height.toDouble(),
      );
      final dst = Rect.fromLTWH(0, 0, W, H);
      canvas.drawImageRect(mapImage!, src, dst, Paint());
      // Semi-transparent overlay to make icons more readable
      canvas.drawRect(
        Rect.fromLTWH(0, 0, W, H),
        Paint()..color = Colors.black.withOpacity(0.15),
      );
    } else {
      // Fallback: draw procedural safari map
      _drawProceduralMap(canvas, W, H);
    }

    // Draw road paths overlay (shows the paths jeeps follow)
    if (layers['paths'] == true) _drawRoadPaths(canvas, W, H);

    if (layers['hackathonTrack'] == true) {
      _drawHackathonTrackOverlay(canvas, W, H);
    }

    // Draw zones overlay
    if (layers['zones'] == true) _drawZones(canvas, W, H);

    // SOS location pulses
    _drawSOSPulses(canvas, W, H);

    // Detour warning indicators
    _drawDetourIndicators(canvas, W, H);

    // Vehicles
    if (layers['vehicles'] == true) _drawVehicles(canvas, W, H);

    // Compass
    _drawCompass(canvas, W, H);
  }

  void _drawHackathonTrackOverlay(Canvas canvas, double W, double H) {
    const split = 0.48;
    canvas.drawRect(
      Rect.fromLTWH(0, 0, W * split, H),
      Paint()..color = const Color(0xE6080808),
    );
    canvas.drawRect(
      Rect.fromLTWH(W * split, 0, W * (1 - split), H),
      Paint()..color = const Color(0xE6D8C8A8),
    );
    final pts = MapPaths.lineFollowerTrack;
    if (pts.length > 1) {
      final dr = MapPaths.lineFollowerDashedRange;
      for (int j = 0; j < pts.length - 1; j++) {
        final dash = j >= dr[0] && j < dr[1];
        canvas.drawLine(
          Offset(pts[j][0] * W, pts[j][1] * H),
          Offset(pts[j + 1][0] * W, pts[j + 1][1] * H),
          Paint()
            ..color = dash
                ? const Color(0xCCFFFFFF)
                : const Color(0xFF101010)
            ..strokeWidth = dash ? 2.4 : 3.6
            ..strokeCap = StrokeCap.round,
        );
      }
    }
    if (layers['checkpoints'] == true) {
      for (final c in MapPaths.lineFollowerCheckpoints) {
        final cx = (c['x'] as double) * W, cy = (c['y'] as double) * H;
        canvas.drawCircle(
          Offset(cx, cy),
          6,
          Paint()..color = ST.amber.withOpacity(0.9),
        );
        _text(
          canvas,
          c['label'] as String,
          Offset(cx + 8, cy - 6),
          Colors.white,
          7.5,
          bold: true,
        );
      }
    }
    if (liveDetections != null) {
      for (final d in liveDetections!) {
        final dx = d.x * W, dy = d.y * H;
        canvas.drawCircle(
          Offset(dx, dy),
          10,
          Paint()..color = ST.blue.withOpacity(0.35),
        );
        _textCentered(canvas, d.emoji, Offset(dx, dy - 1), Colors.white, 11);
      }
    }
    if (trackTelemetry != null) {
      final cx = trackTelemetry!.x * W, cy = trackTelemetry!.y * H;
      canvas.save();
      canvas.translate(cx, cy);
      canvas.rotate(trackTelemetry!.direction * pi / 180);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          const Rect.fromLTWH(-9, -6, 18, 12),
          const Radius.circular(3),
        ),
        Paint()..color = ST.g1,
      );
      canvas.restore();
      _textCentered(
        canvas,
        'CAR',
        Offset(cx, cy + 14),
        trackTelemetry!.inTelemetryDashedZone ? ST.amberL : ST.g0,
        7,
      );
    }
    _text(
      canvas,
      'UNPLUGGED LINE TRACK',
      Offset(10, 10),
      ST.amberL,
      11,
      bold: true,
      letterSpacing: 1.2,
    );
  }

  void _drawProceduralMap(Canvas canvas, double W, double H) {
    // Base terrain
    canvas.drawRect(
      Rect.fromLTWH(0, 0, W, H),
      Paint()..color = const Color(0xFF172D1E),
    );

    // Terrain variation patches
    final rng = Random(1337);
    for (int i = 0; i < 18; i++) {
      final x = rng.nextDouble() * W,
          y = rng.nextDouble() * H,
          r = 25 + rng.nextDouble() * 70;
      canvas.drawOval(
        Rect.fromCenter(center: Offset(x, y), width: r * 2.4, height: r * 1.5),
        Paint()
          ..color =
          Color.lerp(
            const Color(0xFF1A3020),
            const Color(0xFF265530),
            rng.nextDouble(),
          )!,
      );
    }

    // Sand/savannah patches
    for (final s in [
      [0.44, 0.44, 0.22, 0.14],
      [0.74, 0.34, 0.14, 0.10],
      [0.30, 0.20, 0.12, 0.08],
    ]) {
      canvas.drawOval(
        Rect.fromCenter(
          center: Offset(s[0] * W, s[1] * H),
          width: s[2] * W,
          height: s[3] * H,
        ),
        Paint()..color = const Color(0x20C9A96E),
      );
    }

    // Waterholes
    for (final wh in [
      [0.22, 0.76, 0.07],
      [0.68, 0.54, 0.04],
      [0.14, 0.55, 0.03],
    ]) {
      final cx = wh[0] * W, cy = wh[1] * H, r = wh[2] * W;
      canvas.drawOval(
        Rect.fromCenter(center: Offset(cx, cy), width: r * 2, height: r * 1.3),
        Paint()..color = const Color(0x801C6CB4),
      );
      canvas.drawOval(
        Rect.fromCenter(
          center: Offset(cx, cy),
          width: r * 1.3,
          height: r * 0.85,
        ),
        Paint()..color = const Color(0xFF2080C0).withOpacity(0.4),
      );
    }

    // Tree clusters
    _drawTreeClusters(canvas, W, H);
  }

  void _drawTreeClusters(Canvas canvas, double W, double H) {
    const clusters = [
      [0.04, 0.09],
      [0.88, 0.06],
      [0.02, 0.58],
      [0.90, 0.62],
      [0.44, 0.06],
      [0.18, 0.40],
      [0.76, 0.74],
      [0.28, 0.86],
      [0.60, 0.88],
      [0.08, 0.78],
      [0.86, 0.40],
      [0.54, 0.14],
      [0.38, 0.30],
      [0.62, 0.36],
      [0.46, 0.80],
    ];
    final trunk = Paint()..color = const Color(0xFF5C3D1E);
    for (int g = 0; g < clusters.length; g++) {
      final bx = clusters[g][0], by = clusters[g][1];
      for (int i = 0; i < 4; i++) {
        final tx = (bx + sin(i * 2.5 + g) * 0.04) * W,
            ty = (by + cos(i * 2.5 + g) * 0.04) * H;
        final r = 6.0 + (i % 3) * 2.0;
        canvas.drawRect(
          Rect.fromCenter(
            center: Offset(tx, ty + r * 0.3),
            width: 3,
            height: 5,
          ),
          trunk,
        );
        canvas.drawCircle(
          Offset(tx, ty - r * 0.15),
          r * 1.1,
          Paint()..color = const Color(0xFF1A5826),
        );
        canvas.drawCircle(
          Offset(tx, ty - r * 0.5),
          r * 0.85,
          Paint()..color = const Color(0xFF1F6A2F),
        );
        canvas.drawCircle(
          Offset(tx, ty - r * 0.78),
          r * 0.55,
          Paint()..color = const Color(0xFF268038),
        );
      }
    }
  }

  void _drawRoadPaths(Canvas canvas, double W, double H) {
    // Draw all defined road paths with road styling
    final allPaths = [
      MapPaths.mainLoop,
      MapPaths.innerNS,
      MapPaths.innerEW,
      MapPaths.waterholeRoad,
    ];
    final isMain = [true, false, false, false];

    for (int i = 0; i < allPaths.length; i++) {
      final pts = allPaths[i];
      if (pts.length < 2) continue;
      final path = Path()..moveTo(pts[0][0] * W, pts[0][1] * H);
      for (int j = 1; j < pts.length; j++)
        path.lineTo(pts[j][0] * W, pts[j][1] * H);

      // Road shadow
      canvas.drawPath(
        path,
        Paint()
          ..color = Colors.black.withOpacity(0.3)
          ..style = PaintingStyle.stroke
          ..strokeWidth = isMain[i] ? 12 : 8
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round,
      );
      // Road surface
      canvas.drawPath(
        path,
        Paint()
          ..color =
          (isMain[i] ? const Color(0xFFCA9E55) : const Color(0xFFA07C38))
          ..style = PaintingStyle.stroke
          ..strokeWidth = isMain[i] ? 9 : 6
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round,
      );
      // Center line
      if (isMain[i])
        canvas.drawPath(
          path,
          Paint()
            ..color = const Color(0x66FFDC64)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5
            ..strokeCap = StrokeCap.round,
        );
    }

    // Animated direction arrows along main loop
    _drawDirectionArrows(canvas, W, H);
  }

  void _drawDirectionArrows(Canvas canvas, double W, double H) {
    // Arrows animate along the main loop road
    final route = MapPaths.mainLoop;
    const numArrows = 4;
    final arrowPaint = Paint()..color = const Color(0x88FFCD32);
    for (int a = 0; a < numArrows; a++) {
      final phase = (tick * 0.00015 + a / numArrows) % 1.0;
      final segCount = route.length - 1;
      final totalPhase = phase * segCount;
      final seg = totalPhase.floor().clamp(0, segCount - 1);
      final t = totalPhase - seg;
      final pos = PathInterpolator.lerp(route, seg, t);
      final angle = PathInterpolator.heading(route, seg) * pi / 180;

      canvas.save();
      canvas.translate(pos.dx * W, pos.dy * H);
      canvas.rotate(angle);
      canvas.drawPath(
        Path()
          ..moveTo(0, -7)
          ..lineTo(4, 4)
          ..lineTo(0, 1)
          ..lineTo(-4, 4)
          ..close(),
        arrowPaint,
      );
      canvas.restore();
    }
  }

  void _drawZones(Canvas canvas, double W, double H) {
    for (final z in zones) {
      final r = RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: Offset(z.cx * W, z.cy * H),
          width: z.w * W,
          height: z.h * H,
        ),
        const Radius.circular(16),
      );
      canvas.drawRRect(r, Paint()..color = z.color);
      canvas.drawRRect(
        r,
        Paint()
          ..color = z.borderColor.withOpacity(0.7)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.6,
      );
      final sx = (z.cx - z.w / 2) * W, sy = (z.cy - z.h / 2) * H;
      _text(
        canvas,
        'ZONE ${z.id}',
        Offset(sx + 8, sy + 8),
        z.borderColor,
        10,
        bold: true,
        letterSpacing: 1.0,
      );
    }
  }

  void _drawHeatmap(Canvas canvas, double W, double H) {
    // Heatmap uses vehicle positions as proxies since animals are shown on map image
    for (final v in vehicles) {
      final g = const RadialGradient(
        colors: [Color(0x4AFF3030), Color(0x20FF9020), Colors.transparent],
      );
      canvas.drawCircle(
        Offset(v.x * W, v.y * H),
        55,
        Paint()
          ..shader = g.createShader(
            Rect.fromCircle(center: Offset(v.x * W, v.y * H), radius: 55),
          ),
      );
    }
  }

  void _drawSOSPulses(Canvas canvas, double W, double H) {
    for (final sos in sosAlerts) {
      if (sos.sosVehicleId == null) continue;
      final v = vehicles.cast<VehicleModel?>()
          .firstWhere((vv) => vv?.id == sos.sosVehicleId, orElse: () => null);
      if (v == null) continue;
      final cx = v.x * W, cy = v.y * H;
      final phase = (tick * 0.06) % 1.0;
      for (int i = 0; i < 3; i++) {
        final r = 18.0 + i * 14 + phase * 14;
        canvas.drawCircle(Offset(cx, cy), r,
            Paint()..color = ST.red.withOpacity((1 - r / 65) * 0.55)
              ..style = PaintingStyle.stroke..strokeWidth = 2);
      }
      canvas.drawCircle(Offset(cx, cy), 12, Paint()..color = ST.red.withOpacity(0.85));
      _textCentered(canvas, '🆘', Offset(cx, cy - 7), Colors.white, 14);
    }
  }

  void _drawDetourIndicators(Canvas canvas, double W, double H) {
    for (final v in vehicles) {
      if (v.detourState == JeepDetourState.onPath) continue;
      final cx = v.x * W, cy = v.y * H;
      canvas.drawPath(
          Path()..moveTo(cx, cy-22)..lineTo(cx-14, cy+8)..lineTo(cx+14, cy+8)..close(),
          Paint()..color = ST.amber.withOpacity(0.88));
      _textCentered(canvas, '!', Offset(cx, cy - 8), Colors.black, 13);
      _textCentered(canvas, v.blockedByAnimal ?? 'Animal',
          Offset(cx, cy + 18), ST.amber, 8);
    }
  }

  void _drawVehicles(Canvas canvas, double W, double H) {
    for (final v in vehicles) {
      final cx = v.x * W, cy = v.y * H;

      // Alert pulse
      if (v.status == VehicleStatus.alert) {
        final ap = 0.25 + 0.28 * sin(tick * 0.14);
        canvas.drawCircle(
          Offset(cx, cy),
          24,
          Paint()..color = ST.red.withOpacity(ap),
        );
      }

      canvas.save();
      canvas.translate(cx, cy);
      canvas.rotate(v.direction * pi / 180);

      // Drop shadow
      canvas.drawOval(
        Rect.fromCenter(center: const Offset(2, 2), width: 28, height: 18),
        Paint()..color = Colors.black.withOpacity(0.35),
      );

      // Jeep body
      final vc = v.detourState != JeepDetourState.onPath
          ? ST.amber
          : v.status == VehicleStatus.active ? ST.g1
          : v.status == VehicleStatus.alert ? ST.red
          : const Color(0xFF506050);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          const Rect.fromLTWH(-11, -8, 22, 16),
          const Radius.circular(4),
        ),
        Paint()..color = vc,
      );

      // Windshield
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          const Rect.fromLTWH(4, -5, 7, 10),
          const Radius.circular(2),
        ),
        Paint()..color = const Color(0xAAB8DAFF),
      );

      // Wheels
      for (final w in [
        const Offset(-7, -9.5),
        const Offset(-7, 9.5),
        const Offset(5, -9.5),
        const Offset(5, 9.5),
      ]) {
        canvas.drawOval(
          Rect.fromCenter(center: w, width: 8, height: 6),
          Paint()..color = const Color(0xFF181818),
        );
        canvas.drawOval(
          Rect.fromCenter(center: w, width: 5, height: 4),
          Paint()..color = const Color(0xFF333333),
        );
      }

      // Direction arrow
      canvas.drawPath(
        Path()
          ..moveTo(13, 0)
          ..lineTo(9, -3.5)
          ..lineTo(9, 3.5)
          ..close(),
        Paint()..color = Colors.white.withOpacity(0.9),
      );

      canvas.restore();

      // Vehicle label
      final shortName = v.name
          .replaceAll('Jeep ', '')
          .replaceAll('Ranger ', 'R-')
          .replaceAll('Medical Unit', 'Med');
      _textCentered(
        canvas,
        shortName,
        Offset(cx, cy + 19),
        v.status == VehicleStatus.alert ? ST.redL : const Color(0xDDE8F5E9),
        8.0,
      );
      if (v.speed > 0)
        _textCentered(
          canvas,
          '${v.speed.toStringAsFixed(0)}km/h',
          Offset(cx, cy + 28),
          ST.amber.withOpacity(0.85),
          7.5,
        );
    }
  }

  void _drawCompass(Canvas canvas, double W, double H) {
    final cx = W - 48, cy = H - 48;
    const r = 30.0;
    canvas.drawCircle(
      Offset(cx, cy),
      r + 5,
      Paint()..color = const Color(0xCC0F1F14),
    );
    canvas.drawCircle(
      Offset(cx, cy),
      r + 5,
      Paint()
        ..color = ST.gBorder
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2,
    );
    for (final d in [
      ['N', 0.0, ST.red],
      ['E', 90.0, ST.amberL],
      ['S', 270.0, ST.t3],
      ['W', 180.0, ST.t3],
    ]) {
      final angle = ((d[1] as double) - 90) * pi / 180;
      _text(
        canvas,
        d[0] as String,
        Offset(cx + cos(angle) * (r - 9) - 4, cy + sin(angle) * (r - 9) - 5),
        d[2] as Color,
        8.5,
        bold: true,
      );
    }
    canvas.save();
    canvas.translate(cx, cy);
    canvas.rotate(tick * 0.004);
    canvas.drawPath(
      Path()
        ..moveTo(0, -r * 0.52)
        ..lineTo(-4, 0)
        ..lineTo(0, r * 0.28)
        ..lineTo(4, 0)
        ..close(),
      Paint()..color = ST.red,
    );
    canvas.drawPath(
      Path()
        ..moveTo(0, r * 0.28)
        ..lineTo(-3, 0)
        ..lineTo(0, r * 0.52)
        ..lineTo(3, 0)
        ..close(),
      Paint()..color = Colors.white.withOpacity(0.5),
    );
    canvas.drawCircle(Offset.zero, 3.5, Paint()..color = Colors.white);
    canvas.restore();
  }

  void _text(
      Canvas canvas,
      String t,
      Offset pos,
      Color color,
      double size, {
        bool bold = false,
        double letterSpacing = 0,
      }) {
    (TextPainter(
      text: TextSpan(
        text: t,
        style: TextStyle(
          color: color,
          fontSize: size,
          fontWeight: bold ? FontWeight.w700 : FontWeight.w400,
          letterSpacing: letterSpacing,
          shadows:
          bold ? [const Shadow(color: Colors.black, blurRadius: 3)] : null,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout()).paint(canvas, pos);
  }

  void _textCentered(
      Canvas canvas,
      String t,
      Offset pos,
      Color color,
      double size,
      ) {
    final tp = TextPainter(
      text: TextSpan(
        text: t,
        style: TextStyle(
          color: color,
          fontSize: size,
          fontWeight: FontWeight.w600,
          shadows: [const Shadow(color: Colors.black, blurRadius: 3)],
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset(pos.dx - tp.width / 2, pos.dy));
  }

  @override
  bool shouldRepaint(covariant MapPainter old) => true;
}

// ─────────────────────────────────────────────────────────────────────────────
// MAIN ENTRY
// ─────────────────────────────────────────────────────────────────────────────
@pragma('vm:entry-point')
Future<void> _fcmBackgroundHandler(RemoteMessage message) async {
  if (_firebaseConfigured) {
    try {
      await Firebase.initializeApp(
        options: const FirebaseOptions(
          apiKey: _kFirebaseApiKey,
          appId: _kFirebaseAppId,
          messagingSenderId: _kFirebaseMessagingSenderId,
          projectId: _kFirebaseProjectId,
          databaseURL: _kFirebaseDatabaseUrl,
          storageBucket: _kFirebaseStorageBucket,
        ),
      );
    } catch (_) {}
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
    ),
  );

  if (_firebaseConfigured) {
    try {
      await Firebase.initializeApp(
        options: const FirebaseOptions(
          apiKey: _kFirebaseApiKey,
          appId: _kFirebaseAppId,
          messagingSenderId: _kFirebaseMessagingSenderId,
          projectId: _kFirebaseProjectId,
          databaseURL: _kFirebaseDatabaseUrl,
          storageBucket: _kFirebaseStorageBucket,
        ),
      );
      FirebaseMessaging.onBackgroundMessage(_fcmBackgroundHandler);
      if (!kIsWeb) {
        await FirebaseMessaging.instance.requestPermission(
          alert: true,
          badge: true,
          sound: true,
        );
      }
      debugPrint('✅ Firebase connected');
    } catch (e) {
      debugPrint('⚠️ Firebase: $e — sim mode');
    }
  }

  runApp(
    ChangeNotifierProvider(
      create: (_) => SProvider(),
      child: const SafariSyncApp(),
    ),
  );
}

class SafariSyncApp extends StatelessWidget {
  const SafariSyncApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'SafariSync',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: ST.bg,
      colorScheme: const ColorScheme.dark(
        primary: ST.g1,
        secondary: ST.amber,
        error: ST.red,
      ),
      textTheme: GoogleFonts.dmSansTextTheme(ThemeData.dark().textTheme),
      useMaterial3: true,
    ),
    home: const AuthGateScreen(),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// AUTH GATE
// ─────────────────────────────────────────────────────────────────────────────
class AuthGateScreen extends StatefulWidget {
  const AuthGateScreen({super.key});
  @override
  State<AuthGateScreen> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGateScreen>
    with TickerProviderStateMixin {
  late AnimationController _bg;
  bool _isLogin = true, _loading = false, _obscure = true;
  String _error = '';
  final _emailC = TextEditingController(), _passC = TextEditingController();
  final _nameC = TextEditingController(), _phoneC = TextEditingController();
  final _signEmailC = TextEditingController(),
      _signPassC = TextEditingController();
  final _idTypeC = TextEditingController(text: 'Aadhaar'),
      _idNumC = TextEditingController();
  UserRole _selRole = UserRole.tourist;

  @override
  void initState() {
    super.initState();
    _bg = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 20),
    )..repeat();
  }

  @override
  void dispose() {
    _bg.dispose();
    super.dispose();
  }

  Future<void> _doLogin() async {
    setState(() => _loading = true);
    try {
      if (_firebaseConfigured) {
        final cred = await FirebaseAuth.instance.signInWithEmailAndPassword(
          email: _emailC.text.trim(),
          password: _passC.text,
        );
        final doc =
        await FirebaseFirestore.instance
            .collection('users')
            .doc(cred.user?.uid ?? '')
            .get();
        final data = doc.data() ?? {};
        final role = UserRole.values.firstWhere(
              (r) => r.name == (data['role'] ?? 'tourist'),
          orElse: () => UserRole.tourist,
        );
        if (mounted) {
          context.read<SProvider>().init(
            role,
            data['name'] ?? 'User',
            phone: data['phone'] ?? '',
            email: _emailC.text.trim(),
            vehicleId: data['vehicleId'],
          );
          _goMain();
        }
      } else {
        await Future.delayed(const Duration(milliseconds: 700));
        if (mounted) {
          context.read<SProvider>().init(_selRole, 'Demo ${_selRole.name}');
          _goMain();
        }
      }
    } catch (e) {
      setState(() => _error = _friendlyError(e.toString()));
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _doSignup() async {
    if (_nameC.text.isEmpty ||
        _phoneC.text.isEmpty ||
        _signEmailC.text.isEmpty ||
        _signPassC.text.isEmpty) {
      setState(() => _error = 'Please fill all required fields');
      return;
    }
    setState(() => _loading = true);
    try {
      if (_firebaseConfigured) {
        final cred = await FirebaseAuth.instance.createUserWithEmailAndPassword(
          email: _signEmailC.text.trim(),
          password: _signPassC.text,
        );
        await FirebaseFirestore.instance
            .collection('users')
            .doc(cred.user?.uid ?? '')
            .set({
          'name': _nameC.text.trim(),
          'phone': _phoneC.text.trim(),
          'email': _signEmailC.text.trim(),
          'role': _selRole.name,
          'idType': _idTypeC.text.trim(),
          'idNum': _idNumC.text.trim(),
          'joined': FieldValue.serverTimestamp(),
          'status': 'active',
        });
        if (mounted) {
          context.read<SProvider>().init(
            _selRole,
            _nameC.text.trim(),
            phone: _phoneC.text.trim(),
            email: _signEmailC.text.trim(),
          );
          _goMain();
        }
      } else {
        await Future.delayed(const Duration(milliseconds: 700));
        if (mounted) {
          context.read<SProvider>().init(
            _selRole,
            _nameC.text.trim(),
            phone: _phoneC.text.trim(),
            email: _signEmailC.text.trim(),
          );
          _goMain();
        }
      }
    } catch (e) {
      setState(() => _error = _friendlyError(e.toString()));
    }
    if (mounted) setState(() => _loading = false);
  }

  String _friendlyError(String e) {
    if (e.contains('user-not-found')) return 'No account with this email.';
    if (e.contains('wrong-password')) return 'Incorrect password.';
    if (e.contains('email-already-in-use'))
      return 'Account with this email already exists.';
    if (e.contains('weak-password'))
      return 'Password must be at least 6 characters.';
    if (e.contains('invalid-email')) return 'Please enter a valid email.';
    if (e.contains('network-request-failed'))
      return 'No internet. Check your connection.';
    return 'Something went wrong. Please try again.';
  }

  void _goMain() {
    final p = context.read<SProvider>();
    final dest =
        (kIsWeb && p.isAdmin) ? const AdminWebCommandCenter() : const MainShell();
    Navigator.pushReplacement(
      context,
      PageRouteBuilder(
        pageBuilder: (_, a, __) => dest,
        transitionsBuilder:
            (_, anim, __, child) => FadeTransition(opacity: anim, child: child),
        transitionDuration: const Duration(milliseconds: 500),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: ST.bg,
    body: Stack(
      children: [
        AnimatedBuilder(
          animation: _bg,
          builder:
              (_, __) => CustomPaint(
            painter: _BgParticles(_bg.value),
            size: Size.infinite,
          ),
        ),
        SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Logo
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        width: 42,
                        height: 42,
                        decoration: BoxDecoration(
                          color: ST.g1,
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: [
                            BoxShadow(
                              color: ST.g1.withOpacity(0.35),
                              blurRadius: 16,
                            ),
                          ],
                        ),
                        child: const Center(
                          child: Text('🌿', style: TextStyle(fontSize: 22)),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('SAFARISYNC', style: ST.bebas(28, color: ST.g0)),
                          Text(
                            'WILDLIFE INTELLIGENCE v2.2',
                            style: ST.label(8, color: ST.t4),
                          ),
                        ],
                      ),
                    ],
                  ).animate().scale(duration: 600.ms, curve: Curves.elasticOut),
                  const SizedBox(height: 28),

                  // Card
                  Container(
                    width: double.infinity,
                    constraints: const BoxConstraints(maxWidth: 380),
                    decoration: BoxDecoration(
                      color: ST.panel,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: ST.gBorder, width: 1.2),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.4),
                          blurRadius: 30,
                        ),
                      ],
                    ),
                    child: Column(
                      children: [
                        Padding(
                          padding: const EdgeInsets.all(16),
                          child: Row(
                            children: [
                              _AuthTab(
                                'Sign In',
                                _isLogin,
                                    () => setState(
                                      () => {_isLogin = true, _error = ''},
                                ),
                              ),
                              const SizedBox(width: 8),
                              _AuthTab(
                                'Create Account',
                                !_isLogin,
                                    () => setState(
                                      () => {_isLogin = false, _error = ''},
                                ),
                              ),
                            ],
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
                          child:
                          _isLogin ? _buildLoginForm() : _buildSignupForm(),
                        ),
                      ],
                    ),
                  ).animate().fadeIn(duration: 500.ms).slideY(begin: 0.1),
                ],
              ),
            ),
          ),
        ),
      ],
    ),
  );

  Widget _buildLoginForm() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _Field(
        'Email address',
        _emailC,
        icon: Icons.email_outlined,
        keyboard: TextInputType.emailAddress,
      ),
      const SizedBox(height: 10),
      _Field(
        'Password',
        _passC,
        icon: Icons.lock_outline,
        obscure: _obscure,
        suffix: GestureDetector(
          onTap: () => setState(() => _obscure = !_obscure),
          child: Icon(
            _obscure ? Icons.visibility_off : Icons.visibility,
            color: ST.t3,
            size: 18,
          ),
        ),
      ),
      const SizedBox(height: 10),
      if (!_firebaseConfigured) ...[
        Text('Demo mode — select role:', style: ST.body(11, color: ST.t3)),
        const SizedBox(height: 8),
        _RoleSelector(
          selected: _selRole,
          onChanged: (r) => setState(() => _selRole = r),
        ),
        const SizedBox(height: 10),
      ],
      if (_error.isNotEmpty) _ErrorBox(_error),
      const SizedBox(height: 4),
      _PrimaryBtn(
        _loading ? 'Signing in...' : 'Sign In →',
        _loading ? null : _doLogin,
      ),
      const SizedBox(height: 14),
      Center(
        child: GestureDetector(
          onTap: () => setState(() => {_isLogin = false, _error = ''}),
          child: Text(
            "Don't have an account? Sign up →",
            style: ST.body(11.5, color: ST.g0),
          ),
        ),
      ),
    ],
  );

  Widget _buildSignupForm() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text('PERSONAL INFO', style: ST.label(9, color: ST.t3)),
      const SizedBox(height: 8),
      _Field('Full name *', _nameC, icon: Icons.person_outline),
      const SizedBox(height: 8),
      _Field(
        'Mobile number *',
        _phoneC,
        icon: Icons.phone_outlined,
        keyboard: TextInputType.phone,
      ),
      const SizedBox(height: 8),
      _Field(
        'Email address *',
        _signEmailC,
        icon: Icons.email_outlined,
        keyboard: TextInputType.emailAddress,
      ),
      const SizedBox(height: 8),
      _Field(
        'Password (min 6 chars) *',
        _signPassC,
        icon: Icons.lock_outline,
        obscure: true,
      ),
      const SizedBox(height: 14),
      Text('ID VERIFICATION', style: ST.label(9, color: ST.t3)),
      const SizedBox(height: 8),
      _DropdownField('ID Type', _idTypeC, [
        'Aadhaar',
        'PAN Card',
        'Passport',
        'Driving Licence',
        'Voter ID',
      ]),
      const SizedBox(height: 8),
      _Field('ID Number', _idNumC, icon: Icons.badge_outlined),
      const SizedBox(height: 14),
      Text('I AM A', style: ST.label(9, color: ST.t3)),
      const SizedBox(height: 8),
      _RoleSelector(
        selected: _selRole,
        onChanged: (r) => setState(() => _selRole = r),
      ),
      const SizedBox(height: 14),
      if (_error.isNotEmpty) _ErrorBox(_error),
      _PrimaryBtn(
        _loading ? 'Creating account...' : 'Create Account →',
        _loading ? null : _doSignup,
      ),
      const SizedBox(height: 8),
      Center(
        child: Text(
          'By signing up you agree to SafariSync Terms & Privacy Policy.',
          style: ST.body(9.5, color: ST.t4),
          textAlign: TextAlign.center,
        ),
      ),
    ],
  );
}

// Auth helpers
class _AuthTab extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback onTap;
  const _AuthTab(this.label, this.active, this.onTap);
  @override
  build(BuildContext context) => Expanded(
    child: GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: 200.ms,
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: active ? ST.gGlow : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: active ? ST.gBorderBright : ST.gBorder),
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: ST
              .body(12, color: active ? ST.g0 : ST.t3)
              .copyWith(fontWeight: FontWeight.w600),
        ),
      ),
    ),
  );
}

class _Field extends StatelessWidget {
  final String hint;
  final TextEditingController ctrl;
  final IconData? icon;
  final bool obscure;
  final Widget? suffix;
  final TextInputType keyboard;
  const _Field(
      this.hint,
      this.ctrl, {
        this.icon,
        this.obscure = false,
        this.suffix,
        this.keyboard = TextInputType.text,
      });
  @override
  build(BuildContext context) => Container(
    decoration: ST.cardBox(radius: 8),
    child: TextField(
      controller: ctrl,
      obscureText: obscure,
      keyboardType: keyboard,
      style: ST.body(13),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: ST.body(13, color: ST.t4),
        prefixIcon: icon != null ? Icon(icon, color: ST.t3, size: 18) : null,
        suffixIcon: suffix,
        border: InputBorder.none,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 13,
        ),
      ),
    ),
  );
}

class _DropdownField extends StatelessWidget {
  final String hint;
  final TextEditingController ctrl;
  final List<String> options;
  const _DropdownField(this.hint, this.ctrl, this.options);
  @override
  build(BuildContext context) => Container(
    decoration: ST.cardBox(radius: 8),
    child: DropdownButtonFormField<String>(
      value: ctrl.text,
      dropdownColor: ST.panel,
      style: ST.body(13),
      decoration: const InputDecoration(
        border: InputBorder.none,
        contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      ),
      items:
      options
          .map(
            (o) => DropdownMenuItem(
          value: o,
          child: Text(o, style: ST.body(12)),
        ),
      )
          .toList(),
      onChanged: (v) {
        if (v != null) ctrl.text = v;
      },
    ),
  );
}

class _RoleSelector extends StatelessWidget {
  final UserRole selected;
  final ValueChanged<UserRole> onChanged;
  const _RoleSelector({required this.selected, required this.onChanged});
  @override
  build(BuildContext context) => Row(
    children: [
      _RoleChip('🧳 Tourist', UserRole.tourist, selected, onChanged),
      const SizedBox(width: 8),
      _RoleChip('🚙 Driver', UserRole.driver, selected, onChanged),
      const SizedBox(width: 8),
      _RoleChip('🛡 Admin', UserRole.admin, selected, onChanged),
    ],
  );
}

class _RoleChip extends StatelessWidget {
  final String label;
  final UserRole role, selected;
  final ValueChanged<UserRole> onChanged;
  const _RoleChip(this.label, this.role, this.selected, this.onChanged);
  @override
  build(BuildContext context) {
    final on = role == selected;
    return Expanded(
      child: GestureDetector(
        onTap: () => onChanged(role),
        child: AnimatedContainer(
          duration: 180.ms,
          padding: const EdgeInsets.symmetric(vertical: 9),
          decoration: BoxDecoration(
            color: on ? ST.gGlow : Colors.transparent,
            borderRadius: BorderRadius.circular(7),
            border: Border.all(color: on ? ST.gBorderBright : ST.gBorder),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: ST.body(10.5, color: on ? ST.g0 : ST.t3),
          ),
        ),
      ),
    );
  }
}

class _ErrorBox extends StatelessWidget {
  final String msg;
  const _ErrorBox(this.msg);
  @override
  build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 12),
    padding: const EdgeInsets.all(10),
    decoration: ST.glowBox(ST.red),
    child: Row(
      children: [
        const Icon(Icons.error_outline, color: ST.red, size: 16),
        const SizedBox(width: 8),
        Expanded(child: Text(msg, style: ST.body(11, color: ST.redL))),
      ],
    ),
  );
}

class _PrimaryBtn extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;
  const _PrimaryBtn(this.label, this.onTap);
  @override
  build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: AnimatedContainer(
      duration: 180.ms,
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: BoxDecoration(
        color: onTap == null ? ST.g2.withOpacity(0.4) : ST.g1,
        borderRadius: BorderRadius.circular(10),
        boxShadow:
        onTap != null
            ? [BoxShadow(color: ST.g1.withOpacity(0.25), blurRadius: 12)]
            : null,
      ),
      child: Center(
        child: Text(
          label,
          style: ST
              .body(13.5, color: ST.bg)
              .copyWith(fontWeight: FontWeight.w800),
        ),
      ),
    ),
  );
}

class _BgParticles extends CustomPainter {
  final double t;
  _BgParticles(this.t);
  static final _rng = Random(42);
  static final _pts = List.generate(
    40,
        (_) => [_rng.nextDouble(), _rng.nextDouble(), _rng.nextDouble()],
  );
  @override
  void paint(Canvas canvas, Size size) {
    for (final p in _pts) {
      final x = p[0] * size.width,
          y = ((p[1] + t * 0.05) % 1.0) * size.height,
          r = 0.8 + p[2] * 1.8;
      canvas.drawCircle(
        Offset(x, y),
        r,
        Paint()..color = ST.g1.withOpacity(0.08 + p[2] * 0.12),
      );
    }
  }

  @override
  bool shouldRepaint(_) => true;
}

// ─────────────────────────────────────────────────────────────────────────────
// MAIN SHELL — role-aware bottom nav
// ─────────────────────────────────────────────────────────────────────────────
class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}
class _MainShellState extends State<MainShell> {
  int _activeTab = 0;
  OverlayEntry? _toast;

  void switchToTab(String label) {
    final p = context.read<SProvider>();
    final tabs = _buildTabs(p);
    final idx = tabs.indexWhere((t) => t.$2 == label);
    if (idx >= 0) setState(() => _activeTab = idx);
  }

  void _showToast(String title, String msg, {Color? color}) {
    _toast?.remove();
    _toast = OverlayEntry(
      builder:
          (_) => _ToastWidget(
        title: title,
        msg: msg,
        color: color ?? ST.g0,
        onDismiss: () {
          _toast?.remove();
          _toast = null;
        },
      ),
    );
    Overlay.of(context).insert(_toast!);
  }

  // Build tabs based on role
  List<(String, String, Widget)> _buildTabs(SProvider p) {
    final tabs = <(String, String, Widget)>[];

    // v3.0: Track visible to everyone
    tabs.add(('🏁', 'Track', const LFTrackViewScreen()));

    // Live Map — animal probability heatmap (all roles)
    tabs.add(('🗾', 'Live Map', const LiveMapScreen()));

    // Role-specific tabs
    if (p.canSeeAnalytics)
      tabs.add(('📊', 'Analytics', const AnalyticsScreen()));

    if (p.canSeeFleet)
      tabs.add((
      '🚙',
      p.isDriver ? 'My Jeep' : 'Fleet',
      FleetScreen(forDriver: p.isDriver),
      ));

    if (p.canSeeImu) tabs.add(('📡', 'IMU', const ImuScreen()));

    // v3.0: AQI / Weather — everyone
    tabs.add(('🌿', 'Environ', const AqiWeatherScreen()));



    // v3.0: RFID / Session — driver + admin
    if (p.isDriver || p.isAdmin)
      tabs.add(('🏷', 'Session', const RfidReportScreen()));

    // v3.0: Vehicle Control — admin only
    if (p.isAdmin)
      tabs.add(('🎮', 'Control', const VehicleControlScreen()));

    if (p.canSeeTickets)
      tabs.add(('🎫','Tickets', const TicketingScreen()));

    if (p.isTourist || p.isAdmin)
      tabs.add(('📋','My Trips', const MyBookingsScreen()));

    tabs.add(('🛤','Routes', const RoutesScreen()));

    // Admin gets alerts management tab
    if (p.isAdmin) {
      tabs.add(('🔔', 'Alerts', AlertsManagementScreen()));
      tabs.add(('📝', 'Register', const AdminOfflineBookingScreen()));
    }

    return tabs;
  }

  @override
  Widget build(BuildContext context) {
    final prov = context.watch<SProvider>();
    final tabs = _buildTabs(prov);
    final safeTab = _activeTab.clamp(0, tabs.length - 1);

    return Scaffold(
      backgroundColor: ST.bg,
      body:SafeArea(child:Column(children:[
        _TopBar(onToast:_showToast),
        if (!prov.isAdmin) _SOSBanner(prov:prov),
        Expanded(child:tabs[safeTab].$3),
      ])),
      bottomNavigationBar: Container(
        color: ST.bgDeep,
        child: SafeArea(
          top: false,
          child: Container(
            height: 62,
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: ST.gBorder)),
            ),
            child: Row(
              children:
              tabs.asMap().entries.map((e) {
                final idx = e.key;
                final icon = e.value.$1;
                final label = e.value.$2;
                final active = idx == safeTab;
                // Alert badge for alerts tab (admin)
                final showBadge =
                    label == 'Alerts' && prov.unreadAlerts > 0;
                return Expanded(
                  child: GestureDetector(
                    onTap: () => setState(() => _activeTab = idx),
                    child: AnimatedContainer(
                      duration: 180.ms,
                      color: active ? ST.gGlow : Colors.transparent,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                icon,
                                style: TextStyle(
                                  fontSize: active ? 20 : 17,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                label,
                                style: ST.label(
                                  7,
                                  color: active ? ST.g0 : ST.t3,
                                ),
                              ),
                            ],
                          ),
                          if (showBadge)
                            Positioned(
                              top: 8,
                              right: 8,
                              child: Container(
                                width: 14,
                                height: 14,
                                decoration: const BoxDecoration(
                                  color: ST.red,
                                  shape: BoxShape.circle,
                                ),
                                child: Center(
                                  child: Text(
                                    '${prov.unreadAlerts}',
                                    style: ST.label(8, color: Colors.white),
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ),
      ),
    );
  }
}

class _SOSBanner extends StatelessWidget {
  final SProvider prov;
  const _SOSBanner({required this.prov});
  @override build(BuildContext context) => Container(
      padding:const EdgeInsets.symmetric(horizontal:14,vertical:6),
      color:ST.bgDeep,
      child:Row(children:[
        Expanded(child:Text(
            '${prov.weather} · Zone ${prov.vehicles.firstWhere((v)=>v.id==(prov.assignedVehicleId??'j1'),orElse:()=>prov.vehicles.first).zone}',
            style:ST.body(11,color:ST.t2))),
        GestureDetector(
          onLongPress:(){
            prov.triggerSOS();
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                backgroundColor:ST.red.withOpacity(0.9),
                content:Text('🆘 SOS Alert sent! Help is on the way.',
                    style:ST.body(12,color:Colors.white)),
                duration:const Duration(seconds:4)));
          },
          child:Container(
              padding:const EdgeInsets.symmetric(horizontal:14,vertical:6),
              decoration:BoxDecoration(color:ST.red, borderRadius:BorderRadius.circular(8),
                  boxShadow:[BoxShadow(color:ST.red.withOpacity(0.4),blurRadius:8)]),
              child:Row(mainAxisSize:MainAxisSize.min, children:[
                const Text('🆘',style:TextStyle(fontSize:13)), const SizedBox(width:6),
                Text('HOLD SOS',style:ST.label(9,color:Colors.white)),
              ])),
        ),
      ]));
}

// ─────────────────────────────────────────────────────────────────────────────
// TOP BAR
// ─────────────────────────────────────────────────────────────────────────────
class _TopBar extends StatefulWidget {
  final Function(String, String, {Color? color}) onToast;
  const _TopBar({required this.onToast});
  @override
  State<_TopBar> createState() => _TopBarState();
}

class _TopBarState extends State<_TopBar> with SingleTickerProviderStateMixin {
  String _time = '';
  Timer? _timer;
  late AnimationController _pulse;
  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);
    _updateTime();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _updateTime());
  }

  void _updateTime() {
    final n = DateTime.now();
    if (mounted)
      setState(
            () =>
        _time =
        '${n.hour.toString().padLeft(2, '0')}:${n.minute.toString().padLeft(2, '0')}:${n.second.toString().padLeft(2, '0')}',
      );
  }

  @override
  void dispose() {
    _timer?.cancel();
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final prov = context.watch<SProvider>();
    final roleColor =
    prov.isTourist
        ? ST.g0
        : prov.isDriver
        ? ST.blueL
        : ST.amber;
    final roleIcon =
    prov.isTourist
        ? '🧳'
        : prov.isDriver
        ? '🚙'
        : '🛡';
    return Container(
      height: 50,
      color: ST.bgDeep,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Row(
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: ST.g1,
              borderRadius: BorderRadius.circular(8),
              boxShadow: [
                BoxShadow(color: ST.g1.withOpacity(0.3), blurRadius: 8),
              ],
            ),
            child: const Center(
              child: Text('🌿', style: TextStyle(fontSize: 16)),
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text('SAFARISYNC', style: ST.bebas(16, color: ST.g0)),
              Text(
                '${prov.userName} · ${prov.role.name.toUpperCase()}',
                style: ST.label(7, color: ST.t4),
              ),
            ],
          ),
          const Spacer(),
          AnimatedBuilder(
            animation: _pulse,
            builder:
                (_, __) => Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 7,
                vertical: 3,
              ),
              decoration: BoxDecoration(
                color: ST.g1.withOpacity(0.1 + _pulse.value * 0.05),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: ST.g1.withOpacity(0.4)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 5,
                    height: 5,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: ST.g0.withOpacity(0.5 + _pulse.value * 0.5),
                    ),
                  ),
                  const SizedBox(width: 4),
                  Text('LIVE', style: ST.label(8, color: ST.g0)),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(_time, style: ST.mono(9, color: ST.t2)),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
            decoration: BoxDecoration(
              color: roleColor.withOpacity(0.12),
              borderRadius: BorderRadius.circular(5),
              border: Border.all(color: roleColor.withOpacity(0.3)),
            ),
            child: Text(
              '$roleIcon ${prov.role.name.toUpperCase()}',
              style: ST.label(8, color: roleColor),
            ),
          ),
          const SizedBox(width: 8),
          // ── Sign Out Button ──
          GestureDetector(
            onTap: () => _confirmSignOut(context),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
              decoration: BoxDecoration(
                color: ST.red.withOpacity(0.12),
                borderRadius: BorderRadius.circular(5),
                border: Border.all(color: ST.red.withOpacity(0.3)),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.logout, color: ST.red, size: 11),
                const SizedBox(width: 4),
                Text('OUT', style: ST.label(8, color: ST.red)),
              ]),
            ),
          ),
        ],
      ),
    );
  }

  void _confirmSignOut(BuildContext ctx) {
    showDialog(
      context: ctx,
      builder: (_) => AlertDialog(
        backgroundColor: ST.panel,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Sign Out?', style: ST.body(16, color: ST.t1).copyWith(fontWeight: FontWeight.w800)),
        content: Text('You will be returned to the login screen.', style: ST.body(13, color: ST.t3)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancel', style: ST.body(13, color: ST.t3)),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              try { await FirebaseAuth.instance.signOut(); } catch (_) {}
              if (ctx.mounted) {
                Navigator.of(ctx, rootNavigator: true).pushAndRemoveUntil(
                  MaterialPageRoute(builder: (_) => const AuthGateScreen()),
                  (_) => false,
                );
              }
            },
            child: Text('Sign Out', style: ST.body(13, color: ST.red).copyWith(fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

} // end _TopBarState

// ─────────────────────────────────────────────────────────────────────────────
// FULL-SCREEN MAP with image support
// ─────────────────────────────────────────────────────────────────────────────
class _MapFullScreen extends StatefulWidget {
  final Function(String, String, {Color? color}) onToast;
  const _MapFullScreen({required this.onToast});
  @override
  State<_MapFullScreen> createState() => _MapFullScreenState();
}

class _MapFullScreenState extends State<_MapFullScreen>
    with TickerProviderStateMixin {
  late AnimationController _tick;
  double _scale = 1.0, _baseScale = 1.0;
  Offset _offset = Offset.zero, _baseOffset = Offset.zero;
  bool _showLayers = false, _showAlerts = false;
  ui.Image? _mapImage;

  @override
  void initState() {
    super.initState();
    _tick =
    AnimationController(vsync: this, duration: const Duration(seconds: 200))
      ..repeat();
    if (_kUseAssetMap) _loadMapImage();
  }

  @override
  void dispose() {
    _tick.dispose();
    super.dispose();
  }

  double get _tval => _tick.value * 200 * 60;

  Future<void> _loadMapImage() async {
    try {
      final data = await rootBundle.load(_kMapAssetPath);
      final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
      final frame = await codec.getNextFrame();
      if (mounted) setState(() => _mapImage = frame.image);
    } catch (e) {
      debugPrint('Map image load failed: $e');
    }
  }

  void _onTap(TapDownDetails d, SProvider p, Size sz) {
    final lx = (d.localPosition.dx / _scale - _offset.dx) / sz.width;
    final ly = (d.localPosition.dy / _scale - _offset.dy) / sz.height;
    for (final a in p.animals) {
      final dx = (a.x - lx) * sz.width, dy = (a.y - ly) * sz.height;
      if (sqrt(dx * dx + dy * dy) < 22) {
        p.selectAnimal(a.id);
        _showAnimalSheet(p.getAnimal(a.id)!);
        return;
      }
    }
    for (final v in p.vehicles) {
      final dx = (v.x - lx) * sz.width, dy = (v.y - ly) * sz.height;
      if (sqrt(dx * dx + dy * dy) < 22) {
        _showVehicleSheet(v);
        return;
      }
    }
    p.selectAnimal(null);
  }

  void _showAnimalSheet(AnimalModel a) => showModalBottomSheet(
    context: context,
    backgroundColor: ST.panel,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => _AnimalSheet(animal: a),
  );

  void _showVehicleSheet(VehicleModel v) => showModalBottomSheet(
    context: context,
    backgroundColor: ST.panel,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => _VehicleSheet(vehicle: v),
  );

  @override
  Widget build(BuildContext context) {
    final p = context.watch<SProvider>();
    return LayoutBuilder(builder: (ctx, c) {
      final sz = Size(c.maxWidth, c.maxHeight);
      return SizedBox(
        width: c.maxWidth,
        height: c.maxHeight,
        child: Stack(
          children: [
            // ── MAP + GESTURE ──
            GestureDetector(
              onTapDown: (d) => _onTap(d, p, sz),
              onScaleStart: (d) {
                _baseScale = _scale;
                _baseOffset = _offset;
              },
              onScaleUpdate: (d) => setState(() {
                _scale = (_baseScale * d.scale).clamp(0.5, 6.0);
                _offset = _baseOffset + d.focalPointDelta / _scale;
              }),
              child: ClipRect(
                child: Transform.scale(
                  scale: _scale,
                  alignment: Alignment.topLeft,
                  child: Transform.translate(
                    offset: _offset,
                    // Use RepaintBoundary so only this canvas repaints on tick
                    child: RepaintBoundary(
                      child: RepaintBoundary(
                        child: AnimatedBuilder(
                          animation: _tick,
                          builder: (_, __) => CustomPaint(
                            painter: MapPainter(
                              vehicles: p.vehicles,
                              zones: SD.zones,
                              layers: p.layers,
                              showHeatmap: p.showHeatmap,
                              tick: _tval,
                              mapImage: _mapImage,
                              sosAlerts: p.sosAlerts,
                              selectedAnimalId: p.selectedAnimalId,
                              trackTelemetry: p.trackTelemetry,
                              liveDetections: p.liveDetections,
                            ),
                            size: sz,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),

            // ── LEFT CONTROLS ──
            Positioned(
              top: 12,
              left: 12,
              child: Column(
                children: [
                  _MapBtn('+', 'Zoom In',
                          () => setState(() => _scale = (_scale * 1.3).clamp(0.5, 6.0))),
                  const SizedBox(height: 6),
                  _MapBtn('−', 'Zoom Out',
                          () => setState(() => _scale = (_scale * 0.77).clamp(0.5, 6.0))),
                  const SizedBox(height: 6),
                  _MapBtn('⌂', 'Reset', () => setState(() {
                    _scale = 1.0;
                    _offset = Offset.zero;
                  })),
                  const SizedBox(height: 6),
                  _MapBtn(p.showHeatmap ? '🌡' : '🌡', 'Heatmap',
                          () => p.toggleHeatmap(), active: p.showHeatmap),
                  const SizedBox(height: 6),
                  _MapBtn('⏮', 'Replay', () => p.toggleReplay(),
                      active: p.replayMode),
                ],
              ),
            ),

            // ── RIGHT CONTROLS ──
            Positioned(
              top: 12,
              right: 12,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  _MapBtn('🗂', 'Layers',
                          () => setState(() => _showLayers = !_showLayers),
                      active: _showLayers),
                  if (_showLayers) ...[
                    const SizedBox(height: 6),
                    _LayerPanel(p),
                  ],
                  const SizedBox(height: 6),
                  _MapBtn('🔔', 'Alerts',
                          () => setState(() => _showAlerts = !_showAlerts),
                      active: _showAlerts),
                  if (_showAlerts) ...[
                    const SizedBox(height: 6),
                    _AlertsOverlay(p: p),
                  ],
                ],
              ),
            ),

            // ── BOTTOM STATS ──
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: _MapStatsBar(p),
            ),

            // ── OFFLINE BANNER ──
            if (!p.isOnline)
              Positioned(
                top: 52,
                left: 0,
                right: 0,
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    decoration: BoxDecoration(
                      color: ST.amber.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: ST.amber.withOpacity(0.35)),
                    ),
                    child: Text('⚠  OFFLINE — Cached data',
                        style: ST.body(11, color: ST.amber)),
                  ),
                ),
              ),

            // ── REPLAY BAR ──
            if (p.replayMode)
              Positioned(
                top: 12,
                left: 55,
                right: 55,
                child: _ReplayBar(p: p),
              ),

            // ── TOURIST HINT ──
            if (p.isTourist) _TouristMapHint(),
          ],
        ),
      );
    });
  }
}

// Tourist hint overlay (shows recommended route for tourists)
class _TouristMapHint extends StatefulWidget {
  @override
  State<_TouristMapHint> createState() => _TouristMapHintState();
}

class _TouristMapHintState extends State<_TouristMapHint> {
  bool _dismissed = false;
  @override
  build(BuildContext context) {
    if (_dismissed) return const SizedBox();
    return Positioned(
      bottom: 50,
      left: 12,
      right: 12,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: ST
            .glowBox(ST.g0)
            .copyWith(
          boxShadow: [
            BoxShadow(color: Colors.black.withOpacity(0.4), blurRadius: 12),
          ],
        ),
        child: Row(
          children: [
            const Text('🗺', style: TextStyle(fontSize: 18)),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Today\'s Recommended Route',
                    style: ST
                        .body(12, color: ST.g0)
                        .copyWith(fontWeight: FontWeight.w700),
                  ),
                  Text(
                    'Alpha Trail · 14.2km · ~12 sightings',
                    style: ST.body(10, color: ST.t2),
                  ),
                ],
              ),
            ),
            GestureDetector(
              onTap: () => setState(() => _dismissed = true),
              child: Text('✕', style: ST.body(14, color: ST.t3)),
            ),
          ],
        ),
      ),
    );
  }
}

class _MapStatsBar extends StatelessWidget {
  final SProvider p;
  const _MapStatsBar(this.p);
  @override
  build(BuildContext context) => Container(
    height: 40,
    decoration: BoxDecoration(
      color: ST.bgDeep.withOpacity(0.92),
      border: Border(top: BorderSide(color: ST.gBorder)),
    ),
    padding: const EdgeInsets.symmetric(horizontal: 12),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceAround,
      children: [
        _SC('🐾', '${p.animals.length} Animals', ST.g0),
        _SC('🚙', '${p.activeVehicles} Active', ST.amber),
        if (p.trackTelemetry != null)
          _SC(
            '🏎',
            '${p.trackTelemetry!.speed.toStringAsFixed(0)}',
            ST.purpleL,
          ),
        _SC('📡', '${p.espNodes}/14', ST.blueL),
        _SC('🌤', p.weather, ST.t1),
        _SC('🧭', p.heading, ST.g0),
      ],
    ),
  );
}

class _SC extends StatelessWidget {
  final String icon, label;
  final Color c;
  const _SC(this.icon, this.label, this.c);
  @override
  build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(icon, style: const TextStyle(fontSize: 11)),
      const SizedBox(width: 3),
      Text(
        label,
        style: ST.body(9.5, color: c).copyWith(fontWeight: FontWeight.w600),
      ),
    ],
  );
}

class _AlertsOverlay extends StatelessWidget {
  final SProvider p;
  const _AlertsOverlay({required this.p});
  @override
  build(BuildContext context) => Container(
    width: 240,
    constraints: const BoxConstraints(maxHeight: 300),
    decoration: ST.panelBox(radius: 12),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.all(10),
          child: Row(
            children: [
              Text('ALERTS', style: ST.label(9, color: ST.t3)),
              const Spacer(),
              if (p.unreadAlerts > 0)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 5,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: ST.red.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '${p.unreadAlerts} NEW',
                    style: ST.label(8, color: ST.red),
                  ),
                ),
            ],
          ),
        ),
        const Divider(height: 1, color: ST.gBorder),
        Flexible(
          child: ListView(
            shrinkWrap: true,
            children:
            p.visibleAlerts
                .take(6)
                .map(
                  (a) => GestureDetector(
                onTap: () => p.markRead(a.id),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    border: Border(
                      bottom: BorderSide(color: ST.gBorder, width: 0.5),
                    ),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        a.emoji,
                        style: const TextStyle(fontSize: 12),
                      ),
                      const SizedBox(width: 7),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              a.title,
                              style: ST
                                  .body(10, color: ST.t1)
                                  .copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            Text(
                              '${DateTime.now().difference(a.time).inMinutes}m ago',
                              style: ST.body(9, color: ST.t3),
                            ),
                          ],
                        ),
                      ),
                      if (!a.isRead)
                        Container(
                          width: 5,
                          height: 5,
                          margin: const EdgeInsets.only(top: 2),
                          decoration: const BoxDecoration(
                            color: ST.g0,
                            shape: BoxShape.circle,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            )
                .toList(),
          ),
        ),
      ],
    ),
  );
}

class _AnimalSheet extends StatelessWidget {
  final AnimalModel animal;
  const _AnimalSheet({required this.animal});
  @override
  build(BuildContext context) {
    final conf = (animal.confidence * 100).round();
    final cc =
    conf > 90
        ? ST.g0
        : conf > 80
        ? ST.amber
        : ST.red;
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: ST.gBorder,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Text(animal.emoji, style: const TextStyle(fontSize: 44)),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      animal.name,
                      style: ST
                          .body(17, color: ST.t1)
                          .copyWith(fontWeight: FontWeight.w800),
                    ),
                    Text(
                      animal.species,
                      style: ST
                          .body(10, color: ST.t3)
                          .copyWith(fontStyle: FontStyle.italic),
                    ),
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: animal.color.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(5),
                      ),
                      child: Text(
                        animal.status,
                        style: ST.body(11, color: animal.color),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              _ShS('Zone', 'Zone ${animal.zone}', ST.t1),
              _ShS('AI Confidence', '$conf%', cc),
              _ShS('Sightings', '${animal.sightingCount}× today', ST.blueL),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: animal.confidence,
              minHeight: 6,
              backgroundColor: ST.card,
              valueColor: AlwaysStoppedAnimation(cc),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'AI Detection Confidence: $conf% via ${animal.detectedBy}',
            style: ST.body(10, color: cc),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: ST.cardBox(radius: 8),
            child: Text(
              '📍 Map position: (${(animal.x * 1000).round()}, ${(animal.y * 1000).round()})  ·  Live tracking active',
              style: ST.mono(9, color: ST.t3),
            ),
          ),
        ],
      ),
    );
  }
}

class _ShS extends StatelessWidget {
  final String l, v;
  final Color c;
  const _ShS(this.l, this.v, this.c);
  @override
  build(BuildContext context) => Expanded(
    child: Column(
      children: [
        Text(l.toUpperCase(), style: ST.label(7.5, color: ST.t3)),
        const SizedBox(height: 3),
        Text(
          v,
          style: ST.body(12, color: c).copyWith(fontWeight: FontWeight.w700),
        ),
      ],
    ),
  );
}

class _VehicleSheet extends StatelessWidget {
  final VehicleModel vehicle;
  const _VehicleSheet({required this.vehicle});
  Color get _sc =>
      vehicle.status == VehicleStatus.active
          ? ST.g0
          : vehicle.status == VehicleStatus.alert
          ? ST.red
          : ST.t3;
  @override
  build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(20),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 36,
          height: 4,
          decoration: BoxDecoration(
            color: ST.gBorder,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            const Text('🚙', style: TextStyle(fontSize: 40)),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    vehicle.name,
                    style: ST
                        .body(17, color: ST.t1)
                        .copyWith(fontWeight: FontWeight.w800),
                  ),
                  Text(
                    'Driver: ${vehicle.driverName}',
                    style: ST.body(11, color: ST.t3),
                  ),
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: _sc.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(5),
                    ),
                    child: Text(
                      vehicle.status.name.toUpperCase(),
                      style: ST.body(11, color: _sc),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            _ShS(
              'Speed',
              '${vehicle.speed.toStringAsFixed(0)} km/h',
              vehicle.speed > 14 ? ST.red : ST.g0,
            ),
            _ShS('Passengers', '${vehicle.passengers} aboard', ST.blueL),
            _ShS('Zone', vehicle.zone, ST.amber),
          ],
        ),
        const SizedBox(height: 12),
        _LvlBar('Battery', vehicle.batteryLevel / 100, ST.blueL),
        const SizedBox(height: 8),
        _LvlBar('Fuel Level', vehicle.fuelLevel / 100, ST.amber),
        const SizedBox(height: 8),
        if (vehicle.pirTriggered)
          Container(
            padding: const EdgeInsets.all(10),
            decoration: ST.glowBox(ST.red),
            child: Row(
              children: [
                const Icon(Icons.warning, color: ST.red, size: 16),
                const SizedBox(width: 8),
                Text(
                  'PIR Motion Sensor Triggered!',
                  style: ST.body(12, color: ST.redL),
                ),
              ],
            ),
          ),
      ],
    ),
  );
}

class _MapBtn extends StatelessWidget {
  final String icon, tooltip;
  final VoidCallback onTap;
  final bool active;
  const _MapBtn(this.icon, this.tooltip, this.onTap, {this.active = false});
  @override
  build(BuildContext context) => Tooltip(
    message: tooltip,
    child: GestureDetector(
      onTap: onTap,
      child: Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          color: active ? ST.gGlow : ST.panel.withOpacity(0.92),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: active ? ST.gBorderBright : ST.gBorder),
          boxShadow: [
            BoxShadow(color: Colors.black.withOpacity(0.3), blurRadius: 6),
          ],
        ),
        child: Center(
          child: Text(icon, style: const TextStyle(fontSize: 16, color: ST.t1)),
        ),
      ),
    ),
  );
}

class _LayerPanel extends StatelessWidget {
  final SProvider p;
  const _LayerPanel(this.p);
  @override
  build(BuildContext context) => Container(
    width: 130,
    padding: const EdgeInsets.all(8),
    decoration: ST.panelBox(radius: 10),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('LAYERS', style: ST.label(8, color: ST.t3)),
        const SizedBox(height: 6),
        ...[
          ('🐾 Animals', 'animals'),
          ('🚙 Vehicles', 'vehicles'),
          ('🗺 Zones', 'zones'),
          ('🛤 Roads', 'paths'),
          ('💧 Hotspots', 'hotspots'),
          if (p.isDriver || p.isAdmin) ('🏁 UNPLUGGED track', 'hackathonTrack'),
          if (p.isDriver || p.isAdmin) ('📍 Checkpoints', 'checkpoints'),
        ].map(
              (e) => GestureDetector(
            onTap: () => p.toggleLayer(e.$2),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      color:
                      (p.layers[e.$2] ?? true) ? ST.g1 : Colors.transparent,
                      borderRadius: BorderRadius.circular(3),
                      border: Border.all(color: ST.g1.withOpacity(0.5)),
                    ),
                    child:
                    (p.layers[e.$2] ?? true)
                        ? const Icon(
                      Icons.check,
                      size: 9,
                      color: Colors.white,
                    )
                        : null,
                  ),
                  const SizedBox(width: 7),
                  Text(
                    e.$1,
                    style: ST.body(
                      11,
                      color: (p.layers[e.$2] ?? true) ? ST.t1 : ST.t3,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    ),
  );
}

class _ReplayBar extends StatefulWidget {
  final SProvider p;
  const _ReplayBar({required this.p});
  @override
  State<_ReplayBar> createState() => _ReplayBarState();
}

class _ReplayBarState extends State<_ReplayBar> {
  double _v = 0;
  bool _pl = false;
  String get _ts {
    final h = 8 + (_v / 100 * 10).floor();
    final m = ((_v % 10) * 6).floor();
    return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')} ${h < 12 ? 'AM' : 'PM'}';
  }

  @override
  build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
    decoration: ST.panelBox(radius: 10),
    child: Row(
      children: [
        GestureDetector(
          onTap: () => setState(() => _v = max(0, _v - 5)),
          child: const Text('⏮', style: TextStyle(fontSize: 14)),
        ),
        const SizedBox(width: 4),
        GestureDetector(
          onTap: () => setState(() => _pl = !_pl),
          child: Text(_pl ? '⏸' : '▶', style: const TextStyle(fontSize: 14)),
        ),
        const SizedBox(width: 4),
        GestureDetector(
          onTap: () => setState(() => _v = min(100, _v + 5)),
          child: const Text('⏭', style: TextStyle(fontSize: 14)),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: SliderTheme(
            data: SliderThemeData(
              trackHeight: 3,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
              thumbColor: ST.g0,
              activeTrackColor: ST.g1,
              inactiveTrackColor: ST.card,
            ),
            child: Slider(
              value: _v,
              min: 0,
              max: 100,
              onChanged: (v) => setState(() => _v = v),
            ),
          ),
        ),
        const SizedBox(width: 5),
        Text(_ts, style: ST.mono(9)),
        const SizedBox(width: 6),
        GestureDetector(
          onTap: () => widget.p.toggleReplay(),
          child: Text('✕', style: ST.body(13, color: ST.t3)),
        ),
      ],
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// ANALYTICS SCREEN (Admin only)
// ─────────────────────────────────────────────────────────────────────────────
// ─────────────────────────────────────────────────────────────────────────────
// UNPLUGGED LINE-FOLLOWER BOARD (driver / admin mobile)
// ─────────────────────────────────────────────────────────────────────────────
class LineFollowerOnlyPainter extends CustomPainter {
  final TrackCarTelemetry? trackTelemetry;
  final List<LiveDetection> liveDetections;
  final double tick;
  LineFollowerOnlyPainter({
    required this.trackTelemetry,
    required this.liveDetections,
    required this.tick,
  });
  @override
  void paint(Canvas canvas, Size size) {
    final W = size.width, H = size.height;
    canvas.drawRect(Rect.fromLTWH(0, 0, W, H), Paint()..color = ST.bgDeep);
    const split = 0.48;
    canvas.drawRect(
      Rect.fromLTWH(0, 0, W * split, H),
      Paint()..color = const Color(0xFF080808),
    );
    canvas.drawRect(
      Rect.fromLTWH(W * split, 0, W * (1 - split), H),
      Paint()..color = const Color(0xFFD8C8A8),
    );
    final pts = MapPaths.lineFollowerTrack;
    final dr = MapPaths.lineFollowerDashedRange;
    if (pts.length > 1) {
      for (int j = 0; j < pts.length - 1; j++) {
        final dash = j >= dr[0] && j < dr[1];
        canvas.drawLine(
          Offset(pts[j][0] * W, pts[j][1] * H),
          Offset(pts[j + 1][0] * W, pts[j + 1][1] * H),
          Paint()
            ..color = dash ? const Color(0xEEFFFFFF) : const Color(0xFF0A0A0A)
            ..strokeWidth = dash ? 2.8 : 4.2
            ..strokeCap = StrokeCap.round,
        );
      }
    }
    for (final c in MapPaths.lineFollowerCheckpoints) {
      final cx = (c['x'] as double) * W, cy = (c['y'] as double) * H;
      canvas.drawCircle(Offset(cx, cy), 7, Paint()..color = ST.amber);
      (TextPainter(
        text: TextSpan(
          text: c['label'] as String,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 8,
            fontWeight: FontWeight.w700,
            shadows: [Shadow(color: Colors.black, blurRadius: 3)],
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout())
          .paint(canvas, Offset(cx + 8, cy - 6));
    }
    for (final d in liveDetections.take(12)) {
      final dx = d.x * W, dy = d.y * H;
      canvas.drawCircle(Offset(dx, dy), 11, Paint()..color = ST.blue.withOpacity(0.4));
      (TextPainter(
        text: TextSpan(text: d.emoji, style: const TextStyle(fontSize: 12)),
        textDirection: TextDirection.ltr,
      )..layout())
          .paint(canvas, Offset(dx - 6, dy - 7));
    }
    if (trackTelemetry != null) {
      final cx = trackTelemetry!.x * W, cy = trackTelemetry!.y * H;
      canvas.save();
      canvas.translate(cx, cy);
      canvas.rotate(trackTelemetry!.direction * pi / 180);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          const Rect.fromLTWH(-11, -7, 22, 14),
          const Radius.circular(4),
        ),
        Paint()..color = ST.g1,
      );
      canvas.restore();
    }
    (TextPainter(
      text: TextSpan(
        text: 'UNPLUGGED · LIVE',
        style: TextStyle(
          color: ST.amberL,
          fontSize: 12,
          fontWeight: FontWeight.w800,
          shadows: const [Shadow(color: Colors.black, blurRadius: 4)],
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout())
        .paint(canvas, const Offset(12, 10));
  }

  @override
  bool shouldRepaint(covariant LineFollowerOnlyPainter old) =>
      old.tick != tick ||
      old.trackTelemetry != trackTelemetry ||
      old.liveDetections.length != liveDetections.length;
}

class LineFollowerScreen extends StatefulWidget {
  const LineFollowerScreen({super.key});
  @override
  State<LineFollowerScreen> createState() => _LineFollowerScreenState();
}

class _LineFollowerScreenState extends State<LineFollowerScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _ac;
  @override
  void initState() {
    super.initState();
    _ac = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 200),
    )..repeat();
  }

  @override
  void dispose() {
    _ac.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.watch<SProvider>();
    final t = _ac.value * 200 * 60;
    final aqi = p.aqiData;
    return Scaffold(
      backgroundColor: ST.bg,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _RoleBanner(
                    p.isDriver ? '🚙 Driver · Line Follower' : '🛡 Ops · Track',
                    'Official UNPLUGGED path · ESP32 `vehicles/car_1`',
                    ST.blueL,
                  ),
                  if (p.lastAdminCommand != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(10),
                        decoration: ST.glowBox(ST.amber),
                        child: Text(
                          'Last admin command: ${p.lastAdminCommand}',
                          style: ST.mono(10, color: ST.amberL),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: AnimatedBuilder(
                    animation: _ac,
                    builder: (_, __) => CustomPaint(
                      painter: LineFollowerOnlyPainter(
                        trackTelemetry: p.trackTelemetry,
                        liveDetections: p.liveDetections,
                        tick: t,
                      ),
                      size: Size.infinite,
                    ),
                  ),
                ),
              ),
            ),
            if (aqi != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: ST.cardBox(),
                  child: Row(
                    children: [
                      Text('🌫', style: const TextStyle(fontSize: 20)),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'AQI ${aqi.aqi.toStringAsFixed(0)} · PM2.5 ${aqi.pm25.toStringAsFixed(0)}',
                              style: ST.body(12, color: ST.t1)
                                  .copyWith(fontWeight: FontWeight.w700),
                            ),
                            Text(
                              aqi.forecastSummary,
                              style: ST.body(10, color: ST.t3),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      Text(
                        '${aqi.temperature.toStringAsFixed(0)}°C\n${aqi.rainChance4h}% rain',
                        style: ST.mono(10, color: ST.tealL),
                        textAlign: TextAlign.end,
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// ADMIN WEB COMMAND CENTER (Flutter web)
// ─────────────────────────────────────────────────────────────────────────────
class AdminWebCommandCenter extends StatefulWidget {
  const AdminWebCommandCenter({super.key});
  @override
  State<AdminWebCommandCenter> createState() => _AdminWebCommandCenterState();
}

class _AdminWebCommandCenterState extends State<AdminWebCommandCenter>
    with SingleTickerProviderStateMixin {
  late AnimationController _ac;
  double _speed = 35;

  @override
  void initState() {
    super.initState();
    _ac = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 200),
    )..repeat();
  }

  @override
  void dispose() {
    _ac.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.watch<SProvider>();
    final t = _ac.value * 200 * 60;
    final aqi = p.aqiData;
    return Scaffold(
      backgroundColor: ST.bg,
      appBar: AppBar(
        backgroundColor: ST.bgDeep,
        title: Text('SAFARISYNC COMMAND', style: ST.bebas(20)),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Center(
              child: Text(
                '${p.userName} · ADMIN WEB',
                style: ST.label(8, color: ST.amberL),
              ),
            ),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(context).pushAndRemoveUntil(
                MaterialPageRoute(builder: (_) => const AuthGateScreen()),
                (_) => false,
              );
            },
            child: Text('Sign out', style: ST.body(12, color: ST.redL)),
          ),
        ],
      ),
      body: LayoutBuilder(
        builder: (ctx, c) {
          final wide = c.maxWidth > 900;
          Widget trackBlock() => Padding(
                padding: const EdgeInsets.all(12),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: AnimatedBuilder(
                    animation: _ac,
                    builder: (_, __) => CustomPaint(
                      painter: LineFollowerOnlyPainter(
                        trackTelemetry: p.trackTelemetry,
                        liveDetections: p.liveDetections,
                        tick: t,
                      ),
                      size: Size.infinite,
                    ),
                  ),
                ),
              );
          final panel = Expanded(
            flex: wide ? 3 : 1,
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('VEHICLE CONTROL', style: ST.label(9, color: ST.t3)),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _CmdChip('▶ AUTO', () => p.sendAdminVehicleCommand('auto', speed: _speed)),
                      _CmdChip('■ STOP', () => p.sendAdminVehicleCommand('stop')),
                      _CmdChip('⟲ SLOW', () => p.sendAdminVehicleCommand('slow', speed: 18)),
                      _CmdChip('⏩ BOOST', () => p.sendAdminVehicleCommand('boost', speed: 55)),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text('SPEED PRESET', style: ST.label(9, color: ST.t3)),
                  Slider(
                    value: _speed,
                    min: 10,
                    max: 80,
                    divisions: 14,
                    label: '${_speed.round()}%',
                    activeColor: ST.g0,
                    onChanged: (v) => setState(() => _speed = v),
                  ),
                  const SizedBox(height: 14),
                  if (aqi != null) ...[
                    Text('ENV / AQI', style: ST.label(9, color: ST.t3)),
                    const SizedBox(height: 8),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: ST.cardBox(),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${aqi.temperature.toStringAsFixed(1)}°C · ${aqi.humidity.toStringAsFixed(0)}% RH',
                            style: ST.bebas(22, color: ST.tealL),
                          ),
                          Text(
                            'AQI ${aqi.aqi.toStringAsFixed(0)} · PM2.5 ${aqi.pm25.toStringAsFixed(0)} · PM10 ${aqi.pm10.toStringAsFixed(0)}',
                            style: ST.mono(10, color: ST.t2),
                          ),
                          const SizedBox(height: 6),
                          Text(aqi.forecastSummary, style: ST.body(11, color: ST.t3)),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                  ],
                  Text('MISSION', style: ST.label(9, color: ST.t3)),
                  const SizedBox(height: 8),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: ST.glowBox(ST.g1),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Elapsed ${_fmtDur(p.trackRunElapsed)}',
                          style: ST.bebas(20, color: ST.g0),
                        ),
                        Text(
                          '${p.liveDetections.length} vision hits · RFID ${p.rfidFinishSeen ? "DONE ✓" : "pending"}',
                          style: ST.body(11, color: ST.t2),
                        ),
                        if (p.trackTelemetry != null)
                          Text(
                            'car_1 @ (${(p.trackTelemetry!.x * 100).toStringAsFixed(1)}%, ${(p.trackTelemetry!.y * 100).toStringAsFixed(1)}%)  '
                            '${p.trackTelemetry!.inTelemetryDashedZone ? "· DATA ZONE" : ""}',
                            style: ST.mono(9, color: ST.amberL),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text('VISION LOG', style: ST.label(9, color: ST.t3)),
                  const SizedBox(height: 8),
                  ...p.liveDetections.take(8).map(
                        (d) => Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: Container(
                            padding: const EdgeInsets.all(8),
                            decoration: ST.panelBox(radius: 8),
                            child: Row(
                              children: [
                                Text(d.emoji, style: const TextStyle(fontSize: 16)),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    '${d.label} · ${(d.confidence * 100).round()}%',
                                    style: ST.body(11, color: ST.t1),
                                  ),
                                ),
                                Text(
                                  '${d.x.toStringAsFixed(2)},${d.y.toStringAsFixed(2)}',
                                  style: ST.mono(9, color: ST.t3),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                ],
              ),
            ),
          );
          if (wide) {
            return Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(flex: 5, child: trackBlock()),
                panel,
              ],
            );
          }
          return Column(
            children: [
              Expanded(flex: 5, child: trackBlock()),
              panel,
            ],
          );
        },
      ),
    );
  }

  String _fmtDur(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    final h = d.inHours;
    return '${h.toString().padLeft(2, '0')}:$m:$s';
  }
}

class _CmdChip extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _CmdChip(this.label, this.onTap);
  @override
  Widget build(BuildContext context) => ActionChip(
        label: Text(label, style: ST.label(8, color: ST.bgDeep)),
        backgroundColor: ST.g1,
        side: BorderSide(color: ST.gBorderBright),
        onPressed: onTap,
      );
}

class AnalyticsScreen extends StatelessWidget {
  const AnalyticsScreen({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: ST.bg,
    body: SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _RoleBanner(
            '🛡 Admin Dashboard',
            'Full system analytics & control',
            ST.amber,
          ),
          const SizedBox(height: 14),
          Text('ANALYTICS', style: ST.bebas(28)),
          Text(
            '7-day summary · Real-time insights',
            style: ST.body(11, color: ST.t3),
          ),
          const SizedBox(height: 14),
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisSpacing: 10,
            mainAxisSpacing: 10,
            childAspectRatio: 1.8,
            children: [
              _BigStat('457', 'Total Sightings', ST.g0, '↑ 23%'),
              _BigStat('142h', 'Jeep Hours', ST.amber, '6 routes'),
              _BigStat('₹8.4L', 'Revenue', ST.blueL, '↑ 18%'),
              _BigStat('94.2%', 'AI Accuracy', ST.tealL, 'YOLOv8'),
            ],
          ),
          const SizedBox(height: 10),
          _BigStat('12/14', 'Nodes Online', ST.purple, '2 offline'),
          const SizedBox(height: 16),
          _AnalCard(
            'Daily Tourist Count (This Week)',
            child: SizedBox(
              height: 180,
              child: BarChart(
                BarChartData(
                  borderData: FlBorderData(show: false),
                  gridData: FlGridData(
                    show: true,
                    drawVerticalLine: false,
                    horizontalInterval: 30,
                    getDrawingHorizontalLine:
                        (_) => FlLine(color: ST.gBorder, strokeWidth: 0.5),
                  ),
                  titlesData: FlTitlesData(
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 20,
                        getTitlesWidget: (v, _) {
                          const d = [
                            'Mon',
                            'Tue',
                            'Wed',
                            'Thu',
                            'Fri',
                            'Sat',
                            'Sun',
                          ];
                          return v.toInt() < 7
                              ? Text(
                            d[v.toInt()],
                            style: ST.body(9, color: ST.t3),
                          )
                              : const SizedBox();
                        },
                      ),
                    ),
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 28,
                        getTitlesWidget:
                            (v, _) => Text(
                          v.toInt().toString(),
                          style: ST.body(9, color: ST.t3),
                        ),
                      ),
                    ),
                    rightTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    topTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                  ),
                  barGroups:
                  [42, 55, 38, 67, 72, 89, 94]
                      .asMap()
                      .entries
                      .map(
                        (e) => BarChartGroupData(
                      x: e.key,
                      barRods: [
                        BarChartRodData(
                          toY: e.value.toDouble(),
                          color:
                          e.key == 6
                              ? ST.g0
                              : ST.g1.withOpacity(0.5),
                          width: 22,
                          borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(4),
                          ),
                        ),
                      ],
                    ),
                  )
                      .toList(),
                ),
              ),
            ),
          ),
          const SizedBox(height: 14),
          _AnalCard(
            'Animal Activity (24h)',
            child: SizedBox(
              height: 150,
              child: LineChart(
                LineChartData(
                  borderData: FlBorderData(show: false),
                  gridData: FlGridData(
                    show: true,
                    drawVerticalLine: false,
                    getDrawingHorizontalLine:
                        (_) => FlLine(color: ST.gBorder, strokeWidth: 0.5),
                  ),
                  titlesData: FlTitlesData(
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 18,
                        interval: 6,
                        getTitlesWidget:
                            (v, _) => Text(
                          '${v.toInt()}h',
                          style: ST.body(9, color: ST.t3),
                        ),
                      ),
                    ),
                    leftTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    rightTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    topTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                  ),
                  lineBarsData: [
                    LineChartBarData(
                      spots:
                      [
                        2,
                        3,
                        5,
                        4,
                        6,
                        9,
                        13,
                        15,
                        11,
                        10,
                        8,
                        7,
                        5,
                        4,
                        3,
                        5,
                        7,
                        10,
                        15,
                        20,
                        22,
                        17,
                        13,
                        9,
                      ]
                          .asMap()
                          .entries
                          .map(
                            (e) => FlSpot(
                          e.key.toDouble(),
                          e.value.toDouble(),
                        ),
                      )
                          .toList(),
                      isCurved: true,
                      color: ST.g1,
                      barWidth: 2.5,
                      dotData: const FlDotData(show: false),
                      belowBarData: BarAreaData(
                        show: true,
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [ST.g1.withOpacity(0.28), Colors.transparent],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 14),
          _AnalCard(
            'Top Sighted Animals',
            child: Column(
              children:
              [
                ['🐘', 'Elephant', 0.34, ST.g0],
                ['🦁', 'Lion', 0.22, ST.amber],
                ['🦒', 'Giraffe', 0.18, ST.blueL],
                ['🦓', 'Zebra', 0.15, ST.t2],
                ['🦌', 'Impala', 0.11, ST.purple],
              ]
                  .map(
                    (r) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    children: [
                      Text(
                        r[0] as String,
                        style: const TextStyle(fontSize: 16),
                      ),
                      const SizedBox(width: 7),
                      SizedBox(
                        width: 70,
                        child: Text(
                          r[1] as String,
                          style: ST.body(12, color: ST.t2),
                        ),
                      ),
                      Expanded(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(3),
                          child: LinearProgressIndicator(
                            value: r[2] as double,
                            minHeight: 6,
                            backgroundColor: ST.card,
                            valueColor: AlwaysStoppedAnimation(
                              r[3] as Color,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 7),
                      Text(
                        '${((r[2] as double) * 100).round()}%',
                        style: ST
                            .body(10, color: r[3] as Color)
                            .copyWith(fontWeight: FontWeight.w700),
                      ),
                    ],
                  ),
                ),
              )
                  .toList(),
            ),
          ),
          const SizedBox(height: 14),
          _AnalCard(
            'ESP32 Node Health (14 Nodes)',
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              children: List.generate(14, (i) {
                final ok = i != 6 && i != 11;
                return Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 9,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: (ok ? ST.g0 : ST.red).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(5),
                    border: Border.all(
                      color: (ok ? ST.g0 : ST.red).withOpacity(0.28),
                    ),
                  ),
                  child: Text(
                    'N-${(i + 1).toString().padLeft(2, '0')}',
                    style: ST.mono(9, color: ok ? ST.g0 : ST.red),
                  ),
                );
              }),
            ),
          ),
          const SizedBox(height: 14),
          _AnalCard(
            'Revenue Breakdown',
            child: Column(
              children:
              [
                ['🎫 Tickets', '₹5.2L', ST.g0, 0.62],
                ['🚙 Vehicle Hire', '₹2.1L', ST.amber, 0.25],
                ['📸 Photography', '₹0.8L', ST.blueL, 0.10],
                ['🍽 Food & Bev', '₹0.3L', ST.purple, 0.04],
              ]
                  .map(
                    (r) => Padding(
                  padding: const EdgeInsets.only(bottom: 9),
                  child: Row(
                    children: [
                      Text(
                        r[0] as String,
                        style: ST.body(11, color: ST.t2),
                      ),
                      const Spacer(),
                      Text(
                        r[1] as String,
                        style: ST
                            .body(11, color: r[2] as Color)
                            .copyWith(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(width: 8),
                      SizedBox(
                        width: 70,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(3),
                          child: LinearProgressIndicator(
                            value: r[3] as double,
                            minHeight: 6,
                            backgroundColor: ST.card,
                            valueColor: AlwaysStoppedAnimation(
                              r[2] as Color,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              )
                  .toList(),
            ),
          ),
        ],
      ),
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// FLEET SCREEN (Admin: all vehicles | Driver: own vehicle focus)
// ─────────────────────────────────────────────────────────────────────────────
class FleetScreen extends StatelessWidget {
  final bool forDriver;
  const FleetScreen({super.key, this.forDriver = false});
  @override
  Widget build(BuildContext context) {
    final p = context.watch<SProvider>();
    final vehicles =
    forDriver && p.assignedVehicleId != null
        ? p.vehicles.where((v) => v.id == p.assignedVehicleId).toList()
        : p.vehicles;

    return Scaffold(
      backgroundColor: ST.bg,
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (forDriver)
              _RoleBanner(
                '🚙 Driver Mode',
                'Your vehicle status & navigation',
                ST.blueL,
              )
            else
              _RoleBanner(
                '🛡 Fleet Management',
                'All vehicles · Real-time status',
                ST.amber,
              ),
            const SizedBox(height: 14),
            Text(
              forDriver ? 'MY VEHICLE' : 'FLEET MANAGEMENT',
              style: ST.bebas(28),
            ),
            const SizedBox(height: 14),

            if (!forDriver)
              Row(
                children: [
                  _FlStat(
                    '${p.vehicles.where((v) => v.status == VehicleStatus.active).length}',
                    'Active',
                    ST.g0,
                  ),
                  const SizedBox(width: 10),
                  _FlStat(
                    '${p.vehicles.where((v) => v.status == VehicleStatus.parked).length}',
                    'Parked',
                    ST.t3,
                  ),
                  const SizedBox(width: 10),
                  _FlStat(
                    '${p.vehicles.where((v) => v.status == VehicleStatus.alert).length}',
                    'Alert',
                    ST.red,
                  ),
                ],
              ),
            if (!forDriver) const SizedBox(height: 14),

            ...vehicles.map(
                  (v) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _VehicleCard(v: v),
              ),
            ),

            if (forDriver) ...[
              const SizedBox(height: 16),
              _AnalCard(
                'NAVIGATION GUIDANCE',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ...[
                      [
                        '🦁',
                        'Zone B Alert',
                        'Lion activity detected ahead — slow down',
                        ST.red,
                      ],
                      [
                        '🐘',
                        'Zone A Clear',
                        'Elephant herd moved north — safe passage',
                        ST.g0,
                      ],
                      [
                        '💧',
                        'Waterhole Ahead',
                        'Reduce speed for animal crossing',
                        ST.blueL,
                      ],
                      [
                        '🌡',
                        'High Temp',
                        '42°C — ensure tourist hydration',
                        ST.amber,
                      ],
                    ].map(
                          (i) => Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              width: 28,
                              height: 28,
                              decoration: BoxDecoration(
                                color: (i[3] as Color).withOpacity(0.15),
                                borderRadius: BorderRadius.circular(7),
                              ),
                              child: Center(
                                child: Text(
                                  i[0] as String,
                                  style: const TextStyle(fontSize: 13),
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    i[1] as String,
                                    style: ST
                                        .body(12, color: i[3] as Color)
                                        .copyWith(fontWeight: FontWeight.w700),
                                  ),
                                  Text(
                                    i[2] as String,
                                    style: ST.body(11, color: ST.t2),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              _AnalCard(
                'AI PREDICTIONS',
                child: Column(
                  children:
                  SD.predictions.map((d) => _PredRow(data: d)).toList(),
                ),
              ),
            ] else ...[
              const SizedBox(height: 14),
              _AnalCard(
                'AI PREDICTIONS',
                child: Column(
                  children:
                  SD.predictions.map((d) => _PredRow(data: d)).toList(),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// ALERTS MANAGEMENT SCREEN (Admin only)
// ─────────────────────────────────────────────────────────────────────────────
class AlertsManagementScreen extends StatelessWidget {
  const AlertsManagementScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final p = context.watch<SProvider>();
    return Scaffold(
      backgroundColor: ST.bg,
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _RoleBanner(
              '🛡 Admin · Alert Management',
              'Monitor & manage all system alerts',
              ST.amber,
            ),
            const SizedBox(height: 14),
            Text('SYSTEM ALERTS', style: ST.bebas(28)),
            Text(
              '${p.alerts.length} total · ${p.unreadAlerts} unread critical',
              style: ST.body(11, color: ST.t3),
            ),
            const SizedBox(height: 14),
            // SOS active events
            if (p.sosAlerts.isNotEmpty) ...[
              Container(padding: const EdgeInsets.all(12), decoration: ST.glowBox(ST.red),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('🆘 ACTIVE SOS EVENTS', style: ST.label(9, color: ST.red)),
                    const SizedBox(height: 8),
                    ...p.sosAlerts.map((s) => Padding(padding: const EdgeInsets.only(bottom: 8),
                        child: Row(children: [
                          Container(width: 8, height: 8, decoration: const BoxDecoration(color: ST.red, shape: BoxShape.circle)),
                          const SizedBox(width: 8),
                          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(s.sosVehicleName ?? 'Unknown Vehicle',
                                style: ST.body(12, color: ST.redL).copyWith(fontWeight: FontWeight.w700)),
                            Text('By: ${s.sosTriggerBy ?? 'Unknown'} · ${DateTime.now().difference(s.time).inMinutes}m ago',
                                style: ST.body(10, color: ST.t3)),
                            if (s.sosLat != null)
                              Text('GPS: ${s.sosLat!.toStringAsFixed(4)}, ${s.sosLng!.toStringAsFixed(4)}',
                                  style: ST.mono(9, color: ST.amber)),
                          ])),
                        ]))),
                  ])),
              const SizedBox(height: 14),
            ],
            Row(
              children: [
                _FlStat(
                  '${p.alerts.where((a) => a.type == AlertType.critical).length}',
                  'Critical',
                  ST.red,
                ),
                const SizedBox(width: 10),
                _FlStat(
                  '${p.alerts.where((a) => a.type == AlertType.warning).length}',
                  'Warning',
                  ST.amber,
                ),
                const SizedBox(width: 10),
                _FlStat(
                  '${p.alerts.where((a) => a.type == AlertType.info).length}',
                  'Info',
                  ST.blueL,
                ),
              ],
            ),
            const SizedBox(height: 16),
            ...p.alerts.map(
                  (a) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _AlertCard(alert: a, onRead: () => p.markRead(a.id)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AlertCard extends StatelessWidget {
  final AlertModel alert;
  final VoidCallback onRead;
  const _AlertCard({required this.alert, required this.onRead});
  Color get _bc =>
      alert.type == AlertType.critical
          ? ST.red
          : alert.type == AlertType.warning
          ? ST.amber
          : ST.blueL;
  @override
  build(BuildContext context) {
    final diff = DateTime.now().difference(alert.time);
    final ts =
    diff.inMinutes < 60 ? '${diff.inMinutes}m ago' : '${diff.inHours}h ago';
    return GestureDetector(
      onTap: onRead,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: ST.cardBox(
          border: alert.isRead ? null : _bc.withOpacity(0.3),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: _bc.withOpacity(0.15),
                borderRadius: BorderRadius.circular(9),
              ),
              child: Center(
                child: Text(alert.emoji, style: const TextStyle(fontSize: 16)),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          alert.title,
                          style: ST
                              .body(12, color: ST.t1)
                              .copyWith(fontWeight: FontWeight.w700),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: _bc.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          alert.type.name.toUpperCase(),
                          style: ST.label(7.5, color: _bc),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(alert.message, style: ST.body(10.5, color: ST.t2)),
                  const SizedBox(height: 3),
                  Text(ts, style: ST.body(9, color: ST.t3)),
                ],
              ),
            ),
            if (!alert.isRead)
              Container(
                width: 8,
                height: 8,
                margin: const EdgeInsets.only(top: 4),
                decoration: const BoxDecoration(
                  color: ST.g0,
                  shape: BoxShape.circle,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// IMU SCREEN (Admin + Driver)
// ─────────────────────────────────────────────────────────────────────────────
class ImuScreen extends StatelessWidget {
  const ImuScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final p = context.watch<SProvider>();
    final imu = p.imuData;
    if (imu == null)
      return Scaffold(
        backgroundColor: ST.bg,
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(color: ST.g1),
              const SizedBox(height: 16),
              Text(
                'Waiting for GY-91 data...',
                style: ST.body(14, color: ST.t3),
              ),
            ],
          ),
        ),
      );
    return Scaffold(
      backgroundColor: ST.bg,
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (p.isDriver)
              _RoleBanner(
                '🚙 Driver · Vehicle Sensors',
                'Your jeep\'s live sensor data',
                ST.blueL,
              ),
            Text('GY-91 IMU', style: ST.bebas(28)),
            Text(
              'MPU9250 + BMP280 · Real-time sensor fusion · 20Hz',
              style: ST.body(11, color: ST.t3),
            ),
            const SizedBox(height: 14),
            GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisSpacing: 10,
              mainAxisSpacing: 10,
              childAspectRatio: 1.8,
              children: [
                _ImuBig(
                  'TEMPERATURE',
                  '${imu.temperature.toStringAsFixed(1)}°C',
                  ST.amber,
                ),
                _ImuBig(
                  'PRESSURE',
                  '${imu.pressure.toStringAsFixed(1)} hPa',
                  ST.blueL,
                ),
                _ImuBig(
                  'ALTITUDE',
                  '${imu.altitude.toStringAsFixed(1)} m',
                  ST.tealL,
                ),
                _ImuBig('HEADING', '${imu.heading.toStringAsFixed(0)}°', ST.g0),
              ],
            ),
            if (p.aqiData != null) ...[
              const SizedBox(height: 14),
              _AnalCard(
                'AQI NODE (PMS5003 / equivalent)',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      p.aqiData!.aqi.toStringAsFixed(0),
                      style: ST.bebas(34,
                          color: p.aqiData!.aqi > 100 ? ST.red : ST.g0),
                    ),
                    Text(
                      p.aqiData!.forecastSummary,
                      style: ST.body(11, color: ST.t2),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'PM2.5 ${p.aqiData!.pm25.toStringAsFixed(1)} · PM10 ${p.aqiData!.pm10.toStringAsFixed(1)} · '
                      'RH ${p.aqiData!.humidity.toStringAsFixed(0)}% · Rain≤4h ${p.aqiData!.rainChance4h}%',
                      style: ST.mono(10, color: ST.t3),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: ST.cardBox(),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('COMPASS', style: ST.label(9, color: ST.t3)),
                  const SizedBox(height: 12),
                  Center(
                    child: SizedBox(
                      width: 160,
                      height: 160,
                      child: CustomPaint(
                        painter: _CompassPainter(imu.heading),
                        size: const Size(160, 160),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Center(
                    child: Text(
                      '${imu.heading.toStringAsFixed(1)}°',
                      style: ST.bebas(32, color: ST.g0),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            _AnalCard(
              'Accelerometer (m/s²)',
              child: Column(
                children: [
                  _SensorBar('Ax', imu.ax, ST.g0, -3, 3),
                  _SensorBar('Ay', imu.ay, ST.blueL, -3, 3),
                  _SensorBar('Az', imu.az, ST.amber, 0, 20),
                ],
              ),
            ),
            const SizedBox(height: 14),
            _AnalCard(
              'Gyroscope (°/s)',
              child: Column(
                children: [
                  _SensorBar('Gx', imu.gx, ST.purple, -10, 10),
                  _SensorBar('Gy', imu.gy, ST.pink, -10, 10),
                  _SensorBar('Gz', imu.gz, ST.tealL, -10, 10),
                ],
              ),
            ),
            const SizedBox(height: 14),
            _AnalCard(
              'Raw JSON — ESP32 → Firebase RTDB',
              child: Container(
                padding: const EdgeInsets.all(10),
                decoration: ST.panelBox(radius: 8),
                child: Text(
                  '{\n  "device":"GY-91","node":"jeep_1",\n'
                      '  "accel":{"x":${imu.ax.toStringAsFixed(3)},"y":${imu.ay.toStringAsFixed(3)},"z":${imu.az.toStringAsFixed(3)}},\n'
                      '  "gyro":{"x":${imu.gx.toStringAsFixed(3)},"y":${imu.gy.toStringAsFixed(3)},"z":${imu.gz.toStringAsFixed(3)}},\n'
                      '  "bmp":{"temp":${imu.temperature.toStringAsFixed(2)},"pressure":${imu.pressure.toStringAsFixed(2)},"alt":${imu.altitude.toStringAsFixed(2)}},\n'
                      '  "heading":${imu.heading.toStringAsFixed(2)}\n}',
                  style: ST.mono(10, color: ST.g0),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// TICKETING SCREEN (Tourist + Admin)
// ─────────────────────────────────────────────────────────────────────────────
// ─────────────────────────────────────────────────────────────────────────────
// TICKETING SCREEN — Slot-based, real-time Firebase booking (like BookMyShow)
// ─────────────────────────────────────────────────────────────────────────────
class TicketingScreen extends StatefulWidget {
  const TicketingScreen({super.key});
  @override State<TicketingScreen> createState() => _TicketingState();
}
class _TicketingState extends State<TicketingScreen> {
  String? _selectedTicketTypeId;
  bool _loading = false;
  String? _bookingId, _qrData, _bookedType, _bookedDate, _bookedSlot;

  Future<void> _onSlotTap(SlotModel slot, TicketModel tt) async {
    if (slot.isFull) return;
    final result = await Navigator.push<bool>(
        context,
        MaterialPageRoute(
            builder: (_) => FakePaymentScreen(
                ticket: tt,
                date: slot.date,
                timeSlot: slot.timeLabel)));
    if (result == true && mounted) {
      setState(() => _loading = true);
      final prov = context.read<SProvider>();
      final id = await prov.bookSlot(
          slot.id, tt.id, slot.date, slot.timeLabel, tt.price, tt.type);
      if (mounted) {
        setState(() => _loading = false);
        if (id != null) {
          _simulateNotification(prov, id, tt, slot);
          final qr = prov.generateQrData(id, tt.id);
          // Show QR + bank popup first
          await _showBookingSuccessPopup(id, qr, tt, slot);
          if (mounted) {
            setState(() {
              _bookingId = id;
              _qrData = qr;
              _bookedType = tt.type;
              _bookedDate = slot.date;
              _bookedSlot = slot.timeLabel;
            });
          }
        } else {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              backgroundColor: ST.red.withOpacity(0.9),
              content: Text('This slot is full. Please choose another date.',
                  style: ST.body(12, color: Colors.white))));
        }
      }
    }
  }

  void _simulateNotification(
      SProvider prov, String id, TicketModel tt, SlotModel slot) {
    // Simulated email & SMS (replace with real service later)
    debugPrint('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
    debugPrint('📧 EMAIL → ${prov.userEmail}');
    debugPrint('   Booking ID: $id  |  ${tt.type}  |  ${slot.date}');
    debugPrint('📱 SMS → ${prov.userPhone}');
    debugPrint('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
  }

  // ── Booking success popup with QR + bank deduction ──
  Future<void> _showBookingSuccessPopup(
      String bookingId, String qrData, TicketModel tt, SlotModel slot) async {
    final last4 = ['4242','1234','5678','9012'][DateTime.now().second % 4];
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => Dialog(
        backgroundColor: ST.panel,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: ST.g0.withOpacity(0.08),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: ST.g0.withOpacity(0.25)),
              ),
              child: Row(children: [
                const Text('✅', style: TextStyle(fontSize: 28)),
                const SizedBox(width: 12),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Booking Confirmed!',
                    style: ST.body(16, color: ST.g0).copyWith(fontWeight: FontWeight.w900)),
                  Text('Your safari experience is locked in 🎉',
                    style: ST.body(11, color: ST.t3)),
                ])),
              ]),
            ),
            const SizedBox(height: 14),
            // Bank deduction message
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF0D2033),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFF1A4A7A).withOpacity(0.5)),
              ),
              child: Row(children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0072BC).withOpacity(0.2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Text('🏦', style: TextStyle(fontSize: 18)),
                ),
                const SizedBox(width: 12),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Bank Alert — HDFC Bank',
                    style: ST.label(9, color: ST.blueL)),
                  const SizedBox(height: 3),
                  Text('\u20b9${tt.price.toStringAsFixed(0)} debited from A/C XX$last4',
                    style: ST.body(13, color: ST.t1).copyWith(fontWeight: FontWeight.w800)),
                  Text('Ref: SafariSync · $bookingId',
                    style: ST.mono(9, color: ST.t4)),
                ])),
              ]),
            ),
            const SizedBox(height: 14),
            Text('YOUR TICKET QR', style: ST.label(9, color: ST.t3)),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
              child: QrImageView(
                data: qrData,
                version: QrVersions.auto,
                size: 180,
                eyeStyle: const QrEyeStyle(eyeShape: QrEyeShape.square, color: Colors.black),
                dataModuleStyle: const QrDataModuleStyle(
                  dataModuleShape: QrDataModuleShape.square, color: Colors.black),
              ),
            ),
            const SizedBox(height: 8),
            Text('Show at entry gate · RFID validates ticket',
              style: ST.body(10, color: ST.t3)),
            const SizedBox(height: 4),
            SelectableText(bookingId,
              style: ST.mono(10, color: ST.g0).copyWith(letterSpacing: 1.4)),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: ST.card, borderRadius: BorderRadius.circular(10)),
              child: Column(children: [
                _bRow2('Package', tt.type),
                _bRow2('Date', slot.date),
                _bRow2('Slot', slot.timeLabel),
                _bRow2('Amount', '\u20b9${tt.price.toStringAsFixed(0)}'),
              ]),
            ),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => Navigator.pop(ctx),
                style: ElevatedButton.styleFrom(
                  backgroundColor: ST.g1, foregroundColor: ST.bg,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                child: Text('View Full Ticket →',
                  style: ST.body(14, color: ST.bg).copyWith(fontWeight: FontWeight.w800)),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _bRow2(String k, String v) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(children: [
      Text(k, style: ST.body(11, color: ST.t3)),
      const Spacer(),
      Text(v, style: ST.body(11, color: ST.t1).copyWith(fontWeight: FontWeight.w700)),
    ]),
  );

  void _goToMyBookings() {
    // Navigate up to MainShell and switch tab
    final shell = context.findAncestorStateOfType<_MainShellState>();
    if (shell != null) {
      shell.switchToTab('My Trips');
    }
    // Reset ticketing state
    setState(() {
      _bookingId = null;
      _qrData = null;
      _bookedType = null;
      _selectedTicketTypeId = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final p = context.watch<SProvider>();

    if (_bookingId != null) {
      return _BookingConfirmNew(
          id: _bookingId!,
          qr: _qrData!,
          type: _bookedType!,
          date: _bookedDate!,
          timeSlot: _bookedSlot!,
          userName: p.userName,
          userEmail: p.userEmail,
          userPhone: p.userPhone,
          onGoToBookings: _goToMyBookings, // ← fixed redirect
          onClose: () => setState(() {
            _bookingId = null;
            _qrData = null;
            _bookedType = null;
            _selectedTicketTypeId = null;
          }));
    }

    return Scaffold(
        backgroundColor: ST.bg,
        body: Stack(children: [
          SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (p.isTourist)
                      _RoleBanner(
                          '🧳 Book Your Safari',
                          'Reserve up to 7 days in advance · Max 20 per slot',
                          ST.g0),
                    Text('SAFARI TICKETS', style: ST.bebas(28)),
                    Text('Select ticket · Choose date · Pay securely',
                        style: ST.body(11, color: ST.t3)),
                    const SizedBox(height: 14),
                    ...SD.tickets.map((tt) => Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: _TicketTypeCard(
                          ticket: tt,
                          selected: _selectedTicketTypeId == tt.id,
                          onTap: () => setState(() => _selectedTicketTypeId =
                          _selectedTicketTypeId == tt.id ? null : tt.id),
                        ))),
                    if (_selectedTicketTypeId != null)
                      _SlotCalendar(
                        ticket: SD.tickets
                            .firstWhere((t) => t.id == _selectedTicketTypeId),
                        slots: p.getSlotsForTicket(_selectedTicketTypeId!),
                        onSlotTap: _onSlotTap,
                      ),
                    const SizedBox(height: 80),
                  ])),
          if (_loading)
            Container(
                color: Colors.black.withOpacity(0.7),
                child:
                const Center(child: CircularProgressIndicator(color: ST.g1))),
        ]));
  }
}

class _TicketTypeCard extends StatelessWidget {
  final TicketModel ticket; final bool selected; final VoidCallback onTap;
  const _TicketTypeCard({required this.ticket, required this.selected, required this.onTap});
  @override build(BuildContext context) => GestureDetector(onTap: onTap,
      child: AnimatedContainer(duration: 200.ms, padding: const EdgeInsets.all(16),
          decoration: ST.cardBox(border: selected ? ticket.accentColor : null),
          child: Row(children: [
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(ticket.type, style: ST.body(16, color: ST.t1).copyWith(fontWeight: FontWeight.w800)),
              const SizedBox(height: 2),
              Text(ticket.description, style: ST.body(11, color: ST.t3)),
              const SizedBox(height: 6),
              Container(padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(color: ticket.accentColor.withOpacity(0.12), borderRadius: BorderRadius.circular(4)),
                  child: Text(ticket.timeSlot, style: ST.mono(9, color: ticket.accentColor))),
            ])),
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text('₹${ticket.price.toStringAsFixed(0)}', style: ST.bebas(28, color: ticket.accentColor)),
              Text('per person', style: ST.body(9, color: ST.t4)),
              const SizedBox(height: 6),
              Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                      color: selected ? ticket.accentColor : Colors.transparent,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: ticket.accentColor)),
                  child: Text(selected ? '▲ Hide' : 'See Slots →',
                      style: ST.body(10, color: selected ? ST.bg : ticket.accentColor)
                          .copyWith(fontWeight: FontWeight.w700))),
            ]),
          ])));
}

class _SlotCalendar extends StatelessWidget {
  final TicketModel ticket;
  final List<SlotModel> slots;
  final Function(SlotModel, TicketModel) onSlotTap;
  const _SlotCalendar({required this.ticket, required this.slots, required this.onSlotTap});

  String _fmtDate(String ds) {
    final dt = DateTime.tryParse(ds);
    if (dt == null) return ds;
    const months = ['','Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    const wdays = ['Mon','Tue','Wed','Thu','Fri','Sat','Sun'];
    return '${wdays[dt.weekday-1]}, ${dt.day} ${months[dt.month]}';
  }

  @override build(BuildContext context) => Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(14),
      decoration: ST.glowBox(ticket.accentColor),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('NEXT 7 DAYS — SLOT AVAILABILITY', style: ST.label(9, color: ticket.accentColor)),
        const SizedBox(height: 3),
        Text('Real-time · 20 seats max per slot · Book early!', style: ST.body(10, color: ST.t3)),
        const SizedBox(height: 12),
        ...slots.map((s) => Padding(padding: const EdgeInsets.only(bottom: 8),
            child: _SlotRow(slot: s, ticket: ticket, dateLabel: _fmtDate(s.date),
                onTap: () => onSlotTap(s, ticket)))),
      ]));
}

class _SlotRow extends StatelessWidget {
  final SlotModel slot; final TicketModel ticket;
  final String dateLabel; final VoidCallback onTap;
  const _SlotRow({required this.slot, required this.ticket, required this.dateLabel, required this.onTap});
  @override build(BuildContext context) {
    final rem = slot.maxCapacity - slot.bookedCount;
    final pct = slot.bookedCount / slot.maxCapacity;
    final sc = slot.isFull ? ST.red : slot.isAlmostFull ? ST.amber : ST.g0;
    final sl = slot.isFull ? 'SOLD OUT' : slot.isAlmostFull ? '$rem left' : 'Available';
    return GestureDetector(
      onTap: slot.isFull ? null : onTap,
      child: Container(padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
              color: slot.isFull ? ST.red.withOpacity(0.04) : ticket.accentColor.withOpacity(0.04),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: slot.isFull ? ST.red.withOpacity(0.2) : ticket.accentColor.withOpacity(0.25))),
          child: Row(children: [
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(dateLabel, style: ST.body(13, color: slot.isFull ? ST.t3 : ST.t1).copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 2),
              Text(slot.timeLabel, style: ST.mono(10, color: ST.t3)),
              const SizedBox(height: 6),
              ClipRRect(borderRadius: BorderRadius.circular(2),
                  child: LinearProgressIndicator(value: pct, minHeight: 4, backgroundColor: ST.panel,
                      valueColor: AlwaysStoppedAnimation(sc.withOpacity(0.5)))),
              const SizedBox(height: 2),
              Text('${slot.bookedCount}/${slot.maxCapacity} booked', style: ST.body(9, color: ST.t3)),
            ])),
            const SizedBox(width: 12),
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(color: sc.withOpacity(0.15), borderRadius: BorderRadius.circular(5)),
                  child: Text(sl, style: ST.label(9, color: sc))),
              if (!slot.isFull) ...[
                const SizedBox(height: 6),
                Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                    decoration: BoxDecoration(color: ticket.accentColor, borderRadius: BorderRadius.circular(6)),
                    child: Text('Book ₹${ticket.price.toStringAsFixed(0)}',
                        style: ST.body(10, color: ST.bg).copyWith(fontWeight: FontWeight.w800))),
              ],
            ]),
          ])),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// ROUTES SCREEN
// ─────────────────────────────────────────────────────────────────────────────
class RoutesScreen extends StatelessWidget {
  const RoutesScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final p = context.watch<SProvider>();
    return Scaffold(
      backgroundColor: ST.bg,
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (p.isTourist)
              _RoleBanner(
                '🧳 Tourist · Recommended Routes',
                'AI-curated paths for best sightings',
                ST.g0,
              )
            else if (p.isDriver)
              _RoleBanner(
                '🚙 Driver · Route Planning',
                'Today\'s active routes & conditions',
                ST.blueL,
              )
            else
              _RoleBanner(
                '🛡 Admin · All Routes',
                'Manage & monitor all safari routes',
                ST.amber,
              ),
            Text('SMART ROUTING', style: ST.bebas(28)),
            Text(
              'AI-optimized · Real-time animal awareness',
              style: ST.body(11, color: ST.t3),
            ),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: ST.cardBox(),
              child: Row(
                children: [
                  const Text('🧠', style: TextStyle(fontSize: 16)),
                  const SizedBox(width: 10),
                  Text(
                    'AI analysis complete · 3 routes · Updated 2m ago',
                    style: ST.body(11, color: ST.t2),
                  ),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: ST.glowBox(ST.g1),
                    child: Text('LIVE', style: ST.label(9, color: ST.g0)),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            ...SD.routes.map(
                  (r) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _RouteCard(r: r),
              ),
            ),
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: ST.glowBox(ST.g1),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Text('🚦', style: TextStyle(fontSize: 16)),
                      const SizedBox(width: 8),
                      Text(
                        'AI RECOMMENDATION',
                        style: ST.label(9, color: ST.g0),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Take Alpha Trail today. Avoid Zone B until lion activity subsides (~17:30). Optimal waterhole: Zone D at 15:00.',
                    style: ST.body(12, color: ST.t2),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 7,
                    runSpacing: 6,
                    children:
                    [
                      '🐘 High elephant activity',
                      '💧 Waterhole peak 15:00',
                      '🌅 Dusk: 17:00',
                      '⚠ Avoid Zone B',
                    ]
                        .map(
                          (s) => Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: ST.panelBox(radius: 5),
                        child: Text(
                          s,
                          style: ST.body(10, color: ST.t2),
                        ),
                      ),
                    )
                        .toList(),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SHARED WIDGETS
// ─────────────────────────────────────────────────────────────────────────────

// Role banner — shown at top of each screen to indicate role context
class _RoleBanner extends StatelessWidget {
  final String title, subtitle;
  final Color color;
  const _RoleBanner(this.title, this.subtitle, this.color);
  @override
  build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 14),
    padding: const EdgeInsets.all(11),
    decoration: BoxDecoration(
      color: color.withOpacity(0.08),
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: color.withOpacity(0.25)),
    ),
    child: Row(
      children: [
        Container(
          width: 3,
          height: 32,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 10),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: ST
                  .body(12, color: color)
                  .copyWith(fontWeight: FontWeight.w700),
            ),
            Text(subtitle, style: ST.body(10, color: color.withOpacity(0.7))),
          ],
        ),
      ],
    ),
  );
}

class _BigStat extends StatelessWidget {
  final String v, l, sub;
  final Color c;
  const _BigStat(this.v, this.l, this.c, this.sub);
  @override
  build(BuildContext context) => Container(
    padding: const EdgeInsets.all(12),
    decoration: ST.cardBox(),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l.toUpperCase(), style: ST.label(8, color: ST.t3)),
        const SizedBox(height: 2),
        Text(v, style: ST.bebas(26, color: c)),
        Text(sub, style: ST.body(10, color: c.withOpacity(0.7))),
      ],
    ),
  );
}

class _AnalCard extends StatelessWidget {
  final String title;
  final Widget child;
  const _AnalCard(this.title, {required this.child});
  @override
  build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    decoration: ST.cardBox(),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title.toUpperCase(), style: ST.label(9, color: ST.t3)),
        const SizedBox(height: 12),
        child,
      ],
    ),
  );
}

class _FlStat extends StatelessWidget {
  final String v, l;
  final Color c;
  const _FlStat(this.v, this.l, this.c);
  @override
  build(BuildContext context) => Expanded(
    child: Container(
      padding: const EdgeInsets.all(12),
      decoration: ST.cardBox(),
      child: Column(
        children: [
          Text(v, style: ST.bebas(26, color: c)),
          Text(l, style: ST.body(10, color: ST.t3)),
        ],
      ),
    ),
  );
}

class _VehicleCard extends StatelessWidget {
  final VehicleModel v;
  const _VehicleCard({required this.v});
  Color get _sc =>
      v.status == VehicleStatus.active
          ? ST.g0
          : v.status == VehicleStatus.alert
          ? ST.red
          : ST.t3;
  @override
  build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    decoration: ST.cardBox(
      border: v.status == VehicleStatus.alert ? ST.red.withOpacity(0.35) : null,
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text('🚙', style: TextStyle(fontSize: 22)),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    v.name,
                    style: ST
                        .body(13, color: ST.t1)
                        .copyWith(fontWeight: FontWeight.w700),
                  ),
                  Text(
                    '${v.driverName} · ${v.passengers} pax',
                    style: ST.body(10, color: ST.t3),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: _sc.withOpacity(0.15),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                v.status.name.toUpperCase(),
                style: ST.label(9, color: _sc),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            _VStat(
              'SPEED',
              '${v.speed.toStringAsFixed(0)} km/h',
              v.speed > 14 ? ST.red : ST.g0,
            ),
            const SizedBox(width: 6),
            _VStat('HEADING', '${v.direction.toStringAsFixed(0)}°', ST.t1),
            const SizedBox(width: 6),
            _VStat('ZONE', v.zone, ST.amber),
            const SizedBox(width: 6),
            _VStat(
              'PIR',
              v.pirTriggered ? 'TRIG' : 'IDLE',
              v.pirTriggered ? ST.red : ST.g0,
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(child: _LvlBar('Battery', v.batteryLevel / 100, ST.blueL)),
            const SizedBox(width: 10),
            Expanded(child: _LvlBar('Fuel', v.fuelLevel / 100, ST.amber)),
          ],
        ),
      ],
    ),
  );
}

class _VStat extends StatelessWidget {
  final String l, v;
  final Color c;
  const _VStat(this.l, this.v, this.c);
  @override
  build(BuildContext context) => Expanded(
    child: Container(
      padding: const EdgeInsets.symmetric(vertical: 6),
      decoration: ST.panelBox(radius: 6),
      child: Column(
        children: [
          Text(l, style: ST.label(7.5, color: ST.t3)),
          const SizedBox(height: 2),
          Text(
            v,
            style: ST.body(11, color: c).copyWith(fontWeight: FontWeight.w700),
          ),
        ],
      ),
    ),
  );
}

class _LvlBar extends StatelessWidget {
  final String l;
  final double v;
  final Color c;
  const _LvlBar(this.l, this.v, this.c);
  @override
  build(BuildContext context) {
    final pct = (v * 100).round();
    final bc =
    pct < 25
        ? ST.red
        : pct < 50
        ? ST.amber
        : c;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(l, style: ST.body(10, color: ST.t3)),
            const Spacer(),
            Text(
              '$pct%',
              style: ST
                  .body(10, color: bc)
                  .copyWith(fontWeight: FontWeight.w700),
            ),
          ],
        ),
        const SizedBox(height: 4),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: v,
            minHeight: 7,
            backgroundColor: ST.panel,
            valueColor: AlwaysStoppedAnimation(bc),
          ),
        ),
      ],
    );
  }
}

class _PredRow extends StatelessWidget {
  final Map<String, dynamic> data;
  const _PredRow({required this.data});
  @override
  build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 8),
    padding: const EdgeInsets.all(9),
    decoration: ST.panelBox(radius: 8),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(data['icon'], style: const TextStyle(fontSize: 14)),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                data['title'],
                style: ST
                    .body(11.5, color: ST.t1)
                    .copyWith(fontWeight: FontWeight.w600),
              ),
            ),
            Text('${data['conf']}%', style: ST.mono(11, color: ST.g0)),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          data['desc'],
          style: ST.body(10, color: ST.t3),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 5),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: Color(data['tagBg']),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            data['tag'],
            style: ST.label(8, color: Color(data['tagFg'])),
          ),
        ),
      ],
    ),
  );
}

class _ImuBig extends StatelessWidget {
  final String l, v;
  final Color c;
  const _ImuBig(this.l, this.v, this.c);
  @override
  build(BuildContext context) => Container(
    padding: const EdgeInsets.all(12),
    decoration: ST.cardBox(),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l, style: ST.label(8, color: ST.t3)),
        const SizedBox(height: 3),
        Text(v, style: ST.bebas(24, color: c)),
      ],
    ),
  );
}

class _SensorBar extends StatelessWidget {
  final String ax;
  final double val;
  final Color c;
  final double mn, mx;
  const _SensorBar(this.ax, this.val, this.c, this.mn, this.mx);
  @override
  build(BuildContext context) {
    final pct = ((val - mn) / (mx - mn)).clamp(0.0, 1.0);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        children: [
          Row(
            children: [
              SizedBox(
                width: 24,
                child: Text(
                  ax,
                  style: ST
                      .body(12, color: c)
                      .copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              const Spacer(),
              Text(val.toStringAsFixed(3), style: ST.mono(10, color: c)),
            ],
          ),
          const SizedBox(height: 4),
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: pct,
              minHeight: 6,
              backgroundColor: ST.panel,
              valueColor: AlwaysStoppedAnimation(c),
            ),
          ),
        ],
      ),
    );
  }
}

class _CompassPainter extends CustomPainter {
  final double heading;
  const _CompassPainter(this.heading);
  @override
  void paint(Canvas canvas, Size s) {
    final cx = s.width / 2, cy = s.height / 2, r = cx * 0.88;
    canvas.drawCircle(Offset(cx, cy), r, Paint()..color = ST.panel);
    canvas.drawCircle(
      Offset(cx, cy),
      r,
      Paint()
        ..color = ST.gBorder
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
    for (int i = 0; i < 36; i++) {
      final a = i * 10 * pi / 180;
      final inner =
      i % 9 == 0
          ? r - 14
          : i % 3 == 0
          ? r - 8
          : r - 4;
      canvas.drawLine(
        Offset(cx + sin(a) * inner, cy - cos(a) * inner),
        Offset(cx + sin(a) * (r - 1), cy - cos(a) * (r - 1)),
        Paint()
          ..color = (i % 9 == 0 ? ST.t2 : ST.t4)
          ..strokeWidth = (i % 9 == 0 ? 1.2 : 0.7),
      );
    }
    for (final d in [
      ['N', 0.0, ST.red],
      ['E', 90.0, ST.amberL],
      ['S', 180.0, ST.t3],
      ['W', 270.0, ST.t3],
    ]) {
      final a = (d[1] as double) * pi / 180;
      final tp = TextPainter(
        text: TextSpan(
          text: d[0] as String,
          style: TextStyle(
            color: d[2] as Color,
            fontSize: 11,
            fontWeight: FontWeight.w700,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(
        canvas,
        Offset(
          cx + sin(a) * (r - 24) - tp.width / 2,
          cy - cos(a) * (r - 24) - tp.height / 2,
        ),
      );
    }
    canvas.save();
    canvas.translate(cx, cy);
    canvas.rotate(heading * pi / 180);
    canvas.drawPath(
      Path()
        ..moveTo(0, -r * 0.55)
        ..lineTo(-5, 0)
        ..lineTo(0, r * 0.28)
        ..lineTo(5, 0)
        ..close(),
      Paint()..color = ST.red,
    );
    canvas.drawPath(
      Path()
        ..moveTo(0, r * 0.28)
        ..lineTo(-4, 0)
        ..lineTo(0, r * 0.55)
        ..lineTo(4, 0)
        ..close(),
      Paint()..color = Colors.white.withOpacity(0.45),
    );
    canvas.drawCircle(Offset.zero, 5, Paint()..color = Colors.white);
    canvas.drawCircle(Offset.zero, 3, Paint()..color = ST.bgDeep);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _CompassPainter old) => old.heading != heading;
}

// Ticket card
class _TicketCard extends StatelessWidget {
  final TicketModel ticket;
  final VoidCallback onBook;
  const _TicketCard({required this.ticket, required this.onBook});
  @override
  build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: ST.cardBox(),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    ticket.type,
                    style: ST
                        .body(16, color: ST.t1)
                        .copyWith(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 2),
                  Text(ticket.description, style: ST.body(11, color: ST.t3)),
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 7,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: ticket.accentColor.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      ticket.timeSlot,
                      style: ST.mono(9, color: ticket.accentColor),
                    ),
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '₹${ticket.price.toStringAsFixed(0)}',
                  style: ST.bebas(30, color: ticket.accentColor),
                ),
                Text('per person', style: ST.body(9, color: ST.t4)),
              ],
            ),
          ],
        ),
        const SizedBox(height: 12),
        const Divider(color: ST.gBorder, height: 1),
        const SizedBox(height: 10),
        Wrap(
          spacing: 10,
          runSpacing: 6,
          children:
          ticket.features
              .map(
                (f) => Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '✓',
                  style: TextStyle(
                    color: ticket.accentColor,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(width: 5),
                Text(f, style: ST.body(11, color: ST.t2)),
              ],
            ),
          )
              .toList(),
        ),
        const SizedBox(height: 14),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: onBook,
            style: ElevatedButton.styleFrom(
              backgroundColor: ticket.accentColor.withOpacity(0.85),
              foregroundColor: ST.bg,
              padding: const EdgeInsets.symmetric(vertical: 13),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(9),
              ),
              elevation: 0,
            ),
            child: Text(
              'Book Now → Pay Securely',
              style: ST
                  .body(13, color: ST.bg)
                  .copyWith(fontWeight: FontWeight.w800),
            ),
          ),
        ),
      ],
    ),
  );
}

// Route card
class _RouteCard extends StatefulWidget {
  final SafariRoute r;
  const _RouteCard({required this.r});
  @override
  State<_RouteCard> createState() => _RouteCardState();
}

class _RouteCardState extends State<_RouteCard> {
  bool _ex = false;
  @override
  build(BuildContext context) => GestureDetector(
    onTap: () => setState(() => _ex = !_ex),
    child: AnimatedContainer(
      duration: 220.ms,
      padding: const EdgeInsets.all(14),
      decoration: ST.cardBox(
        border: _ex ? widget.r.color.withOpacity(0.4) : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 14,
                height: 14,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: widget.r.color,
                  boxShadow: [
                    BoxShadow(
                      color: widget.r.color.withOpacity(0.4),
                      blurRadius: 6,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.r.name,
                      style: ST
                          .body(14, color: ST.t1)
                          .copyWith(fontWeight: FontWeight.w800),
                    ),
                    Text(
                      '${widget.r.distanceKm.toStringAsFixed(1)} km · ${widget.r.durationMinutes ~/ 60}h ${widget.r.durationMinutes % 60}m · ~${widget.r.estimatedSightings} sightings',
                      style: ST.body(10, color: ST.t3),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                decoration: BoxDecoration(
                  color: widget.r.scoreColor.withOpacity(0.14),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: widget.r.scoreColor.withOpacity(0.35),
                  ),
                ),
                child: Text(
                  widget.r.scoreLabel,
                  style: ST.label(9, color: widget.r.scoreColor),
                ),
              ),
              const SizedBox(width: 8),
              AnimatedRotation(
                turns: _ex ? 0.5 : 0,
                duration: 200.ms,
                child: Icon(Icons.keyboard_arrow_down, color: ST.t3, size: 18),
              ),
            ],
          ),
          if (_ex) ...[
            const SizedBox(height: 12),
            Text(widget.r.note, style: ST.body(12, color: ST.t2)),
            const SizedBox(height: 12),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children:
                widget.r.waypoints
                    .asMap()
                    .entries
                    .expand<Widget>(
                      (e) => [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color:
                        (e.key == 0 ||
                            e.key ==
                                widget.r.waypoints.length - 1)
                            ? widget.r.color.withOpacity(0.2)
                            : ST.panel,
                        borderRadius: BorderRadius.circular(5),
                        border: Border.all(
                          color: widget.r.color.withOpacity(0.4),
                        ),
                      ),
                      child: Text(
                        e.value,
                        style: ST.body(11, color: widget.r.color),
                      ),
                    ),
                    if (e.key < widget.r.waypoints.length - 1)
                      Container(
                        width: 20,
                        height: 1.5,
                        color: widget.r.color.withOpacity(0.35),
                      ),
                  ],
                )
                    .toList(),
              ),
            ),
          ],
        ],
      ),
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// FAKE PAYMENT SCREEN
// ─────────────────────────────────────────────────────────────────────────────
/// Web build has no WebView; same fake checkout flow in Flutter.
class _WebPaymentFallback extends StatelessWidget {
  final TicketModel ticket;
  final String date, timeSlot;
  final VoidCallback onPaid;
  const _WebPaymentFallback({
    required this.ticket,
    required this.date,
    required this.timeSlot,
    required this.onPaid,
  });
  @override
  Widget build(BuildContext context) => SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('SAFARISYNC PAY', style: ST.bebas(22, color: ST.g0)),
            Text('Web checkout · Demo', style: ST.body(11, color: ST.t3)),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: ST.cardBox(),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('ORDER', style: ST.label(9, color: ST.t3)),
                  const SizedBox(height: 8),
                  Text(ticket.type, style: ST.body(14, color: ST.t1).copyWith(fontWeight: FontWeight.w800)),
                  Text('$date · $timeSlot', style: ST.mono(10, color: ST.t3)),
                  const SizedBox(height: 10),
                  Text('₹${ticket.price.toStringAsFixed(0)}',
                      style: ST.bebas(28, color: ST.g0)),
                ],
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: onPaid,
                style: ElevatedButton.styleFrom(
                  backgroundColor: ST.g1,
                  foregroundColor: ST.bg,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                child: Text(
                  'Simulate successful payment',
                  style: ST.body(14, color: ST.bg).copyWith(fontWeight: FontWeight.w800),
                ),
              ),
            ),
          ],
        ),
      );
}

class FakePaymentScreen extends StatefulWidget {
  final TicketModel ticket;
  final String date, timeSlot;
  const FakePaymentScreen({super.key, required this.ticket, required this.date, required this.timeSlot});
  @override
  State<FakePaymentScreen> createState() => _FakePaymentState();
}

class _FakePaymentState extends State<FakePaymentScreen> {
  WebViewController? _wc;
  bool _loaded = false, _processing = false;

  @override
  void initState() {
    super.initState();
    if (kIsWeb) {
      _loaded = true;
    } else {
      _wc = WebViewController()
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        ..setNavigationDelegate(
          NavigationDelegate(
            onPageFinished: (_) => setState(() => _loaded = true),
            onNavigationRequest: (req) {
              if (req.url.contains('safarisync://payment-success')) {
                _handleSuccess();
                return NavigationDecision.prevent;
              }
              return NavigationDecision.navigate;
            },
          ),
        )
        ..loadHtmlString(_buildHtml());
    }
  }

  void _handleSuccess() async {
    setState(() => _processing = true);
    await Future.delayed(const Duration(seconds: 2));
    if (mounted) Navigator.pop(context, true);
  }

  String _buildHtml() {
    final amount = widget.ticket.price.toStringAsFixed(0);
    final type = widget.ticket.type;
    final orderId =
        'ORD${DateTime.now().millisecondsSinceEpoch.toString().substring(8)}';
    final dateStr = widget.date;
    final slotStr = widget.timeSlot;
    return '''<!DOCTYPE html>
<html><head><meta name="viewport" content="width=device-width,initial-scale=1.0,maximum-scale=1.0">
<title>Secure Payment</title>
<style>
*{margin:0;padding:0;box-sizing:border-box;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',sans-serif;}
body{background:#0d1117;color:#e6edf3;min-height:100vh;}
.header{background:#161b22;border-bottom:1px solid #30363d;padding:12px 16px;display:flex;align-items:center;justify-content:space-between;}
.logo{display:flex;align-items:center;gap:8px;} .logo-icon{background:#238636;border-radius:8px;width:30px;height:30px;display:flex;align-items:center;justify-content:center;font-size:15px;}
.logo-text{font-size:15px;font-weight:700;color:#3fb950;letter-spacing:1px;}
.badge{background:#21262d;border:1px solid #30363d;border-radius:20px;padding:3px 9px;font-size:10px;color:#8b949e;display:flex;align-items:center;gap:4px;}
.dot{width:5px;height:5px;background:#3fb950;border-radius:50%;}
.c{padding:14px;max-width:500px;margin:0 auto;}
.oc{background:#161b22;border:1px solid #30363d;border-radius:10px;padding:14px;margin-bottom:12px;}
.ot{font-size:10px;color:#8b949e;letter-spacing:1px;font-weight:600;margin-bottom:8px;}
.or{display:flex;justify-content:space-between;margin-bottom:5px;}
.ol{color:#8b949e;font-size:12px;} .ov{color:#e6edf3;font-size:12px;font-weight:600;}
.ar{border-top:1px solid #30363d;margin-top:8px;padding-top:8px;}
.al{color:#e6edf3;font-size:13px;font-weight:700;} .av{color:#3fb950;font-size:18px;font-weight:800;}
.mc{background:#161b22;border:1px solid #30363d;border-radius:10px;overflow:hidden;margin-bottom:12px;}
.mt{font-size:10px;color:#8b949e;letter-spacing:1px;font-weight:600;padding:10px 14px 6px;}
.tabs{display:flex;border-bottom:1px solid #30363d;}
.tab{flex:1;padding:9px 5px;text-align:center;font-size:11px;color:#8b949e;cursor:pointer;border-bottom:2px solid transparent;transition:all .2s;}
.tab.active{color:#3fb950;border-bottom-color:#3fb950;background:rgba(63,185,80,.05);}
.ti{font-size:15px;margin-bottom:2px;} .ps{display:none;padding:12px 14px;} .ps.active{display:block;}
.ua{display:grid;grid-template-columns:repeat(4,1fr);gap:8px;margin-bottom:12px;}
.ua div{background:#21262d;border:1px solid #30363d;border-radius:9px;padding:10px 6px;text-align:center;cursor:pointer;transition:all .2s;}
.ua div:hover,.ua div.sel{border-color:#3fb950;background:rgba(63,185,80,.1);}
.ui{font-size:20px;margin-bottom:3px;} .un{font-size:9px;color:#8b949e;}
.uir{display:flex;gap:7px;margin-top:5px;}
.uinp{flex:1;background:#21262d;border:1px solid #30363d;border-radius:7px;padding:10px;color:#e6edf3;font-size:12px;outline:none;}
.uinp::placeholder{color:#484f58;}
.ig{margin-bottom:10px;} .il{font-size:10px;color:#8b949e;letter-spacing:.5px;margin-bottom:5px;}
.inf{width:100%;background:#21262d;border:1px solid #30363d;border-radius:7px;padding:10px;color:#e6edf3;font-size:12px;outline:none;}
.inf::placeholder{color:#484f58;} .inr{display:flex;gap:8px;}
.cn{display:flex;gap:6px;margin-bottom:10px;}
.cn div{background:white;border-radius:4px;padding:4px 9px;font-size:10px;font-weight:800;}
.visa{color:#1a1f71;} .mc{color:#eb001b;} .rup{color:#0072bc;}
.bg{display:grid;grid-template-columns:repeat(2,1fr);gap:7px;margin-bottom:10px;}
.bi{background:#21262d;border:1px solid #30363d;border-radius:7px;padding:10px;display:flex;align-items:center;gap:8px;cursor:pointer;transition:all .2s;}
.bi:hover,.bi.sel{border-color:#3fb950;background:rgba(63,185,80,.08);}
.bl{width:28px;height:28px;border-radius:5px;display:flex;align-items:center;justify-content:center;font-size:12px;font-weight:800;}
.bn{font-size:11px;color:#e6edf3;font-weight:600;}
.wg{display:grid;grid-template-columns:repeat(3,1fr);gap:8px;margin-bottom:10px;}
.wi{background:#21262d;border:1px solid #30363d;border-radius:9px;padding:12px 8px;text-align:center;cursor:pointer;transition:all .2s;}
.wi:hover,.wi.sel{border-color:#3fb950;background:rgba(63,185,80,.1);}
.wic{font-size:22px;margin-bottom:4px;} .win{font-size:10px;color:#8b949e;}
.pb{width:100%;background:linear-gradient(135deg,#3fb950,#238636);border:none;border-radius:10px;padding:14px;color:white;font-size:14px;font-weight:800;cursor:pointer;transition:all .2s;letter-spacing:.5px;margin-top:6px;}
.pb:active{transform:scale(.98);}
.si{display:flex;align-items:center;justify-content:center;gap:6px;margin-top:8px;color:#484f58;font-size:10px;}
.si span{color:#3fb950;}
.ov2{display:none;position:fixed;inset:0;background:rgba(0,0,0,.85);z-index:100;align-items:center;justify-content:center;flex-direction:column;}
.ov2.show{display:flex;}
.sp{width:44px;height:44px;border:4px solid #30363d;border-top-color:#3fb950;border-radius:50%;animation:spin .8s linear infinite;margin-bottom:14px;}
@keyframes spin{to{transform:rotate(360deg)}}
.pt{color:#e6edf3;font-size:15px;font-weight:600;margin-bottom:5px;} .ps2{color:#8b949e;font-size:11px;}
.sov{display:none;position:fixed;inset:0;background:rgba(0,0,0,.92);z-index:101;align-items:center;justify-content:center;flex-direction:column;text-align:center;padding:20px;}
.sov.show{display:flex;}
.sic{font-size:56px;margin-bottom:12px;animation:boun .6s ease;}
@keyframes boun{0%{transform:scale(0)}60%{transform:scale(1.2)}100%{transform:scale(1)}}
.stit{font-size:20px;font-weight:800;color:#3fb950;margin-bottom:5px;} .ssub{font-size:13px;color:#8b949e;margin-bottom:16px;}
.samt{background:rgba(63,185,80,.1);border:1px solid rgba(63,185,80,.3);border-radius:10px;padding:10px 22px;font-size:22px;font-weight:800;color:#3fb950;margin-bottom:16px;}
.sref{font-size:10px;color:#484f58;letter-spacing:1px;margin-bottom:20px;}
.cb{background:#3fb950;border:none;border-radius:10px;padding:12px 28px;color:white;font-size:13px;font-weight:700;cursor:pointer;}
</style></head><body>
<div class="header"><div class="logo"><div class="logo-icon">🌿</div><div class="logo-text">SAFARISYNC PAY</div></div><div class="badge"><div class="dot"></div>256-bit SSL</div></div>
<div class="c">
  <div class="oc"><div class="ot">ORDER SUMMARY</div>
    <div class="or"><span class="ol">Safari Package</span><span class="ov">$type</span></div>
    <div class="or"><span class="ol">Order ID</span><span class="ov">#$orderId</span></div>
    <div class="or"><span class="ol">Date</span><span class="ov">$dateStr</span></div>
    <div class="or"><span class="ol">Slot</span><span class="ov">$slotStr</span></div>
    <div class="or ar"><span class="al">Total Amount</span><span class="av">₹$amount</span></div>
  </div>
  <div class="mc"><div class="mt">CHOOSE PAYMENT METHOD</div>
    <div class="tabs">
      <div class="tab active" onclick="sw(0)"><div class="ti">📲</div>UPI</div>
      <div class="tab" onclick="sw(1)"><div class="ti">💳</div>Card</div>
      <div class="tab" onclick="sw(2)"><div class="ti">🏦</div>Net Banking</div>
      <div class="tab" onclick="sw(3)"><div class="ti">👜</div>Wallet</div>
    </div>
    <div class="ps active" id="s0">
      <div class="ua">
        <div class="sel" onclick="sa(this)"><div class="ui">💜</div><div class="un">PhonePe</div></div>
        <div onclick="sa(this)"><div class="ui">🎨</div><div class="un">GPay</div></div>
        <div onclick="sa(this)"><div class="ui">🔵</div><div class="un">Paytm</div></div>
        <div onclick="sa(this)"><div class="ui">🇮🇳</div><div class="un">BHIM</div></div>
      </div>
      <div style="font-size:10px;color:#484f58;margin-bottom:6px;">Or enter UPI ID</div>
      <div class="uir"><input class="uinp" placeholder="yourname@upi" type="text"><button onclick="pay()" style="background:#238636;border:none;border-radius:7px;padding:10px 14px;color:white;font-size:12px;font-weight:700;cursor:pointer;">Verify</button></div>
      <button class="pb" onclick="pay()">Pay ₹$amount</button>
    </div>
    <div class="ps" id="s1">
      <div class="cn"><div class="visa">VISA</div><div class="mc">MC</div><div class="rup">RuPay</div></div>
      <div class="ig"><div class="il">CARD NUMBER</div><input class="inf" placeholder="0000  0000  0000  0000" maxlength="19" type="tel"></div>
      <div class="ig"><div class="il">CARDHOLDER NAME</div><input class="inf" placeholder="Name as on card" type="text"></div>
      <div class="inr"><div class="ig" style="flex:1"><div class="il">EXPIRY</div><input class="inf" placeholder="MM / YY" maxlength="5" type="tel"></div>
        <div class="ig" style="flex:1"><div class="il">CVV</div><input class="inf" placeholder="•••" maxlength="3" type="tel"></div></div>
      <button class="pb" onclick="pay()">Pay ₹$amount Securely</button>
    </div>
    <div class="ps" id="s2">
      <div class="bg">
        <div class="bi sel" onclick="sb(this)"><div class="bl" style="background:#0072bc;color:white;">SBI</div><div class="bn">State Bank</div></div>
        <div class="bi" onclick="sb(this)"><div class="bl" style="background:#e60026;color:white;">BOB</div><div class="bn">Bank of Baroda</div></div>
        <div class="bi" onclick="sb(this)"><div class="bl" style="background:#004b87;color:white;">PNB</div><div class="bn">Punjab National</div></div>
        <div class="bi" onclick="sb(this)"><div class="bl" style="background:#d71920;color:white;">AXIS</div><div class="bn">Axis Bank</div></div>
        <div class="bi" onclick="sb(this)"><div class="bl" style="background:#0068b8;color:white;">HDFC</div><div class="bn">HDFC Bank</div></div>
        <div class="bi" onclick="sb(this)"><div class="bl" style="background:#f37020;color:white;">ICICI</div><div class="bn">ICICI Bank</div></div>
      </div>
      <button class="pb" onclick="pay()">Proceed to Net Banking</button>
    </div>
    <div class="ps" id="s3">
      <div class="wg">
        <div class="wi sel" onclick="sw2(this)"><div class="wic">💙</div><div class="win">Paytm</div></div>
        <div class="wi" onclick="sw2(this)"><div class="wic">🟡</div><div class="win">Amazon Pay</div></div>
        <div class="wi" onclick="sw2(this)"><div class="wic">🛒</div><div class="win">Flipkart</div></div>
        <div class="wi" onclick="sw2(this)"><div class="wic">⚡</div><div class="win">Jio Pay</div></div>
        <div class="wi" onclick="sw2(this)"><div class="wic">🔴</div><div class="win">Airtel</div></div>
        <div class="wi" onclick="sw2(this)"><div class="wic">🍕</div><div class="win">Zomato Pay</div></div>
      </div>
      <button class="pb" onclick="pay()">Pay from Wallet</button>
    </div>
  </div>
  <div class="si">🔒 <span>Secured by SafariSync Pay</span> · PCI DSS · RBI Approved</div>
</div>
<div class="ov2" id="proc"><div class="sp"></div><div class="pt">Processing payment...</div><div class="ps2">Please do not press back</div></div>
<div class="sov" id="succ">
  <div class="sic">✅</div><div class="stit">Payment Successful!</div>
  <div class="ssub">Your safari experience is confirmed</div>
  <div class="samt">₹$amount</div><div class="sref">REF: $orderId · APPROVED</div>
  <button class="cb" onclick="cont()">Continue to App →</button>
</div>
<script>
function sw(i){document.querySelectorAll('.tab').forEach((t,j)=>t.classList.toggle('active',j===i));document.querySelectorAll('.ps').forEach((s,j)=>s.classList.toggle('active',j===i));}
function sa(el){document.querySelectorAll('.ua div').forEach(a=>a.classList.remove('sel'));el.classList.add('sel');}
function sb(el){document.querySelectorAll('.bi').forEach(b=>b.classList.remove('sel'));el.classList.add('sel');}
function sw2(el){document.querySelectorAll('.wi').forEach(w=>w.classList.remove('sel'));el.classList.add('sel');}
function pay(){document.getElementById('proc').classList.add('show');setTimeout(function(){document.getElementById('proc').classList.remove('show');document.getElementById('succ').classList.add('show');},2500);}
function cont(){window.location.href='safarisync://payment-success';}
</script></body></html>''';
  }

  @override
  build(BuildContext context) => Scaffold(
    backgroundColor: ST.bgDeep,
    appBar: AppBar(
      backgroundColor: ST.bgDeep,
      elevation: 0,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back_ios, color: ST.t2, size: 19),
        onPressed: () => Navigator.pop(context, false),
      ),
      title: Text(
        'Secure Payment',
        style: ST.body(15, color: ST.t1).copyWith(fontWeight: FontWeight.w600),
      ),
      centerTitle: true,
      actions: [
        Padding(
          padding: const EdgeInsets.only(right: 12),
          child: Center(
            child: Text('🔒 SSL', style: ST.label(9, color: ST.g0)),
          ),
        ),
      ],
    ),
    body: Stack(
      children: [
        if (!_loaded)
          const Center(child: CircularProgressIndicator(color: ST.g1)),
        Opacity(
          opacity: _loaded ? 1 : 0,
          child: kIsWeb
              ? _WebPaymentFallback(
                  ticket: widget.ticket,
                  date: widget.date,
                  timeSlot: widget.timeSlot,
                  onPaid: _handleSuccess,
                )
              : WebViewWidget(controller: _wc!),
        ),
        if (_processing)
          Container(
            color: Colors.black.withOpacity(0.7),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const CircularProgressIndicator(color: ST.g1),
                  const SizedBox(height: 16),
                  Text(
                    'Confirming booking...',
                    style: ST.body(14, color: ST.t1),
                  ),
                ],
              ),
            ),
          ),
      ],
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// LIVE MAP SCREEN — Animal probability heatmap on the hackathon track
// ─────────────────────────────────────────────────────────────────────────────
class LiveMapScreen extends StatefulWidget {
  const LiveMapScreen({super.key});
  @override State<LiveMapScreen> createState() => _LiveMapScreenState();
}

class _LiveMapScreenState extends State<LiveMapScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _tickCtrl;
  final _rng = Random(DateTime.now().millisecondsSinceEpoch);
  Timer? _driftTimer;

  // Per-animal probability that drifts slowly over time
  late Map<String, double> _animalProb;

  @override
  void initState() {
    super.initState();
    _tickCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 16),
    )..repeat();

    _animalProb = {
      for (final a in _trackAnimals) a['label'] as String: 0.55 + _rng.nextDouble() * 0.40
    };

    // Drift probabilities slowly
    _driftTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      if (!mounted) return;
      setState(() {
        for (final key in _animalProb.keys) {
          final delta = (_rng.nextDouble() - 0.45) * 0.12;
          _animalProb[key] = (_animalProb[key]! + delta).clamp(0.30, 0.98);
        }
      });
    });
  }

  @override
  void dispose() {
    _driftTimer?.cancel();
    _tickCtrl.dispose();
    super.dispose();
  }

  // Unique set of track animals (one entry per label)
  static const List<Map<String, dynamic>> _trackAnimals = [
    {'label': 'Camel',      'emoji': '🐪', 'color': 0xFFD9A848},
    {'label': 'Tiger',      'emoji': '🐅', 'color': 0xFFE84040},
    {'label': 'Lion',       'emoji': '🦁', 'color': 0xFFF5A623},
    {'label': 'Bull',       'emoji': '🐂', 'color': 0xFF92400E},
    {'label': 'Polar Bear', 'emoji': '🐻‍❄️', 'color': 0xFFE2E8F0},
    {'label': 'Giraffe',    'emoji': '🦒', 'color': 0xFFFDD07A},
  ];

  Color _probColor(double prob) {
    if (prob >= 0.80) return const Color(0xFFE84040);
    if (prob >= 0.60) return const Color(0xFFF5A623);
    return const Color(0xFF6EDB75);
  }

  String _probLabel(double prob) {
    if (prob >= 0.80) return 'HIGH';
    if (prob >= 0.60) return 'MED';
    return 'LOW';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ST.bg,
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Header ──
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: ST.purple.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: ST.purple),
                    ),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Container(
                        width: 6, height: 6,
                        decoration: const BoxDecoration(color: ST.purple, shape: BoxShape.circle),
                      ).animate(onPlay: (c) => c.repeat())
                           .fadeOut(duration: 900.ms).then().fadeIn(duration: 900.ms),
                      const SizedBox(width: 6),
                      Text('LIVE PROBABILITY', style: GoogleFonts.jetBrainsMono(
                        fontSize: 9, color: ST.purple,
                      )),
                    ]),
                  ),
                  const Spacer(),
                  Text('Animal Hotspot Map', style: ST.body(11, color: ST.t3)),
                ]),
                const SizedBox(height: 6),
                Text('LIVE MAP', style: GoogleFonts.dmSans(
                  fontSize: 28, color: ST.purple, fontWeight: FontWeight.w900, letterSpacing: 2,
                )),
                Text('Sighting probability · Updated every 3s',
                    style: GoogleFonts.dmSans(fontSize: 11, color: ST.t3)),
              ]),
            ),

            // ── Track Map with Heatmap Overlay ──
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: AspectRatio(
                aspectRatio: 1277 / 819,
                child: Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFF0D2014),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: ST.purple.withOpacity(0.4), width: 1.2),
                    boxShadow: [
                      BoxShadow(color: ST.purple.withOpacity(0.08), blurRadius: 24, spreadRadius: 2),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(15),
                    child: AnimatedBuilder(
                      animation: _tickCtrl,
                      builder: (_, __) => CustomPaint(
                        painter: _LiveMapPainter(
                          tick: _tickCtrl.value,
                          animalProb: _animalProb,
                        ),
                        child: Container(),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 14),

            // ── Legend ──
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(children: [
                _ProbLegend('HIGH ≥80%', const Color(0xFFE84040)),
                const SizedBox(width: 10),
                _ProbLegend('MED ≥60%', const Color(0xFFF5A623)),
                const SizedBox(width: 10),
                _ProbLegend('LOW <60%', const Color(0xFF6EDB75)),
              ]),
            ),
            const SizedBox(height: 14),

            // ── Animal Probability Cards ──
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
              child: Text('ANIMAL SIGHTING PROBABILITY',
                  style: GoogleFonts.dmSans(fontSize: 9, color: ST.t3, fontWeight: FontWeight.w700, letterSpacing: 1)),
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 110,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                separatorBuilder: (_, __) => const SizedBox(width: 10),
                itemCount: _trackAnimals.length,
                itemBuilder: (_, i) {
                  final a = _trackAnimals[i];
                  final label = a['label'] as String;
                  final prob = _animalProb[label] ?? 0.5;
                  final color = _probColor(prob);
                  return Container(
                    width: 100,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: color.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: color.withOpacity(0.4)),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(a['emoji'] as String, style: const TextStyle(fontSize: 26)),
                        const SizedBox(height: 4),
                        Text(label, style: GoogleFonts.dmSans(
                          fontSize: 9, color: ST.t2, fontWeight: FontWeight.w700,
                        ), maxLines: 1, overflow: TextOverflow.ellipsis),
                        const SizedBox(height: 4),
                        Text('${(prob * 100).toStringAsFixed(0)}%',
                            style: GoogleFonts.jetBrainsMono(fontSize: 14, color: color, fontWeight: FontWeight.w800)),
                        Text(_probLabel(prob),
                            style: GoogleFonts.jetBrainsMono(fontSize: 7, color: color)),
                      ],
                    ),
                  ).animate(key: ValueKey('$label-${(prob * 10).toInt()}')).fadeIn(duration: 300.ms);
                },
              ),
            ),
            const SizedBox(height: 16),

            // ── Zone Summary ──
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
              child: Text('TRACK ZONE ACTIVITY',
                  style: GoogleFonts.dmSans(fontSize: 9, color: ST.t3, fontWeight: FontWeight.w700, letterSpacing: 1)),
            ),
            const SizedBox(height: 8),
            ..._buildZoneSummary(),
            const SizedBox(height: 80),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildZoneSummary() {
    // Assign animals to sections of the track
    final zones = [
      {'name': 'Right Loop (A1–A6)', 'animals': ['Camel', 'Tiger', 'Lion', 'Bull', 'Polar Bear', 'Giraffe']},
      {'name': 'Bottom Straight (A7–A8)', 'animals': ['Camel', 'Tiger']},
      {'name': 'Left Column (A9–A12)', 'animals': ['Lion', 'Bull', 'Polar Bear', 'Giraffe']},
      {'name': 'Top Arc (A13–A17)', 'animals': ['Camel', 'Tiger', 'Lion', 'Bull', 'Polar Bear']},
    ];

    return zones.map((z) {
      final animals = z['animals'] as List<String>;
      final avgProb = animals.fold(0.0, (sum, a) => sum + (_animalProb[a] ?? 0.5)) / animals.length;
      final color = _probColor(avgProb);
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: ST.cardBox(border: color.withOpacity(0.3)),
          child: Row(children: [
            Container(width: 4, height: 36, decoration: BoxDecoration(
              color: color, borderRadius: BorderRadius.circular(2))),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(z['name'] as String, style: ST.body(12, color: ST.t1).copyWith(fontWeight: FontWeight.w700)),
              Text('${animals.join(' · ')}', style: ST.body(9, color: ST.t3), maxLines: 1, overflow: TextOverflow.ellipsis),
            ])),
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text('${(avgProb * 100).toStringAsFixed(0)}%',
                  style: GoogleFonts.jetBrainsMono(fontSize: 16, color: color, fontWeight: FontWeight.w800)),
              Text(_probLabel(avgProb), style: GoogleFonts.jetBrainsMono(fontSize: 8, color: color)),
            ]),
          ]),
        ),
      );
    }).toList();
  }
}

// ── Legend pill ──
Widget _ProbLegend(String label, Color color) => Row(mainAxisSize: MainAxisSize.min, children: [
  Container(width: 10, height: 10, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
  const SizedBox(width: 5),
  Text(label, style: GoogleFonts.dmSans(fontSize: 9, color: ST.t3, fontWeight: FontWeight.w600)),
]);

// ─────────────────────────────────────────────────────────────────────────────
// LIVE MAP PAINTER — Heatmap overlay on the hackathon track
// ─────────────────────────────────────────────────────────────────────────────
class _LiveMapPainter extends CustomPainter {
  final double tick;
  final Map<String, double> animalProb;

  _LiveMapPainter({required this.tick, required this.animalProb});

  // The same animal positions from track_models.dart
  static const List<Map<String, dynamic>> _animals = [
    {'label': 'Camel',      'emoji': '🐪', 'x': 0.39154, 'y': 0.46276, 'color': 0xFFD9A848},
    {'label': 'Tiger',      'emoji': '🐅', 'x': 0.38450, 'y': 0.61782, 'color': 0xFFE84040},
    {'label': 'Lion',       'emoji': '🦁', 'x': 0.57962, 'y': 0.60806, 'color': 0xFFF5A623},
    {'label': 'Bull',       'emoji': '🐂', 'x': 0.67737, 'y': 0.67985, 'color': 0xFF92400E},
    {'label': 'Polar Bear', 'emoji': '🐻‍❄️', 'x': 0.81050, 'y': 0.89377, 'color': 0xFFE2E8F0},
    {'label': 'Giraffe',    'emoji': '🦒', 'x': 0.80736, 'y': 0.76800, 'color': 0xFFFDD07A},
    // secondary positions
    {'label': 'Camel',      'emoji': '🐪', 'x': 0.67815, 'y': 0.97680, 'color': 0xFFD9A848},
    {'label': 'Tiger',      'emoji': '🐅', 'x': 0.12295, 'y': 0.91453, 'color': 0xFFE84040},
    {'label': 'Lion',       'emoji': '🦁', 'x': 0.12295, 'y': 0.75946, 'color': 0xFFF5A623},
    {'label': 'Bull',       'emoji': '🐂', 'x': 0.11825, 'y': 0.62149, 'color': 0xFF92400E},
    {'label': 'Polar Bear', 'emoji': '🐻‍❄️', 'x': 0.12842, 'y': 0.46642, 'color': 0xFFE2E8F0},
    {'label': 'Giraffe',    'emoji': '🦒', 'x': 0.12607, 'y': 0.33211, 'color': 0xFFFDD07A},
    {'label': 'Camel',      'emoji': '🐪', 'x': 0.12139, 'y': 0.04640, 'color': 0xFFD9A848},
    {'label': 'Tiger',      'emoji': '🐅', 'x': 0.32107, 'y': 0.17460, 'color': 0xFFE84040},
    {'label': 'Lion',       'emoji': '🦁', 'x': 0.62254, 'y': 0.17460, 'color': 0xFFF5A623},
    {'label': 'Bull',       'emoji': '🐂', 'x': 0.84260, 'y': 0.03907, 'color': 0xFF92400E},
    {'label': 'Polar Bear', 'emoji': '🐻‍❄️', 'x': 0.84182, 'y': 0.46764, 'color': 0xFFE2E8F0},
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final W = size.width;
    final H = size.height;

    // ── Background (same as Live Track) ──
    const splitX = 0.265;
    canvas.drawRect(Rect.fromLTWH(0, 0, W * splitX, H),
        Paint()..color = const Color(0xFF1A1A1A));
    canvas.drawRect(Rect.fromLTWH(W * splitX, 0, W * (1 - splitX), H),
        Paint()..color = const Color(0xFFF8F8F8));

    // ── Grid (white side) ──
    final gridPaint = Paint()..color = const Color(0xFFDDDDDD)..strokeWidth = 0.4;
    for (double x = W * splitX; x < W; x += W / 18) {
      canvas.drawLine(Offset(x, 0), Offset(x, H), gridPaint);
    }
    for (double y = 0; y < H; y += H / 14) {
      canvas.drawLine(Offset(W * splitX, y), Offset(W, y), gridPaint);
    }

    // ── Track surface ──
    _drawTrack(canvas, W, H);

    // ── Heatmap blobs per animal position ──
    for (final a in _animals) {
      final prob = animalProb[a['label'] as String] ?? 0.5;
      final ax = (a['x'] as double) * W;
      final ay = (a['y'] as double) * H;
      final baseColor = Color(a['color'] as int);
      final pulse = (sin(tick * pi * 3 + ax + ay) + 1) / 2;
      final radius = 18.0 + prob * 22 + pulse * 6;
      // Outer glow – probability-weighted
      canvas.drawCircle(
        Offset(ax, ay),
        radius,
        Paint()
          ..color = baseColor.withOpacity(0.10 + prob * 0.20)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, radius * 0.6),
      );
      // Middle ring
      canvas.drawCircle(Offset(ax, ay), 10 + prob * 6, Paint()..color = baseColor.withOpacity(0.55));
      // Centre dot
      canvas.drawCircle(Offset(ax, ay), 5, Paint()..color = baseColor);

      // Probability label
      final pct = '${(prob * 100).toStringAsFixed(0)}%';
      final tp = TextPainter(
        text: TextSpan(text: pct, style: TextStyle(
          fontFamily: 'monospace', fontSize: 7, color: Colors.white,
          fontWeight: FontWeight.bold,
          shadows: [Shadow(color: Colors.black54, blurRadius: 3)],
        )),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(ax - tp.width / 2, ay + 9));
    }

    // ── Emoji labels ──
    for (final a in _animals) {
      final ax = (a['x'] as double) * W;
      final ay = (a['y'] as double) * H;
      final etp = TextPainter(
        text: TextSpan(text: a['emoji'] as String, style: const TextStyle(fontSize: 11)),
        textDirection: TextDirection.ltr,
      )..layout();
      etp.paint(canvas, Offset(ax - etp.width / 2, ay - etp.height - 10));
    }
  }

  void _drawTrack(Canvas canvas, double W, double H) {
    // Duplicate the track drawing (same as _TrackPainter but simplified for heatmap)
    final pts = _trackPath;
    final surfacePaint = Paint()
      ..color = const Color(0xFFD8C49A)
      ..style = PaintingStyle.stroke
      ..strokeWidth = W * 0.065
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final p = Path()..moveTo(pts[0][0] * W, pts[0][1] * H);
    for (int i = 1; i < pts.length; i++) {
      p.lineTo(pts[i][0] * W, pts[i][1] * H);
    }
    canvas.drawPath(p, surfacePaint);

    // Center line (dim purple for heatmap mode)
    final centerPaint = Paint()
      ..color = const Color(0xFF9B7FEF).withOpacity(0.4)
      ..style = PaintingStyle.stroke
      ..strokeWidth = W * 0.008
      ..strokeCap = StrokeCap.round;
    canvas.drawPath(p, centerPaint);
  }

  // Inlined subset of LineFollowerTrack.path (key waypoints only for efficiency)
  static const List<List<double>> _trackPath = [
    [0.39468, 0.39926],[0.33908, 0.41978],[0.30774, 0.47131],[0.29210, 0.54578],
    [0.30774, 0.61661],[0.33908, 0.66545],[0.38449, 0.69231],[0.46280, 0.68742],
    [0.52076, 0.68742],[0.59202, 0.68986],[0.64683, 0.72894],[0.68285, 0.77900],
    [0.71417, 0.83150],[0.74863, 0.88523],[0.78700, 0.94139],[0.83477, 0.97557],
    [0.88488, 0.96459],[0.92092, 0.91087],[0.94128, 0.83760],[0.89741, 0.71184],
    [0.84651, 0.68131],[0.79718, 0.70330],[0.76351, 0.75580],[0.68051, 0.89011],
    [0.63977, 0.94506],[0.58731, 0.97680],[0.51371, 0.97680],[0.39389, 0.98047],
    [0.25528, 0.97557],[0.10415, 0.97557],[0.03837, 0.89499],[0.04228, 0.76067],
    [0.10571, 0.68498],[0.17932, 0.66057],[0.20752, 0.59706],[0.20438, 0.48230],
    [0.15975, 0.41880],[0.09866, 0.39682],[0.04307, 0.33211],[0.03289, 0.22100],
    [0.07049, 0.13553],[0.12451, 0.10989],[0.18168, 0.11477],[0.26000, 0.10989],
    [0.32889, 0.10745],[0.44949, 0.10989],[0.57399, 0.10745],[0.70399, 0.11234],
    [0.83242, 0.11234],[0.89351, 0.13431],[0.92795, 0.20147],[0.93109, 0.29426],
    [0.89820, 0.37240],[0.84494, 0.40293],[0.76038, 0.39804],[0.66016, 0.39804],
    [0.55000, 0.39865],[0.46744, 0.39926],[0.39468, 0.39926],
  ];

  @override
  bool shouldRepaint(covariant _LiveMapPainter old) =>
      old.tick != tick || old.animalProb != animalProb;
}

// ─────────────────────────────────────────────────────────────────────────────
// MY BOOKINGS SCREEN — Tourist's trip history with QR codes
// ─────────────────────────────────────────────────────────────────────────────
class MyBookingsScreen extends StatelessWidget {
  const MyBookingsScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final p = context.watch<SProvider>();
    return Scaffold(backgroundColor: ST.bg, body: SingleChildScrollView(
        padding: const EdgeInsets.all(16), child: Column(
        crossAxisAlignment: CrossAxisAlignment.start, children: [
      _RoleBanner('🎫 My Bookings', 'Your safari tickets with QR codes', ST.g0),
      Text('MY TRIPS', style: ST.bebas(28)),
      Text('${p.myBookings.length} booking${p.myBookings.length==1?'':'s'} · '
          'Tap any to expand QR', style: ST.body(11, color: ST.t3)),
      const SizedBox(height: 14),
      if (p.myBookings.isEmpty)
        Center(child: Padding(padding: const EdgeInsets.all(48),
            child: Column(children: [
              const Text('🎫', style: TextStyle(fontSize: 52)),
              const SizedBox(height: 12),
              Text('No bookings yet', style: ST.body(16, color: ST.t2).copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              Text('Book a safari ticket to get started', style: ST.body(12, color: ST.t3)),
            ])))
      else
        ...p.myBookings.map((b) => Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _MyBookingCard(booking: b))),
    ])));
  }
}

class _MyBookingCard extends StatefulWidget {
  final BookingModel booking;
  const _MyBookingCard({required this.booking});
  @override State<_MyBookingCard> createState() => _MyBookingCardState();
}
class _MyBookingCardState extends State<_MyBookingCard> {
  bool _expanded = false;
  Color get _ac {
    final tt = SD.tickets.cast<TicketModel?>()
        .firstWhere((t) => t?.type == widget.booking.ticketType, orElse: () => null);
    return tt?.accentColor ?? ST.g0;
  }
  @override build(BuildContext context) => GestureDetector(
      onTap: () => setState(() => _expanded = !_expanded),
      child: AnimatedContainer(duration: 200.ms, padding: const EdgeInsets.all(14),
          decoration: ST.cardBox(border: _expanded ? _ac.withOpacity(0.4) : null),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Container(width: 40, height: 40,
                  decoration: BoxDecoration(color: _ac.withOpacity(0.15), borderRadius: BorderRadius.circular(10)),
                  child: const Center(child: Text('🎫', style: TextStyle(fontSize: 20)))),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(widget.booking.ticketType, style: ST.body(14, color: ST.t1).copyWith(fontWeight: FontWeight.w800)),
                Text('${widget.booking.date} · ${widget.booking.timeSlot}', style: ST.body(11, color: ST.t3)),
              ])),
              Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Text('₹${widget.booking.price.toStringAsFixed(0)}', style: ST.bebas(20, color: _ac)),
                Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(color: ST.g0.withOpacity(0.1), borderRadius: BorderRadius.circular(4)),
                    child: Text('CONFIRMED', style: ST.label(7, color: ST.g0))),
              ]),
            ]),
            const SizedBox(height: 6),
            Text(widget.booking.bookingId,
                style: ST.mono(10, color: _ac).copyWith(letterSpacing: 1.4)),
            if (_expanded) ...[
              const SizedBox(height: 14),
              const Divider(color: ST.gBorder, height: 1),
              const SizedBox(height: 14),
              Center(child: Container(padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10)),
                  child: QrImageView(data: widget.booking.qrData, version: QrVersions.auto, size: 185,
                      eyeStyle: const QrEyeStyle(eyeShape: QrEyeShape.square, color: Colors.black),
                      dataModuleStyle: const QrDataModuleStyle(dataModuleShape: QrDataModuleShape.square, color: Colors.black)))),
              const SizedBox(height: 8),
              Center(child: Text('Show at entry gate · RFID scan validates ticket',
                  style: ST.body(10, color: ST.t3))),
              const SizedBox(height: 12),
              Container(padding: const EdgeInsets.all(10), decoration: ST.cardBox(radius: 8),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('BOOKING DETAILS', style: ST.label(8, color: ST.t3)),
                    const SizedBox(height: 8),
                    _BRow2('Name', widget.booking.userName),
                    _BRow2('Email', widget.booking.userEmail),
                    _BRow2('Phone', widget.booking.userPhone),
                    _BRow2('Date', widget.booking.date),
                    _BRow2('Slot', widget.booking.timeSlot),
                    _BRow2('Amount', '₹${widget.booking.price.toStringAsFixed(0)}'),
                    _BRow2('Booked', '${widget.booking.bookedAt.day}/${widget.booking.bookedAt.month}/${widget.booking.bookedAt.year}'),
                  ])),
              const SizedBox(height: 8),
              Container(padding: const EdgeInsets.all(10), decoration: ST.glowBox(ST.g1),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [const Icon(Icons.email_outlined, color: ST.g0, size: 13),
                      const SizedBox(width: 6),
                      Expanded(child: Text('Confirmation sent to ${widget.booking.userEmail}',
                          style: ST.body(10, color: ST.t2)))]),
                    const SizedBox(height: 4),
                    Row(children: [const Icon(Icons.sms_outlined, color: ST.g0, size: 13),
                      const SizedBox(width: 6),
                      Expanded(child: Text('SMS sent to ${widget.booking.userPhone}',
                          style: ST.body(10, color: ST.t2)))]),
                  ])),
            ],
          ])));
}

class _BRow2 extends StatelessWidget {
  final String l, v; const _BRow2(this.l, this.v);
  @override build(BuildContext context) => Padding(padding: const EdgeInsets.only(bottom: 4),
      child: Row(children: [
        SizedBox(width: 54, child: Text(l, style: ST.body(10, color: ST.t3))),
        Expanded(child: Text(v, style: ST.body(11, color: ST.t1).copyWith(fontWeight: FontWeight.w600))),
      ]));
}

// Updated _BookingConfirmNew (replaces the old _BookingConfirm for the new flow)
class _BookingConfirmNew extends StatelessWidget {
  final String id, qr, type, date, timeSlot, userName, userEmail, userPhone;
  final VoidCallback onGoToBookings; // ← new
  final VoidCallback onClose;
  const _BookingConfirmNew(
      {required this.id,
        required this.qr,
        required this.type,
        required this.date,
        required this.timeSlot,
        required this.userName,
        required this.userEmail,
        required this.userPhone,
        required this.onGoToBookings,
        required this.onClose});

  @override
  Widget build(BuildContext context) => Scaffold(
      backgroundColor: ST.bg,
      body: Center(
          child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                const Text('🎫', style: TextStyle(fontSize: 64))
                    .animate()
                    .scale(duration: 600.ms, curve: Curves.elasticOut),
                const SizedBox(height: 12),
                Text('BOOKING CONFIRMED', style: ST.bebas(30))
                    .animate()
                    .fadeIn(delay: 200.ms),
                Text('$type · $date',
                    style: ST.body(13, color: ST.t2))
                    .animate()
                    .fadeIn(delay: 300.ms),
                Text(timeSlot, style: ST.mono(11, color: ST.t3))
                    .animate()
                    .fadeIn(delay: 350.ms),
                const SizedBox(height: 20),
                Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(14)),
                    child: QrImageView(
                        data: qr,
                        version: QrVersions.auto,
                        size: 200,
                        eyeStyle: const QrEyeStyle(
                            eyeShape: QrEyeShape.square,
                            color: Colors.black),
                        dataModuleStyle: const QrDataModuleStyle(
                            dataModuleShape: QrDataModuleShape.square,
                            color: Colors.black)))
                    .animate()
                    .fadeIn(delay: 400.ms)
                    .scale(begin: const Offset(0.8, 0.8)),
                const SizedBox(height: 12),
                Text('Show QR at entry gate · RFID validated',
                    style: ST.body(11, color: ST.t3)),
                const SizedBox(height: 12),
                Container(
                    padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    decoration: ST.glowBox(ST.g1),
                    child: Text(id,
                        style:
                        ST.mono(13, color: ST.g0).copyWith(letterSpacing: 2))),
                const SizedBox(height: 12),
                Container(
                    padding: const EdgeInsets.all(12),
                    decoration: ST.glowBox(ST.g1),
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(children: [
                            const Icon(Icons.email, color: ST.g0, size: 14),
                            const SizedBox(width: 6),
                            Expanded(
                                child: Text(
                                    'Confirmation email sent to $userEmail',
                                    style: ST.body(10, color: ST.t2)))
                          ]),
                          const SizedBox(height: 4),
                          Row(children: [
                            const Icon(Icons.sms, color: ST.g0, size: 14),
                            const SizedBox(width: 6),
                            Expanded(
                                child: Text(
                                    'SMS confirmation sent to $userPhone',
                                    style: ST.body(10, color: ST.t2)))
                          ]),
                          const SizedBox(height: 4),
                          Row(children: [
                            const Icon(Icons.notifications,
                                color: ST.g0, size: 14),
                            const SizedBox(width: 6),
                            Expanded(
                                child: Text('Push notification sent',
                                    style: ST.body(10, color: ST.t2)))
                          ]),
                        ])),
                const SizedBox(height: 22),
                // PRIMARY: Go to My Bookings
                SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                        onPressed: onGoToBookings, // ← redirects correctly
                        style: ElevatedButton.styleFrom(
                            backgroundColor: ST.g1,
                            foregroundColor: ST.bg,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10)),
                            elevation: 0),
                        child: Text('View My Bookings →',
                            style: ST
                                .body(14, color: ST.bg)
                                .copyWith(fontWeight: FontWeight.w800)))),
                const SizedBox(height: 10),
                // SECONDARY: Stay on ticketing
                GestureDetector(
                    onTap: onClose,
                    child: Text('Book another ticket',
                        style: ST.body(12, color: ST.t3))),
              ]).animate().fadeIn(duration: 400.ms))));
}

// Booking confirmation
class _BookingConfirm extends StatelessWidget {
  final String id, qr, type;
  final VoidCallback onClose;
  const _BookingConfirm({
    required this.id,
    required this.qr,
    required this.type,
    required this.onClose,
  });
  @override
  build(BuildContext context) => Scaffold(
    backgroundColor: ST.bg,
    body: Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '🎫',
              style: const TextStyle(fontSize: 64),
            ).animate().scale(duration: 600.ms, curve: Curves.elasticOut),
            const SizedBox(height: 12),
            Text(
              'BOOKING CONFIRMED',
              style: ST.bebas(30),
            ).animate().fadeIn(delay: 200.ms),
            Text(
              type,
              style: ST.body(14, color: ST.t2),
            ).animate().fadeIn(delay: 300.ms),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
              ),
              child: QrImageView(
                data: qr,
                version: QrVersions.auto,
                size: 200,
                eyeStyle: const QrEyeStyle(
                  eyeShape: QrEyeShape.square,
                  color: Colors.black,
                ),
                dataModuleStyle: const QrDataModuleStyle(
                  dataModuleShape: QrDataModuleShape.square,
                  color: Colors.black,
                ),
              ),
            )
                .animate()
                .fadeIn(delay: 400.ms)
                .scale(begin: const Offset(0.8, 0.8)),
            const SizedBox(height: 14),
            Text(
              'Show QR at entry gate · RFID validated on scan',
              style: ST.body(11, color: ST.t3),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: ST.glowBox(ST.g1),
              child: Text(
                id,
                style: ST.mono(13, color: ST.g0).copyWith(letterSpacing: 2),
              ),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: ST.cardBox(radius: 8),
              child: Text(
                'Payment verified ✓ · Booking confirmed ✓\nValid for today\'s date only',
                style: ST.body(11, color: ST.t2),
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: 22),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: onClose,
                style: ElevatedButton.styleFrom(
                  backgroundColor: ST.g1,
                  foregroundColor: ST.bg,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  elevation: 0,
                ),
                child: Text(
                  'Back to Dashboard',
                  style: ST
                      .body(14, color: ST.bg)
                      .copyWith(fontWeight: FontWeight.w800),
                ),
              ),
            ),
          ],
        ).animate().fadeIn(duration: 400.ms),
      ),
    ),
  );
}

// Toast widget
class _ToastWidget extends StatefulWidget {
  final String title, msg;
  final Color color;
  final VoidCallback onDismiss;
  const _ToastWidget({
    required this.title,
    required this.msg,
    required this.color,
    required this.onDismiss,
  });
  @override
  State<_ToastWidget> createState() => _ToastState();
}

class _ToastState extends State<_ToastWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _ac;
  late Animation<double> _fade, _slide;
  @override
  void initState() {
    super.initState();
    _ac = AnimationController(vsync: this, duration: 300.ms);
    _fade = CurvedAnimation(parent: _ac, curve: Curves.easeOut);
    _slide = Tween<double>(
      begin: 20,
      end: 0,
    ).animate(CurvedAnimation(parent: _ac, curve: Curves.easeOut));
    _ac.forward();
    Future.delayed(const Duration(seconds: 3), () async {
      if (mounted) {
        await _ac.reverse();
        if (mounted) widget.onDismiss();
      }
    });
  }

  @override
  void dispose() {
    _ac.dispose();
    super.dispose();
  }

  @override
  build(BuildContext context) => Positioned(
    bottom: 75,
    left: 14,
    right: 14,
    child: AnimatedBuilder(
      animation: _ac,
      builder:
          (_, __) => Opacity(
        opacity: _fade.value,
        child: Transform.translate(
          offset: Offset(0, _slide.value),
          child: Material(
            color: Colors.transparent,
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: ST.panel,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: widget.color.withOpacity(0.5),
                  width: 1.2,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.4),
                    blurRadius: 14,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Container(
                    width: 4,
                    height: 36,
                    decoration: BoxDecoration(
                      color: widget.color,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.title,
                          style: ST
                              .body(12, color: widget.color)
                              .copyWith(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          widget.msg,
                          style: ST.body(11, color: ST.t2),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  GestureDetector(
                    onTap: widget.onDismiss,
                    child: Text('✕', style: ST.body(14, color: ST.t3)),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
// ─────────────────────────────────────────────────────────────────────────────
// END OF SAFARISYNC v2.2
// ─────────────────────────────────────────────────────────────────────────────