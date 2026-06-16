// lib/widgets/buddy_character.dart
// Pip the Robot — drawn in pure Flutter/CustomPainter.
// No external image assets needed; renders cleanly on all resolutions.
// Animates between idle (gentle bobbing), happy (bouncing), and sad (shaking).

import 'package:flutter/material.dart';
import '../providers/story_provider.dart';
import '../utils/app_theme.dart';

class BuddyCharacter extends StatefulWidget {
  final QuizState quizState;
  final AudioState audioState;

  const BuddyCharacter({
    super.key,
    required this.quizState,
    required this.audioState,
  });

  @override
  State<BuddyCharacter> createState() => _BuddyCharacterState();
}

class _BuddyCharacterState extends State<BuddyCharacter>
    with TickerProviderStateMixin {
  late AnimationController _bobController;
  late AnimationController _bounceController;
  late AnimationController _speakController;
  late Animation<double> _bobAnim;
  late Animation<double> _bounceAnim;
  late Animation<double> _speakAnim;

  @override
  void initState() {
    super.initState();

    // Idle bob — continuous gentle float
    _bobController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    )..repeat(reverse: true);
    _bobAnim = Tween<double>(begin: -6, end: 6).animate(
      CurvedAnimation(parent: _bobController, curve: Curves.easeInOut),
    );

    // Happy bounce — triggered on correct answer
    _bounceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _bounceAnim = Tween<double>(begin: 0, end: -20).animate(
      CurvedAnimation(parent: _bounceController, curve: Curves.elasticOut),
    );

    // Speaking pulse — gentle scale while TTS plays
    _speakController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    )..repeat(reverse: true);
    _speakAnim = Tween<double>(begin: 1.0, end: 1.06).animate(
      CurvedAnimation(parent: _speakController, curve: Curves.easeInOut),
    );
  }

  @override
  void didUpdateWidget(BuddyCharacter oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.quizState == QuizState.correct &&
        oldWidget.quizState != QuizState.correct) {
      _triggerHappyBounce();
    }
  }

  void _triggerHappyBounce() {
    _bounceController.reset();
    _bounceController.repeat(reverse: true, period: const Duration(milliseconds: 400));
    Future.delayed(const Duration(milliseconds: 2000), () {
      if (mounted) _bounceController.stop();
    });
  }

  @override
  void dispose() {
    _bobController.dispose();
    _bounceController.dispose();
    _speakController.dispose();
    super.dispose();
  }

  bool get _isSpeaking => widget.audioState == AudioState.playing;
  bool get _isHappy => widget.quizState == QuizState.correct;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([_bobAnim, _bounceAnim, _speakAnim]),
      builder: (context, child) {
        final yOffset = _isHappy
            ? _bounceAnim.value
            : _bobAnim.value;
        final scale = _isSpeaking ? _speakAnim.value : 1.0;

        return Transform.translate(
          offset: Offset(0, yOffset),
          child: Transform.scale(
            scale: scale,
            child: _buildPip(),
          ),
        );
      },
    );
  }

  Widget _buildPip() {
    return SizedBox(
      width: 130,
      height: 160,
      child: CustomPaint(
        painter: _PipPainter(
          isHappy: _isHappy,
          isSpeaking: _isSpeaking,
          isWrong: widget.quizState == QuizState.wrong,
        ),
      ),
    );
  }
}

// ── Custom painter for Pip the Robot ────────────────────────────────────────

class _PipPainter extends CustomPainter {
  final bool isHappy;
  final bool isSpeaking;
  final bool isWrong;

  _PipPainter({
    required this.isHappy,
    required this.isSpeaking,
    required this.isWrong,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final paint = Paint()..isAntiAlias = true;

    // ── Body ──
    paint.color = const Color(0xFF90CAF9); // Light blue robot body
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(cx - 38, size.height * 0.38, 76, 80),
        const Radius.circular(18),
      ),
      paint,
    );

    // ── Chest panel ──
    paint.color = const Color(0xFF42A5F5);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(cx - 24, size.height * 0.50, 48, 30),
        const Radius.circular(8),
      ),
      paint,
    );

    // ── Chest LED indicator ──
    paint.color = isSpeaking
        ? const Color(0xFF69F0AE) // Green when speaking
        : (isHappy ? const Color(0xFFFFD740) : const Color(0xFFFF5252));
    canvas.drawCircle(Offset(cx, size.height * 0.60), 8, paint);

    // ── Head ──
    paint.color = const Color(0xFF64B5F6);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(cx - 36, size.height * 0.08, 72, 62),
        const Radius.circular(22),
      ),
      paint,
    );

    // ── Antenna ──
    paint.color = const Color(0xFF42A5F5);
    paint.strokeWidth = 4;
    paint.style = PaintingStyle.stroke;
    canvas.drawLine(Offset(cx, size.height * 0.08), Offset(cx, size.height * 0.01), paint);
    paint.style = PaintingStyle.fill;
    paint.color = PebloColors.sunYellow;
    canvas.drawCircle(Offset(cx, size.height * 0.01), 6, paint);

    // ── Eyes ──
    _drawEye(canvas, cx - 14, size.height * 0.24, paint);
    _drawEye(canvas, cx + 14, size.height * 0.24, paint);

    // ── Mouth ──
    _drawMouth(canvas, size, cx, paint);

    // ── Arms ──
    paint.color = const Color(0xFF64B5F6);
    // Left arm
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(cx - 58, size.height * 0.42, 20, 44),
        const Radius.circular(10),
      ),
      paint,
    );
    // Right arm
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(cx + 38, size.height * 0.42, 20, 44),
        const Radius.circular(10),
      ),
      paint,
    );

    // ── Legs ──
    // Left leg
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(cx - 30, size.height * 0.85, 20, 32),
        const Radius.circular(8),
      ),
      paint,
    );
    // Right leg
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(cx + 10, size.height * 0.85, 20, 32),
        const Radius.circular(8),
      ),
      paint,
    );

    // ── Gear icon on body (blue gear — story detail!) ──
    paint.color = const Color(0xFF1565C0).withOpacity(0.5);
    paint.style = PaintingStyle.stroke;
    paint.strokeWidth = 2;
    canvas.drawCircle(Offset(cx, size.height * 0.60), 4, paint);
  }

  void _drawEye(Canvas canvas, double x, double y, Paint paint) {
    // Eye white
    paint.style = PaintingStyle.fill;
    paint.color = Colors.white;
    canvas.drawCircle(Offset(x, y), 9, paint);

    // Pupil
    paint.color = isHappy ? const Color(0xFF1A237E) : const Color(0xFF37474F);
    canvas.drawCircle(Offset(x, y + (isHappy ? -1 : 0)), 5, paint);

    // Shine
    paint.color = Colors.white;
    canvas.drawCircle(Offset(x + 2, y - 2), 2, paint);

    // Happy eye squint (arc overlay when happy)
    if (isHappy) {
      paint.color = const Color(0xFF64B5F6);
      paint.style = PaintingStyle.fill;
      canvas.drawOval(
        Rect.fromCenter(center: Offset(x, y - 5), width: 18, height: 10),
        paint,
      );
    }
  }

  void _drawMouth(Canvas canvas, Size size, double cx, Paint paint) {
    final path = Path();
    paint.style = PaintingStyle.stroke;
    paint.strokeWidth = 3;
    paint.strokeCap = StrokeCap.round;

    if (isHappy) {
      // Big smile
      paint.color = const Color(0xFF1A237E);
      path.moveTo(cx - 16, size.height * 0.36);
      path.quadraticBezierTo(cx, size.height * 0.44, cx + 16, size.height * 0.36);
    } else if (isWrong) {
      // Sad frown
      paint.color = PebloColors.coralRed;
      path.moveTo(cx - 14, size.height * 0.40);
      path.quadraticBezierTo(cx, size.height * 0.34, cx + 14, size.height * 0.40);
    } else {
      // Neutral small smile
      paint.color = const Color(0xFF1565C0);
      path.moveTo(cx - 12, size.height * 0.37);
      path.quadraticBezierTo(cx, size.height * 0.42, cx + 12, size.height * 0.37);
    }

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_PipPainter oldDelegate) =>
      oldDelegate.isHappy != isHappy ||
      oldDelegate.isSpeaking != isSpeaking ||
      oldDelegate.isWrong != isWrong;
}
