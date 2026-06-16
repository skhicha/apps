// lib/widgets/quiz_widget.dart
// Data-driven quiz renderer — handles any number of options without code changes.
// Features: shake on wrong answer, confetti + celebration on correct answer,
// haptic feedback, smooth slide-in reveal animation.

import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:confetti/confetti.dart';
import 'package:provider/provider.dart';
import '../providers/story_provider.dart';
import '../utils/app_theme.dart';

class QuizWidget extends StatefulWidget {
  const QuizWidget({super.key});

  @override
  State<QuizWidget> createState() => _QuizWidgetState();
}

class _QuizWidgetState extends State<QuizWidget>
    with TickerProviderStateMixin {
  // ── Shake animation for wrong answers ──
  late AnimationController _shakeController;
  late Animation<double> _shakeAnim;

  // ── Slide-in reveal animation ──
  late AnimationController _slideController;
  late Animation<Offset> _slideAnim;
  late Animation<double> _fadeAnim;

  // ── Confetti ──
  late ConfettiController _confettiController;

  // Track last wrong count to trigger shake
  int _lastWrongAttempts = 0;
  bool _confettiPlayed = false;

  @override
  void initState() {
    super.initState();

    // Shake: quick left-right oscillation
    _shakeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _shakeAnim = TweenSequence([
      TweenSequenceItem(tween: Tween<double>(begin: 0, end: -12), weight: 1),
      TweenSequenceItem(tween: Tween<double>(begin: -12, end: 12), weight: 2),
      TweenSequenceItem(tween: Tween<double>(begin: 12, end: -8), weight: 2),
      TweenSequenceItem(tween: Tween<double>(begin: -8, end: 8), weight: 2),
      TweenSequenceItem(tween: Tween<double>(begin: 8, end: 0), weight: 1),
    ]).animate(CurvedAnimation(parent: _shakeController, curve: Curves.linear));

    // Slide-up fade-in reveal
    _slideController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _slideAnim = Tween<Offset>(
      begin: const Offset(0, 0.3),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _slideController, curve: Curves.easeOutCubic));
    _fadeAnim = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _slideController, curve: const Interval(0, 0.7)),
    );

    // Confetti
    _confettiController =
        ConfettiController(duration: const Duration(seconds: 3));

    // Start reveal animation immediately
    _slideController.forward();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _checkForStateChanges();
  }

  void _checkForStateChanges() {
    final provider = context.read<StoryProvider>();

    // Trigger shake if a new wrong attempt occurred
    if (provider.wrongAttempts > _lastWrongAttempts) {
      _lastWrongAttempts = provider.wrongAttempts;
      _triggerShake();
    }

    // Trigger confetti if just became correct
    if (provider.quizState == QuizState.correct) {
      _confettiController.play();
    }
  }

  void _triggerShake() {
    HapticFeedback.mediumImpact();
    _shakeController.reset();
    _shakeController.forward();
  }

  @override
  void dispose() {
    _shakeController.dispose();
    _slideController.dispose();
    _confettiController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<StoryProvider>(
      builder: (context, provider, _) {
        // React to wrong attempts
        if (provider.wrongAttempts > _lastWrongAttempts) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _lastWrongAttempts = provider.wrongAttempts;
            _triggerShake();
          });
        }
        // React to correct answer
        if (provider.quizState == QuizState.correct && !_confettiPlayed) {
          _confettiPlayed = true;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _confettiController.play();
            HapticFeedback.heavyImpact();
          });
        }

        return FadeTransition(
          opacity: _fadeAnim,
          child: SlideTransition(
            position: _slideAnim,
            child: Stack(
              alignment: Alignment.topCenter,
              children: [
                _buildQuizCard(context, provider),

                // ── Confetti overlay ──
                ConfettiWidget(
                  confettiController: _confettiController,
                  blastDirection: -pi / 2, // Shoot upward
                  numberOfParticles: 30,
                  gravity: 0.3,
                  emissionFrequency: 0.06,
                  colors: const [
                    PebloColors.sunYellow,
                    PebloColors.skyBlue,
                    PebloColors.grassGreen,
                    PebloColors.softPurple,
                    PebloColors.warmOrange,
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildQuizCard(BuildContext context, StoryProvider provider) {
    final isCorrect = provider.quizState == QuizState.correct;

    return AnimatedBuilder(
      animation: _shakeAnim,
      builder: (context, child) {
        return Transform.translate(
          offset: Offset(_shakeAnim.value, 0),
          child: child,
        );
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 400),
        width: double.infinity,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: isCorrect
                ? [const Color(0xFF2E7D32), const Color(0xFF388E3C)]
                : [const Color(0xFF4A148C), const Color(0xFF6A1B9A)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: PebloRadius.card,
          boxShadow: [
            BoxShadow(
              color: (isCorrect ? PebloColors.grassGreen : PebloColors.softPurple)
                  .withOpacity(0.4),
              blurRadius: 20,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        padding: const EdgeInsets.all(PebloSpacing.lg),
        child: isCorrect ? _buildSuccessState() : _buildActiveQuiz(context, provider),
      ),
    );
  }

  // ── Active quiz with data-driven options ──────────────────────────────────

  Widget _buildActiveQuiz(BuildContext context, StoryProvider provider) {
    final quiz = provider.quiz;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Quiz header
        Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: PebloColors.sunYellow,
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Text(
                '🧠 Quiz Time!',
                style: TextStyle(
                  color: PebloColors.deepBlue,
                  fontWeight: FontWeight.w800,
                  fontSize: 13,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: PebloSpacing.md),

        // Question text — from JSON
        Text(
          quiz.question,
          style: PebloTextStyles.questionText,
        ),
        const SizedBox(height: PebloSpacing.lg),

        // Options — dynamically rendered from JSON list
        // Handles 3, 4, or 5 options without any code changes
        ...List.generate(quiz.options.length, (index) {
          return Padding(
            padding: const EdgeInsets.only(bottom: PebloSpacing.sm),
            child: _OptionButton(
              label: quiz.options[index],
              index: index,
              selectedOption: provider.selectedOption,
              quizState: provider.quizState,
              correctAnswer: quiz.answer,
              onTap: () => context.read<StoryProvider>().selectOption(quiz.options[index]),
            ),
          );
        }),
      ],
    );
  }

  // ── Success state ─────────────────────────────────────────────────────────

  Widget _buildSuccessState() {
    return Column(
      children: [
        const Text(
          '🎉',
          style: TextStyle(fontSize: 52),
        ),
        const SizedBox(height: PebloSpacing.md),
        const Text(
          'Amazing job!',
          style: TextStyle(
            color: Colors.white,
            fontSize: 26,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: PebloSpacing.sm),
        const Text(
          "You're a story superstar! ⭐",
          style: TextStyle(
            color: Color(0xFFA5D6A7),
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: PebloSpacing.lg),
        // Stars row
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(
            5,
            (i) => const Padding(
              padding: EdgeInsets.symmetric(horizontal: 4),
              child: Icon(Icons.star_rounded, color: PebloColors.sunYellow, size: 32),
            ),
          ),
        ),
      ],
    );
  }
}

// ── Option Button Widget ──────────────────────────────────────────────────────

class _OptionButton extends StatelessWidget {
  final String label;
  final int index;
  final String? selectedOption;
  final QuizState quizState;
  final String correctAnswer;
  final VoidCallback onTap;

  // Option letter labels — A, B, C, D, E...
  static const _letters = ['A', 'B', 'C', 'D', 'E'];

  const _OptionButton({
    required this.label,
    required this.index,
    required this.selectedOption,
    required this.quizState,
    required this.correctAnswer,
    required this.onTap,
  });

  bool get _isSelected => selectedOption == label;
  bool get _isCorrect => label.trim().toLowerCase() == correctAnswer.trim().toLowerCase();
  bool get _quizDone => quizState == QuizState.correct;

  Color get _backgroundColor {
    if (_quizDone && _isCorrect) return PebloColors.grassGreen;
    if (_isSelected && quizState == QuizState.wrong) return PebloColors.optionWrong;
    if (_isSelected) return PebloColors.skyBlue.withOpacity(0.3);
    return Colors.white;
  }

  Color get _borderColor {
    if (_quizDone && _isCorrect) return PebloColors.grassGreen;
    if (_isSelected && quizState == QuizState.wrong) return PebloColors.coralRed;
    if (_isSelected) return PebloColors.skyBlue;
    return Colors.white.withOpacity(0.3);
  }

  @override
  Widget build(BuildContext context) {
    final disabled = _quizDone;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      decoration: BoxDecoration(
        color: _backgroundColor,
        borderRadius: PebloRadius.option,
        border: Border.all(color: _borderColor, width: 2.5),
        boxShadow: _isSelected
            ? [
                BoxShadow(
                  color: _borderColor.withOpacity(0.4),
                  blurRadius: 8,
                  offset: const Offset(0, 3),
                )
              ]
            : [],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: PebloRadius.option,
          onTap: disabled ? null : onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: PebloSpacing.md,
              vertical: PebloSpacing.sm + 4,
            ),
            child: Row(
              children: [
                // Letter badge
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: _isSelected
                        ? (_quizDone && _isCorrect
                            ? PebloColors.deepBlue
                            : PebloColors.deepBlue)
                        : const Color(0xFFE3F2FD),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Center(
                    child: Text(
                      index < _letters.length ? _letters[index] : '${index + 1}',
                      style: TextStyle(
                        color: _isSelected ? Colors.white : PebloColors.deepBlue,
                        fontWeight: FontWeight.w800,
                        fontSize: 14,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: PebloSpacing.md),

                // Option text
                Expanded(
                  child: Text(
                    label,
                    style: PebloTextStyles.optionText.copyWith(
                      color: _isSelected || (_quizDone && _isCorrect)
                          ? PebloColors.textDark
                          : PebloColors.textDark,
                    ),
                  ),
                ),

                // Correct/wrong icon
                if (_quizDone && _isCorrect)
                  const Icon(Icons.check_circle_rounded,
                      color: PebloColors.deepBlue, size: 22)
                else if (_isSelected && quizState == QuizState.wrong)
                  const Icon(Icons.cancel_rounded,
                      color: PebloColors.coralRed, size: 22),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
