// lib/widgets/story_card.dart
// Displays the story text and the "Read Me a Story" button.
// Handles all audio states: idle, loading, playing, error, finished.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/story_provider.dart';
import '../utils/app_theme.dart';

class StoryCard extends StatelessWidget {
  const StoryCard({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<StoryProvider>(
      builder: (context, provider, _) {
        return Container(
          width: double.infinity,
          decoration: BoxDecoration(
            color: PebloColors.storyCardBg,
            borderRadius: PebloRadius.card,
            border: Border.all(
              color: PebloColors.storyCardBorder,
              width: 2.5,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.15),
                blurRadius: 20,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          padding: const EdgeInsets.all(PebloSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Header row ──
              Row(
                children: [
                  const Icon(Icons.auto_stories_rounded,
                      color: PebloColors.deepBlue, size: 22),
                  const SizedBox(width: 8),
                  Text(
                    'Story Time ✨',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: PebloColors.deepBlue,
                      letterSpacing: 0.5,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: PebloSpacing.md),

              // ── Story text ──
              Text(
                provider.storyContent,
                style: PebloTextStyles.storyText,
              ),
              const SizedBox(height: PebloSpacing.lg),

              // ── CTA Button ──
              _buildButton(context, provider),

              // ── Error message ──
              if (provider.audioState == AudioState.error &&
                  provider.errorMessage != null)
                Padding(
                  padding: const EdgeInsets.only(top: PebloSpacing.md),
                  child: _buildErrorBanner(provider.errorMessage!),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildButton(BuildContext context, StoryProvider provider) {
    final state = provider.audioState;
    final isDisabled = state == AudioState.loading || state == AudioState.playing;

    String label;
    IconData icon;
    Color color;

    switch (state) {
      case AudioState.idle:
        label = 'Read Me a Story! 🎙️';
        icon = Icons.play_circle_filled_rounded;
        color = PebloColors.deepBlue;
        break;
      case AudioState.loading:
        label = 'Getting ready...';
        icon = Icons.hourglass_top_rounded;
        color = PebloColors.textMuted;
        break;
      case AudioState.playing:
        label = 'Listening... 🔊';
        icon = Icons.graphic_eq_rounded;
        color = PebloColors.grassGreen;
        break;
      case AudioState.finished:
        label = 'Play Again 🔁';
        icon = Icons.replay_rounded;
        color = PebloColors.warmOrange;
        break;
      case AudioState.error:
        label = 'Try Again 🔄';
        icon = Icons.refresh_rounded;
        color = PebloColors.coralRed;
        break;
    }

    return SizedBox(
      width: double.infinity,
      height: 54,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        decoration: BoxDecoration(
          borderRadius: PebloRadius.button,
          gradient: isDisabled
              ? null
              : LinearGradient(
                  colors: [color, color.withOpacity(0.8)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
          color: isDisabled ? Colors.grey.shade300 : null,
          boxShadow: isDisabled
              ? []
              : [
                  BoxShadow(
                    color: color.withOpacity(0.4),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: PebloRadius.button,
            onTap: isDisabled
                ? null
                : () {
                    if (state == AudioState.error) {
                      context.read<StoryProvider>().retryNarration();
                    } else {
                      context.read<StoryProvider>().startNarration();
                    }
                  },
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Spinner for loading, icon otherwise
                if (state == AudioState.loading)
                  const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      color: PebloColors.textMuted,
                    ),
                  )
                else
                  Icon(icon,
                      color: isDisabled ? PebloColors.textMuted : Colors.white,
                      size: 22),
                const SizedBox(width: 10),
                Text(
                  label,
                  style: PebloTextStyles.buttonText.copyWith(
                    color: isDisabled ? PebloColors.textMuted : Colors.white,
                    fontSize: 16,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildErrorBanner(String message) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: PebloColors.coralRed.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: PebloColors.coralRed.withOpacity(0.4)),
      ),
      child: Row(
        children: [
          const Icon(Icons.warning_amber_rounded,
              color: PebloColors.coralRed, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                color: PebloColors.coralRed,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
