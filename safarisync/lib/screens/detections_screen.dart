// ─────────────────────────────────────────────────────────────────────────────
// SafariSync v3.0 — ESP32-CAM Detections Screen
// Real-time animal/object detection feed from onboard edge AI system
// ─────────────────────────────────────────────────────────────────────────────
import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../models/track_models.dart';
import '../main.dart' show ST, SProvider;

class DetectionsScreen extends StatefulWidget {
  const DetectionsScreen({super.key});
  @override State<DetectionsScreen> createState() => _DetectionsState();
}

class _DetectionsState extends State<DetectionsScreen> {
  final List<DetectedObject> _detections = [];
  final _rng = Random();
  Timer? _simTimer;
  String _filter = 'ALL';

  static const _simLabels = [
    ['Giraffe', '🦒'], ['Lion', '🦁'], ['Elephant', '🐘'], ['Zebra', '🦓'],
    ['Rhino', '🦏'], ['Leopard', '🐆'], ['Buffalo', '🐃'], ['Deer', '🦌'],
    ['Hippo', '🦛'], ['Bear', '🐻'], ['Parrot', '🦜'],
  ];

  @override
  void initState() {
    super.initState();
    // Seed with some pre-existing detections
    for (int i = 0; i < 5; i++) {
      _addSimDetection(offset: Duration(minutes: i * 3 + _rng.nextInt(2)));
    }
    // Simulate live detection stream
    _simTimer = Timer.periodic(const Duration(seconds: 8), (_) {
      if (mounted) _addSimDetection();
    });
  }

  void _addSimDetection({Duration? offset}) {
    final lbl = _simLabels[_rng.nextInt(_simLabels.length)];
    final det = DetectedObject(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      label: lbl[0],
      confidence: 0.65 + _rng.nextDouble() * 0.34,
      timestamp: DateTime.now().subtract(offset ?? Duration.zero),
      trackX: 0.08 + _rng.nextDouble() * 0.88,
      trackY: 0.08 + _rng.nextDouble() * 0.88,
      emoji: lbl[1],
    );
    if (mounted) setState(() {
      _detections.insert(0, det);
      if (_detections.length > 50) _detections.removeLast();
    });
  }

  @override
  void dispose() {
    _simTimer?.cancel();
    super.dispose();
  }

  List<DetectedObject> get _filtered => _filter == 'ALL'
      ? _detections
      : _detections.where((d) => d.label == _filter).toList();

  Map<String, int> get _counts {
    final m = <String, int>{};
    for (final d in _detections) m[d.label] = (m[d.label] ?? 0) + 1;
    return m;
  }

  String _fmtAgo(DateTime ts) {
    final diff = DateTime.now().difference(ts);
    if (diff.inSeconds < 60) return '${diff.inSeconds}s ago';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    return '${diff.inHours}h ago';
  }

  @override
  Widget build(BuildContext context) {
    final p = context.watch<SProvider>();
    final isTourist = p.isTourist;
    final filtered = _filtered;
    final counts = _counts;
    final topLabel = counts.isEmpty ? '' :
        counts.entries.reduce((a, b) => a.value > b.value ? a : b).key;

    return Scaffold(
      backgroundColor: ST.bg,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header ──
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Text('📷 DETECTIONS', style: GoogleFonts.dmSans(
                  fontSize: 24, color: ST.blueL, fontWeight: FontWeight.w900, letterSpacing: 1.5,
                )),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: ST.blueL.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: ST.blueL.withOpacity(0.4)),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Container(
                      width: 6, height: 6,
                      decoration: const BoxDecoration(color: ST.blueL, shape: BoxShape.circle),
                    ).animate(onPlay: (c) => c.repeat()).fadeOut(duration: 800.ms).then().fadeIn(duration: 800.ms),
                    const SizedBox(width: 6),
                    Text('LIVE', style: GoogleFonts.jetBrainsMono(fontSize: 9, color: ST.blueL)),
                  ]),
                ),
              ]),
              Text('ESP32-CAM · Edge AI · Real-time object classification',
                  style: GoogleFonts.dmSans(fontSize: 11, color: ST.t3)),
            ]),
          ),

          // ── Stats Cards ──
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(children: [
              _StatCard('TOTAL', '${_detections.length}', ST.blueL),
              const SizedBox(width: 10),
              _StatCard('UNIQUE', '${counts.length}', ST.tealL),
              const SizedBox(width: 10),
              _StatCard('TOP', topLabel.isEmpty ? '--' : topLabel, ST.amberL),
            ]),
          ),
          const SizedBox(height: 12),

          // ── Species Breakdown ──
          if (!isTourist && counts.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text('SPECIES BREAKDOWN', style: GoogleFonts.dmSans(
                fontSize: 9, color: ST.t3, fontWeight: FontWeight.w700, letterSpacing: 1,
              )),
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 60,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemCount: counts.length,
                itemBuilder: (_, i) {
                  final entry = counts.entries.toList()[i];
                  final emoji = _detections
                      .firstWhere((d) => d.label == entry.key).emoji;
                  return Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: ST.glowBox(ST.blueL),
                    child: Row(children: [
                      Text(emoji, style: const TextStyle(fontSize: 18)),
                      const SizedBox(width: 8),
                      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(entry.key, style: GoogleFonts.dmSans(
                          fontSize: 10, color: ST.t1, fontWeight: FontWeight.w700,
                        )),
                        Text('${entry.value}×', style: GoogleFonts.jetBrainsMono(
                          fontSize: 9, color: ST.blueL,
                        )),
                      ]),
                    ]),
                  );
                },
              ),
            ),
            const SizedBox(height: 12),
          ],

          // ── Filter Row ──
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(children: [
              _FilterChip('ALL', _filter, () => setState(() => _filter = 'ALL')),
              ...counts.keys.map((k) => Padding(
                padding: const EdgeInsets.only(left: 8),
                child: _FilterChip(k, _filter, () => setState(() => _filter = k)),
              )),
            ]),
          ),
          const SizedBox(height: 12),

          // ── Detection List ──
          Expanded(
            child: filtered.isEmpty
                ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Text('🔍', style: TextStyle(fontSize: 48)),
              const SizedBox(height: 12),
              Text('No detections yet', style: GoogleFonts.dmSans(fontSize: 14, color: ST.t3)),
            ]))
                : ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: filtered.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (_, i) {
                final d = filtered[i];
                return _DetectionCard(d: d, ago: _fmtAgo(d.timestamp), isTourist: isTourist)
                    .animate()
                    .fadeIn(duration: 300.ms, delay: (i * 30).ms)
                    .slideX(begin: 0.05);
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Detection Card ───────────────────────────────────────────────────────────
class _DetectionCard extends StatelessWidget {
  final DetectedObject d;
  final String ago;
  final bool isTourist;
  const _DetectionCard({required this.d, required this.ago, required this.isTourist});

  Color get _confColor {
    if (d.confidence >= 0.9) return ST.g0;
    if (d.confidence >= 0.75) return ST.amber;
    return ST.red;
  }

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: ST.card,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: _confColor.withOpacity(0.3)),
    ),
    child: Row(children: [
      // Emoji icon
      Container(
        width: 52, height: 52,
        decoration: BoxDecoration(
          color: _confColor.withOpacity(0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _confColor.withOpacity(0.4)),
        ),
        child: Center(child: Text(d.emoji, style: const TextStyle(fontSize: 26))),
      ),
      const SizedBox(width: 14),
      // Info
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(d.label, style: GoogleFonts.dmSans(
          fontSize: 16, color: ST.t1, fontWeight: FontWeight.w800,
        )),
        if (!isTourist) ...[
          const SizedBox(height: 4),
          Text('ID: ${d.id.substring(d.id.length - 6)}',
              style: GoogleFonts.jetBrainsMono(fontSize: 9, color: ST.t4)),
        ],
        const SizedBox(height: 6),
        // Confidence bar
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Text(d.confidenceLabel, style: GoogleFonts.dmSans(
              fontSize: 9, color: _confColor, fontWeight: FontWeight.w700, letterSpacing: 1,
            )),
            const Spacer(),
            Text('${(d.confidence * 100).toStringAsFixed(1)}%',
                style: GoogleFonts.jetBrainsMono(fontSize: 9, color: _confColor)),
          ]),
          const SizedBox(height: 4),
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: d.confidence,
              backgroundColor: _confColor.withOpacity(0.1),
              valueColor: AlwaysStoppedAnimation(_confColor),
              minHeight: 4,
            ),
          ),
        ]),
      ])),
      const SizedBox(width: 10),
      // Timestamp
      Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Text(ago, style: GoogleFonts.dmSans(fontSize: 10, color: ST.t4)),
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: _confColor.withOpacity(0.1),
            shape: BoxShape.circle,
          ),
          child: Icon(Icons.photo_camera, size: 14, color: _confColor),
        ),
      ]),
    ]),
  );
}

// ─── Helpers ─────────────────────────────────────────────────────────────────
class _StatCard extends StatelessWidget {
  final String label, value;
  final Color color;
  const _StatCard(this.label, this.value, this.color);
  @override
  Widget build(BuildContext context) => Expanded(
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: color.withOpacity(0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(children: [
        Text(label, style: GoogleFonts.dmSans(fontSize: 8, color: ST.t4, letterSpacing: 1,
          fontWeight: FontWeight.w700)),
        const SizedBox(height: 4),
        Text(value, style: GoogleFonts.dmSans(fontSize: 18, color: color,
          fontWeight: FontWeight.w900), maxLines: 1, overflow: TextOverflow.ellipsis),
      ]),
    ),
  );
}

class _FilterChip extends StatelessWidget {
  final String label, selected;
  final VoidCallback onTap;
  const _FilterChip(this.label, this.selected, this.onTap);
  @override
  Widget build(BuildContext context) {
    final active = label == selected;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: 180.ms,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: active ? ST.blueL.withOpacity(0.15) : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: active ? ST.blueL : ST.gBorder),
        ),
        child: Text(label, style: GoogleFonts.dmSans(
          fontSize: 11, color: active ? ST.blueL : ST.t3, fontWeight: FontWeight.w600,
        )),
      ),
    );
  }
}
