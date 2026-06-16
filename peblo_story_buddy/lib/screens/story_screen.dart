// lib/screens/story_screen.dart
// The main (and only) screen of the Peblo Story Buddy.
// Orchestrates: background, Pip character, story card, quiz reveal.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/story_provider.dart';
import '../utils/app_theme.dart';
import '../widgets/buddy_character.dart';
import '../widgets/story_card.dart';
import '../widgets/quiz_widget.dart';

class StoryScreen extends StatelessWidget {
  const StoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        // ── Full-screen night-sky gradient ──
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: PebloColors.skyGradient,
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: SafeArea(
          child: Consumer<StoryProvider>(
            builder: (context, provider, _) {
              return SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: PebloSpacing.lg,
                    vertical: PebloSpacing.md,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      // ── Top bar ──
                      _buildTopBar(),
                      const SizedBox(height: PebloSpacing.sm),

                      // ── Decorative stars background ──
                      _buildStarsRow(),
                      const SizedBox(height: PebloSpacing.md),

                      // ── Pip the Robot ──
                      BuddyCharacter(
                        quizState: provider.quizState,
                        audioState: provider.audioState,
                      ),
                      const SizedBox(height: PebloSpacing.xs),

                      // ── Buddy name badge ──
                      _buildBuddyBadge(provider),
                      const SizedBox(height: PebloSpacing.lg),

                      // ── Story card with TTS button ──
                      const StoryCard(),
                      const SizedBox(height: PebloSpacing.lg),

                      // ── Quiz — smoothly revealed after audio ends ──
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 400),
                        switchInCurve: Curves.easeOutCubic,
                        switchOutCurve: Curves.easeIn,
                        transitionBuilder: (child, animation) {
                          return FadeTransition(opacity: animation, child: child);
                        },
                        child: provider.isQuizVisible
                            ? const QuizWidget(key: ValueKey('quiz'))
                            : const SizedBox.shrink(key: ValueKey('empty')),
                      ),

                      const SizedBox(height: PebloSpacing.xl),

                      // ── Reset button (only after quiz attempted) ──
                      if (provider.quizState == QuizState.correct)
                        _buildResetButton(context),
                      const SizedBox(height: PebloSpacing.lg),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  // ── Top bar ────────────────────────────────────────────────────────────────

  Widget _buildTopBar() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        // Peblo logo text
        RichText(
          text: const TextSpan(
            children: [
              TextSpan(
                text: 'peb',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.5,
                ),
              ),
              TextSpan(
                text: 'lo',
                style: TextStyle(
                  color: PebloColors.sunYellow,
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.5,
                ),
              ),
            ],
          ),
        ),
        // Points badge
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.15),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.white.withOpacity(0.3)),
          ),
          child: const Row(
            children: [
              Icon(Icons.star_rounded, color: PebloColors.sunYellow, size: 16),
              SizedBox(width: 4),
              Text(
                '0 XP',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ── Decorative floating stars ──────────────────────────────────────────────

  Widget _buildStarsRow() {
    return SizedBox(
      height: 20,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: List.generate(
          7,
          (i) => Icon(
            Icons.star_rounded,
            color: Colors.white.withOpacity(i % 2 == 0 ? 0.6 : 0.3),
            size: i % 3 == 0 ? 14 : 10,
          ),
        ),
      ),
    );
  }

  // ── Buddy name badge ───────────────────────────────────────────────────────

  Widget _buildBuddyBadge(StoryProvider provider) {
    String statusText;
    Color statusColor;

    switch (provider.audioState) {
      case AudioState.playing:
        statusText = '🔊 Reading the story...';
        statusColor = PebloColors.grassGreen;
        break;
      case AudioState.loading:
        statusText = '⏳ Getting ready...';
        statusColor = PebloColors.sunYellow;
        break;
      case AudioState.error:
        statusText = '😕 Something went wrong';
        statusColor = PebloColors.coralRed;
        break;
      default:
        statusText = provider.quizState == QuizState.correct
            ? '🎉 You did it!'
            : '👋 Hi! I am Pip!';
        statusColor = Colors.white;
    }

    return Column(
      children: [
        Text(
          statusText,
          style: TextStyle(
            color: statusColor,
            fontWeight: FontWeight.w700,
            fontSize: 15,
          ),
        ),
      ],
    );
  }

  // ── Reset / Play Again button ──────────────────────────────────────────────

  Widget _buildResetButton(BuildContext context) {
    return GestureDetector(
      onTap: () => context.read<StoryProvider>().reset(),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.15),
          borderRadius: BorderRadius.circular(30),
          border: Border.all(color: Colors.white.withOpacity(0.5), width: 2),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.refresh_rounded, color: Colors.white, size: 20),
            SizedBox(width: 8),
            Text(
              'Play Again',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
                fontSize: 16,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
