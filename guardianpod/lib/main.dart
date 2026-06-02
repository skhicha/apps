// lib/main.dart
// GUARDIANPOD PRO — COMPETITION EDITION
// Features: Real-time GPS tracking, live BLE SOS, animated dashboard,
// safety heatmap, SOS history, guardian network, dark/light mode,
// pulse animations, battery status, step counter, geofence alerts

import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

// ─────────────────────────────────────────────────────────────
//  THEME & CONSTANTS
// ─────────────────────────────────────────────────────────────

class AppColors {
  static const gradientStart  = Color(0xFF0F0C29);
  static const gradientMid    = Color(0xFF302B63);
  static const gradientEnd    = Color(0xFF24243E);
  static const accent         = Color(0xFF7C4DFF);
  static const accentLight    = Color(0xFFB388FF);
  static const danger         = Color(0xFFFF1744);
  static const dangerDark     = Color(0xFFB71C1C);
  static const safe           = Color(0xFF00E676);
  static const warning        = Color(0xFFFFD740);
  static const cardDark       = Color(0xFF1E1B3A);
  static const cardDarker     = Color(0xFF15122E);
  static const textPrimary    = Color(0xFFF0EEFF);
  static const textSecondary  = Color(0xFFAEA8D3);
}

// ─────────────────────────────────────────────────────────────
//  ENTRY POINT
// ─────────────────────────────────────────────────────────────

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
  ));
  await Firebase.initializeApp();
  runApp(const GuardianPodApp());
}

class GuardianPodApp extends StatelessWidget {
  const GuardianPodApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => BleScannerService()),
        ChangeNotifierProvider(create: (_) => AuthService()),
        ChangeNotifierProvider(create: (_) => LocationService()),
        ChangeNotifierProvider(create: (_) => AppStateService()),
        Provider(create: (_) => NotificationService()),
      ],
      child: MaterialApp(
        title: "GuardianPod Pro",
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          brightness: Brightness.dark,
          scaffoldBackgroundColor: AppColors.gradientStart,
          colorScheme: const ColorScheme.dark(
            primary: AppColors.accent,
            secondary: AppColors.accentLight,
            surface: AppColors.cardDark,
          ),
          textTheme: GoogleFonts.poppinsTextTheme(
            ThemeData.dark().textTheme,
          ).apply(bodyColor: AppColors.textPrimary, displayColor: AppColors.textPrimary),
          cardTheme: const CardThemeData(color: AppColors.cardDark, elevation: 0),
          appBarTheme: const AppBarTheme(
            backgroundColor: Colors.transparent,
            elevation: 0,
            centerTitle: true,
            titleTextStyle: TextStyle(
              color: AppColors.textPrimary,
              fontSize: 18,
              fontWeight: FontWeight.w600,
              letterSpacing: 1.2,
            ),
            iconTheme: IconThemeData(color: AppColors.textPrimary),
          ),
        ),
        home: const RootScreen(),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
//  APP STATE (global UI state)
// ─────────────────────────────────────────────────────────────

class SosHistoryEntry {
  final String deviceId;
  final SosSource source;
  final DateTime ts;
  final double? lat;
  final double? lon;

  SosHistoryEntry({
    required this.deviceId,
    required this.source,
    required this.ts,
    this.lat,
    this.lon,
  });

  String get timeAgo {
    final diff = DateTime.now().difference(ts);
    if (diff.inMinutes < 1) return "Just now";
    if (diff.inHours < 1) return "${diff.inMinutes}m ago";
    return "${diff.inHours}h ago";
  }
}

class AppStateService extends ChangeNotifier {
  int _currentIndex = 0;
  int get currentIndex => _currentIndex;
  void setIndex(int i) { _currentIndex = i; notifyListeners(); }

  bool emergencyActive = false;
  int podBattery = 87;
  int podSteps = 4213;
  bool geofenceEnabled = true;
  double geofenceRadius = 500;
  LatLng? geofenceCenter;

  List<SosHistoryEntry> sosHistory = [];

  void addSos(SosHistoryEntry e) {
    sosHistory.insert(0, e);
    if (sosHistory.length > 50) sosHistory.removeLast();
    notifyListeners();
  }

  void setEmergency(bool v) { emergencyActive = v; notifyListeners(); }
  void setBattery(int v)    { podBattery = v; notifyListeners(); }
  void setSteps(int v)      { podSteps = v; notifyListeners(); }

  Timer? _demoTimer;
  void startDemoUpdates() {
    _demoTimer?.cancel();
    _demoTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      podBattery = max(0, podBattery - 1);
      podSteps += Random().nextInt(30);
      notifyListeners();
    });
  }

  @override
  void dispose() { _demoTimer?.cancel(); super.dispose(); }
}

// ─────────────────────────────────────────────────────────────
//  AUTH SERVICE
// ─────────────────────────────────────────────────────────────

class AuthService extends ChangeNotifier {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  User? _user;
  User? get user => _user;

  AuthService() {
    _user = _auth.currentUser;
    _auth.authStateChanges().listen((u) {
      _user = u;
      notifyListeners();
    });
  }

  Future<void> signInEmail(String e, String p) =>
      _auth.signInWithEmailAndPassword(email: e, password: p);
  Future<void> registerEmail(String e, String p) =>
      _auth.createUserWithEmailAndPassword(email: e, password: p);
  Future<String?> signInAnon() async {
    try {
      await _auth.signInAnonymously();
      return null;
    } on FirebaseAuthException catch (e) {
      return e.message ?? e.code;
    } catch (e) { return e.toString(); }
  }
  Future<void> signOut() async {
    await _auth.signOut();
    _user = null;
    notifyListeners();
  }
}

// ─────────────────────────────────────────────────────────────
//  BLE SERVICE
//  Flow:
//   1. Tap "Scan" → Bluetooth turns on if off
//   2. App scans in background for GuardianPod_ devices
//   3. Native bottom-sheet dialog lists found devices
//   4. User taps a device → native Android pairing dialog fires
//   5. After pairing, GATT connect → discover services → subscribe
// ─────────────────────────────────────────────────────────────

enum SosSource { ble, simulated, manual, geofence }

class SosEvent {
  final String deviceId;
  final SosSource source;
  final DateTime ts;
  SosEvent({required this.deviceId, required this.source, DateTime? timestamp})
      : ts = timestamp ?? DateTime.now();
}

class BleDevice {
  final String id;
  final String name;
  final BluetoothDevice rawDevice;
  BleDevice({required this.id, required this.name, required this.rawDevice});
}

class BleScannerService extends ChangeNotifier {
  // ── UUIDs — exactly matching your firmware ──
  // SERVICE_UUID        "12345678-1234-1234-1234-123456789abc"
  // CHARACTERISTIC_UUID "87654321-1234-1234-1234-123456789abc"
  static const _serviceUUID = "12345678-1234-1234-1234-123456789abc";
  static const _sosCharUUID = "87654321-1234-1234-1234-123456789abc";

  // ── Device name your ESP32 broadcasts ──
  // Matches exactly: "GUARDIANPOD" (case-insensitive check below)
  static const _deviceName = "GUARDIANPOD";

  StreamSubscription<List<ScanResult>>?         _scanSub;
  StreamSubscription<BluetoothConnectionState>? _connStateSub;
  StreamSubscription<List<int>>?                _charNotifySub; // characteristic notify sub
  StreamSubscription<BluetoothAdapterState>?    _adapterSub;

  final List<BleDevice> devices = [];
  bool scanning = false;

  BluetoothDevice?  _connectedBtDevice;
  BleDevice?        connectedDevice;
  String            connectionStatus = "Tap 'Scan' to find your watch";

  final StreamController<SosEvent> _sosCtrl =
  StreamController<SosEvent>.broadcast();
  Stream<SosEvent> get sosStream => _sosCtrl.stream;

  // ────────────────────────────────────────────────────────────
  //  _isOurDevice
  //  Accepts the device if its name:
  //   • equals "GUARDIANPOD" (your current firmware name), OR
  //   • starts with "GuardianPod" (old firmware), OR
  //   • contains "GUARDIAN" (any variant)
  //  This is case-insensitive so "guardianpod" also matches.
  // ────────────────────────────────────────────────────────────
  bool _isOurDevice(String name) {
    if (name.isEmpty) return false;
    final upper = name.toUpperCase();
    return upper == "GUARDIANPOD" ||
        upper.startsWith("GUARDIANPOD") ||
        upper.contains("GUARDIAN");
  }

  // ────────────────────────────────────────────────────────────
  //  findDevices
  //
  //  WHY PAIRED DEVICES DON'T SHOW IN BLE SCAN:
  //  Once a device is bonded (paired) in Android Bluetooth settings,
  //  it stops advertising constantly. A normal BLE scan won't find
  //  it. The fix is to check bondedDevices FIRST, then run a scan
  //  for any newly advertising (unpaired) devices, then merge both.
  //
  //  WHAT HAPPENS:
  //  1. BT turned on if needed (system dialog)
  //  2. bondedDevices checked → GUARDIANPOD found immediately
  //  3. Short scan also runs to catch new/unpaired devices
  //  4. All found devices shown in picker sheet
  //  5. User taps → connectTo() runs → GATT connect → SOS subscribe
  // ────────────────────────────────────────────────────────────
  Future<List<BleDevice>> findDevices() async {
    devices.clear();
    scanning = true;
    connectionStatus = "Looking for GUARDIANPOD…";
    notifyListeners();

    // ── Step 1: Turn Bluetooth on if off ──
    try {
      final state = await FlutterBluePlus.adapterState.first
          .timeout(const Duration(seconds: 3));
      if (state != BluetoothAdapterState.on && Platform.isAndroid) {
        await FlutterBluePlus.turnOn();
        await FlutterBluePlus.adapterState
            .where((s) => s == BluetoothAdapterState.on)
            .first
            .timeout(const Duration(seconds: 8),
            onTimeout: () => BluetoothAdapterState.off);
      }
    } catch (_) {}

    // ── Step 2: Check already-bonded devices ──
    // This is the MAIN fix for "connected in phone but not showing".
    // A paired device doesn't re-advertise so scan alone misses it.
    if (Platform.isAndroid) {
      try {
        final bonded = await FlutterBluePlus.bondedDevices;
        for (final bd in bonded) {
          final name = bd.platformName;
          final id   = bd.remoteId.str;
          if (_isOurDevice(name) && !devices.any((d) => d.id == id)) {
            devices.add(BleDevice(id: id, name: name, rawDevice: bd));
            notifyListeners();
          }
        }
      } catch (_) {}
    }

    // ── Step 3: Also scan for NEW (unpaired/re-advertising) devices ──
    // Runs for 6 seconds. Any device seen is added if not already in list.
    // NO name filter here — we show everything, user picks their device.
    try {
      await FlutterBluePlus.stopScan();
      await FlutterBluePlus.startScan(
        timeout: const Duration(seconds: 6),
        androidUsesFineLocation: false,
      );
      _scanSub?.cancel();
      _scanSub = FlutterBluePlus.scanResults.listen((results) {
        bool changed = false;
        for (final r in results) {
          final name = r.device.platformName;
          final id   = r.device.remoteId.str;
          // Add if it's our device AND not already in the list
          if (_isOurDevice(name) && !devices.any((d) => d.id == id)) {
            devices.add(BleDevice(id: id, name: name, rawDevice: r.device));
            changed = true;
          }
        }
        if (changed) notifyListeners();
      });
      await Future.delayed(const Duration(seconds: 6));
      await FlutterBluePlus.stopScan();
      _scanSub?.cancel();
    } catch (_) {}

    scanning = false;

    if (devices.isEmpty) {
      connectionStatus =
      "GUARDIANPOD not found.\n\n"
          "If you already paired it in phone Bluetooth settings, "
          "it should appear here automatically. Make sure the watch "
          "is powered on and within range.";
    } else {
      connectionStatus = "${devices.length} device(s) found — tap to connect";
    }
    notifyListeners();

    return List.unmodifiable(devices);
  }

  // Keep old name as alias so nothing else in the code breaks
  Future<List<BleDevice>> startScanAndWait() => findDevices();

  void stopScan() {
    scanning = false;
    _scanSub?.cancel();
    FlutterBluePlus.stopScan();
    connectionStatus = connectedDevice != null
        ? "Connected to ${connectedDevice!.name}"
        : "Scan stopped";
    notifyListeners();
  }

  // ────────────────────────────────────────────────────────────
  //  connectTo
  //  Works for both bonded and new devices.
  //  Bonded: Android skips pairing, goes straight to GATT.
  //  New: Android shows pairing confirmation dialog automatically.
  // ────────────────────────────────────────────────────────────
  Future<void> connectTo(BleDevice dev) async {
    if (_connectedBtDevice != null) await _cleanDisconnect();

    connectionStatus = "Connecting to ${dev.name}…";
    notifyListeners();

    try {
      final btDev = dev.rawDevice;
      _connectedBtDevice = btDev;

      // Watch for disconnection events
      _connStateSub?.cancel();
      _connStateSub = btDev.connectionState.listen((state) {
        if (state == BluetoothConnectionState.disconnected) {
          connectedDevice    = null;
          _connectedBtDevice = null;
          connectionStatus   = "Watch disconnected. Tap Scan to reconnect.";
          notifyListeners();
        }
      });

      // Connect (20s timeout — bonded devices connect in <1s)
      await btDev.connect(
        autoConnect: false,
        timeout: const Duration(seconds: 20),
      );

      // Request larger MTU for GPS strings
      if (Platform.isAndroid) {
        try { await btDev.requestMtu(512); } catch (_) {}
      }

      // Discover GATT services
      final services = await btDev.discoverServices();
      BluetoothCharacteristic? sosChar;

      // Pass 1: match by service UUID + char UUID (exact match — your firmware)
      for (final svc in services) {
        if (svc.serviceUuid.toString().toLowerCase() ==
            _serviceUUID.toLowerCase()) {
          for (final c in svc.characteristics) {
            if (c.characteristicUuid.toString().toLowerCase() ==
                _sosCharUUID.toLowerCase()) {
              sosChar = c;
              break;
            }
          }
        }
        if (sosChar != null) break;
      }

      // Pass 2: fallback — match char UUID in any service
      if (sosChar == null) {
        outer:
        for (final svc in services) {
          for (final c in svc.characteristics) {
            if (c.characteristicUuid.toString().toLowerCase() ==
                _sosCharUUID.toLowerCase()) {
              sosChar = c;
              break outer;
            }
          }
        }
      }

      // Pass 3 — last resort: first NOTIFY or READ/WRITE characteristic
      if (sosChar == null) {
        for (final svc in services) {
          for (final c in svc.characteristics) {
            if (c.properties.notify || c.properties.read) {
              sosChar = c;
              break;
            }
          }
          if (sosChar != null) break;
        }
      }

      if (sosChar == null) {
        connectedDevice  = dev;
        connectionStatus = "Connected to ${dev.name} "
            "— no readable characteristic found. Check firmware UUIDs.";
        notifyListeners();
        return;
      }

      // ── Subscribe OR Poll depending on firmware capability ──
      //
      // Your current firmware: PROPERTY_READ | PROPERTY_WRITE (no NOTIFY)
      //   → App polls every 500ms by reading the value directly
      //   → When value changes from "0"/"idle" to "1"/"ALERT", SOS fires
      //
      // If you add PROPERTY_NOTIFY to firmware later:
      //   → App subscribes and receives instant push on button press
      //
      _charNotifySub?.cancel();

      if (sosChar.properties.notify || sosChar.properties.indicate) {
        // ── NOTIFY mode (instant, preferred) ──
        debugPrint("[BLE] Subscribing to NOTIFY on ${sosChar.characteristicUuid}");
        await sosChar.setNotifyValue(true);
        _charNotifySub = sosChar.onValueReceived.listen((bytes) {
          if (bytes.isEmpty) return;
          debugPrint("[BLE SOS] NOTIFY bytes: $bytes");
          if (_isSosTrigger(bytes)) triggerSos(dev.name);
        });

      } else if (sosChar.properties.read) {
        // ── READ POLLING mode (works with your current firmware) ──
        // Reads the characteristic every 500ms.
        // When button is pressed, firmware sets value to "1" or "ALERT".
        // App detects the change and fires SOS.
        debugPrint("[BLE] Starting READ poll on ${sosChar.characteristicUuid}");
        String _lastValue = "";

        _charNotifySub = Stream.periodic(
            const Duration(milliseconds: 500)).asyncMap((_) async {
          try {
            final bytes = await sosChar!.read();
            return bytes;
          } catch (_) { return <int>[]; }
        }).listen((bytes) {
          if (bytes.isEmpty) return;
          final current = String.fromCharCodes(bytes).trim();
          debugPrint("[BLE POLL] Value: '$current' (prev: '$_lastValue')");

          // Only trigger SOS when value CHANGES to a trigger value
          // (avoids firing repeatedly while button is held)
          if (current != _lastValue) {
            _lastValue = current;
            if (_isSosTrigger(bytes)) {
              debugPrint("[BLE SOS] Poll trigger fired!");
              triggerSos(dev.name);
            }
          }
        });
      }

      connectedDevice  = dev;
      connectionStatus = sosChar.properties.notify
          ? "Connected to ${dev.name} ✓ (NOTIFY)"
          : "Connected to ${dev.name} ✓ (polling)";
      notifyListeners();

    } catch (e) {
      connectionStatus =
      "Connection failed: ${e.toString().replaceAll('Exception: ', '')}";
      connectedDevice    = null;
      _connectedBtDevice = null;
      notifyListeners();
      rethrow;
    }
  }

  // ── _isSosTrigger ──────────────────────────────────────────
  // Returns true if the bytes from the characteristic represent
  // a button-press / SOS event.
  // Your firmware writes the string "1" when button is pressed.
  // Handles all common firmware patterns:
  //   • ASCII string "1"  (your current firmware)
  //   • ASCII string "ALERT", "SOS", "FALL", "EMERGENCY"
  //   • Raw byte 0x01
  //   • Any single non-zero byte
  bool _isSosTrigger(List<int> bytes) {
    if (bytes.isEmpty) return false;
    final raw = String.fromCharCodes(bytes).trim().toUpperCase();
    return raw == "1"              ||
        raw.contains("ALERT")  ||
        raw.contains("SOS")    ||
        raw.contains("FALL")   ||
        raw.contains("EMERG")  ||
        bytes[0] == 0x01       ||
        bytes[0] == 0x31       ||  // ASCII "1"
        (bytes.length == 1 && bytes[0] != 0x00);
  }

  Future<void> _cleanDisconnect() async {
    _charNotifySub?.cancel();
    _connStateSub?.cancel();
    try { await _connectedBtDevice?.disconnect(); } catch (_) {}
    _connectedBtDevice = null;
    connectedDevice    = null;
    connectionStatus   = "Disconnected";
    notifyListeners();
  }

  Future<void> disconnect() => _cleanDisconnect();

  void triggerSos(String deviceId) {
    debugPrint("[SOS] triggerSos called — deviceId: $deviceId");
    _sosCtrl.add(SosEvent(deviceId: deviceId, source: SosSource.ble));
  }

  void simulateWearableSos() {
    _sosCtrl.add(SosEvent(
        deviceId: "SIMULATED_POD", source: SosSource.simulated));
  }

  @override
  void dispose() {
    _scanSub?.cancel();
    _connStateSub?.cancel();
    _charNotifySub?.cancel();
    _adapterSub?.cancel();
    _sosCtrl.close();
    super.dispose();
  }
}

// ─────────────────────────────────────────────────────────────
//  LOCATION SERVICE
// ─────────────────────────────────────────────────────────────

class LocationService extends ChangeNotifier {
  bool sharing = false;
  Position? lastPos;
  List<LatLng> breadcrumb = [];
  Timer? _timer;

  final firestore = FirebaseFirestore.instance;
  final rtdb = FirebaseDatabase.instance;

  Future<bool> request() async =>
      (await Permission.location.request()).isGranted;

  Future<void> startSharing(String uid) async {
    if (!await request()) return;
    sharing = true;
    notifyListeners();
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 5), (_) async {
      try {
        final pos = await Geolocator.getCurrentPosition(
            desiredAccuracy: LocationAccuracy.best);
        lastPos = pos;
        final ll = LatLng(pos.latitude, pos.longitude);
        breadcrumb.add(ll);
        if (breadcrumb.length > 200) breadcrumb.removeAt(0);
        notifyListeners();

        await firestore.collection("live_locations").doc(uid).set({
          "lat": pos.latitude,
          "lon": pos.longitude,
          "accuracy": pos.accuracy,
          "ts": FieldValue.serverTimestamp(),
        });
        await rtdb.ref("live_locations/$uid").set({
          "lat": pos.latitude,
          "lon": pos.longitude,
          "ts": DateTime.now().toIso8601String(),
        });
      } catch (_) {}
    });
  }

  void stopSharing() {
    sharing = false;
    _timer?.cancel();
    notifyListeners();
  }
}

// ─────────────────────────────────────────────────────────────
//  NOTIFICATION SERVICE
// ─────────────────────────────────────────────────────────────

class NotificationService {
  final FlutterLocalNotificationsPlugin plugin = FlutterLocalNotificationsPlugin();
  final StreamController<bool> _navCtrl = StreamController<bool>.broadcast();
  Stream<bool> get navStream => _navCtrl.stream;

  NotificationService() { _init(); }

  Future<void> _init() async {
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const ios = DarwinInitializationSettings();
    await plugin.initialize(
      const InitializationSettings(android: android, iOS: ios),
      onDidReceiveNotificationResponse: (_) => _navCtrl.add(true),
    );
    const channel = AndroidNotificationChannel(
      'guardian_sos_channel', 'Guardian SOS Alerts',
      description: 'Emergency siren alerts',
      importance: Importance.max,
      playSound: true,
      sound: RawResourceAndroidNotificationSound('siren'),
    );
    await plugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);
  }

  Future<void> notifySos(String msg) async {
    const android = AndroidNotificationDetails(
      'guardian_sos_channel', 'Guardian SOS Alerts',
      channelDescription: 'Emergency siren alerts',
      importance: Importance.max,
      priority: Priority.max,
      playSound: true,
      sound: RawResourceAndroidNotificationSound('siren'),
      color: Color(0xFFFF1744),
      largeIcon: DrawableResourceAndroidBitmap('@mipmap/ic_launcher'),
      styleInformation: BigTextStyleInformation(''),
    );
    await plugin.show(999, "🚨 SOS ALERT — GuardianPod", msg,
        NotificationDetails(android: android));
    _navCtrl.add(true);
  }

  Future<void> notifySafe(String msg) async {
    const android = AndroidNotificationDetails(
      'guardian_safe_channel', 'Safe Alerts',
      channelDescription: 'Safety notifications',
      importance: Importance.defaultImportance,
      priority: Priority.defaultPriority,
      color: Color(0xFF00E676),
    );
    await plugin.show(998, "✅ GuardianPod", msg, NotificationDetails(android: android));
  }
}

// ─────────────────────────────────────────────────────────────
//  ROOT SCREEN
// ─────────────────────────────────────────────────────────────

class RootScreen extends StatelessWidget {
  const RootScreen({super.key});

  Future<void> _askPerms() async {
    await Permission.location.request();
    if (Platform.isAndroid) {
      await Permission.bluetoothScan.request();
      await Permission.bluetoothConnect.request();
    }
    await Permission.notification.request();
  }

  @override
  Widget build(BuildContext context) {
    _askPerms();
    return Consumer<AuthService>(builder: (_, auth, __) {
      if (auth.user == null) return const AuthGate();
      return const MainShell();
    });
  }
}

// ─────────────────────────────────────────────────────────────
//  AUTH GATE
// ─────────────────────────────────────────────────────────────

class AuthGate extends StatefulWidget {
  const AuthGate({super.key});
  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> with TickerProviderStateMixin {
  final emailCtrl = TextEditingController();
  final passCtrl  = TextEditingController();
  bool loading = false;
  late AnimationController _pulseCtrl;
  late Animation<double> _pulse;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(vsync: this, duration: const Duration(seconds: 2))
      ..repeat(reverse: true);
    _pulse = Tween(begin: 0.95, end: 1.05).animate(
        CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut));
  }

  @override
  void dispose() { _pulseCtrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final auth = context.read<AuthService>();
    final size = MediaQuery.of(context).size;

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [AppColors.gradientStart, AppColors.gradientMid, AppColors.gradientEnd],
          ),
        ),
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(28),
            child: Column(
              children: [
                SizedBox(height: size.height * 0.06),
                ScaleTransition(
                  scale: _pulse,
                  child: Container(
                    width: 110, height: 110,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: const RadialGradient(
                        colors: [AppColors.accent, AppColors.gradientMid],
                      ),
                      boxShadow: [
                        BoxShadow(color: AppColors.accent.withOpacity(0.5),
                            blurRadius: 30, spreadRadius: 5),
                      ],
                    ),
                    child: const Icon(Icons.shield_rounded, size: 60, color: Colors.white),
                  ),
                ),
                const SizedBox(height: 20),
                Text("GuardianPod Pro",
                    style: GoogleFonts.poppins(
                        fontSize: 28, fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary, letterSpacing: 1)),
                const SizedBox(height: 6),
                Text("Your child's safety, in your hands",
                    style: GoogleFonts.poppins(
                        fontSize: 13, color: AppColors.textSecondary)),
                const SizedBox(height: 40),
                _GlassCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text("Welcome Back", style: GoogleFonts.poppins(
                          fontSize: 20, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
                      const SizedBox(height: 20),
                      _StyledField(controller: emailCtrl, label: "Email", icon: Icons.email_rounded),
                      const SizedBox(height: 14),
                      _StyledField(controller: passCtrl, label: "Password",
                          icon: Icons.lock_rounded, obscure: true),
                      const SizedBox(height: 24),
                      SizedBox(
                        width: double.infinity,
                        height: 54,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.accent,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16)),
                            elevation: 0,
                          ),
                          onPressed: loading ? null : () async {
                            setState(() => loading = true);
                            final email = emailCtrl.text.trim();
                            final pass  = passCtrl.text.trim();
                            if (email.isEmpty) {
                              _snack("Enter your email");
                              setState(() => loading = false); return;
                            }
                            try {
                              await auth.signInEmail(email, pass);
                            } on FirebaseAuthException catch (e) {
                              if (e.code == 'user-not-found' || e.code == 'wrong-password'
                                  || e.code == 'invalid-credential') {
                                if (!mounted) return;
                                Navigator.push(context, MaterialPageRoute(
                                    builder: (_) => SignupScreen(email: email)));
                                setState(() => loading = false); return;
                              }
                              _snack("Auth error: ${e.code}");
                            }
                            setState(() => loading = false);
                          },
                          child: loading
                              ? const SizedBox(width: 24, height: 24,
                              child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                              : Text("Sign In", style: GoogleFonts.poppins(
                              fontSize: 16, fontWeight: FontWeight.w600, color: Colors.white)),
                        ),
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        height: 54,
                        child: OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppColors.accentLight,
                            side: const BorderSide(color: AppColors.accent, width: 1.5),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16)),
                          ),
                          onPressed: () {
                            final email = emailCtrl.text.trim();
                            Navigator.push(context, MaterialPageRoute(
                                builder: (_) => SignupScreen(email: email)));
                          },
                          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                            const Icon(Icons.person_add_rounded, size: 18, color: AppColors.accentLight),
                            const SizedBox(width: 8),
                            Text("Create New Account", style: GoogleFonts.poppins(
                                fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.accentLight)),
                          ]),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(children: [
                        Expanded(child: Divider(color: Colors.white.withOpacity(0.1), thickness: 1)),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          child: Text("or", style: GoogleFonts.poppins(
                              fontSize: 12, color: AppColors.textSecondary)),
                        ),
                        Expanded(child: Divider(color: Colors.white.withOpacity(0.1), thickness: 1)),
                      ]),
                      const SizedBox(height: 8),
                      Center(
                        child: TextButton.icon(
                          onPressed: loading ? null : () async {
                            setState(() => loading = true);
                            try {
                              final cred = await FirebaseAuth.instance.signInAnonymously();
                              if (!mounted) return;
                              if (cred.user != null) {
                                Navigator.of(context).pushAndRemoveUntil(
                                  MaterialPageRoute(builder: (_) => const MainShell()),
                                      (r) => false,
                                );
                              }
                            } on FirebaseAuthException catch (e) {
                              if (!mounted) return;
                              setState(() => loading = false);
                              if (e.code == 'operation-not-allowed') {
                                showDialog(
                                  context: context,
                                  builder: (_) => AlertDialog(
                                    backgroundColor: AppColors.cardDark,
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                                    title: Row(children: [
                                      const Icon(Icons.warning_rounded, color: AppColors.warning),
                                      const SizedBox(width: 10),
                                      Text("Enable Guest Login", style: GoogleFonts.poppins(
                                          color: AppColors.textPrimary, fontWeight: FontWeight.w700)),
                                    ]),
                                    content: Column(mainAxisSize: MainAxisSize.min,
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text("Anonymous sign-in is not enabled in your Firebase project. To fix this:", style: GoogleFonts.poppins(fontSize: 13, color: AppColors.textSecondary, height: 1.5)),
                                          const SizedBox(height: 12),
                                          _InstructionStep(n: "1", text: "Go to console.firebase.google.com"),
                                          _InstructionStep(n: "2", text: "Select your project"),
                                          _InstructionStep(n: "3", text: "Authentication → Sign-in method"),
                                          _InstructionStep(n: "4", text: "Click Anonymous → Enable → Save"),
                                        ]),
                                    actions: [
                                      ElevatedButton(
                                        style: ElevatedButton.styleFrom(backgroundColor: AppColors.accent, foregroundColor: Colors.white),
                                        onPressed: () => Navigator.pop(context),
                                        child: Text("Got it", style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
                                      ),
                                    ],
                                  ),
                                );
                              } else {
                                _snack("Guest error: ${e.message ?? e.code}");
                              }
                            } catch (e) {
                              if (!mounted) return;
                              setState(() => loading = false);
                              _snack("Unexpected error: $e");
                            }
                          },
                          icon: const Icon(Icons.visibility_off_rounded,
                              size: 16, color: AppColors.textSecondary),
                          label: Text("Browse as Guest (limited access)",
                              style: GoogleFonts.poppins(
                                  color: AppColors.textSecondary, fontSize: 12)),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(msg), backgroundColor: AppColors.cardDark));
  }
}

// ─────────────────────────────────────────────────────────────
//  SIGNUP SCREEN
// ─────────────────────────────────────────────────────────────

class SignupScreen extends StatefulWidget {
  final String email;
  const SignupScreen({super.key, required this.email});
  @override
  State<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends State<SignupScreen> {
  final PageController _pageCtrl = PageController();
  int _step = 0;
  bool loading = false;

  final emailCtrl   = TextEditingController();
  final passCtrl    = TextEditingController();
  final confirmCtrl = TextEditingController();
  final nameCtrl    = TextEditingController();
  final dobCtrl     = TextEditingController();
  final phoneCtrl   = TextEditingController();
  final addressCtrl = TextEditingController();
  final cityCtrl    = TextEditingController();
  String? selectedGender;
  DateTime? selectedDob;

  final guardianNameCtrl  = TextEditingController();
  final guardianPhoneCtrl = TextEditingController();
  final emergency2Ctrl    = TextEditingController();
  final emergency2NameCtrl= TextEditingController();
  final medicalCtrl       = TextEditingController();
  String? selectedRelationship;
  String? selectedBloodGroup;

  final deviceNameCtrl = TextEditingController();
  final childNameCtrl  = TextEditingController();
  final childAgeCtrl   = TextEditingController();
  final schoolCtrl     = TextEditingController();
  String? selectedChildGender;

  @override
  void initState() {
    super.initState();
    emailCtrl.text = widget.email;
  }

  @override
  void dispose() {
    _pageCtrl.dispose();
    for (final c in [emailCtrl, passCtrl, confirmCtrl, nameCtrl, dobCtrl,
      phoneCtrl, addressCtrl, cityCtrl, guardianNameCtrl,
      guardianPhoneCtrl, emergency2Ctrl, emergency2NameCtrl,
      medicalCtrl, deviceNameCtrl, childNameCtrl,
      childAgeCtrl, schoolCtrl]) c.dispose();
    super.dispose();
  }

  void _nextStep() {
    if (_step < 3) {
      if (!_validateStep()) return;
      setState(() => _step++);
      _pageCtrl.animateToPage(_step,
          duration: const Duration(milliseconds: 350), curve: Curves.easeInOut);
    } else {
      _submit();
    }
  }

  void _prevStep() {
    if (_step > 0) {
      setState(() => _step--);
      _pageCtrl.animateToPage(_step,
          duration: const Duration(milliseconds: 350), curve: Curves.easeInOut);
    } else {
      Navigator.pop(context);
    }
  }

  bool _validateStep() {
    String? err;
    switch (_step) {
      case 0:
        if (emailCtrl.text.trim().isEmpty) err = "Enter your email";
        else if (passCtrl.text.length < 6)  err = "Password must be at least 6 characters";
        else if (passCtrl.text != confirmCtrl.text) err = "Passwords do not match";
        break;
      case 1:
        if (nameCtrl.text.trim().isEmpty) err = "Enter your full name";
        else if (phoneCtrl.text.trim().isEmpty) err = "Enter your phone number";
        break;
      case 2:
        if (guardianNameCtrl.text.trim().isEmpty) err = "Enter guardian name";
        else if (guardianPhoneCtrl.text.trim().isEmpty) err = "Enter guardian phone";
        break;
      case 3:
        if (childNameCtrl.text.trim().isEmpty) err = "Enter the child's name";
        break;
    }
    if (err != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(err, style: GoogleFonts.poppins(fontSize: 13)),
        backgroundColor: AppColors.danger,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ));
      return false;
    }
    return true;
  }

  Future<void> _submit() async {
    if (!_validateStep()) return;
    setState(() => loading = true);

    final auth = context.read<AuthService>();
    try {
      await auth.registerEmail(emailCtrl.text.trim(), passCtrl.text.trim());
      final uid = FirebaseAuth.instance.currentUser!.uid;

      await FirebaseFirestore.instance.collection("users").doc(uid).set({
        "uid": uid,
        "email": emailCtrl.text.trim(),
        "created_at": FieldValue.serverTimestamp(),
        "full_name": nameCtrl.text.trim(),
        "date_of_birth": dobCtrl.text.trim(),
        "gender": selectedGender ?? "",
        "phone": phoneCtrl.text.trim(),
        "address": addressCtrl.text.trim(),
        "city": cityCtrl.text.trim(),
        "guardian": {
          "name": guardianNameCtrl.text.trim(),
          "phone": guardianPhoneCtrl.text.trim(),
          "relationship": selectedRelationship ?? "",
        },
        "emergency_contact_2": {
          "name": emergency2NameCtrl.text.trim(),
          "phone": emergency2Ctrl.text.trim(),
        },
        "blood_group": selectedBloodGroup ?? "",
        "medical_conditions": medicalCtrl.text.trim(),
        "child_name": childNameCtrl.text.trim(),
        "child_age": childAgeCtrl.text.trim(),
        "child_gender": selectedChildGender ?? "",
        "school_name": schoolCtrl.text.trim(),
        "device_name": deviceNameCtrl.text.trim().isEmpty
            ? "GUARDIANPOD"
            : deviceNameCtrl.text.trim(),
        "profile_complete": true,
      });

      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const MainShell()),
              (r) => false);
    } on FirebaseAuthException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text("Auth error: ${e.message ?? e.code}", style: GoogleFonts.poppins()),
          backgroundColor: AppColors.danger,
          behavior: SnackBarBehavior.floating,
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text("Error saving data: $e", style: GoogleFonts.poppins()),
          backgroundColor: AppColors.danger,
          behavior: SnackBarBehavior.floating,
        ));
      }
    }

    if (mounted) setState(() => loading = false);
  }

  Widget _stepIndicator() {
    const labels = ["Account", "Personal", "Guardian", "Device"];
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(4, (i) {
        final done = i < _step;
        final active = i == _step;
        return Row(children: [
          Column(children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              width: active ? 32 : 24,
              height: active ? 32 : 24,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: done ? AppColors.safe
                    : active ? AppColors.accent
                    : AppColors.cardDarker,
                border: Border.all(
                    color: active ? AppColors.accent
                        : done ? AppColors.safe
                        : Colors.white.withOpacity(0.1),
                    width: 2),
              ),
              child: Center(child: done
                  ? const Icon(Icons.check_rounded, size: 14, color: Colors.white)
                  : Text("${i+1}", style: GoogleFonts.poppins(
                fontSize: active ? 13 : 11,
                fontWeight: FontWeight.w700,
                color: active ? Colors.white : AppColors.textSecondary,
              ))),
            ),
            const SizedBox(height: 4),
            Text(labels[i], style: GoogleFonts.poppins(
                fontSize: 9,
                color: active ? AppColors.accent
                    : done ? AppColors.safe
                    : AppColors.textSecondary,
                fontWeight: active ? FontWeight.w700 : FontWeight.normal)),
          ]),
          if (i < 3)
            Container(
              width: 36, height: 2,
              margin: const EdgeInsets.only(bottom: 20),
              color: i < _step ? AppColors.safe : Colors.white.withOpacity(0.1),
            ),
        ]);
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft, end: Alignment.bottomRight,
            colors: [AppColors.gradientStart, AppColors.gradientMid, AppColors.gradientEnd],
          ),
        ),
        child: SafeArea(
          child: Column(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 12, 20, 0),
              child: Row(children: [
                IconButton(
                  icon: const Icon(Icons.arrow_back_ios_rounded, color: AppColors.textPrimary),
                  onPressed: _prevStep,
                ),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text("Create Account", style: GoogleFonts.poppins(
                      fontSize: 20, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                  Text("Step ${_step + 1} of 4", style: GoogleFonts.poppins(
                      fontSize: 12, color: AppColors.textSecondary)),
                ])),
              ]),
            ),
            const SizedBox(height: 16),
            _stepIndicator(),
            const SizedBox(height: 16),
            Expanded(
              child: PageView(
                controller: _pageCtrl,
                physics: const NeverScrollableScrollPhysics(),
                children: [
                  _buildStep1(),
                  _buildStep2(),
                  _buildStep3(),
                  _buildStep4(),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
              child: SizedBox(
                width: double.infinity, height: 56,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _step == 3 ? AppColors.safe : AppColors.accent,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                    elevation: 0,
                  ),
                  onPressed: loading ? null : _nextStep,
                  child: loading
                      ? const SizedBox(width: 24, height: 24,
                      child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                      : Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Text(
                      _step == 3 ? "Create My Account" : "Continue",
                      style: GoogleFonts.poppins(
                          fontSize: 16, fontWeight: FontWeight.w700, color: Colors.white),
                    ),
                    const SizedBox(width: 8),
                    Icon(_step == 3 ? Icons.check_circle_rounded : Icons.arrow_forward_rounded,
                        size: 20, color: Colors.white),
                  ]),
                ),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _buildStep1() => _StepPage(
    icon: Icons.account_circle_rounded,
    title: "Account Details",
    subtitle: "Your login credentials",
    children: [
      _StyledField(controller: emailCtrl, label: "Email Address *", icon: Icons.email_rounded, type: TextInputType.emailAddress),
      const SizedBox(height: 12),
      _StyledField(controller: passCtrl, label: "Password (min 6 chars) *", icon: Icons.lock_rounded, obscure: true),
      const SizedBox(height: 12),
      _StyledField(controller: confirmCtrl, label: "Confirm Password *", icon: Icons.lock_outline_rounded, obscure: true),
    ],
  );

  Widget _buildStep2() {
    return _StepPage(
      icon: Icons.person_rounded,
      title: "Personal Information",
      subtitle: "Tell us about yourself",
      children: [
        _StyledField(controller: nameCtrl, label: "Full Name *", icon: Icons.badge_rounded),
        const SizedBox(height: 12),
        GestureDetector(
          onTap: () async {
            final picked = await showDatePicker(
              context: context,
              initialDate: selectedDob ?? DateTime(2010, 1, 1),
              firstDate: DateTime(1940),
              lastDate: DateTime.now(),
              builder: (ctx, child) => Theme(
                data: ThemeData.dark().copyWith(
                  colorScheme: const ColorScheme.dark(
                    primary: AppColors.accent,
                    onPrimary: Colors.white,
                    surface: AppColors.cardDark,
                    onSurface: AppColors.textPrimary,
                  ),
                  dialogBackgroundColor: AppColors.cardDarker,
                ),
                child: child!,
              ),
            );
            if (picked != null) {
              setState(() {
                selectedDob = picked;
                dobCtrl.text =
                "${picked.day.toString().padLeft(2,'0')}/${picked.month.toString().padLeft(2,'0')}/${picked.year}";
              });
            }
          },
          child: AbsorbPointer(
            child: _StyledField(
              controller: dobCtrl,
              label: "Date of Birth *",
              icon: Icons.calendar_today_rounded,
              suffixIcon: Icons.expand_more_rounded,
            ),
          ),
        ),
        const SizedBox(height: 12),
        _DropdownField(
          label: "Gender *",
          icon: Icons.wc_rounded,
          value: selectedGender,
          items: const ["Male", "Female", "Non-binary", "Prefer not to say"],
          onChanged: (v) => setState(() => selectedGender = v),
        ),
        const SizedBox(height: 12),
        _StyledField(controller: phoneCtrl, label: "Your Phone Number *", icon: Icons.phone_rounded, type: TextInputType.phone),
        const SizedBox(height: 12),
        _StyledField(controller: addressCtrl, label: "Home Address", icon: Icons.home_rounded),
        const SizedBox(height: 12),
        _StyledField(controller: cityCtrl, label: "City / State", icon: Icons.location_city_rounded),
      ],
    );
  }

  Widget _buildStep3() {
    return _StepPage(
      icon: Icons.shield_rounded,
      title: "Guardian & Emergency",
      subtitle: "Who to call in an emergency",
      children: [
        _InfoBanner(text: "These contacts are called automatically when SOS is triggered. Make sure they are reachable 24/7."),
        const SizedBox(height: 12),
        _StyledField(controller: guardianNameCtrl, label: "Primary Guardian Name *", icon: Icons.person_rounded),
        const SizedBox(height: 12),
        _StyledField(controller: guardianPhoneCtrl, label: "Guardian Phone *", icon: Icons.phone_rounded, type: TextInputType.phone),
        const SizedBox(height: 12),
        _DropdownField(
          label: "Relationship to Child *",
          icon: Icons.family_restroom_rounded,
          value: selectedRelationship,
          items: const ["Father", "Mother", "Guardian", "Grandparent", "Uncle", "Aunt", "Sibling", "Other"],
          onChanged: (v) => setState(() => selectedRelationship = v),
        ),
        const SizedBox(height: 12),
        _StyledField(controller: emergency2NameCtrl, label: "2nd Emergency Contact Name", icon: Icons.person_outline_rounded),
        const SizedBox(height: 12),
        _StyledField(controller: emergency2Ctrl, label: "2nd Contact Phone", icon: Icons.phone_callback_rounded, type: TextInputType.phone),
        const SizedBox(height: 12),
        _DropdownField(
          label: "Blood Group",
          icon: Icons.bloodtype_rounded,
          value: selectedBloodGroup,
          items: const ["A+", "A-", "B+", "B-", "AB+", "AB-", "O+", "O-", "Unknown"],
          onChanged: (v) => setState(() => selectedBloodGroup = v),
        ),
        const SizedBox(height: 12),
        _StyledField(controller: medicalCtrl, label: "Medical Conditions / Allergies", icon: Icons.medical_information_rounded),
      ],
    );
  }

  Widget _buildStep4() {
    return _StepPage(
      icon: Icons.watch_rounded,
      title: "Child & Device Info",
      subtitle: "Who is wearing the SafetyPod?",
      children: [
        _StyledField(controller: childNameCtrl, label: "Child's Name *", icon: Icons.child_care_rounded),
        const SizedBox(height: 12),
        _StyledField(controller: childAgeCtrl, label: "Child's Age", icon: Icons.cake_rounded, type: TextInputType.number),
        const SizedBox(height: 12),
        _DropdownField(
          label: "Child's Gender",
          icon: Icons.wc_rounded,
          value: selectedChildGender,
          items: const ["Male", "Female", "Other", "Prefer not to say"],
          onChanged: (v) => setState(() => selectedChildGender = v),
        ),
        const SizedBox(height: 12),
        _StyledField(controller: schoolCtrl, label: "School / Institution Name", icon: Icons.school_rounded),
        const SizedBox(height: 12),
        _StyledField(controller: deviceNameCtrl, label: "Device BLE Name (e.g. GUARDIANPOD)", icon: Icons.bluetooth_rounded),
        const SizedBox(height: 12),
        _InfoBanner(text: "The device name must match what your hardware broadcasts over Bluetooth. Leave blank to use the default."),
      ],
    );
  }
}

class _StepPage extends StatelessWidget {
  final IconData icon;
  final String title, subtitle;
  final List<Widget> children;
  const _StepPage({required this.icon, required this.title,
    required this.subtitle, required this.children});

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    padding: const EdgeInsets.symmetric(horizontal: 20),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Container(
          width: 44, height: 44,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: const LinearGradient(colors: [AppColors.accent, AppColors.gradientMid]),
          ),
          child: Icon(icon, color: Colors.white, size: 22),
        ),
        const SizedBox(width: 12),
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: GoogleFonts.poppins(
              fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
          Text(subtitle, style: GoogleFonts.poppins(
              fontSize: 12, color: AppColors.textSecondary)),
        ]),
      ]),
      const SizedBox(height: 20),
      Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: AppColors.cardDark.withOpacity(0.85),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white.withOpacity(0.08)),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.3),
              blurRadius: 20, offset: const Offset(0, 8))],
        ),
        child: Column(children: children),
      ),
      const SizedBox(height: 20),
    ]),
  );
}

class _InfoBanner extends StatelessWidget {
  final String text;
  const _InfoBanner({required this.text});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: AppColors.accent.withOpacity(0.08),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: AppColors.accent.withOpacity(0.25)),
    ),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Icon(Icons.info_outline_rounded, color: AppColors.accent, size: 16),
      const SizedBox(width: 8),
      Expanded(child: Text(text, style: GoogleFonts.poppins(
          fontSize: 11, color: AppColors.textSecondary, height: 1.5))),
    ]),
  );
}

// ─────────────────────────────────────────────────────────────
//  MAIN SHELL
// ─────────────────────────────────────────────────────────────

class MainShell extends StatefulWidget {
  const MainShell({super.key});
  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  StreamSubscription<SosEvent>? _sosSub;

  @override
  void initState() {
    super.initState();
    context.read<AppStateService>().startDemoUpdates();

    final ble   = context.read<BleScannerService>();
    final loc   = context.read<LocationService>();
    final notif = context.read<NotificationService>();
    final app   = context.read<AppStateService>();

    _sosSub = ble.sosStream.listen((evt) async {
      if (!mounted) return;
      final uid = FirebaseAuth.instance.currentUser?.uid ?? "demo_user";

      // ── Log SOS immediately — do NOT wait for GPS ──
      app.addSos(SosHistoryEntry(
        deviceId: evt.deviceId,
        source:   evt.source,
        ts:       evt.ts,
        lat:      null,
        lon:      null,
      ));
      app.setEmergency(true);
      app.setIndex(1); // switch to Map tab in background

      // ── Open Emergency Screen immediately ──
      if (!mounted) return;
      Navigator.push(context, _emergencyRoute(evt));

      // ── Start GPS + notification in background (non-blocking) ──
      loc.startSharing(uid).then((_) {
        final pos = loc.lastPos;
        if (pos != null && app.sosHistory.isNotEmpty) {
          // Update the first entry with coordinates once GPS arrives
          final existing = app.sosHistory.first;
          if (existing.deviceId == evt.deviceId && existing.lat == null) {
            app.sosHistory[0] = SosHistoryEntry(
              deviceId: existing.deviceId,
              source:   existing.source,
              ts:       existing.ts,
              lat:      pos.latitude,
              lon:      pos.longitude,
            );
            app.notifyListeners();
          }
        }
      });

      notif.notifySos(
          "SOS from ${evt.deviceId}!\n"
              "Location: acquiring GPS…");
    });

    notif.navStream.listen((_) {
      if (!mounted || app.emergencyActive) return;
      _autoOpenEmergency();
    });
  }

  void _autoOpenEmergency() async {
    final loc = context.read<LocationService>();
    final uid = FirebaseAuth.instance.currentUser?.uid ?? "demo_user";
    await loc.startSharing(uid);
    if (!mounted) return;
    Navigator.push(context, _emergencyRoute(
        SosEvent(deviceId: "AUTO_DEMO", source: SosSource.simulated)));
  }

  MaterialPageRoute _emergencyRoute(SosEvent evt) => MaterialPageRoute(
      builder: (_) => EmergencyScreen(
          onStop: () {
            context.read<LocationService>().stopSharing();
            context.read<AppStateService>().setEmergency(false);
          },
          sosOrigin: evt));

  @override
  void dispose() { _sosSub?.cancel(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppStateService>();
    final screens = [
      const HomeDashboard(),
      const MapScreen(),
      const SosHistoryScreen(),
      const SettingsScreen(),
    ];

    return Scaffold(
      body: screens[app.currentIndex],
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: AppColors.cardDarker,
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.4), blurRadius: 20)],
        ),
        child: BottomNavigationBar(
          currentIndex: app.currentIndex,
          onTap: app.setIndex,
          backgroundColor: Colors.transparent,
          selectedItemColor: AppColors.accent,
          unselectedItemColor: AppColors.textSecondary,
          type: BottomNavigationBarType.fixed,
          elevation: 0,
          selectedLabelStyle: GoogleFonts.poppins(fontWeight: FontWeight.w600, fontSize: 11),
          unselectedLabelStyle: GoogleFonts.poppins(fontSize: 11),
          items: const [
            BottomNavigationBarItem(icon: Icon(Icons.dashboard_rounded), label: "Dashboard"),
            BottomNavigationBarItem(icon: Icon(Icons.map_rounded),       label: "Live Map"),
            BottomNavigationBarItem(icon: Icon(Icons.history_rounded),   label: "SOS Log"),
            BottomNavigationBarItem(icon: Icon(Icons.settings_rounded),  label: "Settings"),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
//  HOME DASHBOARD
// ─────────────────────────────────────────────────────────────

class HomeDashboard extends StatefulWidget {
  const HomeDashboard({super.key});
  @override
  State<HomeDashboard> createState() => _HomeDashboardState();
}

class _HomeDashboardState extends State<HomeDashboard>
    with TickerProviderStateMixin {
  late AnimationController _pulseCtrl;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
        vsync: this, duration: const Duration(seconds: 2))..repeat(reverse: true);
  }

  @override
  void dispose() { _pulseCtrl.dispose(); super.dispose(); }

  Future<void> _manualSOS() async {
    final uid   = FirebaseAuth.instance.currentUser?.uid ?? "demo_user";
    final loc   = context.read<LocationService>();
    final notif = context.read<NotificationService>();
    final app   = context.read<AppStateService>();

    // Log SOS immediately
    app.addSos(SosHistoryEntry(
      deviceId: "MANUAL",
      source: SosSource.manual,
      ts: DateTime.now(),
      lat: null,
      lon: null,
    ));
    app.setEmergency(true);

    // Open Emergency Screen right away
    if (!mounted) return;
    Navigator.push(context, MaterialPageRoute(
        builder: (_) => EmergencyScreen(
            onStop: () {
              loc.stopSharing();
              app.setEmergency(false);
            },
            sosOrigin: SosEvent(deviceId: "MANUAL", source: SosSource.manual))));

    // Start GPS + notification in background
    loc.startSharing(uid).then((_) {
      final pos = loc.lastPos;
      notif.notifySos(
          "Manual SOS!\nLocation: ${pos != null ? '${pos.latitude.toStringAsFixed(5)}, ${pos.longitude.toStringAsFixed(5)}' : 'Acquiring…'}");
    });
  }

  @override
  Widget build(BuildContext context) {
    final ble  = context.watch<BleScannerService>();
    final loc  = context.watch<LocationService>();
    final app  = context.watch<AppStateService>();
    final auth = context.read<AuthService>();

    // ── isConnected now reflects true BLE state ──
    final isConnected = ble.connectedDevice != null;

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft, end: Alignment.bottomRight,
            colors: [AppColors.gradientStart, AppColors.gradientMid, AppColors.gradientEnd],
          ),
        ),
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [

                // ── Header ──
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text("GuardianPod Pro",
                          style: GoogleFonts.poppins(fontSize: 22,
                              fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                      Text("Safety Dashboard",
                          style: GoogleFonts.poppins(fontSize: 12, color: AppColors.textSecondary)),
                    ]),
                    Row(children: [
                      _PodStatusDot(connected: isConnected),
                      const SizedBox(width: 10),
                      GestureDetector(
                        onTap: auth.signOut,
                        child: Container(
                          width: 40, height: 40,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: AppColors.cardDark,
                            border: Border.all(color: AppColors.accent.withOpacity(0.4)),
                          ),
                          child: const Icon(Icons.logout_rounded,
                              size: 18, color: AppColors.textSecondary),
                        ),
                      ),
                    ]),
                  ],
                ),

                const SizedBox(height: 20),

                // ── Status Cards Row ──
                Row(children: [
                  Expanded(child: _MiniStatCard(
                    label: "Battery",
                    value: "${app.podBattery}%",
                    icon: _batteryIcon(app.podBattery),
                    color: app.podBattery > 20 ? AppColors.safe : AppColors.danger,
                  )),
                  const SizedBox(width: 10),
                  Expanded(child: _MiniStatCard(
                    label: "Steps Today",
                    value: "${app.podSteps}",
                    icon: Icons.directions_walk_rounded,
                    color: AppColors.accentLight,
                  )),
                  const SizedBox(width: 10),
                  Expanded(child: _MiniStatCard(
                    label: "GPS",
                    value: loc.sharing ? "Live" : "Off",
                    icon: Icons.location_on_rounded,
                    color: loc.sharing ? AppColors.safe : AppColors.textSecondary,
                  )),
                ]),

                const SizedBox(height: 16),

                // ── Device Connection Card ──
                _GlassCard(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                      Text("SafetyPod Device",
                          style: GoogleFonts.poppins(
                              fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
                      _PillBadge(
                        label: isConnected
                            ? "Connected"
                            : ble.scanning
                            ? "Scanning"
                            : "Offline",
                        color: isConnected
                            ? AppColors.safe
                            : ble.scanning
                            ? AppColors.warning
                            : AppColors.danger,
                      ),
                    ]),
                    const SizedBox(height: 8),
                    Text(
                      ble.connectionStatus,
                      style: GoogleFonts.poppins(fontSize: 13, color: AppColors.textSecondary),
                    ),

                    const SizedBox(height: 12),
                    Row(children: [
                      Expanded(
                        child: _ActionButton(
                          label: ble.scanning ? "Scanning…" : "Scan for Watch",
                          icon: ble.scanning
                              ? Icons.bluetooth_searching_rounded
                              : Icons.bluetooth_rounded,
                          color: AppColors.accent,
                          onTap: () async {
                            if (ble.scanning) {
                              ble.stopScan();
                              return;
                            }
                            // Show scanning indicator immediately
                            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                              content: Row(children: [
                                const SizedBox(width: 16, height: 16,
                                    child: CircularProgressIndicator(
                                        color: Colors.white, strokeWidth: 2)),
                                const SizedBox(width: 12),
                                Text("Looking for GUARDIANPOD…",
                                    style: GoogleFonts.poppins(fontSize: 13)),
                              ]),
                              backgroundColor: AppColors.cardDark,
                              duration: const Duration(seconds: 9),
                            ));

                            // Check bonded devices + scan for new ones
                            final found = await ble.findDevices();

                            ScaffoldMessenger.of(context).hideCurrentSnackBar();

                            if (!mounted) return;

                            if (found.isEmpty) {
                              showDialog(
                                context: context,
                                builder: (_) => AlertDialog(
                                  backgroundColor: AppColors.cardDark,
                                  shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(20)),
                                  title: Row(children: [
                                    const Icon(Icons.bluetooth_disabled_rounded,
                                        color: AppColors.warning, size: 22),
                                    const SizedBox(width: 10),
                                    Text("Device Not Found",
                                        style: GoogleFonts.poppins(
                                            fontSize: 16,
                                            fontWeight: FontWeight.w700,
                                            color: AppColors.textPrimary)),
                                  ]),
                                  content: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          "GUARDIANPOD was not found. "
                                              "Try these steps:",
                                          style: GoogleFonts.poppins(
                                              fontSize: 13,
                                              color: AppColors.textSecondary,
                                              height: 1.5),
                                        ),
                                        const SizedBox(height: 14),
                                        _HowToStep("1",
                                            "Make sure the watch is powered on and within 1 metre of your phone"),
                                        _HowToStep("2",
                                            "Go to phone Settings → Bluetooth → pair 'GUARDIANPOD' there first"),
                                        _HowToStep("3",
                                            "Come back to this app and tap 'Scan for Watch' again — it will appear instantly"),
                                        _HowToStep("4",
                                            "The watch must advertise as 'GUARDIANPOD' — confirm this in your firmware"),
                                      ]),
                                  actions: [
                                    ElevatedButton(
                                      style: ElevatedButton.styleFrom(
                                          backgroundColor: AppColors.accent,
                                          foregroundColor: Colors.white),
                                      onPressed: () => Navigator.pop(context),
                                      child: Text("Got it",
                                          style: GoogleFonts.poppins(
                                              fontWeight: FontWeight.w600)),
                                    ),
                                  ],
                                ),
                              );
                              return;
                            }

                            // ── Native-style Bluetooth device picker ──
                            await showModalBottomSheet(
                              context: context,
                              backgroundColor: Colors.transparent,
                              isScrollControlled: true,
                              builder: (_) => _BluetoothPickerSheet(
                                devices: found,
                                onPick: (dev) async {
                                  Navigator.pop(context);

                                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                                    content: Row(children: [
                                      const SizedBox(width: 16, height: 16,
                                          child: CircularProgressIndicator(
                                              color: Colors.white, strokeWidth: 2)),
                                      const SizedBox(width: 12),
                                      Expanded(child: Text(
                                          "Connecting to ${dev.name}…",
                                          style: GoogleFonts.poppins(fontSize: 13))),
                                    ]),
                                    backgroundColor: AppColors.cardDark,
                                    duration: const Duration(seconds: 25),
                                  ));

                                  try {
                                    await ble.connectTo(dev);
                                    if (!mounted) return;
                                    ScaffoldMessenger.of(context).hideCurrentSnackBar();
                                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                                      content: Text(ble.connectionStatus,
                                          style: GoogleFonts.poppins(fontSize: 13)),
                                      backgroundColor: ble.connectedDevice != null
                                          ? const Color(0xFF00C853)
                                          : AppColors.danger.withOpacity(0.9),
                                      duration: const Duration(seconds: 3),
                                    ));
                                  } catch (e) {
                                    if (!mounted) return;
                                    ScaffoldMessenger.of(context).hideCurrentSnackBar();
                                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                                      content: Text("Connection failed: $e",
                                          style: GoogleFonts.poppins(fontSize: 12)),
                                      backgroundColor: AppColors.danger.withOpacity(0.9),
                                      duration: const Duration(seconds: 4),
                                    ));
                                  }
                                },
                              ),
                            );
                          },
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _ActionButton(
                          label: loc.sharing ? "Stop GPS" : "Start GPS",
                          icon: Icons.gps_fixed_rounded,
                          color: loc.sharing ? AppColors.warning : AppColors.safe,
                          onTap: () {
                            final uid = FirebaseAuth.instance.currentUser?.uid ?? "demo_user";
                            if (loc.sharing) loc.stopSharing();
                            else loc.startSharing(uid);
                          },
                        ),
                      ),
                    ]),
                  ]),
                ),

                const SizedBox(height: 16),

                // ── Live Location Preview ──
                _GlassCard(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                      Text("Live Location",
                          style: GoogleFonts.poppins(fontSize: 15,
                              fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
                      if (loc.sharing)
                        _PulsingDot(controller: _pulseCtrl),
                    ]),
                    const SizedBox(height: 8),
                    if (loc.lastPos != null) ...[
                      Text(
                        "${loc.lastPos!.latitude.toStringAsFixed(5)}, ${loc.lastPos!.longitude.toStringAsFixed(5)}",
                        style: GoogleFonts.robotoMono(
                            fontSize: 13, color: AppColors.accentLight),
                      ),
                      Text("Accuracy: ±${loc.lastPos!.accuracy.toStringAsFixed(1)} m",
                          style: GoogleFonts.poppins(fontSize: 11, color: AppColors.textSecondary)),
                    ] else
                      Text("Location not yet fetched",
                          style: GoogleFonts.poppins(fontSize: 13, color: AppColors.textSecondary)),
                    const SizedBox(height: 10),
                    _ActionButton(
                      label: "Open Full Map",
                      icon: Icons.map_rounded,
                      color: AppColors.accent,
                      onTap: () => context.read<AppStateService>().setIndex(1),
                    ),
                  ]),
                ),

                const SizedBox(height: 16),

                // ── SOS History Preview ──
                _GlassCard(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                      Text("Recent SOS Events",
                          style: GoogleFonts.poppins(fontSize: 15,
                              fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
                      TextButton(
                        onPressed: () => context.read<AppStateService>().setIndex(2),
                        child: Text("View All",
                            style: GoogleFonts.poppins(fontSize: 12, color: AppColors.accent)),
                      ),
                    ]),
                    if (app.sosHistory.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: Row(children: [
                          const Icon(Icons.check_circle_rounded, color: AppColors.safe, size: 20),
                          const SizedBox(width: 8),
                          Text("All clear — No SOS events",
                              style: GoogleFonts.poppins(fontSize: 13, color: AppColors.safe)),
                        ]),
                      )
                    else
                      ...app.sosHistory.take(2).map((e) => _SosHistoryTile(entry: e)),
                  ]),
                ),

                const SizedBox(height: 20),

                // ── GIANT SOS BUTTON ──
                GestureDetector(
                  onTap: _manualSOS,
                  child: AnimatedBuilder(
                    animation: _pulseCtrl,
                    builder: (_, child) => Transform.scale(
                      scale: app.emergencyActive
                          ? 0.95 + (_pulseCtrl.value * 0.05)
                          : 1.0,
                      child: child,
                    ),
                    child: Container(
                      width: double.infinity,
                      height: 90,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(24),
                        gradient: const LinearGradient(
                          colors: [AppColors.danger, AppColors.dangerDark],
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.danger.withOpacity(0.5),
                            blurRadius: 30, spreadRadius: 2, offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                        const Icon(Icons.sos_rounded, color: Colors.white, size: 38),
                        const SizedBox(width: 14),
                        Column(mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text("EMERGENCY SOS",
                                  style: GoogleFonts.poppins(
                                      fontSize: 18, fontWeight: FontWeight.w800,
                                      color: Colors.white, letterSpacing: 1.5)),
                              Text("Tap to alert your guardian",
                                  style: GoogleFonts.poppins(
                                      fontSize: 11, color: Colors.white70)),
                            ]),
                      ]),
                    ),
                  ),
                ),

                const SizedBox(height: 16),

                // ── Demo/Simulate ──
                Row(children: [
                  Expanded(child: _ActionButton(
                    label: "Simulate SOS",
                    icon: Icons.sim_card_alert_rounded,
                    color: AppColors.warning,
                    onTap: () => context.read<BleScannerService>().simulateWearableSos(),
                  )),
                ]),

                const SizedBox(height: 30),
              ],
            ),
          ),
        ),
      ),
    );
  }

  IconData _batteryIcon(int v) {
    if (v > 80) return Icons.battery_full_rounded;
    if (v > 50) return Icons.battery_5_bar_rounded;
    if (v > 20) return Icons.battery_3_bar_rounded;
    return Icons.battery_alert_rounded;
  }
}

// ─────────────────────────────────────────────────────────────
//  EMERGENCY SCREEN
//  • Full-screen live map as background
//  • Pulsing "SOS TRIGGERED" banner on top
//  • Marker tracks position in real time
//  • Call buttons + police list overlay at bottom
// ─────────────────────────────────────────────────────────────

class EmergencyScreen extends StatefulWidget {
  final VoidCallback onStop;
  final SosEvent? sosOrigin;
  const EmergencyScreen({super.key, required this.onStop, required this.sosOrigin});
  @override
  State<EmergencyScreen> createState() => _EmergencyScreenState();
}

class _EmergencyScreenState extends State<EmergencyScreen>
    with TickerProviderStateMixin {

  // ── State ──
  Timer?  _countdown;
  int     countdown = 300;  // 5 min auto-stop
  Position? pos;

  List<PoliceStation> stations = [];

  // ── Animations ──
  late AnimationController _alertCtrl;   // red background pulse
  late AnimationController _pinCtrl;     // map pin bounce
  late Animation<double>   _pinAnim;

  // ── Map ──
  final MapController _mapCtrl = MapController();
  bool _mapReady = false;

  // ── Subscriptions ──
  StreamSubscription? _posSub;

  @override
  void initState() {
    super.initState();

    // Background red pulse
    _alertCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 900))
      ..repeat(reverse: true);

    // Pin bounce
    _pinCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 600))
      ..repeat(reverse: true);
    _pinAnim = Tween(begin: 0.0, end: -10.0).animate(
        CurvedAnimation(parent: _pinCtrl, curve: Curves.easeInOut));

    _setupPoliceStations();
    _startLocationStream();
    _startCountdown();
  }

  void _startCountdown() {
    _countdown = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) { t.cancel(); return; }
      setState(() => countdown--);
      if (countdown <= 0) {
        t.cancel();
        widget.onStop();
        Navigator.pop(context);
      }
    });
  }

  void _startLocationStream() {
    _posSub = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.best,
        distanceFilter: 2,   // only emit if moved ≥2m
      ),
    ).listen((p) {
      if (!mounted) return;
      setState(() => pos = p);
      // Move map to follow the user in real time
      if (_mapReady) {
        try {
          _mapCtrl.move(LatLng(p.latitude, p.longitude),
              _mapCtrl.camera.zoom);
        } catch (_) {}
      }
    });
  }

  void _setupPoliceStations() {
    stations = [
      PoliceStation(name: "Police Control Room",  phone: "100",  location: const LatLng(20.5959, 78.9649)),
      PoliceStation(name: "Emergency Services",    phone: "112",  location: const LatLng(20.5916, 78.9649)),
      PoliceStation(name: "Women Safety Helpdesk", phone: "1091", location: const LatLng(20.5938, 78.9606)),
      PoliceStation(name: "Child Helpline",        phone: "1098", location: const LatLng(20.5948, 78.9670)),
    ];
  }

  Future<void> _call(String phone) async {
    final uri = Uri.parse("tel:$phone");
    if (await canLaunchUrl(uri)) launchUrl(uri);
  }

  String _fmt(int s) =>
      "${(s ~/ 60).toString().padLeft(2,'0')}:${(s % 60).toString().padLeft(2,'0')}";

  void _showPinStop() {
    final ctrl = TextEditingController();
    showDialog(context: context, builder: (_) => AlertDialog(
      backgroundColor: AppColors.cardDark,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Text("Stop SOS",
          style: GoogleFonts.poppins(
              color: AppColors.textPrimary, fontWeight: FontWeight.w700)),
      content: TextField(
        controller: ctrl,
        maxLength: 4,
        obscureText: true,
        keyboardType: TextInputType.number,
        style: const TextStyle(color: AppColors.textPrimary),
        decoration: const InputDecoration(
          labelText: "Enter 4-digit PIN",
          labelStyle: TextStyle(color: AppColors.textSecondary),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text("Cancel",
              style: GoogleFonts.poppins(color: AppColors.textSecondary)),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: AppColors.danger),
          onPressed: () {
            if (ctrl.text.length == 4) {
              widget.onStop();
              Navigator.popUntil(context, (r) => r.isFirst);
            }
          },
          child: Text("Stop SOS", style: GoogleFonts.poppins()),
        ),
      ],
    ));
  }

  @override
  void dispose() {
    _countdown?.cancel();
    _posSub?.cancel();
    _alertCtrl.dispose();
    _pinCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = pos;
    final hasPos = p != null;
    final center = hasPos
        ? LatLng(p.latitude, p.longitude)
        : const LatLng(20.5937, 78.9629); // fallback centre

    return Scaffold(
      body: Stack(
        children: [

          // ── LAYER 1: Full-screen live map ──
          FlutterMap(
            mapController: _mapCtrl,
            options: MapOptions(
              initialCenter: center,
              initialZoom: 16.0,
              onMapReady: () => setState(() => _mapReady = true),
            ),
            children: [
              TileLayer(
                urlTemplate: "https://tile.openstreetmap.org/{z}/{x}/{y}.png",
                userAgentPackageName: 'com.guardianpod.app',
                maxZoom: 20,
              ),

              // Police station markers
              MarkerLayer(markers: [
                for (final st in stations)
                  Marker(
                    point: st.location,
                    width: 36, height: 36,
                    child: const Icon(Icons.local_police_rounded,
                        size: 30, color: Colors.blue),
                  ),
              ]),

              // Live position marker (bouncing pin)
              if (hasPos)
                MarkerLayer(markers: [
                  Marker(
                    point: center,
                    width: 80, height: 90,
                    child: AnimatedBuilder(
                      animation: _pinAnim,
                      builder: (_, __) => Transform.translate(
                        offset: Offset(0, _pinAnim.value),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // Glowing red circle
                            AnimatedBuilder(
                              animation: _alertCtrl,
                              builder: (_, child) => Container(
                                width: 44, height: 44,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: AppColors.danger,
                                  boxShadow: [
                                    BoxShadow(
                                      color: AppColors.danger.withOpacity(
                                          0.4 + 0.4 * _alertCtrl.value),
                                      blurRadius: 20 + 10 * _alertCtrl.value,
                                      spreadRadius: 4 + 4 * _alertCtrl.value,
                                    ),
                                  ],
                                ),
                                child: const Icon(Icons.sos_rounded,
                                    color: Colors.white, size: 24),
                              ),
                            ),
                            // Pin stem
                            Container(
                              width: 3, height: 14,
                              decoration: BoxDecoration(
                                color: AppColors.danger,
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                            // Shadow dot
                            Container(
                              width: 10, height: 4,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: Colors.black.withOpacity(0.3),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ]),
            ],
          ),

          // ── LAYER 2: Animated red tint over map (subtle, not blocking) ──
          AnimatedBuilder(
            animation: _alertCtrl,
            builder: (_, __) => IgnorePointer(
              child: Container(
                color: AppColors.danger.withOpacity(
                    0.04 + 0.04 * _alertCtrl.value),
              ),
            ),
          ),

          // ── LAYER 3: Top SOS banner ──
          SafeArea(
            child: Column(
              children: [
                // ── Top bar ──
                AnimatedBuilder(
                  animation: _alertCtrl,
                  builder: (_, child) => Container(
                    margin: const EdgeInsets.fromLTRB(12, 12, 12, 0),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      color: Color.lerp(const Color(0xFFCC0000),
                          const Color(0xFFFF1744), _alertCtrl.value),
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.danger.withOpacity(0.6),
                          blurRadius: 20, spreadRadius: 2,
                        ),
                      ],
                    ),
                    child: child,
                  ),
                  child: Row(children: [
                    // SOS icon
                    const Icon(Icons.sos_rounded,
                        size: 32, color: Colors.white),
                    const SizedBox(width: 10),
                    // Text
                    Expanded(child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text("SOS TRIGGERED",
                              style: GoogleFonts.poppins(
                                  fontSize: 16, fontWeight: FontWeight.w800,
                                  color: Colors.white, letterSpacing: 1.5)),
                          Text(
                            widget.sosOrigin != null
                                ? "From: ${widget.sosOrigin!.deviceId}"
                                : "Manual trigger",
                            style: GoogleFonts.poppins(
                                fontSize: 11, color: Colors.white70),
                          ),
                        ])),
                    // Countdown pill
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.25),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(_fmt(countdown),
                          style: GoogleFonts.robotoMono(
                              fontSize: 14, color: Colors.white,
                              fontWeight: FontWeight.w700)),
                    ),
                    const SizedBox(width: 8),
                    // STOP button
                    GestureDetector(
                      onTap: _showPinStop,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                              color: Colors.white.withOpacity(0.5)),
                        ),
                        child: Text("STOP",
                            style: GoogleFonts.poppins(
                                fontSize: 12, fontWeight: FontWeight.w700,
                                color: Colors.white)),
                      ),
                    ),
                  ]),
                ),

                // ── Coordinates pill ──
                if (hasPos)
                  Container(
                    margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.65),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Row(children: [
                      const Icon(Icons.location_on_rounded,
                          color: AppColors.safe, size: 14),
                      const SizedBox(width: 6),
                      Expanded(child: Text(
                        "${p.latitude.toStringAsFixed(6)}, "
                            "${p.longitude.toStringAsFixed(6)}  "
                            "· ±${p.accuracy.toStringAsFixed(0)}m  "
                            "· LIVE",
                        style: GoogleFonts.robotoMono(
                            fontSize: 11, color: Colors.white),
                        overflow: TextOverflow.ellipsis,
                      )),
                      // Pulsing live dot
                      AnimatedBuilder(
                        animation: _alertCtrl,
                        builder: (_, __) => Container(
                          width: 8, height: 8,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: AppColors.safe,
                            boxShadow: [BoxShadow(
                              color: AppColors.safe.withOpacity(
                                  0.4 + 0.5 * _alertCtrl.value),
                              blurRadius: 6 + 4 * _alertCtrl.value,
                              spreadRadius: 1,
                            )],
                          ),
                        ),
                      ),
                    ]),
                  )
                else
                // GPS acquiring...
                  Container(
                    margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.65),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      const SizedBox(width: 14, height: 14,
                          child: CircularProgressIndicator(
                              color: AppColors.warning, strokeWidth: 2)),
                      const SizedBox(width: 8),
                      Text("Acquiring GPS location…",
                          style: GoogleFonts.poppins(
                              fontSize: 12, color: Colors.white70)),
                    ]),
                  ),

                const Spacer(),

                // ── Bottom panel ──
                Container(
                  margin: const EdgeInsets.fromLTRB(12, 0, 12, 16),
                  decoration: BoxDecoration(
                    color: const Color(0xE6120B0B), // dark red, 90% opaque
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(
                        color: AppColors.danger.withOpacity(0.4)),
                    boxShadow: [BoxShadow(
                        color: Colors.black.withOpacity(0.5),
                        blurRadius: 20, offset: const Offset(0, 8))],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [

                      // Call buttons row
                      Padding(
                        padding: const EdgeInsets.fromLTRB(14, 14, 14, 8),
                        child: Row(children: [
                          Expanded(child: _EmergencyCallBtn(
                              label: "Guardian",
                              icon: Icons.call_rounded,
                              color: const Color(0xFF00C853),
                              onTap: () => _call("+911234567890"))),
                          const SizedBox(width: 8),
                          Expanded(child: _EmergencyCallBtn(
                              label: "Police\n100",
                              icon: Icons.local_police_rounded,
                              color: Colors.blue,
                              onTap: () => _call("100"))),
                          const SizedBox(width: 8),
                          Expanded(child: _EmergencyCallBtn(
                              label: "Emerg\n112",
                              icon: Icons.sos_rounded,
                              color: Colors.orange,
                              onTap: () => _call("112"))),
                          const SizedBox(width: 8),
                          Expanded(child: _EmergencyCallBtn(
                              label: "Child\n1098",
                              icon: Icons.child_care_rounded,
                              color: Colors.purple,
                              onTap: () => _call("1098"))),
                        ]),
                      ),

                      Divider(color: Colors.white.withOpacity(0.08),
                          height: 1),

                      // Police stations list
                      Padding(
                        padding:
                        const EdgeInsets.fromLTRB(14, 8, 14, 4),
                        child: Row(children: [
                          const Icon(Icons.local_police_rounded,
                              color: Colors.yellow, size: 14),
                          const SizedBox(width: 6),
                          Text("Emergency Numbers",
                              style: GoogleFonts.poppins(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.white70)),
                        ]),
                      ),
                      ...stations.map((st) => InkWell(
                        onTap: () => _call(st.phone),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 8),
                          child: Row(children: [
                            const Icon(Icons.local_police_rounded,
                                color: Colors.yellow, size: 16),
                            const SizedBox(width: 10),
                            Expanded(child: Text(st.name,
                                style: GoogleFonts.poppins(
                                    fontSize: 12,
                                    color: Colors.white70))),
                            Text(st.phone,
                                style: GoogleFonts.robotoMono(
                                    fontSize: 11,
                                    color: AppColors.accentLight)),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: const Color(0xFF00C853),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text("CALL",
                                  style: GoogleFonts.poppins(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w700,
                                      color: Colors.white)),
                            ),
                          ]),
                        ),
                      )),
                      const SizedBox(height: 8),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
//  MAP SCREEN
// ─────────────────────────────────────────────────────────────

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});
  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  LatLng center = const LatLng(20.5937, 78.9629);
  LatLng? live;
  StreamSubscription? _fsSub;
  bool _following = true;
  final MapController _mapCtrl = MapController();

  @override
  void initState() {
    super.initState();
    final uid = FirebaseAuth.instance.currentUser?.uid ?? "demo_user";
    _fsSub = FirebaseFirestore.instance
        .collection("live_locations").doc(uid).snapshots().listen((snap) {
      final d = snap.data();
      if (d != null && mounted) {
        setState(() {
          live = LatLng((d["lat"] as num).toDouble(), (d["lon"] as num).toDouble());
          if (_following) center = live!;
        });
        if (_following) _mapCtrl.move(live!, 16);
      }
    });
  }

  @override
  void dispose() { _fsSub?.cancel(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final loc = context.watch<LocationService>();
    return Scaffold(
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapCtrl,
            options: MapOptions(
              center: center, zoom: 15,
              onPositionChanged: (_, hasGesture) {
                if (hasGesture && _following) setState(() => _following = false);
              },
            ),
            children: [
              TileLayer(
                urlTemplate: "https://tile.openstreetmap.org/{z}/{x}/{y}.png",
                userAgentPackageName: 'com.guardianpod.app',
                maxZoom: 20,
              ),
              if (loc.breadcrumb.length > 1)
                PolylineLayer(polylines: [
                  Polyline(
                    points: loc.breadcrumb,
                    color: AppColors.accent.withOpacity(0.7),
                    strokeWidth: 3,
                  ),
                ]),
              if (live != null)
                MarkerLayer(markers: [
                  Marker(
                    point: live!, width: 80, height: 80,
                    child: Column(children: [
                      Container(
                        width: 44, height: 44,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: AppColors.accent,
                          boxShadow: [BoxShadow(
                              color: AppColors.accent.withOpacity(0.6),
                              blurRadius: 20, spreadRadius: 4)],
                        ),
                        child: const Icon(Icons.person_rounded, color: Colors.white, size: 26),
                      ),
                      Container(
                        margin: const EdgeInsets.only(top: 4),
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppColors.accent,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text("LIVE", style: GoogleFonts.poppins(
                            fontSize: 9, color: Colors.white, fontWeight: FontWeight.w700)),
                      ),
                    ]),
                  ),
                ]),
            ],
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    decoration: BoxDecoration(
                      color: AppColors.cardDark.withOpacity(0.9),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Row(children: [
                      Container(
                        width: 10, height: 10,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: loc.sharing ? AppColors.safe : AppColors.danger,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        loc.sharing ? "Live GPS Tracking Active" : "GPS Tracking Off",
                        style: GoogleFonts.poppins(
                            fontSize: 13, color: AppColors.textPrimary,
                            fontWeight: FontWeight.w600),
                      ),
                    ]),
                  ),
                  if (live != null) ...[
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(
                        color: AppColors.cardDark.withOpacity(0.9),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        "${live!.latitude.toStringAsFixed(5)}, ${live!.longitude.toStringAsFixed(5)}",
                        style: GoogleFonts.robotoMono(
                            fontSize: 12, color: AppColors.accentLight),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          Positioned(
            bottom: 30, right: 20,
            child: FloatingActionButton(
              backgroundColor: _following ? AppColors.accent : AppColors.cardDark,
              onPressed: () {
                setState(() => _following = true);
                if (live != null) _mapCtrl.move(live!, 16);
              },
              child: Icon(
                Icons.my_location_rounded,
                color: _following ? Colors.white : AppColors.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
//  SOS HISTORY SCREEN
// ─────────────────────────────────────────────────────────────

class SosHistoryScreen extends StatelessWidget {
  const SosHistoryScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppStateService>();
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft, end: Alignment.bottomRight,
            colors: [AppColors.gradientStart, AppColors.gradientMid, AppColors.gradientEnd],
          ),
        ),
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                child: Text("SOS History",
                    style: GoogleFonts.poppins(fontSize: 22,
                        fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Text("${app.sosHistory.length} events recorded",
                    style: GoogleFonts.poppins(fontSize: 13, color: AppColors.textSecondary)),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: app.sosHistory.isEmpty
                    ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.check_circle_outline_rounded, size: 64, color: AppColors.safe),
                  const SizedBox(height: 12),
                  Text("No SOS events yet",
                      style: GoogleFonts.poppins(fontSize: 16, color: AppColors.textSecondary)),
                  Text("Stay safe!",
                      style: GoogleFonts.poppins(fontSize: 13, color: AppColors.textSecondary)),
                ]))
                    : ListView.separated(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: app.sosHistory.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (_, i) => _SosHistoryTile(entry: app.sosHistory[i]),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
//  SETTINGS SCREEN — unchanged from original
// ─────────────────────────────────────────────────────────────

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _notifSos = true;
  bool _notifBattery = true;
  bool _notifGeofence = true;
  int _updateInterval = 5;
  String _sosPin = "1234";
  List<Map<String, String>> _contacts = [
    {"name": "Parent / Guardian", "phone": "+911234567890"},
  ];

  void _showGeofenceDialog(AppStateService app) {
    double radius = app.geofenceRadius;
    showDialog(context: context, builder: (_) => StatefulBuilder(
      builder: (ctx, setS) => AlertDialog(
        backgroundColor: AppColors.cardDark,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(children: [
          const Icon(Icons.fence_rounded, color: AppColors.accent, size: 22),
          const SizedBox(width: 10),
          Text("Geofence Settings", style: GoogleFonts.poppins(
              fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
        ]),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(
            "Geofence creates an invisible boundary around your child's safe zone. "
                "If the SafetyPod moves outside this radius, you'll receive an instant alert.",
            style: GoogleFonts.poppins(fontSize: 12, color: AppColors.textSecondary, height: 1.6),
          ),
          const SizedBox(height: 18),
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Text("Safe Radius", style: GoogleFonts.poppins(
                fontSize: 13, color: AppColors.textPrimary, fontWeight: FontWeight.w600)),
            Text("${radius.round()} m", style: GoogleFonts.poppins(
                fontSize: 13, color: AppColors.accent, fontWeight: FontWeight.w700)),
          ]),
          Slider(
            value: radius, min: 50, max: 2000, divisions: 39,
            activeColor: AppColors.accent, inactiveColor: AppColors.cardDarker,
            onChanged: (v) => setS(() => radius = v),
          ),
        ]),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text("Cancel", style: GoogleFonts.poppins(color: AppColors.textSecondary)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.accent, foregroundColor: Colors.white),
            onPressed: () {
              app.geofenceRadius = radius;
              app.notifyListeners();
              Navigator.pop(context);
              _toast("Geofence radius saved: ${radius.round()} m");
            },
            child: Text("Save", style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    ));
  }

  void _showPinDialog() {
    final ctrl = TextEditingController(text: _sosPin);
    showDialog(context: context, builder: (_) => AlertDialog(
      backgroundColor: AppColors.cardDark,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Row(children: [
        const Icon(Icons.lock_rounded, color: AppColors.accent, size: 22),
        const SizedBox(width: 10),
        Text("SOS Stop PIN", style: GoogleFonts.poppins(
            fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
      ]),
      content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(
          "This 4-digit PIN is required to stop an active SOS emergency.",
          style: GoogleFonts.poppins(fontSize: 12, color: AppColors.textSecondary, height: 1.5),
        ),
        const SizedBox(height: 16),
        _StyledField(controller: ctrl, label: "4-digit PIN",
            icon: Icons.pin_rounded, obscure: true, type: TextInputType.number),
      ]),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text("Cancel", style: GoogleFonts.poppins(color: AppColors.textSecondary)),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: AppColors.accent, foregroundColor: Colors.white),
          onPressed: () {
            if (ctrl.text.length == 4) {
              setState(() => _sosPin = ctrl.text);
              Navigator.pop(context);
              _toast("PIN updated successfully");
            } else {
              _toast("PIN must be exactly 4 digits");
            }
          },
          child: Text("Save PIN", style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
        ),
      ],
    ));
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: GoogleFonts.poppins(fontSize: 13)),
      backgroundColor: AppColors.cardDark,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      duration: const Duration(seconds: 2),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final app  = context.watch<AppStateService>();
    final auth = context.read<AuthService>();

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft, end: Alignment.bottomRight,
            colors: [AppColors.gradientStart, AppColors.gradientMid, AppColors.gradientEnd],
          ),
        ),
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text("Settings",
                  style: GoogleFonts.poppins(fontSize: 22,
                      fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
              Text("Tap any option to configure",
                  style: GoogleFonts.poppins(fontSize: 12, color: AppColors.textSecondary)),
              const SizedBox(height: 20),

              _SectionHeader(label: "Safety & Alerts"),
              const SizedBox(height: 8),
              _GlassCard(child: Column(children: [
                _TappableSettingsTile(
                  icon: Icons.fence_rounded, iconColor: AppColors.safe,
                  label: "Geofence Alerts",
                  subtitle: app.geofenceEnabled
                      ? "Active · ${app.geofenceRadius.round()} m radius"
                      : "Disabled — tap to configure",
                  trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                    Switch(
                      value: app.geofenceEnabled,
                      onChanged: (v) { app.geofenceEnabled = v; app.notifyListeners(); },
                      activeColor: AppColors.accent,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    const Icon(Icons.chevron_right_rounded, color: AppColors.textSecondary, size: 18),
                  ]),
                  onTap: () => _showGeofenceDialog(app),
                ),
                _Divider(),
                _TappableSettingsTile(
                  icon: Icons.lock_rounded, iconColor: AppColors.danger,
                  label: "SOS Stop PIN",
                  subtitle: "PIN to cancel emergency mode · ${_sosPin.replaceAll(RegExp(r'.'), '●')}",
                  trailing: const Icon(Icons.chevron_right_rounded, color: AppColors.textSecondary),
                  onTap: _showPinDialog,
                ),
              ])),

              const SizedBox(height: 16),

              _GlassCard(child: Row(children: [
                Container(
                  width: 48, height: 48,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: const LinearGradient(colors: [AppColors.accent, AppColors.gradientMid]),
                  ),
                  child: const Icon(Icons.shield_rounded, color: Colors.white, size: 26),
                ),
                const SizedBox(width: 14),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text("GuardianPod Pro",
                      style: GoogleFonts.poppins(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                  Text("v2.0 · Competition Edition · Firebase + BLE + GPS",
                      style: GoogleFonts.poppins(fontSize: 10, color: AppColors.textSecondary)),
                ])),
              ])),

              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity, height: 50,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.cardDark,
                    foregroundColor: AppColors.danger,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    side: const BorderSide(color: AppColors.danger, width: 1),
                  ),
                  icon: const Icon(Icons.logout_rounded),
                  label: Text("Sign Out", style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
                  onPressed: auth.signOut,
                ),
              ),
              const SizedBox(height: 30),
            ]),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
//  SETTINGS HELPER WIDGETS
// ─────────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  final String label;
  const _SectionHeader({required this.label});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(left: 4),
    child: Text(label.toUpperCase(),
        style: GoogleFonts.poppins(fontSize: 11, fontWeight: FontWeight.w700,
            color: AppColors.accent, letterSpacing: 1.2)),
  );
}

class _Divider extends StatelessWidget {
  @override
  Widget build(BuildContext context) =>
      Divider(color: Colors.white.withOpacity(0.06), height: 1, thickness: 1);
}

class _TappableSettingsTile extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String label, subtitle;
  final Widget trailing;
  final VoidCallback onTap;
  const _TappableSettingsTile({
    required this.icon, required this.iconColor,
    required this.label, required this.subtitle,
    required this.trailing, required this.onTap,
  });
  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(16),
    splashColor: AppColors.accent.withOpacity(0.1),
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(children: [
        Container(
          width: 40, height: 40,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            color: iconColor.withOpacity(0.12),
          ),
          child: Icon(icon, color: iconColor, size: 20),
        ),
        const SizedBox(width: 14),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: GoogleFonts.poppins(
              fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
          Text(subtitle, style: GoogleFonts.poppins(
              fontSize: 11, color: AppColors.textSecondary)),
        ])),
        trailing,
      ]),
    ),
  );
}

// ─────────────────────────────────────────────────────────────
//  DATA MODELS
// ─────────────────────────────────────────────────────────────

class PoliceStation {
  final String name;
  final String phone;
  final LatLng location;
  const PoliceStation({required this.name, required this.phone, required this.location});
}

// ─────────────────────────────────────────────────────────────
//  HELPER — numbered step row used in "device not found" dialog
// ─────────────────────────────────────────────────────────────

class _HowToStep extends StatelessWidget {
  final String number, text;
  const _HowToStep(this.number, this.text);
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Container(
        width: 22, height: 22,
        decoration: BoxDecoration(
            shape: BoxShape.circle, color: AppColors.accent),
        child: Center(child: Text(number,
            style: GoogleFonts.poppins(
                fontSize: 11, fontWeight: FontWeight.w700,
                color: Colors.white))),
      ),
      const SizedBox(width: 10),
      Expanded(child: Text(text,
          style: GoogleFonts.poppins(
              fontSize: 12, color: AppColors.textPrimary, height: 1.4))),
    ]),
  );
}

// ─────────────────────────────────────────────────────────────
//  BLUETOOTH DEVICE PICKER SHEET
//  Looks and feels exactly like the native Bluetooth pairing UI
//  that Android shows when you connect AirPods / earbuds / etc.
// ─────────────────────────────────────────────────────────────

class _BluetoothPickerSheet extends StatelessWidget {
  final List<BleDevice> devices;
  final void Function(BleDevice) onPick;
  const _BluetoothPickerSheet({required this.devices, required this.onPick});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF1C1934),
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle bar
          Container(
            margin: const EdgeInsets.only(top: 12),
            width: 40, height: 4,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.2),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 20),

          // Header row — matches Android BT picker style
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Row(children: [
              Container(
                width: 42, height: 42,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.accent.withOpacity(0.15),
                  border: Border.all(color: AppColors.accent.withOpacity(0.4)),
                ),
                child: const Icon(Icons.bluetooth_rounded,
                    color: AppColors.accent, size: 22),
              ),
              const SizedBox(width: 14),
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text("Available devices",
                    style: GoogleFonts.poppins(
                        fontSize: 17, fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary)),
                Text("${devices.length} GUARDIANPOD device(s) found",
                    style: GoogleFonts.poppins(
                        fontSize: 12, color: AppColors.textSecondary)),
              ]),
            ]),
          ),

          const SizedBox(height: 16),
          Divider(color: Colors.white.withOpacity(0.07), thickness: 1),

          // Device list
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: devices.length,
            separatorBuilder: (_, __) =>
                Divider(color: Colors.white.withOpacity(0.05), height: 1),
            itemBuilder: (_, i) {
              final dev = devices[i];
              return InkWell(
                onTap: () => onPick(dev),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 24, vertical: 16),
                  child: Row(children: [
                    // Watch icon with accent glow
                    Container(
                      width: 48, height: 48,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: AppColors.cardDarker,
                        border: Border.all(
                            color: AppColors.accent.withOpacity(0.3)),
                        boxShadow: [BoxShadow(
                            color: AppColors.accent.withOpacity(0.15),
                            blurRadius: 10, spreadRadius: 1)],
                      ),
                      child: const Icon(Icons.watch_rounded,
                          color: AppColors.accentLight, size: 24),
                    ),
                    const SizedBox(width: 16),
                    Expanded(child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(dev.name,
                              style: GoogleFonts.poppins(
                                  fontSize: 14, fontWeight: FontWeight.w600,
                                  color: AppColors.textPrimary)),
                          Text("Tap to connect via GATT",
                              style: GoogleFonts.poppins(
                                  fontSize: 12, color: AppColors.textSecondary)),
                        ])),
                    // Chevron — just like native Android
                    const Icon(Icons.chevron_right_rounded,
                        color: AppColors.textSecondary, size: 22),
                  ]),
                ),
              );
            },
          ),

          // Cancel button
          Padding(
            padding: EdgeInsets.fromLTRB(
                24, 8, 24, MediaQuery.of(context).padding.bottom + 20),
            child: SizedBox(
              width: double.infinity, height: 50,
              child: OutlinedButton(
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.textSecondary,
                  side: BorderSide(
                      color: Colors.white.withOpacity(0.15), width: 1),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                ),
                onPressed: () => Navigator.pop(context),
                child: Text("Cancel",
                    style: GoogleFonts.poppins(
                        fontSize: 15, fontWeight: FontWeight.w600,
                        color: AppColors.textSecondary)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
//  REUSABLE WIDGETS — all unchanged from original
// ─────────────────────────────────────────────────────────────

class _InstructionStep extends StatelessWidget {
  final String n, text;
  const _InstructionStep({required this.n, required this.text});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Container(width: 22, height: 22,
          decoration: BoxDecoration(shape: BoxShape.circle, color: AppColors.accent),
          child: Center(child: Text(n, style: GoogleFonts.poppins(
              fontSize: 11, fontWeight: FontWeight.w700, color: Colors.white)))),
      const SizedBox(width: 10),
      Expanded(child: Text(text, style: GoogleFonts.poppins(
          fontSize: 12, color: AppColors.textPrimary, height: 1.4))),
    ]),
  );
}

class _GlassCard extends StatelessWidget {
  final Widget child;
  const _GlassCard({required this.child});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      color: AppColors.cardDark.withOpacity(0.85),
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: Colors.white.withOpacity(0.08)),
      boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.3),
          blurRadius: 20, offset: const Offset(0, 8))],
    ),
    child: child,
  );
}

class _StyledField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final IconData icon;
  final bool obscure;
  final TextInputType? type;
  final IconData? suffixIcon;
  const _StyledField({
    required this.controller, required this.label, required this.icon,
    this.obscure = false, this.type, this.suffixIcon,
  });
  @override
  Widget build(BuildContext context) => TextField(
    controller: controller,
    obscureText: obscure,
    keyboardType: type,
    style: GoogleFonts.poppins(color: AppColors.textPrimary, fontSize: 14),
    decoration: InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(color: AppColors.textSecondary),
      prefixIcon: Icon(icon, color: AppColors.accent, size: 20),
      suffixIcon: suffixIcon != null
          ? Icon(suffixIcon, color: AppColors.textSecondary, size: 20)
          : null,
      filled: true,
      fillColor: AppColors.cardDarker,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.accent, width: 1.5)),
    ),
  );
}

class _DropdownField extends StatelessWidget {
  final String label;
  final IconData icon;
  final String? value;
  final List<String> items;
  final ValueChanged<String?> onChanged;
  const _DropdownField({
    required this.label, required this.icon, required this.value,
    required this.items, required this.onChanged,
  });
  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      color: AppColors.cardDarker,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(
        color: value != null ? AppColors.accent.withOpacity(0.5) : Colors.transparent,
        width: 1.5,
      ),
    ),
    child: DropdownButtonFormField<String>(
      value: value,
      isExpanded: true,
      dropdownColor: AppColors.cardDark,
      style: GoogleFonts.poppins(color: AppColors.textPrimary, fontSize: 14),
      iconEnabledColor: AppColors.textSecondary,
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: AppColors.textSecondary),
        prefixIcon: Icon(icon, color: AppColors.accent, size: 20),
        filled: true, fillColor: Colors.transparent,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide.none),
        contentPadding: const EdgeInsets.symmetric(vertical: 14),
      ),
      items: items.map((item) => DropdownMenuItem(
        value: item,
        child: Text(item, style: GoogleFonts.poppins(
            color: AppColors.textPrimary, fontSize: 14)),
      )).toList(),
      onChanged: onChanged,
    ),
  );
}

class _MiniStatCard extends StatelessWidget {
  final String label, value;
  final IconData icon;
  final Color color;
  const _MiniStatCard({required this.label, required this.value,
    required this.icon, required this.color});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
    decoration: BoxDecoration(
      color: AppColors.cardDark,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: color.withOpacity(0.3)),
    ),
    child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      Icon(icon, color: color, size: 22),
      const SizedBox(height: 6),
      Text(value, style: GoogleFonts.poppins(
          fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
      Text(label, style: GoogleFonts.poppins(
          fontSize: 10, color: AppColors.textSecondary)),
    ]),
  );
}

class _ActionButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  const _ActionButton({required this.label, required this.icon,
    required this.color, required this.onTap});
  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      height: 46,
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withOpacity(0.4)),
      ),
      child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(icon, color: color, size: 18),
        const SizedBox(width: 8),
        Text(label, style: GoogleFonts.poppins(
            fontSize: 13, fontWeight: FontWeight.w600, color: color)),
      ]),
    ),
  );
}

class _PillBadge extends StatelessWidget {
  final String label;
  final Color color;
  const _PillBadge({required this.label, required this.color});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: BoxDecoration(
      color: color.withOpacity(0.15),
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: color.withOpacity(0.5)),
    ),
    child: Text(label, style: GoogleFonts.poppins(
        fontSize: 11, fontWeight: FontWeight.w600, color: color)),
  );
}

// ── _PodStatusDot now reads real BLE state ──
class _PodStatusDot extends StatelessWidget {
  final bool connected;
  const _PodStatusDot({required this.connected});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
    decoration: BoxDecoration(
      color: (connected ? AppColors.safe : AppColors.danger).withOpacity(0.12),
      borderRadius: BorderRadius.circular(20),
      border: Border.all(
          color: (connected ? AppColors.safe : AppColors.danger).withOpacity(0.4)),
    ),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      Container(
        width: 7, height: 7,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: connected ? AppColors.safe : AppColors.danger,
        ),
      ),
      const SizedBox(width: 5),
      Text(connected ? "Pod Online" : "Pod Offline",
          style: GoogleFonts.poppins(
              fontSize: 11,
              color: connected ? AppColors.safe : AppColors.danger,
              fontWeight: FontWeight.w600)),
    ]),
  );
}

class _PulsingDot extends StatelessWidget {
  final AnimationController controller;
  const _PulsingDot({required this.controller});
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller,
    builder: (_, __) => Container(
      width: 8, height: 8,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: AppColors.safe,
        boxShadow: [BoxShadow(
            color: AppColors.safe.withOpacity(0.4 + 0.4 * controller.value),
            blurRadius: 8 + 4 * controller.value,
            spreadRadius: 2)],
      ),
    ),
  );
}

class _SosHistoryTile extends StatelessWidget {
  final SosHistoryEntry entry;
  const _SosHistoryTile({required this.entry});

  Color get _sourceColor {
    switch (entry.source) {
      case SosSource.ble: return AppColors.danger;
      case SosSource.manual: return AppColors.warning;
      case SosSource.simulated: return AppColors.accentLight;
      case SosSource.geofence: return Colors.orange;
    }
  }

  String get _sourceLabel {
    switch (entry.source) {
      case SosSource.ble: return "Hardware SOS";
      case SosSource.manual: return "Manual SOS";
      case SosSource.simulated: return "Simulated";
      case SosSource.geofence: return "Geofence";
    }
  }

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: AppColors.cardDark,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: _sourceColor.withOpacity(0.3)),
    ),
    child: Row(children: [
      Container(
        width: 44, height: 44,
        decoration: BoxDecoration(shape: BoxShape.circle,
            color: _sourceColor.withOpacity(0.15)),
        child: Icon(Icons.sos_rounded, color: _sourceColor, size: 22),
      ),
      const SizedBox(width: 12),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(entry.deviceId, style: GoogleFonts.poppins(
            fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
        Text(
          entry.lat != null
              ? "${entry.lat!.toStringAsFixed(4)}, ${entry.lon!.toStringAsFixed(4)}"
              : "Location unavailable",
          style: GoogleFonts.robotoMono(fontSize: 11, color: AppColors.textSecondary),
        ),
      ])),
      Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
        _PillBadge(label: _sourceLabel, color: _sourceColor),
        const SizedBox(height: 4),
        Text(entry.timeAgo, style: GoogleFonts.poppins(
            fontSize: 11, color: AppColors.textSecondary)),
      ]),
    ]),
  );
}

class _EmergencyCallBtn extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  const _EmergencyCallBtn({required this.label, required this.icon,
    required this.color, required this.onTap});
  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      height: 58,
      decoration: BoxDecoration(
        color: color.withOpacity(0.18),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withOpacity(0.5)),
      ),
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(icon, color: color, size: 22),
        const SizedBox(height: 3),
        Text(label, style: GoogleFonts.poppins(
            fontSize: 10, color: Colors.white, fontWeight: FontWeight.w600),
            textAlign: TextAlign.center),
      ]),
    ),
  );
}