// ─────────────────────────────────────────────────────────────────────────────
// SafariSync v3.0 — RFID Events & Session Report Screen
// Lap timing, checkpoint log, and end-of-session summary report
// ─────────────────────────────────────────────────────────────────────────────
import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../models/track_models.dart';
import '../main.dart' show ST, SProvider;

class RfidReportScreen extends StatefulWidget {
  const RfidReportScreen({super.key});
  @override State<RfidReportScreen> createState() => _RfidReportState();
}

class _RfidReportState extends State<RfidReportScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseCtrl;
  final List<RfidEvent> _events = [];
  final List<MapEntry<String, int>> _lapTimes = []; // lap num -> ms
  int _lapCount = 0;
  int _elapsedMs = 0;
  int _finalElapsedMs = 0; // snapshots elapsed time when session stops
  int _bestLapMs = 0;
  bool _sessionActive = false;
  Timer? _elapsedTimer;
  final _rng = Random();

  // Checkpoint hit tracker for simulation
  int _simPathIdx = 0;
  Timer? _simTimer;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);

    // Simulate RFID events for demo
    _startSessionSim();
  }

  void _startSessionSim() {
    _sessionActive = true;
    _finalElapsedMs = 0; // reset snapshot for new session
    _elapsedTimer = Timer.periodic(const Duration(milliseconds: 100), (_) {
      if (mounted && _sessionActive) setState(() => _elapsedMs += 100);
    });

    // Simulate checkpoint passings
    _simTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      if (!mounted || !_sessionActive) return;
      final cps = LineFollowerTrack.checkpoints;
      final cp = cps[_simPathIdx % cps.length];
      _simPathIdx++;

      final isFinish = cp['id'] == 'CP0';
      int? lapTime;
      if (isFinish && _lapCount > 0) {
        lapTime = 38000 + _rng.nextInt(8000);
        _lapTimes.add(MapEntry('Lap $_lapCount', lapTime));
        if (_bestLapMs == 0 || lapTime < _bestLapMs) _bestLapMs = lapTime;
        _lapCount++;
      } else if (isFinish) {
        _lapCount++;
      }

      final event = RfidEvent(
        tagId: 'TAG_${_rng.nextInt(9999).toString().padLeft(4, '0')}',
        checkpointName: cp['name'] as String,
        checkpointId: cp['id'] as String,
        timestamp: DateTime.now(),
        lapNumber: _lapCount,
        lapTimeMs: lapTime,
      );
      if (mounted) setState(() {
        _events.insert(0, event);
        if (_events.length > 30) _events.removeLast();
      });
    });
  }

  void _stopSession() {
    // Snapshot elapsed time BEFORE cancelling timer, so the report shows correct value
    _finalElapsedMs = _elapsedMs;
    setState(() => _sessionActive = false);
    _elapsedTimer?.cancel();
    _simTimer?.cancel();
  }

  void _resetSession() {
    _elapsedTimer?.cancel();
    _simTimer?.cancel();
    setState(() {
      _sessionActive = false;
      _events.clear();
      _lapTimes.clear();
      _lapCount = 0;
      _elapsedMs = 0;
      _finalElapsedMs = 0;
      _bestLapMs = 0;
      _simPathIdx = 0;
    });
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    _elapsedTimer?.cancel();
    _simTimer?.cancel();
    super.dispose();
  }

  String _fmtTime(int ms) {
    final totalS = ms ~/ 1000;
    final m = totalS ~/ 60;
    final s = totalS % 60;
    final msR = (ms % 1000) ~/ 10;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}.${msR.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final p = context.watch<SProvider>();

    return Scaffold(
      backgroundColor: ST.bg,
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Header ──
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Text('🏁 SESSION', style: GoogleFonts.dmSans(
                    fontSize: 26, color: ST.amberL, fontWeight: FontWeight.w900, letterSpacing: 2,
                  )),
                  const Spacer(),
                  if (_sessionActive)
                    AnimatedBuilder(
                      animation: _pulseCtrl,
                      builder: (_, __) => Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: ST.g1.withOpacity(0.1 + _pulseCtrl.value * 0.1),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: ST.g1.withOpacity(0.6 + _pulseCtrl.value * 0.4)),
                        ),
                        child: Text('● RECORDING', style: GoogleFonts.jetBrainsMono(
                          fontSize: 9, color: ST.g0,
                        )),
                      ),
                    ),
                ]),
                Text('RFID Checkpoints · Lap Timing · Session Report',
                    style: GoogleFonts.dmSans(fontSize: 11, color: ST.t3)),
              ]),
            ),

            // ── Giant Timer ──
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 16),
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 28),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    const Color(0xFF1A2E12),
                    ST.amber.withOpacity(0.06),
                  ],
                ),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: ST.amberL.withOpacity(0.3), width: 1.5),
              ),
              child: Column(children: [
                Text('ELAPSED', style: GoogleFonts.dmSans(
                  fontSize: 10, color: ST.t4, letterSpacing: 2, fontWeight: FontWeight.w700,
                )),
                const SizedBox(height: 8),
                Text(
                  _fmtTime(_elapsedMs),
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: 44, color: ST.amberL, fontWeight: FontWeight.bold,
                    letterSpacing: 2,
                  ),
                ),
                const SizedBox(height: 16),
                Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  _LapBadge('LAP', '$_lapCount', ST.g0),
                  const SizedBox(width: 20),
                  _LapBadge('BEST', _bestLapMs == 0 ? '--' : _fmtTime(_bestLapMs), ST.tealL),
                  const SizedBox(width: 20),
                  _LapBadge('LAST', _lapTimes.isEmpty ? '--' : _fmtTime(_lapTimes.last.value), ST.blueL),
                ]),
              ]),
            ),
            const SizedBox(height: 12),

            // ── Control Buttons (Admin/Driver) ──
            if (p.isAdmin || p.isDriver) Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(children: [
                if (!_sessionActive)
                  Expanded(child: _ActionBtn('▶ START SESSION', ST.g1, _startSessionSim)),
                if (_sessionActive)
                  Expanded(child: _ActionBtn('■ STOP SESSION', ST.amber, _stopSession)),
                const SizedBox(width: 10),
                Expanded(child: _ActionBtn('↺ RESET', ST.t3, _resetSession)),
                if (!_sessionActive && _events.isNotEmpty) ...[
                  const SizedBox(width: 10),
                  Expanded(child: _ActionBtn('📄 REPORT', ST.blueL, _showReport)),
                ],
              ]),
            ),
            const SizedBox(height: 14),

            // ── Lap Times Table ──
            if (_lapTimes.isNotEmpty) ...[
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text('LAP TIMES', style: GoogleFonts.dmSans(
                  fontSize: 9, color: ST.t3, fontWeight: FontWeight.w700, letterSpacing: 1,
                )),
              ),
              const SizedBox(height: 8),
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 16),
                decoration: ST.cardBox(),
                child: Column(children: [
                  // Header
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    child: Row(children: [
                      Text('LAP', style: GoogleFonts.dmSans(fontSize: 10, color: ST.t3,
                          fontWeight: FontWeight.w700)),
                      const Spacer(),
                      Text('TIME', style: GoogleFonts.dmSans(fontSize: 10, color: ST.t3,
                          fontWeight: FontWeight.w700)),
                      const SizedBox(width: 60),
                      Text('DELTA', style: GoogleFonts.dmSans(fontSize: 10, color: ST.t3,
                          fontWeight: FontWeight.w700)),
                    ]),
                  ),
                  const Divider(height: 1, color: Color(0xFF1D3324)),
                  ..._lapTimes.asMap().entries.map((e) {
                    final isBest = e.value.value == _bestLapMs;
                    final delta = e.key > 0
                        ? e.value.value - _lapTimes[e.key - 1].value
                        : 0;
                    final deltaStr = e.key == 0 ? '--'
                        : delta > 0 ? '+${(delta / 1000).toStringAsFixed(2)}s'
                        : '${(delta / 1000).toStringAsFixed(2)}s';
                    final deltaColor = delta > 0 ? ST.red : ST.g0;
                    return Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      decoration: isBest
                          ? BoxDecoration(color: ST.tealL.withOpacity(0.06))
                          : null,
                      child: Row(children: [
                        Text(e.value.key, style: GoogleFonts.dmSans(
                          fontSize: 13, color: isBest ? ST.tealL : ST.t1,
                          fontWeight: isBest ? FontWeight.w800 : FontWeight.w600,
                        )),
                        if (isBest) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: ST.tealL.withOpacity(0.15),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text('BEST', style: GoogleFonts.dmSans(
                              fontSize: 8, color: ST.tealL, fontWeight: FontWeight.w700,
                            )),
                          ),
                        ],
                        const Spacer(),
                        Text(_fmtTime(e.value.value), style: GoogleFonts.jetBrainsMono(
                          fontSize: 14, color: isBest ? ST.tealL : ST.t1,
                          fontWeight: FontWeight.bold,
                        )),
                        SizedBox(
                          width: 70,
                          child: Text(deltaStr, textAlign: TextAlign.right,
                              style: GoogleFonts.jetBrainsMono(
                                fontSize: 11, color: e.key == 0 ? ST.t4 : deltaColor,
                              )),
                        ),
                      ]),
                    );
                  }),
                ]),
              ),
              const SizedBox(height: 14),
            ],

            // ── Checkpoint Log ──
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text('CHECKPOINT LOG', style: GoogleFonts.dmSans(
                fontSize: 9, color: ST.t3, fontWeight: FontWeight.w700, letterSpacing: 1,
              )),
            ),
            const SizedBox(height: 8),
            if (_events.isEmpty)
              Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(children: [
                    const Text('🏷️', style: TextStyle(fontSize: 40)),
                    const SizedBox(height: 8),
                    Text('No RFID events yet', style: GoogleFonts.dmSans(fontSize: 13, color: ST.t3)),
                    Text('Start session and drive over checkpoints',
                        style: GoogleFonts.dmSans(fontSize: 11, color: ST.t4)),
                  ]),
                ),
              )
            else
              ..._events.take(15).map((e) => _RfidEventTile(e: e, fmtTime: _fmtTime)),
            const SizedBox(height: 80),
          ],
        ),
      ),
    );
  }

  void _showReport() {
    final p = context.read<SProvider>();
    // Use _finalElapsedMs (snapshot on stop) so Total Time is always accurate;
    // fall back to live _elapsedMs if the session is still running or was never stopped.
    final reportElapsed = _finalElapsedMs > 0 ? _finalElapsedMs : _elapsedMs;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _SessionReportSheet(
        elapsedMs: reportElapsed,
        lapCount: _lapCount,
        lapTimes: _lapTimes,
        bestLapMs: _bestLapMs,
        events: _events,
        fmtTime: _fmtTime,
      ),
    );
  }
}

// ─── Session Report Sheet ────────────────────────────────────────────────────
class _SessionReportSheet extends StatelessWidget {
  final int elapsedMs, lapCount, bestLapMs;
  final List<MapEntry<String, int>> lapTimes;
  final List<RfidEvent> events;
  final String Function(int) fmtTime;

  const _SessionReportSheet({
    required this.elapsedMs,
    required this.lapCount,
    required this.lapTimes,
    required this.bestLapMs,
    required this.events,
    required this.fmtTime,
  });

  @override
  Widget build(BuildContext context) {
    final detectedSet = <String>{'Giraffe', 'Lion', 'Elephant', 'Zebra'};

    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      maxChildSize: 0.95,
      minChildSize: 0.5,
      builder: (_, ctrl) => Container(
        decoration: BoxDecoration(
          color: ST.panel,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          border: Border.all(color: ST.gBorder),
        ),
        child: SingleChildScrollView(
          controller: ctrl,
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Handle
              Center(child: Container(
                width: 40, height: 4,
                margin: const EdgeInsets.only(bottom: 20),
                decoration: BoxDecoration(
                  color: ST.gBorder, borderRadius: BorderRadius.circular(2),
                ),
              )),

              // Title
              Row(children: [
                const Text('📄', style: TextStyle(fontSize: 28)),
                const SizedBox(width: 10),
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('SESSION REPORT', style: GoogleFonts.dmSans(
                    fontSize: 22, color: ST.amberL, fontWeight: FontWeight.w900,
                  )),
                  Text('Generated: ${DateTime.now().toString().substring(0, 19)}',
                      style: GoogleFonts.jetBrainsMono(fontSize: 9, color: ST.t4)),
                ]),
              ]),
              const SizedBox(height: 20),

              Container(
                padding: const EdgeInsets.all(16),
                decoration: ST.glowBox(ST.amber),
                child: Column(children: [
                  _ReportRow('Total Time', fmtTime(elapsedMs), ST.amberL),
                  _ReportRow('Total Laps', '$lapCount', ST.g0),
                  _ReportRow('Best Lap', bestLapMs == 0 ? '--' : fmtTime(bestLapMs), ST.tealL),
                  _ReportRow('Checkpoints Passed', '${events.length}', ST.blueL),
                  _ReportRow('Objects Detected', '${detectedSet.length}', ST.purple),
                  _ReportRow('Track Status', 'COMPLETED', ST.g0),
                ]),
              ),
              const SizedBox(height: 16),

              Text('DETECTED ANIMALS', style: GoogleFonts.dmSans(
                fontSize: 9, color: ST.t3, fontWeight: FontWeight.w700, letterSpacing: 1,
              )),
              const SizedBox(height: 8),
              Wrap(spacing: 8, runSpacing: 8, children: detectedSet.map((s) {
                const emojis = {'Giraffe': '🦒', 'Lion': '🦁', 'Elephant': '🐘', 'Zebra': '🦓'};
                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: ST.glowBox(ST.g1),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Text(emojis[s] ?? '🐾', style: const TextStyle(fontSize: 18)),
                    const SizedBox(width: 6),
                    Text(s, style: GoogleFonts.dmSans(fontSize: 12, color: ST.t1,
                      fontWeight: FontWeight.w700)),
                  ]),
                );
              }).toList()),
              const SizedBox(height: 20),

              // Lap breakdown
              if (lapTimes.isNotEmpty) ...[
                Text('LAP BREAKDOWN', style: GoogleFonts.dmSans(
                  fontSize: 9, color: ST.t3, fontWeight: FontWeight.w700, letterSpacing: 1,
                )),
                const SizedBox(height: 8),
                ...lapTimes.map((e) => Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: _ReportRow(e.key, fmtTime(e.value),
                      e.value == bestLapMs ? ST.tealL : ST.t1),
                )),
              ],
              const SizedBox(height: 20),

              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(context),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: ST.amber,
                    foregroundColor: ST.bg,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: Text('Close Report', style: GoogleFonts.dmSans(
                    fontSize: 14, color: ST.bg, fontWeight: FontWeight.w800,
                  )),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Helper Widgets ───────────────────────────────────────────────────────────
class _LapBadge extends StatelessWidget {
  final String label, value;
  final Color color;
  const _LapBadge(this.label, this.value, this.color);
  @override
  Widget build(BuildContext context) => Column(children: [
    Text(label, style: GoogleFonts.dmSans(fontSize: 9, color: ST.t4, letterSpacing: 1,
      fontWeight: FontWeight.w700)),
    const SizedBox(height: 4),
    Text(value, style: GoogleFonts.jetBrainsMono(fontSize: 14, color: color,
      fontWeight: FontWeight.bold)),
  ]);
}

class _ActionBtn extends StatelessWidget {
  final String label;
  final Color color;
  final VoidCallback onTap;
  const _ActionBtn(this.label, this.color, this.onTap);
  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(vertical: 11),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withOpacity(0.5)),
      ),
      child: Center(child: Text(label, style: GoogleFonts.dmSans(
        fontSize: 11, color: color, fontWeight: FontWeight.w800,
      ))),
    ),
  );
}

class _RfidEventTile extends StatelessWidget {
  final RfidEvent e;
  final String Function(int) fmtTime;
  const _RfidEventTile({required this.e, required this.fmtTime});
  @override
  Widget build(BuildContext context) {
    final isFinish = e.checkpointId == 'CP0';
    final color = isFinish ? ST.amberL : ST.blueL;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 3),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: ST.cardBox(border: color.withOpacity(isFinish ? 0.5 : 0.2)),
        child: Row(children: [
          Text(isFinish ? '🏁' : '📡', style: const TextStyle(fontSize: 18)),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(e.checkpointName, style: GoogleFonts.dmSans(
              fontSize: 13, color: color, fontWeight: FontWeight.w700,
            )),
            Text('Tag: ${e.tagId} · Lap ${e.lapNumber}',
                style: GoogleFonts.jetBrainsMono(fontSize: 9, color: ST.t4)),
          ])),
          if (e.lapTimeMs != null) Text(
            fmtTime(e.lapTimeMs!),
            style: GoogleFonts.jetBrainsMono(fontSize: 12, color: ST.tealL, fontWeight: FontWeight.bold),
          ),
        ]),
      ).animate().fadeIn(duration: 300.ms).slideX(begin: 0.1),
    );
  }
}

class _ReportRow extends StatelessWidget {
  final String label, value;
  final Color color;
  const _ReportRow(this.label, this.value, this.color);
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 5),
    child: Row(children: [
      Text(label, style: GoogleFonts.dmSans(fontSize: 12, color: ST.t2)),
      const Spacer(),
      Text(value, style: GoogleFonts.jetBrainsMono(fontSize: 13, color: color,
        fontWeight: FontWeight.bold)),
    ]),
  );
}
