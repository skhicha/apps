// ─────────────────────────────────────────────────────────────────────────────
// SafariSync v3.0 — AQI & Weather Screen
// Real-time air quality, temperature, and environmental forecasting
// ─────────────────────────────────────────────────────────────────────────────
import 'dart:math';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:provider/provider.dart';
import '../models/track_models.dart';
import '../main.dart' show ST, SProvider;

class AqiWeatherScreen extends StatefulWidget {
  const AqiWeatherScreen({super.key});
  @override State<AqiWeatherScreen> createState() => _AqiWeatherState();
}

class _AqiWeatherState extends State<AqiWeatherScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseCtrl;
  AqiData _current = AqiData.simulated();
  final List<AqiData> _history = [];
  final _rng = Random();
  Timer? _simTimer;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);

    // Seed history
    _history.add(_current);
    for (int i = 0; i < 29; i++) {
      _current = _current.copyWithSimStep(_rng);
      _history.add(_current);
    }

    // Simulate real-time updates (will be overridden by Firebase in SProvider)
    _simTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      if (!mounted) return;
      final p = context.read<SProvider>();
      final live = p.aqiDataV3;
      setState(() {
        _current = live ?? _current.copyWithSimStep(_rng);
        _history.add(_current);
        if (_history.length > 60) _history.removeAt(0);
      });
    });
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    _simTimer?.cancel();
    super.dispose();
  }

  Color _aqiColor(int aqi) {
    if (aqi <= 50) return ST.g0;
    if (aqi <= 100) return const Color(0xFFF5D042);
    if (aqi <= 150) return ST.amber;
    if (aqi <= 200) return ST.red;
    if (aqi <= 300) return ST.purple;
    return const Color(0xFF7E0023);
  }

  List<FlSpot> _tempSpots() => List.generate(
    _history.length,
        (i) => FlSpot(i.toDouble(), _history[i].temperature),
  );

  List<FlSpot> _aqiSpots() => List.generate(
    _history.length,
        (i) => FlSpot(i.toDouble(), _history[i].aqiIndex.toDouble()),
  );

  List<FlSpot> _humSpots() => List.generate(
    _history.length,
        (i) => FlSpot(i.toDouble(), _history[i].humidity),
  );

  @override
  Widget build(BuildContext context) {
    final p = context.watch<SProvider>();
    final aqi = p.aqiDataV3 ?? _current;
    final aqiC = _aqiColor(aqi.aqiIndex);

    return Scaffold(
      backgroundColor: ST.bg,
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Header ──
            Row(children: [
              Text('🌿', style: const TextStyle(fontSize: 28)),
              const SizedBox(width: 10),
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('ENVIRONMENT', style: GoogleFonts.dmSans(
                  fontSize: 26, color: ST.g0, fontWeight: FontWeight.w900, letterSpacing: 2,
                )),
                Text('AQI · Temperature · Air Quality · Forecast',
                    style: GoogleFonts.dmSans(fontSize: 11, color: ST.t3)),
              ]),
            ]).animate().fadeIn(duration: 400.ms).slideY(begin: -0.2),
            const SizedBox(height: 20),

            // ── Main Weather Card ──
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    const Color(0xFF162A1C),
                    aqiC.withOpacity(0.08),
                  ],
                ),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: aqiC.withOpacity(0.4), width: 1.2),
              ),
              child: Column(children: [
                Row(children: [
                  // Temperature
                  Expanded(child: Column(children: [
                    Text(
                      '${aqi.temperature.toStringAsFixed(1)}°C',
                      style: GoogleFonts.dmSans(
                        fontSize: 48, color: ST.t1, fontWeight: FontWeight.w900,
                      ),
                    ),
                    Text(aqi.weatherDescription, style: GoogleFonts.dmSans(
                      fontSize: 13, color: ST.t2, fontWeight: FontWeight.w600,
                    )),
                    const SizedBox(height: 4),
                    Text(aqi.weatherEmoji, style: const TextStyle(fontSize: 32)),
                  ])),
                  Container(width: 1, height: 80, color: ST.gBorder),
                  // AQI ring
                  Expanded(child: Column(children: [
                    AnimatedBuilder(
                      animation: _pulseCtrl,
                      builder: (_, __) => CustomPaint(
                        size: const Size(90, 90),
                        painter: _AqiRingPainter(
                          aqi: aqi.aqiIndex,
                          color: aqiC,
                          pulse: _pulseCtrl.value,
                        ),
                      ),
                    ),
                    Text(aqi.status, style: GoogleFonts.dmSans(
                      fontSize: 12, color: aqiC, fontWeight: FontWeight.w700,
                    )),
                  ])),
                ]),
                const SizedBox(height: 16),
                // Forecast bar
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(children: [
                    const Icon(Icons.wb_cloudy_outlined, color: ST.blueL, size: 18),
                    const SizedBox(width: 10),
                    Expanded(child: Text(aqi.forecastText, style: GoogleFonts.dmSans(
                      fontSize: 12, color: ST.t2,
                    ))),
                  ]),
                ),
              ]),
            ).animate().fadeIn(duration: 500.ms).scale(begin: const Offset(0.95, 0.95)),
            const SizedBox(height: 16),

            // ── Stats Grid ──
            GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisSpacing: 10,
              mainAxisSpacing: 10,
              childAspectRatio: 1.6,
              children: [
                _EnvCard('💧 HUMIDITY', '${aqi.humidity.toStringAsFixed(0)}%', ST.blueL,
                    sub: _humLabel(aqi.humidity)),
                _EnvCard('🟤 PM2.5', '${aqi.pm25.toStringAsFixed(1)} µg/m³', ST.amber,
                    sub: _pm25Label(aqi.pm25)),
                _EnvCard('🌫 CO₂', '${aqi.co2.toStringAsFixed(0)} ppm', ST.tealL,
                    sub: aqi.co2 < 600 ? 'Normal' : 'Elevated'),
                _EnvCard('🌡 FEELS LIKE', '${(aqi.temperature + aqi.humidity * 0.05).toStringAsFixed(1)}°C',
                    ST.pink, sub: 'Heat Index'),
              ],
            ).animate().fadeIn(duration: 600.ms, delay: 100.ms),
            const SizedBox(height: 16),

            // ── Temperature Chart ──
            _ChartCard(
              title: 'TEMPERATURE (°C)',
              color: ST.amber,
              spots: _tempSpots(),
              minY: 20, maxY: 50,
              unit: '°C',
            ).animate().fadeIn(duration: 700.ms, delay: 200.ms),
            const SizedBox(height: 12),

            // ── AQI Chart ──
            _ChartCard(
              title: 'AQI INDEX',
              color: aqiC,
              spots: _aqiSpots(),
              minY: 0, maxY: 300,
              unit: 'AQI',
            ).animate().fadeIn(duration: 700.ms, delay: 300.ms),
            const SizedBox(height: 12),

            // ── AQI Scale Legend ──
            _AqiScaleLegend(),
            const SizedBox(height: 12),

            // ── Hourly Forecast ──
            _HourlyForecast(baseTemp: aqi.temperature, baseHum: aqi.humidity),
            const SizedBox(height: 80),
          ],
        ),
      ),
    );
  }

  String _humLabel(double h) {
    if (h < 30) return 'Very Dry';
    if (h < 50) return 'Comfortable';
    if (h < 70) return 'Humid';
    return 'Very Humid';
  }

  String _pm25Label(double p) {
    if (p < 12) return 'Good';
    if (p < 35) return 'Moderate';
    if (p < 55) return 'Unhealthy';
    return 'Hazardous';
  }
}

// ─── AQI Ring Painter ─────────────────────────────────────────────────────────
class _AqiRingPainter extends CustomPainter {
  final int aqi;
  final Color color;
  final double pulse;
  _AqiRingPainter({required this.aqi, required this.color, required this.pulse});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width * 0.42;
    final sweepAngle = (aqi.clamp(0, 300) / 300) * 2 * pi;

    // Background ring
    canvas.drawCircle(center, radius,
        Paint()
          ..color = color.withOpacity(0.1)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 10);

    // Progress arc
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -pi / 2,
      sweepAngle,
      false,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 10
        ..strokeCap = StrokeCap.round,
    );

    // Pulse effect
    canvas.drawCircle(center, radius + 4 + pulse * 6,
        Paint()
          ..color = color.withOpacity(0.05 + pulse * 0.08)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2);

    // Center text
    final tp = TextPainter(
      text: TextSpan(
        text: '$aqi',
        style: TextStyle(
          fontSize: 22, fontWeight: FontWeight.bold, color: color,
          fontFamily: 'monospace',
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset(center.dx - tp.width / 2, center.dy - tp.height / 2));
  }

  @override bool shouldRepaint(_AqiRingPainter old) => true;
}

// ─── Environment Card ─────────────────────────────────────────────────────────
class _EnvCard extends StatelessWidget {
  final String title, value;
  final Color color;
  final String? sub;
  const _EnvCard(this.title, this.value, this.color, {this.sub});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: color.withOpacity(0.06),
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: color.withOpacity(0.3)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(title, style: GoogleFonts.dmSans(fontSize: 9, color: ST.t3,
          fontWeight: FontWeight.w700, letterSpacing: 1)),
        const SizedBox(height: 4),
        Text(value, style: GoogleFonts.dmSans(fontSize: 18, color: color,
          fontWeight: FontWeight.w900)),
        if (sub != null) Text(sub!, style: GoogleFonts.dmSans(fontSize: 9, color: ST.t3)),
      ],
    ),
  );
}

// ─── Line Chart Card ─────────────────────────────────────────────────────────
class _ChartCard extends StatelessWidget {
  final String title;
  final Color color;
  final List<FlSpot> spots;
  final double minY, maxY;
  final String unit;
  const _ChartCard({
    required this.title, required this.color, required this.spots,
    required this.minY, required this.maxY, required this.unit,
  });
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    decoration: ST.cardBox(),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: GoogleFonts.dmSans(fontSize: 9, color: ST.t3,
          fontWeight: FontWeight.w700, letterSpacing: 1)),
        const SizedBox(height: 12),
        SizedBox(
          height: 100,
          child: LineChart(
            LineChartData(
              minY: minY, maxY: maxY,
              gridData: FlGridData(
                show: true,
                getDrawingHorizontalLine: (_) => FlLine(color: ST.gBorder, strokeWidth: 0.5),
                getDrawingVerticalLine: (_) => FlLine(color: Colors.transparent),
              ),
              borderData: FlBorderData(show: false),
              titlesData: FlTitlesData(
                leftTitles: AxisTitles(sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 36,
                  getTitlesWidget: (v, _) => Text('${v.toInt()}',
                      style: GoogleFonts.jetBrainsMono(fontSize: 8, color: ST.t4)),
                )),
                rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
              ),
              lineBarsData: [
                LineChartBarData(
                  spots: spots,
                  isCurved: true,
                  color: color,
                  barWidth: 2,
                  dotData: FlDotData(show: false),
                  belowBarData: BarAreaData(
                    show: true,
                    color: color.withOpacity(0.08),
                  ),
                ),
              ],
            ),
          ),
        ),
        if (spots.isNotEmpty) Align(
          alignment: Alignment.centerRight,
          child: Text(
            'Current: ${spots.last.y.toStringAsFixed(1)} $unit',
            style: GoogleFonts.jetBrainsMono(fontSize: 9, color: color),
          ),
        ),
      ],
    ),
  );
}

// ─── AQI Scale Legend ────────────────────────────────────────────────────────
class _AqiScaleLegend extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    decoration: ST.cardBox(),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('AQI SCALE', style: GoogleFonts.dmSans(fontSize: 9, color: ST.t3,
          fontWeight: FontWeight.w700, letterSpacing: 1)),
        const SizedBox(height: 10),
        ...const [
          [0, 50, '🟢 Good', ST.g0],
          [51, 100, '🟡 Moderate', Color(0xFFF5D042)],
          [101, 150, '🟠 Sensitive Groups', ST.amber],
          [151, 200, '🔴 Unhealthy', ST.red],
          [201, 300, '🟣 Very Unhealthy', ST.purple],
        ].map((row) => Padding(
          padding: const EdgeInsets.only(bottom: 5),
          child: Row(children: [
            Text(row[2] as String, style: GoogleFonts.dmSans(
              fontSize: 11, color: row[3] as Color, fontWeight: FontWeight.w600,
            )),
            const Spacer(),
            Text('${row[0]}–${row[1]}', style: GoogleFonts.jetBrainsMono(
              fontSize: 10, color: ST.t3,
            )),
          ]),
        )),
      ],
    ),
  );
}

// ─── Hourly Forecast ─────────────────────────────────────────────────────────
class _HourlyForecast extends StatelessWidget {
  final double baseTemp, baseHum;
  const _HourlyForecast({required this.baseTemp, required this.baseHum});

  @override
  Widget build(BuildContext context) {
    final rng = Random(42);
    final now = DateTime.now();
    final hours = List.generate(8, (i) {
      final t = now.add(Duration(hours: i));
      final temp = baseTemp + sin(i * 0.8) * 3 + (rng.nextDouble() - 0.5) * 2;
      final hum = baseHum + cos(i * 0.6) * 8 + (rng.nextDouble() - 0.5) * 3;
      final emojis = ['☀️', '🌤', '⛅', '🌦', '🌧', '⛈'];
      final emoji = hum > 75 ? emojis[3 + (i % 3)]
          : temp > 35 ? emojis[0]
          : emojis[1 + (i % 2)];
      return {'h': t.hour, 'temp': temp.clamp(20.0, 50.0), 'emoji': emoji};
    });

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: ST.cardBox(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('8-HOUR FORECAST', style: GoogleFonts.dmSans(
            fontSize: 9, color: ST.t3, fontWeight: FontWeight.w700, letterSpacing: 1,
          )),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: hours.map((h) => Column(children: [
              Text('${h['h'].toString().padLeft(2, '0')}:00',
                  style: GoogleFonts.jetBrainsMono(fontSize: 9, color: ST.t3)),
              const SizedBox(height: 4),
              Text(h['emoji'] as String, style: const TextStyle(fontSize: 18)),
              const SizedBox(height: 4),
              Text('${(h['temp'] as double).toStringAsFixed(0)}°',
                  style: GoogleFonts.dmSans(fontSize: 11, color: ST.t1,
                    fontWeight: FontWeight.w700)),
            ])).toList(),
          ),
        ],
      ),
    );
  }
}
