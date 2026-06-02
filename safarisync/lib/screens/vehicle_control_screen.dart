// ─────────────────────────────────────────────────────────────────────────────
// SafariSync v3.0 — Vehicle Control Screen (Admin Only)
// Full remote control panel for the autonomous line-follower car
// ─────────────────────────────────────────────────────────────────────────────
import 'dart:math';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:firebase_database/firebase_database.dart';
import '../models/track_models.dart';
import '../main.dart' show ST, SProvider;

class VehicleControlScreen extends StatefulWidget {
  const VehicleControlScreen({super.key});
  @override State<VehicleControlScreen> createState() => _VehicleControlState();
}

class _VehicleControlState extends State<VehicleControlScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseCtrl;
  double _speedSetpoint = 70;
  String _mode = 'stopped';       // autonomous | manual | stopped | brake
  String _direction = 'FORWARD';  // FORWARD | REVERSE
  bool _eStop = false;
  TrackVehicleState _vehicleState = TrackVehicleState.initial();
  String _lastCommand = 'NONE';
  DateTime? _lastCommandTs;
  final _cmdLog = <Map<String, dynamic>>[];
  bool _connected = false;

  // Simulated state
  final _rng = Random();
  Timer? _simTimer;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat(reverse: true);
    _subscribeFirebase();
  }

  void _subscribeFirebase() {
    try {
      FirebaseDatabase.instance.ref('vehicle/track_car_1').onValue.listen((event) {
        final raw = event.snapshot.value;
        if (raw == null || !mounted) return;
        final d = Map<dynamic, dynamic>.from(raw as Map);
        if (mounted) setState(() {
          _vehicleState = TrackVehicleState.fromMap(d);
          _mode = _vehicleState.mode;
          _connected = true;
        });
      }, onError: (_) => setState(() => _connected = false));
    } catch (_) {}
  }

  void _sendCommand(String cmd, {int? speed, String? direction}) {
    if (_eStop && cmd != 'RESET_ESTOP') return;
    setState(() {
      _lastCommand = cmd;
      _lastCommandTs = DateTime.now();
      _cmdLog.insert(0, {
        'cmd': cmd,
        'speed': speed ?? _speedSetpoint.toInt(),
        'ts': DateTime.now(),
        'dir': direction ?? _direction,
      });
      if (_cmdLog.length > 20) _cmdLog.removeLast();
      _mode = cmd == 'START' ? 'autonomous'
          : cmd == 'STOP' ? 'stopped'
          : cmd == 'EMERGENCY_STOP' ? 'stopped'
          : cmd == 'MANUAL' ? 'manual'
          : _mode;
    });

    try {
      FirebaseDatabase.instance.ref('vehicle/track_car_1/control').set({
        'command': cmd,
        'auto_mode': cmd == 'START',
        'speed_setpoint': speed ?? _speedSetpoint.toInt(),
        'direction': direction ?? _direction,
        'ts': ServerValue.timestamp,
        'admin': context.read<SProvider>().userName,
      });
    } catch (_) {}

    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      backgroundColor: cmd == 'EMERGENCY_STOP' ? ST.red
          : cmd == 'STOP' ? ST.amber : ST.g1,
      content: Row(children: [
        Text(cmd == 'EMERGENCY_STOP' ? '🆘' : cmd == 'STOP' ? '■' : '▶',
            style: const TextStyle(fontSize: 18)),
        const SizedBox(width: 10),
        Text('Command: $cmd sent', style: GoogleFonts.dmSans(
          color: Colors.white, fontWeight: FontWeight.w700)),
      ]),
      duration: const Duration(seconds: 2),
    ));
  }

  void _triggerEStop() {
    setState(() => _eStop = true);
    _sendCommand('EMERGENCY_STOP');
  }

  void _resetEStop() {
    setState(() => _eStop = false);
    _sendCommand('RESET_ESTOP');
  }

  Color get _modeColor => _mode == 'autonomous' ? ST.g0
      : _mode == 'manual' ? ST.blueL
      : _mode == 'brake' ? ST.amber
      : ST.red;

  String get _modeLabel => _mode == 'autonomous' ? '🤖 AUTONOMOUS'
      : _mode == 'manual' ? '🕹 MANUAL'
      : _mode == 'brake' ? '⚠ BRAKE'
      : '■ STOPPED';

  @override
  void dispose() {
    _pulseCtrl.dispose();
    _simTimer?.cancel();
    super.dispose();
  }

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
            // ── Header ──
            Row(children: [
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('🎮 CONTROL', style: GoogleFonts.dmSans(
                  fontSize: 26, color: ST.amber, fontWeight: FontWeight.w900, letterSpacing: 2,
                )),
                Text('Admin Vehicle Control · Line Follower Car',
                    style: GoogleFonts.dmSans(fontSize: 11, color: ST.t3)),
              ]),
              const Spacer(),
              AnimatedBuilder(
                animation: _pulseCtrl,
                builder: (_, __) => Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: _modeColor.withOpacity(0.1 + _pulseCtrl.value * 0.08),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: _modeColor.withOpacity(0.7)),
                  ),
                  child: Text(_modeLabel, style: GoogleFonts.dmSans(
                    fontSize: 10, color: _modeColor, fontWeight: FontWeight.w800,
                  )),
                ),
              ),
            ]).animate().fadeIn(duration: 400.ms),
            const SizedBox(height: 16),

            // ── E-STOP (always visible at top) ──
            if (!_eStop) GestureDetector(
              onLongPress: _triggerEStop,
              child: AnimatedBuilder(
                animation: _pulseCtrl,
                builder: (_, __) => Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 22),
                  decoration: BoxDecoration(
                    color: ST.red.withOpacity(0.1 + _pulseCtrl.value * 0.08),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: ST.red, width: 2),
                    boxShadow: [BoxShadow(
                      color: ST.red.withOpacity(0.2 + _pulseCtrl.value * 0.2),
                      blurRadius: 20,
                    )],
                  ),
                  child: Column(children: [
                    const Text('🆘', style: TextStyle(fontSize: 36)),
                    const SizedBox(height: 6),
                    Text('EMERGENCY STOP', style: GoogleFonts.dmSans(
                      fontSize: 18, color: ST.red, fontWeight: FontWeight.w900, letterSpacing: 2,
                    )),
                    Text('HOLD TO ACTIVATE', style: GoogleFonts.dmSans(
                      fontSize: 10, color: ST.redL, letterSpacing: 1,
                    )),
                  ]),
                ),
              ),
            )
            else Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 18),
              decoration: BoxDecoration(
                color: ST.red.withOpacity(0.2),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: ST.red, width: 2),
              ),
              child: Column(children: [
                const Text('🛑', style: TextStyle(fontSize: 36)),
                Text('EMERGENCY STOP ACTIVE', style: GoogleFonts.dmSans(
                  fontSize: 16, color: ST.redL, fontWeight: FontWeight.w900,
                )),
                const SizedBox(height: 8),
                GestureDetector(
                  onTap: _resetEStop,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                    decoration: BoxDecoration(
                      color: ST.g1.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: ST.g1),
                    ),
                    child: Text('TAP TO RESET', style: GoogleFonts.dmSans(
                      fontSize: 11, color: ST.g0, fontWeight: FontWeight.w800, letterSpacing: 1,
                    )),
                  ),
                ),
              ]),
            ),
            const SizedBox(height: 16),

            // ── Mode Selector ──
            Text('MODE', style: GoogleFonts.dmSans(
              fontSize: 9, color: ST.t3, fontWeight: FontWeight.w700, letterSpacing: 1,
            )),
            const SizedBox(height: 8),
            Row(children: [
              _ModeBtn('🤖 AUTO', 'autonomous', _mode, () => _sendCommand('START')),
              const SizedBox(width: 8),
              _ModeBtn('🕹 MANUAL', 'manual', _mode, () => _sendCommand('MANUAL')),
              const SizedBox(width: 8),
              _ModeBtn('■ STOP', 'stopped', _mode, () => _sendCommand('STOP')),
            ]),
            const SizedBox(height: 16),

            // ── Speed Control ──
            Container(
              padding: const EdgeInsets.all(16),
              decoration: ST.cardBox(),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Text('SPEED SETPOINT', style: GoogleFonts.dmSans(
                      fontSize: 9, color: ST.t3, fontWeight: FontWeight.w700, letterSpacing: 1,
                    )),
                    const Spacer(),
                    Text('${_speedSetpoint.toInt()}%', style: GoogleFonts.jetBrainsMono(
                      fontSize: 18, color: ST.g0, fontWeight: FontWeight.bold,
                    )),
                  ]),
                  SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      activeTrackColor: ST.g1,
                      inactiveTrackColor: ST.gBorder,
                      thumbColor: ST.g0,
                      overlayColor: ST.g1.withOpacity(0.12),
                      trackHeight: 6,
                      thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 10),
                    ),
                    child: Slider(
                      value: _speedSetpoint,
                      min: 0, max: 100, divisions: 20,
                      onChanged: (v) => setState(() => _speedSetpoint = v),
                      onChangeEnd: (v) => _sendCommand('SET_SPEED', speed: v.toInt()),
                    ),
                  ),
                  Row(mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: ['0%', '25%', '50%', '75%', '100%'].map((l) =>
                        Text(l, style: GoogleFonts.jetBrainsMono(fontSize: 8, color: ST.t4))).toList(),
                  ),
                  const SizedBox(height: 10),
                  // Speed presets
                  Row(children: [
                    for (final sp in [25, 50, 70, 90])
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: GestureDetector(
                          onTap: () {
                            setState(() => _speedSetpoint = sp.toDouble());
                            _sendCommand('SET_SPEED', speed: sp);
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                            decoration: BoxDecoration(
                              color: _speedSetpoint == sp.toDouble()
                                  ? ST.g1.withOpacity(0.2) : Colors.transparent,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: _speedSetpoint == sp.toDouble()
                                  ? ST.g1 : ST.gBorder),
                            ),
                            child: Text('$sp%', style: GoogleFonts.dmSans(
                              fontSize: 11,
                              color: _speedSetpoint == sp.toDouble() ? ST.g0 : ST.t3,
                              fontWeight: FontWeight.w700,
                            )),
                          ),
                        ),
                      ),
                  ]),
                ],
              ),
            ),
            const SizedBox(height: 12),

            // ── Direction (Manual mode) ──
            if (_mode == 'manual') ...[
              Container(
                padding: const EdgeInsets.all(16),
                decoration: ST.glowBox(ST.blueL),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('DIRECTION CONTROL', style: GoogleFonts.dmSans(
                      fontSize: 9, color: ST.blueL, fontWeight: FontWeight.w700, letterSpacing: 1,
                    )),
                    const SizedBox(height: 16),
                    // D-pad style layout
                    Center(child: Column(children: [
                      _DpadBtn('▲ FORWARD', () {
                        setState(() => _direction = 'FORWARD');
                        _sendCommand('MANUAL', direction: 'FORWARD');
                      }),
                      const SizedBox(height: 8),
                      Row(mainAxisSize: MainAxisSize.min, children: [
                        _DpadBtn('◄ LEFT', () {
                          setState(() => _direction = 'LEFT');
                          _sendCommand('MANUAL', direction: 'LEFT');
                        }),
                        const SizedBox(width: 8),
                        Container(
                          width: 50, height: 50,
                          decoration: BoxDecoration(
                            color: ST.gBorder.withOpacity(0.3),
                            shape: BoxShape.circle,
                          ),
                          child: Center(child: Text('🎯', style: const TextStyle(fontSize: 20))),
                        ),
                        const SizedBox(width: 8),
                        _DpadBtn('RIGHT ►', () {
                          setState(() => _direction = 'RIGHT');
                          _sendCommand('MANUAL', direction: 'RIGHT');
                        }),
                      ]),
                      const SizedBox(height: 8),
                      _DpadBtn('▼ REVERSE', () {
                        setState(() => _direction = 'REVERSE');
                        _sendCommand('MANUAL', direction: 'REVERSE');
                      }),
                    ])),
                  ],
                ),
              ),
              const SizedBox(height: 12),
            ],

            // ── Live Vehicle Stats ──
            Container(
              padding: const EdgeInsets.all(14),
              decoration: ST.cardBox(),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('LIVE VEHICLE TELEMETRY', style: GoogleFonts.dmSans(
                    fontSize: 9, color: ST.t3, fontWeight: FontWeight.w700, letterSpacing: 1,
                  )),
                  const SizedBox(height: 10),
                  Row(children: [
                    _TelemetryBox('SPEED', '${_vehicleState.speed.toInt()}%', ST.g0),
                    _TelemetryBox('BATTERY', '${_vehicleState.battery}%',
                        _vehicleState.battery > 50 ? ST.g0
                            : _vehicleState.battery > 25 ? ST.amber : ST.red),
                    _TelemetryBox('IR L', _vehicleState.irLeft == 1 ? '●' : '○',
                        _vehicleState.irLeft == 1 ? ST.g0 : ST.t4),
                    _TelemetryBox('IR C', _vehicleState.irCenter == 1 ? '●' : '○',
                        _vehicleState.irCenter == 1 ? ST.g0 : ST.t4),
                    _TelemetryBox('IR R', _vehicleState.irRight == 1 ? '●' : '○',
                        _vehicleState.irRight == 1 ? ST.g0 : ST.t4),
                  ]),
                  const SizedBox(height: 10),
                  Row(children: [
                    const Icon(Icons.radio, color: ST.t4, size: 14),
                    const SizedBox(width: 6),
                    Text(_connected ? 'Firebase RTDB connected · real-time'
                        : 'Simulation mode — connect hardware',
                        style: GoogleFonts.jetBrainsMono(fontSize: 9,
                            color: _connected ? ST.g0 : ST.amber)),
                  ]),
                ],
              ),
            ),
            const SizedBox(height: 12),

            // ── Command Log ──
            if (_cmdLog.isNotEmpty) ...[
              Text('COMMAND LOG', style: GoogleFonts.dmSans(
                fontSize: 9, color: ST.t3, fontWeight: FontWeight.w700, letterSpacing: 1,
              )),
              const SizedBox(height: 8),
              ...(_cmdLog.take(8)).map((c) {
                final ts = c['ts'] as DateTime;
                final diff = DateTime.now().difference(ts).inSeconds;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: ST.cardBox(),
                    child: Row(children: [
                      Text('→', style: GoogleFonts.jetBrainsMono(fontSize: 12, color: ST.amber)),
                      const SizedBox(width: 8),
                      Text(c['cmd'] as String, style: GoogleFonts.jetBrainsMono(
                        fontSize: 11, color: ST.t1, fontWeight: FontWeight.bold,
                      )),
                      const SizedBox(width: 8),
                      Text('${c['speed']}%', style: GoogleFonts.jetBrainsMono(
                        fontSize: 9, color: ST.g0,
                      )),
                      const Spacer(),
                      Text('${diff}s ago', style: GoogleFonts.jetBrainsMono(
                        fontSize: 9, color: ST.t4,
                      )),
                    ]),
                  ),
                );
              }),
            ],
            const SizedBox(height: 80),
          ],
        ),
      ),
    );
  }
}

// ─── Helper Widgets ───────────────────────────────────────────────────────────
class _ModeBtn extends StatelessWidget {
  final String label, mode, current;
  final VoidCallback onTap;
  const _ModeBtn(this.label, this.mode, this.current, this.onTap);

  Color get _color => mode == 'autonomous' ? ST.g0
      : mode == 'manual' ? ST.blueL
      : ST.amber;

  @override
  Widget build(BuildContext context) => Expanded(
    child: GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: 180.ms,
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: current == mode ? _color.withOpacity(0.18) : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: current == mode ? _color : ST.gBorder),
        ),
        child: Text(label, textAlign: TextAlign.center, style: GoogleFonts.dmSans(
          fontSize: 11, color: current == mode ? _color : ST.t3,
          fontWeight: FontWeight.w800,
        )),
      ),
    ),
  );
}

class _DpadBtn extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _DpadBtn(this.label, this.onTap);
  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: ST.blueL.withOpacity(0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: ST.blueL.withOpacity(0.5)),
      ),
      child: Text(label, style: GoogleFonts.dmSans(
        fontSize: 11, color: ST.blueL, fontWeight: FontWeight.w700,
      )),
    ),
  );
}

class _TelemetryBox extends StatelessWidget {
  final String label, value;
  final Color color;
  const _TelemetryBox(this.label, this.value, this.color);
  @override
  Widget build(BuildContext context) => Expanded(
    child: Column(children: [
      Text(label, style: GoogleFonts.dmSans(fontSize: 8, color: ST.t4, letterSpacing: 0.5)),
      const SizedBox(height: 3),
      Text(value, style: GoogleFonts.jetBrainsMono(fontSize: 13, color: color,
        fontWeight: FontWeight.bold)),
    ]),
  );
}
