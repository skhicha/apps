// ─────────────────────────────────────────────────────────────────────────────
// SafariSync v3.0 — Line Follower Track Screen
// Renders the exact hackathon track with live vehicle position from Firebase
// ─────────────────────────────────────────────────────────────────────────────
import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:firebase_database/firebase_database.dart';
import '../models/track_models.dart';
import '../main.dart' show ST, SProvider, UserRole;

// ─────────────────────────────────────────────────────────────────────────────
// LINE FOLLOWER TRACK SCREEN
// ─────────────────────────────────────────────────────────────────────────────
class LFTrackViewScreen extends StatefulWidget {
  const LFTrackViewScreen({super.key});
  @override State<LFTrackViewScreen> createState() => _LFTrackState();
}

class _LFTrackState extends State<LFTrackViewScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _tickCtrl;
  TrackVehicleState _vehicleState = TrackVehicleState.initial();
  List<RfidEvent> _rfidEvents = [];
  List<DetectedObject> _detections = [];
  int _lapCount = 0;
  int _elapsedMs = 0;
  int _lastLapMs = 0;
  int _bestLapMs = 0;
  String _mode = 'stopped';
  bool _firebaseConnected = false;

  // Simulated vehicle state for demo mode
  int _simPathIndex = 0;
  double _simProgress = 0.0;
  final _rng = Random();

  @override
  void initState() {
    super.initState();
    _tickCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 16), // ~60fps
    )..repeat();
    _tickCtrl.addListener(_onTick);
    _subscribeFirebase();
    _startTimer();
  }

  Timer? _timer;
  void _startTimer() {
    _timer = Timer.periodic(const Duration(milliseconds: 100), (_) {
      if (_mode != 'stopped' && mounted) {
        setState(() => _elapsedMs += 100);
      }
    });
  }

  void _subscribeFirebase() {
    try {
      final ref = FirebaseDatabase.instance.ref('vehicle/track_car_1');
      ref.onValue.listen((event) {
        final raw = event.snapshot.value;
        if (raw == null || !mounted) return;
        final d = Map<dynamic, dynamic>.from(raw as Map);
        final state = TrackVehicleState.fromMap(d);

        // RFID events
        final rfidData = d['rfid'] as Map?;
        if (rfidData != null) {
          final newLap = (rfidData['lap_count'] as num?)?.toInt() ?? 0;
          if (newLap > _lapCount) {
            final event = RfidEvent.fromMap(rfidData, newLap);
            setState(() {
              _lapCount = newLap;
              _lastLapMs = event.lapTimeMs ?? 0;
              if (_bestLapMs == 0 || _lastLapMs < _bestLapMs) {
                _bestLapMs = _lastLapMs;
              }
              _rfidEvents.insert(0, event);
              if (_rfidEvents.length > 20) _rfidEvents.removeLast();
            });
          }
        }

        // Detections
        final detList = d['detections'];
        if (detList != null && detList is List && detList.isNotEmpty) {
          final det = DetectedObject.fromMap(Map<dynamic, dynamic>.from(detList.last as Map));
          if (mounted) {
            setState(() {
              if (_detections.isEmpty || _detections.first.label != det.label) {
                _detections.insert(0, det);
                if (_detections.length > 10) _detections.removeLast();
              }
            });
          }
        }

        if (mounted) {
          setState(() {
            _vehicleState = state;
            _elapsedMs = state.elapsedMs > 0 ? state.elapsedMs : _elapsedMs;
            _mode = state.mode;
            _firebaseConnected = true;
          });
        }
      }, onError: (_) => setState(() => _firebaseConnected = false));
    } catch (_) {}
  }

  void _onTick() {
    if (_firebaseConnected || !mounted) return;
    // Simulation mode: animate vehicle along path
    setState(() {
      if (_mode == 'stopped') return;

      // Check if next step would reach or pass the END index BEFORE advancing
      if (_simPathIndex == LineFollowerTrack.dashedStart - 1 &&
          _simProgress + 0.005 >= 1.0) {
        // Snap car exactly to P93 (END) and halt
        _simProgress = 1.0;
        _mode = 'stopped';
        // Record journey completion
        _lapCount++;
        final lt = _elapsedMs > 0 ? _elapsedMs : 38000;
        _lastLapMs = lt;
        if (_bestLapMs == 0 || lt < _bestLapMs) _bestLapMs = lt;
        _rfidEvents.insert(0, RfidEvent(
          tagId: 'END',
          checkpointName: 'Finish Line',
          checkpointId: 'CP6',
          timestamp: DateTime.now(),
          lapNumber: _lapCount,
          lapTimeMs: _lastLapMs,
        ));
        if (_rfidEvents.length > 20) _rfidEvents.removeLast();
        // Update vehicle state to exact END position
        final endPos = LineFollowerTrack.interpolate(
            LineFollowerTrack.dashedStart - 1, 1.0);
        _vehicleState = TrackVehicleState(
          x: endPos[0], y: endPos[1],
          pathIndex: LineFollowerTrack.dashedStart - 1,
          pathProgress: 1.0,
          mode: 'stopped',
          speed: 0,
          battery: (90 - _lapCount * 2).clamp(10, 100),
          irLeft: 0, irCenter: 1, irRight: 0,
          deviationMm: 0,
          elapsedMs: _elapsedMs,
        );
        return;
      }

      _simProgress += 0.005;
      if (_simProgress >= 1.0) {
        _simProgress = 0.0;
        _simPathIndex++;
        // Safety net: if we somehow hit dashedStart, stop anyway
        if (_simPathIndex >= LineFollowerTrack.dashedStart) {
          _simPathIndex = LineFollowerTrack.dashedStart - 1;
          _simProgress = 1.0;
          _mode = 'stopped';
        }
      }
      final pos = LineFollowerTrack.interpolate(_simPathIndex, _simProgress);
      _vehicleState = TrackVehicleState(
        x: pos[0], y: pos[1],
        pathIndex: _simPathIndex,
        pathProgress: _simProgress,
        mode: _mode,
        speed: _mode == 'stopped' ? 0 : 65 + (_rng.nextDouble() * 20 - 10),
        battery: (90 - _lapCount * 2).clamp(10, 100),
        irLeft: _rng.nextDouble() < 0.1 ? 1 : 0,
        irCenter: 1,
        irRight: _rng.nextDouble() < 0.1 ? 1 : 0,
        deviationMm: _rng.nextDouble() * 5,
        elapsedMs: _elapsedMs,
      );
    });
  }

  @override
  void dispose() {
    _tickCtrl.removeListener(_onTick);
    _tickCtrl.dispose();
    _timer?.cancel();
    super.dispose();
  }

  String _fmtTime(int ms) {
    final s = ms ~/ 1000;
    final m = s ~/ 60;
    final ss = s % 60;
    final msR = (ms % 1000) ~/ 10;
    return '${m.toString().padLeft(2, '0')}:${ss.toString().padLeft(2, '0')}.${msR.toString().padLeft(2, '0')}';
  }

  String _fmtLap(int? ms) {
    if (ms == null || ms == 0) return '--:--.--';
    return _fmtTime(ms);
  }

  @override
  Widget build(BuildContext context) {
    final p = context.watch<SProvider>();
    final v = _vehicleState;

    return Scaffold(
      backgroundColor: ST.bg,
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Header ──
            Container(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: (_firebaseConnected ? ST.g1 : ST.amber).withOpacity(0.15),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: _firebaseConnected ? ST.g1 : ST.amber,
                        ),
                      ),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Container(
                          width: 6, height: 6,
                          decoration: BoxDecoration(
                            color: _firebaseConnected ? ST.g0 : ST.amber,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          _firebaseConnected ? 'LIVE' : 'SIM',
                          style: GoogleFonts.jetBrainsMono(
                            fontSize: 9, color: _firebaseConnected ? ST.g0 : ST.amber,
                          ),
                        ),
                      ]),
                    ),
                    const Spacer(),
                    Text(
                      v.mode.toUpperCase(),
                      style: GoogleFonts.dmSans(
                        fontSize: 11,
                        color: v.mode == 'autonomous' ? ST.g0
                            : v.mode == 'stopped' ? ST.red
                            : ST.amber,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      width: 8, height: 8,
                      decoration: BoxDecoration(
                        color: v.mode == 'autonomous' ? ST.g0
                            : v.mode == 'stopped' ? ST.red
                            : ST.amber,
                        shape: BoxShape.circle,
                      ),
                    )
                        .animate(onPlay: (c) => c.repeat())
                        .fadeOut(duration: 800.ms)
                        .then()
                        .fadeIn(duration: 800.ms),
                  ]),
                  const SizedBox(height: 6),
                  Text('LIVE TRACK', style: GoogleFonts.dmSans(
                    fontSize: 28, color: ST.g0, fontWeight: FontWeight.w900, letterSpacing: 2,
                  )),
                  Text('Line Follower · ESP32 Autonomous Navigation',
                      style: GoogleFonts.dmSans(fontSize: 11, color: ST.t3)),
                ],
              ),
            ),

            // ── Session Stats Strip ──
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 16),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: ST.cardBox(),
              child: Row(children: [
                _StatPill('ELAPSED', _fmtTime(_elapsedMs), ST.tealL),
                _vDiv(),
                _StatPill('LAP', '${_lapCount}', ST.g0),
                _vDiv(),
                _StatPill('LAST', _fmtLap(_lastLapMs), ST.blueL),
                _vDiv(),
                _StatPill('BEST', _fmtLap(_bestLapMs), ST.amberL),
              ]),
            ),
            const SizedBox(height: 12),

            // ── Track Canvas: aspect ratio matches the 1277×819 image ──
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: AspectRatio(
                aspectRatio: 1277 / 819,  // exact track image ratio
                child: Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFF0D2014),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: ST.gBorder, width: 1.2),
                    boxShadow: [
                      BoxShadow(
                        color: ST.g1.withOpacity(0.06),
                        blurRadius: 20,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(15),
                    child: AnimatedBuilder(
                      animation: _tickCtrl,
                      builder: (_, __) => CustomPaint(
                        painter: _TrackPainter(
                          vehicleState: _vehicleState,
                          detections: _detections,
                          tick: _tickCtrl.value,
                          lapCount: _lapCount,
                        ),
                        child: Container(),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),

            // ── IR Sensor Indicators ──
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(children: [
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: ST.cardBox(),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('IR SENSORS', style: GoogleFonts.dmSans(
                          fontSize: 9, color: ST.t3, fontWeight: FontWeight.w700, letterSpacing: 1,
                        )),
                        const SizedBox(height: 10),
                        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                          _IrLed('L', v.irLeft == 1),
                          const SizedBox(width: 20),
                          _IrLed('C', v.irCenter == 1),
                          const SizedBox(width: 20),
                          _IrLed('R', v.irRight == 1),
                        ]),
                        const SizedBox(height: 8),
                        Center(
                          child: Text(
                            v.onTrack ? 'ON TRACK' : '⚠ OFF TRACK',
                            style: GoogleFonts.jetBrainsMono(
                              fontSize: 9,
                              color: v.onTrack ? ST.g0 : ST.red,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: ST.cardBox(),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('VEHICLE STATUS', style: GoogleFonts.dmSans(
                          fontSize: 9, color: ST.t3, fontWeight: FontWeight.w700, letterSpacing: 1,
                        )),
                        const SizedBox(height: 8),
                        _StatusRow('Speed', '${v.speed.toStringAsFixed(0)}%', ST.g0),
                        const SizedBox(height: 4),
                        _StatusRow('Battery', '${v.battery}%',
                            v.battery > 50 ? ST.g0 : v.battery > 25 ? ST.amber : ST.red),
                        const SizedBox(height: 4),
                        _StatusRow('Deviation', '${v.deviationMm.toStringAsFixed(1)}mm', ST.blueL),
                      ],
                    ),
                  ),
                ),
              ]),
            ),
            const SizedBox(height: 12),

            // ── Admin Control (admin role only) ──
            if (p.isAdmin) _AdminQuickControl(onCommand: _sendCommand),

            // ── RFID Log ──
            if (_rfidEvents.isNotEmpty) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                child: Text('CHECKPOINT LOG', style: GoogleFonts.dmSans(
                  fontSize: 9, color: ST.t3, fontWeight: FontWeight.w700, letterSpacing: 1,
                )),
              ),
              const SizedBox(height: 8),
              ..._rfidEvents.take(5).map((e) => Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 3),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: ST.cardBox(border: ST.gBorderBright),
                  child: Row(children: [
                    Container(
                      width: 28, height: 28,
                      decoration: BoxDecoration(
                        color: ST.g1.withOpacity(0.15),
                        shape: BoxShape.circle,
                      ),
                      child: Center(
                        child: Text('🏁', style: const TextStyle(fontSize: 13)),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(e.checkpointName, style: GoogleFonts.dmSans(
                          fontSize: 12, color: ST.t1, fontWeight: FontWeight.w700,
                        )),
                        Text('Lap ${e.lapNumber} · ${e.formattedLapTime}',
                            style: GoogleFonts.jetBrainsMono(fontSize: 9, color: ST.t3)),
                      ],
                    )),
                    Text(e.formattedLapTime, style: GoogleFonts.jetBrainsMono(
                      fontSize: 13, color: ST.g0,
                    )),
                  ]),
                ).animate().fadeIn(duration: 300.ms).slideX(begin: 0.1),
              )),
              const SizedBox(height: 12),
            ],

            // ── Detected Objects ──
            if (_detections.isNotEmpty) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                child: Text('DETECTED OBJECTS', style: GoogleFonts.dmSans(
                  fontSize: 9, color: ST.t3, fontWeight: FontWeight.w700, letterSpacing: 1,
                )),
              ),
              const SizedBox(height: 8),
              SizedBox(
                height: 80,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  separatorBuilder: (_, __) => const SizedBox(width: 10),
                  itemCount: _detections.length,
                  itemBuilder: (_, i) {
                    final d = _detections[i];
                    return Container(
                      width: 90,
                      padding: const EdgeInsets.all(10),
                      decoration: ST.cardBox(border: ST.g1.withOpacity(0.3)),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(d.emoji, style: const TextStyle(fontSize: 22)),
                          const SizedBox(height: 4),
                          Text(d.label, style: GoogleFonts.dmSans(
                            fontSize: 9, color: ST.t2,
                            fontWeight: FontWeight.w600,
                          ), maxLines: 1, overflow: TextOverflow.ellipsis),
                          Text('${(d.confidence * 100).toStringAsFixed(0)}%',
                              style: GoogleFonts.jetBrainsMono(fontSize: 8, color: ST.g0)),
                        ],
                      ),
                    ).animate().scale(duration: 300.ms, curve: Curves.elasticOut);
                  },
                ),
              ),
            ],
            const SizedBox(height: 80),
          ],
        ),
      ),
    );
  }

  void _sendCommand(String cmd, {int? speed}) {
    // In sim mode, manage local state directly
    if (!_firebaseConnected) {
      setState(() {
        if (cmd == 'START') {
          _simPathIndex = 0;
          _simProgress = 0.0;
          _mode = 'autonomous';
          _elapsedMs = 0;
          _lapCount = 0;
          _lastLapMs = 0;
        } else if (cmd == 'STOP' || cmd == 'EMERGENCY_STOP') {
          _mode = 'stopped';
        }
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          backgroundColor: ST.g1.withOpacity(0.9),
          content: Text('Sim: $cmd', style: GoogleFonts.dmSans(color: ST.bg)),
          duration: const Duration(seconds: 1),
        ));
      }
      return;
    }
    try {
      FirebaseDatabase.instance.ref('vehicle/track_car_1/control').set({
        'command': cmd,
        'auto_mode': cmd == 'START',
        'speed_setpoint': speed ?? 70,
        'direction': 'FORWARD',
        'ts': ServerValue.timestamp,
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          backgroundColor: ST.g1.withOpacity(0.9),
          content: Text('Command sent: $cmd', style: GoogleFonts.dmSans(color: ST.bg)),
          duration: const Duration(seconds: 2),
        ));
      }

    } catch (_) {}
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// TRACK PAINTER — calibrated to the actual hackathon image
// ─────────────────────────────────────────────────────────────────────────────
class _TrackPainter extends CustomPainter {
  final TrackVehicleState vehicleState;
  final List<DetectedObject> detections;
  final double tick;
  final int lapCount;

  _TrackPainter({
    required this.vehicleState,
    required this.detections,
    required this.tick,
    required this.lapCount,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final W = size.width;
    final H = size.height;

    // ── 1. Background: black left ~26%, white right ──
    const splitX = 0.265; // approximate split between black & white halves
    canvas.drawRect(Rect.fromLTWH(0, 0, W * splitX, H),
        Paint()..color = const Color(0xFF1A1A1A));
    canvas.drawRect(Rect.fromLTWH(W * splitX, 0, W * (1 - splitX), H),
        Paint()..color = const Color(0xFFF8F8F8));

    // ── 2. Subtle grid (only on white side) ──
    final gridPaint = Paint()
      ..color = const Color(0xFFDDDDDD)
      ..strokeWidth = 0.4;
    for (double x = W * splitX; x < W; x += W / 18) {
      canvas.drawLine(Offset(x, 0), Offset(x, H), gridPaint);
    }
    for (double y = 0; y < H; y += H / 14) {
      canvas.drawLine(Offset(W * splitX, y), Offset(W, y), gridPaint);
    }

    // ── 3. Track wide surface (beige) ──
    _drawTrackSurface(canvas, W, H);

    // ── 4. Track center line — solid everywhere, DASHED on bridge ──
    _drawCenterLine(canvas, W, H);

    // ── 5. START & END markers on either side of the dashed segment ──
    _drawStartEndMarkers(canvas, W, H);

    // ── 6. Animal markers at rectangular dash positions ──
    _drawAnimalMarkers(canvas, W, H);

    // ── 7. RFID checkpoint markers ──
    _drawCheckpoints(canvas, W, H);

    // ── 8. Direction arrows ──
    _drawArrows(canvas, W, H);

    // ── 9. Vehicle ──
    _drawVehicle(canvas, W, H);

    // ── 10. Overlay (lap / mode) ──
    _drawOverlay(canvas, W, H);
  }

  // ─── Track surface (wide cream road) ────────────────────────────────────────
  void _drawTrackSurface(Canvas canvas, double W, double H) {
    final pts = LineFollowerTrack.path;

    // Cream surface
    final surfacePaint = Paint()
      ..color = const Color(0xFFD8C49A)
      ..style = PaintingStyle.stroke
      ..strokeWidth = W * 0.072
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    // Inner bright highlight
    final highlightPaint = Paint()
      ..color = const Color(0xFFEEDFBF)
      ..style = PaintingStyle.stroke
      ..strokeWidth = W * 0.044
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final p = Path()..moveTo(pts[0][0] * W, pts[0][1] * H);
    for (int i = 1; i < pts.length; i++) {
      p.lineTo(pts[i][0] * W, pts[i][1] * H);
    }
    canvas.drawPath(p, surfacePaint);
    canvas.drawPath(p, highlightPaint);
  }

  // ─── Center line: solid black + dashed segment override ─────────────────────
  void _drawCenterLine(Canvas canvas, double W, double H) {
    final pts = LineFollowerTrack.path;
    final solidPaint = Paint()
      ..color = const Color(0xFF111111)
      ..style = PaintingStyle.stroke
      ..strokeWidth = W * 0.016
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    // Build full solid line first
    final full = Path()..moveTo(pts[0][0] * W, pts[0][1] * H);
    for (int i = 1; i < pts.length; i++) {
      full.lineTo(pts[i][0] * W, pts[i][1] * H);
    }
    canvas.drawPath(full, solidPaint);

    // ── Override the dashed segment with white cover then drawn dashes ──
    final ds = LineFollowerTrack.dashedStart;
    final de = LineFollowerTrack.dashedEnd;

    // White cover to erase solid line on the bridge
    final coverPaint = Paint()
      ..color = const Color(0xFFF2E8D0) // matches track surface color
      ..style = PaintingStyle.stroke
      ..strokeWidth = W * 0.058
      ..strokeCap = StrokeCap.butt;

    final coverPath = Path()..moveTo(pts[ds][0] * W, pts[ds][1] * H);
    for (int i = ds + 1; i <= de; i++) {
      coverPath.lineTo(pts[i][0] * W, pts[i][1] * H);
    }
    canvas.drawPath(coverPath, coverPaint);

    // Now draw dashes on the bridge
    _drawDashedSegment(canvas, pts, ds, de, W, H);
  }

  void _drawDashedSegment(
    Canvas canvas,
    List<List<double>> pts,
    int from,
    int to,
    double W,
    double H,
  ) {
    final dashPaint = Paint()
      ..color = const Color(0xFF111111)
      ..style = PaintingStyle.stroke
      ..strokeWidth = W * 0.013
      ..strokeCap = StrokeCap.butt;

    // Collect all points in the segment
    final segPts = <Offset>[];
    for (int i = from; i <= to; i++) {
      segPts.add(Offset(pts[i][0] * W, pts[i][1] * H));
    }

    // Walk along and draw dashes
    const dashLen = 12.0;
    const gapLen = 8.0;
    double remaining = dashLen;
    bool drawing = true;

    for (int i = 0; i < segPts.length - 1; i++) {
      var a = segPts[i];
      var b = segPts[i + 1];
      double segLen = (b - a).distance;
      double walked = 0;

      while (walked < segLen) {
        final stepLen = remaining.clamp(0, segLen - walked);
        final t0 = walked / segLen;
        final t1 = (walked + stepLen) / segLen;
        final p0 = Offset.lerp(a, b, t0)!;
        final p1 = Offset.lerp(a, b, t1)!;

        if (drawing) {
          canvas.drawLine(p0, p1, dashPaint);
        }

        walked += stepLen;
        remaining -= stepLen;
        if (remaining <= 0) {
          drawing = !drawing;
          remaining = drawing ? dashLen : gapLen;
        }
      }
    }
  }

  // ─── START & END flag markers ────────────────────────────────────────────────
  void _drawStartEndMarkers(Canvas canvas, double W, double H) {
    final pulse = (sin(tick * pi * 3) + 1) / 2;

    // START marker — left side of dashed segment
    _drawFlagMarker(
      canvas,
      Offset(LineFollowerTrack.startX * W, LineFollowerTrack.startY * H),
      'START',
      const Color(0xFF2ECC70),
      pulse,
    );

    // END marker — right side of dashed segment
    _drawFlagMarker(
      canvas,
      Offset(LineFollowerTrack.endX * W, LineFollowerTrack.endY * H),
      'END',
      const Color(0xFFE84040),
      pulse,
    );
  }

  void _drawFlagMarker(
    Canvas canvas,
    Offset center,
    String label,
    Color color,
    double pulse,
  ) {
    // Pulsing outer ring
    canvas.drawCircle(
      center,
      14 + pulse * 5,
      Paint()..color = color.withOpacity(0.15 + pulse * 0.1),
    );

    // Inner solid circle
    canvas.drawCircle(center, 10, Paint()..color = color.withOpacity(0.9));

    // White border ring
    canvas.drawCircle(
      center,
      10,
      Paint()
        ..color = Colors.white.withOpacity(0.7)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );

    // Checkered flag pattern (mini 2×2)
    final sqSize = 4.5;
    for (int r = 0; r < 2; r++) {
      for (int c = 0; c < 2; c++) {
        final isBlack = (r + c) % 2 == 0;
        canvas.drawRect(
          Rect.fromLTWH(
            center.dx - sqSize + c * sqSize,
            center.dy - sqSize + r * sqSize,
            sqSize,
            sqSize,
          ),
          Paint()..color = isBlack ? Colors.black87 : Colors.white,
        );
      }
    }

    // Label
    final tp = TextPainter(
      text: TextSpan(
        text: label,
        style: TextStyle(
          fontFamily: 'monospace',
          fontSize: 8,
          color: color,
          fontWeight: FontWeight.bold,
          letterSpacing: 0.5,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    // Background pill
    final pillRect = RRect.fromRectAndRadius(
      Rect.fromCenter(
        center: Offset(center.dx, center.dy + 17),
        width: tp.width + 8,
        height: tp.height + 4,
      ),
      const Radius.circular(3),
    );
    canvas.drawRRect(pillRect, Paint()..color = color.withOpacity(0.85));
    tp.paint(
      canvas,
      Offset(center.dx - tp.width / 2, center.dy + 17 - tp.height / 2),
    );
  }

  // ─── Animal markers at the rectangular dash positions ────────────────────────
  void _drawAnimalMarkers(Canvas canvas, double W, double H) {
    for (final a in LineFollowerTrack.trackAnimals) {
      final ax = (a['x'] as double) * W;
      final ay = (a['y'] as double) * H;
      final label = a['label'] as String;
      final emoji = a['emoji'] as String;

      final isDetected = detections.any(
        (d) => d.label.toLowerCase().contains(label.toLowerCase()),
      );

      final color = isDetected
          ? const Color(0xFF6EDB75)
          : const Color(0xFF4A9EF5);

      // Animated pulse glow when detected
      if (isDetected) {
        final pulse = (sin(tick * pi * 4) + 1) / 2;
        canvas.drawCircle(
          Offset(ax, ay),
          16 + pulse * 6,
          Paint()..color = color.withOpacity(0.18 + pulse * 0.12),
        );
      }

      // Rectangular marker (like the dashes in the image)
      final rectW = 18.0;
      final rectH = 12.0;
      final rrect = RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset(ax, ay), width: rectW, height: rectH),
        const Radius.circular(2),
      );
      canvas.drawRRect(rrect, Paint()..color = color.withOpacity(0.85));
      canvas.drawRRect(
        rrect,
        Paint()
          ..color = Colors.white.withOpacity(0.5)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1,
      );

      // Emoji above the marker
      final etp = TextPainter(
        text: TextSpan(text: emoji, style: const TextStyle(fontSize: 13)),
        textDirection: TextDirection.ltr,
      )..layout();
      etp.paint(canvas, Offset(ax - etp.width / 2, ay - rectH / 2 - etp.height - 2));

      // Animal name tag below
      final ntp = TextPainter(
        text: TextSpan(
          text: label.length > 5 ? label.substring(0, 5) : label,
          style: TextStyle(
            fontFamily: 'monospace',
            fontSize: 6,
            color: color,
            fontWeight: FontWeight.bold,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      ntp.paint(canvas, Offset(ax - ntp.width / 2, ay + rectH / 2 + 2));
    }
  }

  // ─── RFID checkpoint markers ─────────────────────────────────────────────────
  void _drawCheckpoints(Canvas canvas, double W, double H) {
    // Only draw non-bridge checkpoints (START/END are handled separately)
    for (final cp in LineFollowerTrack.checkpoints) {
      final id = cp['id'] as String;
      if (id == 'CP3' || id == 'CP4') continue; // bridge markers = START/END
      final cx = (cp['x'] as double) * W;
      final cy = (cp['y'] as double) * H;

      final pulse =
          (sin(tick * 2 * pi * 2 + (cp['pathIndex'] as int) * 0.5) + 1) / 2;
      canvas.drawCircle(Offset(cx, cy), 12 + pulse * 5,
          Paint()..color = const Color(0xFFF5A623).withOpacity(0.15));
      canvas.drawCircle(
          Offset(cx, cy), 7, Paint()..color = const Color(0xFFF5A623).withOpacity(0.88));
      canvas.drawCircle(
        Offset(cx, cy),
        7,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5
          ..color = const Color(0xFFF5A623),
      );

      final tp = TextPainter(
        text: TextSpan(
          text: id,
          style: const TextStyle(
            fontFamily: 'monospace',
            fontSize: 6,
            color: Color(0xFFF5A623),
            fontWeight: FontWeight.bold,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(cx - tp.width / 2, cy + 10));
    }
  }

  // ─── Direction arrows ────────────────────────────────────────────────────────
  void _drawArrows(Canvas canvas, double W, double H) {
    const numArrows = 4;
    final pts = LineFollowerTrack.path;
    for (int i = 0; i < numArrows; i++) {
      final phase = (tick * 0.35 + i / numArrows) % 1.0;
      final totalSegs = pts.length - 1;
      final segF = phase * totalSegs;
      final seg = segF.floor().clamp(0, totalSegs - 1);
      // Skip drawing arrows on dashed segment
      if (LineFollowerTrack.isDashed(seg)) continue;
      final t = segF - seg;
      final pos = LineFollowerTrack.interpolate(seg, t);
      final angle = LineFollowerTrack.heading(seg) * pi / 180;

      canvas.save();
      canvas.translate(pos[0] * W, pos[1] * H);
      canvas.rotate(angle);
      canvas.drawPath(
        Path()
          ..moveTo(0, -5)
          ..lineTo(3.5, 3.5)
          ..lineTo(0, 1.5)
          ..lineTo(-3.5, 3.5)
          ..close(),
        Paint()..color = const Color(0xBBF5D042),
      );
      canvas.restore();
    }
  }

  // ─── Vehicle ─────────────────────────────────────────────────────────────────
  void _drawVehicle(Canvas canvas, double W, double H) {
    final vx = vehicleState.x * W;
    final vy = vehicleState.y * H;
    final seg =
        vehicleState.pathIndex.clamp(0, LineFollowerTrack.path.length - 2);
    // smoothHeading interpolates between current & next segment directions
    // so the car rotates gradually at each waypoint — eliminates the abrupt
    // 45° snap at the P74 inflection (left S-turn) that made it look off-path.
    final angle = LineFollowerTrack.smoothHeading(
            seg, vehicleState.pathProgress) *
        pi / 180;

    // Glow
    canvas.drawCircle(
      Offset(vx, vy),
      22,
      Paint()
        ..color = const Color(0xFF6EDB75).withOpacity(0.22)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 14),
    );

    canvas.save();
    canvas.translate(vx, vy);
    canvas.rotate(angle);

    // Body
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset.zero, width: 18, height: 26),
        const Radius.circular(5),
      ),
      Paint()..color = const Color(0xFF2ECC70),
    );

    // Windshield
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: const Offset(0, -6), width: 12, height: 10),
        const Radius.circular(3),
      ),
      Paint()..color = const Color(0xFF9DCEFF).withOpacity(0.85),
    );

    // Headlights
    canvas.drawRect(
      Rect.fromCenter(center: const Offset(0, -13), width: 14, height: 3),
      Paint()..color = const Color(0xFFFFD700),
    );

    canvas.restore();

    // IR sensor dots
    final irColors = [
      vehicleState.irLeft == 1
          ? const Color(0xFF6EDB75)
          : const Color(0xFF333333),
      vehicleState.irCenter == 1
          ? const Color(0xFF6EDB75)
          : const Color(0xFF333333),
      vehicleState.irRight == 1
          ? const Color(0xFF6EDB75)
          : const Color(0xFF333333),
    ];
    for (int i = 0; i < 3; i++) {
      canvas.drawCircle(
        Offset(vx + (i - 1) * 7.0, vy),
        3,
        Paint()..color = irColors[i],
      );
    }
  }

  // ─── Overlay: lap + mode ──────────────────────────────────────────────────────
  void _drawOverlay(Canvas canvas, double W, double H) {
    _drawLabel(canvas, 'LAP $lapCount', const Offset(10, 10),
        const Color(0xFF6EDB75));
    final modeColor = vehicleState.mode == 'autonomous'
        ? const Color(0xFF6EDB75)
        : vehicleState.mode == 'stopped'
            ? const Color(0xFFE84040)
            : const Color(0xFFF5A623);
    _drawLabel(
        canvas, vehicleState.mode.toUpperCase(), Offset(W - 90, 10), modeColor);
  }

  void _drawLabel(Canvas canvas, String text, Offset pos, Color color) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          fontFamily: 'monospace',
          fontSize: 10,
          color: color,
          fontWeight: FontWeight.bold,
          letterSpacing: 1,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(
            pos.dx - 4, pos.dy - 2, tp.width + 8, tp.height + 4),
        const Radius.circular(4),
      ),
      Paint()..color = color.withOpacity(0.13),
    );
    tp.paint(canvas, pos);
  }

  @override
  bool shouldRepaint(_TrackPainter old) => true;
}

// ─────────────────────────────────────────────────────────────────────────────
// ADMIN QUICK CONTROL STRIP
// ─────────────────────────────────────────────────────────────────────────────
class _AdminQuickControl extends StatefulWidget {
  final Function(String cmd, {int? speed}) onCommand;
  const _AdminQuickControl({required this.onCommand});
  @override State<_AdminQuickControl> createState() => _AQCState();
}
class _AQCState extends State<_AdminQuickControl> {
  double _speed = 70;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
    child: Container(
      padding: const EdgeInsets.all(14),
      decoration: ST.glowBox(ST.amber),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('🛡 VEHICLE CONTROL', style: GoogleFonts.dmSans(
            fontSize: 9, color: ST.amber, fontWeight: FontWeight.w700, letterSpacing: 1,
          )),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: _CmdBtn('▶ START', ST.g1, () => widget.onCommand('START', speed: _speed.toInt()))),
            const SizedBox(width: 8),
            Expanded(child: _CmdBtn('■ STOP', ST.amber, () => widget.onCommand('STOP'))),
            const SizedBox(width: 8),
            Expanded(child: _CmdBtn('🆘 E-STOP', ST.red, () => widget.onCommand('EMERGENCY_STOP'))),
          ]),
          const SizedBox(height: 10),
          Row(children: [
            Text('SPEED: ${_speed.toInt()}%', style: GoogleFonts.jetBrainsMono(
              fontSize: 10, color: ST.t2,
            )),
            const SizedBox(width: 10),
            Expanded(child: SliderTheme(
              data: SliderTheme.of(context).copyWith(
                activeTrackColor: ST.g1,
                inactiveTrackColor: ST.gBorder,
                thumbColor: ST.g0,
                overlayColor: ST.g1.withOpacity(0.12),
                trackHeight: 3,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
              ),
              child: Slider(
                value: _speed,
                min: 0, max: 100,
                onChanged: (v) => setState(() => _speed = v),
                onChangeEnd: (v) => widget.onCommand('SET_SPEED', speed: v.toInt()),
              ),
            )),
          ]),
        ],
      ),
    ),
  );
}

class _CmdBtn extends StatelessWidget {
  final String label;
  final Color color;
  final VoidCallback onTap;
  const _CmdBtn(this.label, this.color, this.onTap);
  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color),
      ),
      child: Center(child: Text(label, style: GoogleFonts.dmSans(
        fontSize: 11, color: color, fontWeight: FontWeight.w800,
      ))),
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// HELPER WIDGETS
// ─────────────────────────────────────────────────────────────────────────────
class _StatPill extends StatelessWidget {
  final String label, value;
  final Color color;
  const _StatPill(this.label, this.value, this.color);
  @override
  Widget build(BuildContext context) => Expanded(child: Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(label, style: GoogleFonts.dmSans(fontSize: 8, color: ST.t4, letterSpacing: 1, fontWeight: FontWeight.w600)),
      const SizedBox(height: 2),
      Text(value, style: GoogleFonts.jetBrainsMono(fontSize: 12, color: color, fontWeight: FontWeight.bold)),
    ],
  ));
}

class _vDiv extends StatelessWidget {
  const _vDiv();
  @override Widget build(BuildContext context) => Container(
    width: 1, height: 28, color: ST.gBorder,
    margin: const EdgeInsets.symmetric(horizontal: 4),
  );
}

class _IrLed extends StatelessWidget {
  final String label;
  final bool active;
  const _IrLed(this.label, this.active);
  @override
  Widget build(BuildContext context) => Column(
    children: [
      AnimatedContainer(
        duration: 150.ms,
        width: 24, height: 24,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: active ? ST.g1 : ST.gBorder.withOpacity(0.3),
          boxShadow: active
              ? [BoxShadow(color: ST.g1.withOpacity(0.5), blurRadius: 10)]
              : null,
        ),
      ),
      const SizedBox(height: 4),
      Text(label, style: GoogleFonts.jetBrainsMono(fontSize: 9, color: ST.t3)),
    ],
  );
}

class _StatusRow extends StatelessWidget {
  final String label, value;
  final Color color;
  const _StatusRow(this.label, this.value, this.color);
  @override
  Widget build(BuildContext context) => Row(children: [
    Text(label, style: GoogleFonts.dmSans(fontSize: 10, color: ST.t3)),
    const Spacer(),
    Text(value, style: GoogleFonts.jetBrainsMono(fontSize: 11, color: color)),
  ]);
}
