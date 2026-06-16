// lib/providers/story_provider.dart
// Central state manager using Provider.
// Manages: TTS lifecycle, audio states, quiz reveal, quiz interaction.

import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';
import '../models/quiz_question.dart';

// ─── Enums ──────────────────────────────────────────────────────────────────

enum AudioState {
  idle,       // Initial state — nothing happening
  loading,    // Preparing TTS engine
  playing,    // Actively narrating
  finished,   // Narration complete, quiz should reveal
  error,      // Something went wrong
}

enum QuizState {
  hidden,     // Quiz not yet revealed
  active,     // Child is answering
  wrong,      // Wrong answer submitted (triggers shake)
  correct,    // Correct answer! Celebration time
}

// ─── Provider ────────────────────────────────────────────────────────────────

class StoryProvider extends ChangeNotifier {
  // ── Private fields ──
  final FlutterTts _tts = FlutterTts();

  AudioState _audioState = AudioState.idle;
  QuizState _quizState = QuizState.hidden;
  String? _errorMessage;
  String? _selectedOption;
  int _wrongAttempts = 0;

  // ── The story content ──
  static const String storyText =
      'Once upon a time, a clever little robot named Pip lost his shiny blue gear '
      'in the Whispering Woods...';

  // ── The quiz — loaded from JSON, as if from backend ──
  // In production, this would come from an API call.
  final QuizQuestion _quiz = QuizQuestion.fromJson({
    'question': "What colour was Pip the Robot's lost gear?",
    'options': ['Red', 'Green', 'Blue', 'Yellow'],
    'answer': 'Blue',
  });

  // ── Getters ──
  AudioState get audioState => _audioState;
  QuizState get quizState => _quizState;
  String? get errorMessage => _errorMessage;
  String? get selectedOption => _selectedOption;
  int get wrongAttempts => _wrongAttempts;
  QuizQuestion get quiz => _quiz;
  String get storyContent => storyText;
  bool get isQuizVisible => _quizState != QuizState.hidden;

  // ─── Constructor: configure TTS engine ───────────────────────────────────

  StoryProvider() {
    _initTts();
  }

  Future<void> _initTts() async {
    // Optimise for children — warm, slightly slow English
    await _tts.setLanguage('en-IN'); // Indian English — familiar to target audience
    await _tts.setSpeechRate(0.48);  // Slightly slower for children
    await _tts.setVolume(1.0);
    await _tts.setPitch(1.1);        // Slightly higher pitch — more playful

    // Callbacks
    _tts.setStartHandler(() {
      _setAudioState(AudioState.playing);
    });

    _tts.setCompletionHandler(() {
      _setAudioState(AudioState.finished);
      // Reveal quiz after audio ends
      Future.delayed(const Duration(milliseconds: 600), () {
        _revealQuiz();
      });
    });

    _tts.setErrorHandler((msg) {
      _errorMessage = 'Oops! Could not play the story. Tap to try again.';
      _setAudioState(AudioState.error);
    });

    _tts.setCancelHandler(() {
      if (_audioState == AudioState.playing) {
        _setAudioState(AudioState.idle);
      }
    });
  }

  // ─── Public Actions ───────────────────────────────────────────────────────

  /// Called when the child taps "Read Me a Story".
  Future<void> startNarration() async {
    if (_audioState == AudioState.playing) return;

    _errorMessage = null;
    _setAudioState(AudioState.loading);

    try {
      // Small delay to show loading state — also lets TTS engine warm up
      await Future.delayed(const Duration(milliseconds: 300));

      final result = await _tts.speak(storyText);
      if (result != 1) {
        // speak() returns 1 on success
        throw Exception('TTS failed to start');
      }
    } catch (e) {
      _errorMessage = 'Could not play the story right now. Tap to try again! 🎙️';
      _setAudioState(AudioState.error);
    }
  }

  /// Stop narration mid-way if needed.
  Future<void> stopNarration() async {
    await _tts.stop();
    _setAudioState(AudioState.idle);
  }

  /// Called when child selects a quiz option.
  void selectOption(String option) {
    if (_quizState == QuizState.correct) return; // Prevent re-selection after win

    _selectedOption = option;

    if (_quiz.isCorrect(option)) {
      _quizState = QuizState.correct;
    } else {
      _wrongAttempts++;
      _quizState = QuizState.wrong;
      // Reset to active after shake animation completes
      Future.delayed(const Duration(milliseconds: 650), () {
        if (_quizState == QuizState.wrong) {
          _quizState = QuizState.active;
          notifyListeners();
        }
      });
    }

    notifyListeners();
  }

  /// Retry narration after an error.
  Future<void> retryNarration() async {
    _errorMessage = null;
    await startNarration();
  }

  /// Reset everything — useful for replay.
  Future<void> reset() async {
    await _tts.stop();
    _audioState = AudioState.idle;
    _quizState = QuizState.hidden;
    _errorMessage = null;
    _selectedOption = null;
    _wrongAttempts = 0;
    notifyListeners();
  }

  // ─── Private helpers ──────────────────────────────────────────────────────

  void _setAudioState(AudioState state) {
    _audioState = state;
    notifyListeners();
  }

  void _revealQuiz() {
    _quizState = QuizState.active;
    notifyListeners();
  }

  @override
  void dispose() {
    _tts.stop();
    super.dispose();
  }
}
