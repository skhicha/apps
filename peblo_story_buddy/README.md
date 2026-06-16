# 🤖 Peblo Story Buddy — Intern Challenge Submission

> *An AI-powered story narration and quiz app for children, built with Flutter.*

---

## Framework Choice: Flutter ✅

**Why Flutter over Swift?**

Peblo's primary audience is children in India on mid-range Android devices (~3GB RAM). Flutter was the natural choice because:

- **Single codebase** covers both Android (primary) and iOS — maximum reach with one implementation.
- **Dart's AOT compilation** produces fast, native-like performance on mid-range hardware.
- **Widget tree rebuilds** are surgical with `Consumer<T>` and `Selector<T>` from Provider — only the widgets that need to change actually repaint.
- **`flutter_tts`** wraps both `TextToSpeech` on Android and `AVSpeechSynthesizer` on iOS — no platform channels needed.
- Flutter's **Impeller rendering engine** (enabled by default in recent Flutter versions) keeps animations at a consistent 60fps even on weaker GPUs.

---

## Architecture: Provider State Management

The entire app flows through a single `StoryProvider` (`lib/providers/story_provider.dart`):

```
PebloApp
  └── ChangeNotifierProvider<StoryProvider>
        └── StoryScreen
              ├── Consumer → BuddyCharacter   (audio + quiz state → expressions)
              ├── Consumer → StoryCard        (audio state → button label/style)
              └── Consumer → QuizWidget       (quiz state → options, shake, confetti)
```

**State enums:**

```dart
enum AudioState { idle, loading, playing, finished, error }
enum QuizState  { hidden, active, wrong, correct }
```

Every widget reads exactly the state it needs. `Consumer<StoryProvider>` is scoped so a quiz state change never triggers a story card rebuild, and vice versa.

---

## Audio → Quiz Transition

The transition between narration ending and the quiz appearing is handled entirely in `StoryProvider`:

```dart
_tts.setCompletionHandler(() {
  _setAudioState(AudioState.finished);
  Future.delayed(const Duration(milliseconds: 600), () {
    _revealQuiz(); // sets quizState = QuizState.active
  });
});
```

The 600ms delay is intentional — it gives the child a breath between the story ending and the quiz appearing, rather than an abrupt switch. In `StoryScreen`, the quiz is wrapped in an `AnimatedSwitcher` with a fade + slide transition:

```dart
AnimatedSwitcher(
  duration: const Duration(milliseconds: 400),
  child: provider.isQuizVisible
      ? const QuizWidget(key: ValueKey('quiz'))
      : const SizedBox.shrink(key: ValueKey('empty')),
)
```

`QuizWidget` itself plays an additional slide-up + fade animation on first build, giving a two-stage reveal that feels smooth and intentional.

---

## Data-Driven Quiz Renderer

The quiz is **never hardcoded** in the UI. The `QuizQuestion` model parses from raw JSON:

```dart
// lib/models/quiz_question.dart
factory QuizQuestion.fromJson(Map<String, dynamic> json) {
  return QuizQuestion(
    question: json['question'] as String,
    options: List<String>.from(json['options'] as List),
    answer:   json['answer'] as String,
  );
}
```

In `StoryProvider`, the quiz is loaded as if it came from Peblo's backend:

```dart
final QuizQuestion _quiz = QuizQuestion.fromJson({
  "question": "What colour was Pip the Robot's lost gear?",
  "options":  ["Red", "Green", "Blue", "Yellow"],
  "answer":   "Blue"
});
```

In `QuizWidget`, options are rendered with a **`List.generate`**:

```dart
...List.generate(quiz.options.length, (index) {
  return _OptionButton(label: quiz.options[index], ...);
})
```

**This means:**
- A JSON with 3 options → 3 buttons rendered. ✅
- A JSON with 5 options → 5 buttons rendered. ✅
- A completely different question and answer → works with zero code changes. ✅

To switch to live data, replace the hardcoded map with an `http.get()` call and call `QuizQuestion.fromJson(response.data)`.

---

## Audio Loading & Failure States

`AudioState` covers every real-world scenario:

| State | What the user sees |
|---|---|
| `idle` | "Read Me a Story! 🎙️" button, bright blue |
| `loading` | Spinner + "Getting ready..." — TTS engine warming up |
| `playing` | "Listening... 🔊" — disabled button so child can't interrupt |
| `finished` | "Play Again 🔁" — orange replay button |
| `error` | Red "Try Again 🔄" + friendly error banner explaining what went wrong |

The error path:
```dart
_tts.setErrorHandler((msg) {
  _errorMessage = 'Oops! Could not play the story. Tap to try again.';
  _setAudioState(AudioState.error);
});
```

A retry calls `retryNarration()` which resets error state and re-invokes `startNarration()`. The app **never hangs or crashes** — all TTS calls are wrapped in try/catch.

---

## Caching Approach

**Current implementation (device TTS):** Device TTS synthesis is on-device — no network, no caching needed. Audio is synthesized in real-time from text.

**If ElevenLabs (or any remote audio) were integrated:**

```dart
// Pseudocode for remote audio caching
Future<File> _getCachedAudio(String text) async {
  final cacheDir = await getApplicationCacheDirectory();
  final key = md5(text); // Hash the text as cache key
  final file = File('${cacheDir.path}/$key.mp3');
  
  if (await file.exists()) return file; // Cache hit — no network call
  
  final bytes = await ElevenLabsApi.synthesize(text); // Cache miss
  await file.writeAsBytes(bytes);
  return file;
}
```

This ensures the story is only downloaded once. On subsequent plays, the cached `.mp3` is used — critical for mid-range devices on slow connections.

---

## Performance on Mid-Range Android Devices

Several deliberate choices to stay lightweight:

### 1. No image assets for Pip
Pip the Robot is drawn with `CustomPainter` — pure vector shapes on a `Canvas`. No PNG/WebP assets to decode, no memory spikes. Renders crisply on any DPI.

### 2. Minimal widget rebuilds
`Consumer<StoryProvider>` wraps only the subtree that needs to react. A quiz state change (`QuizState.wrong`) triggers a rebuild only in `QuizWidget`, not in `StoryCard` or `BuddyCharacter`.

### 3. Animations at 60fps
- Shake: `TweenSequence` with a `AnimationController` — runs on the UI thread without `setState`.
- Bob/float: `repeat(reverse: true)` — continuous, lightweight.
- Confetti: `confetti` package uses a particle system; capped at 30 particles (`numberOfParticles: 30`) to avoid overloading the GPU.

### 4. No unnecessary packages
Dependencies are minimal: `provider`, `flutter_tts`, `confetti`, `vibration`. No heavy image loading, no Firebase, no analytics SDK dragging in megabytes.

### 5. `BouncingScrollPhysics`
Smooth on all devices, no janky `ClampingScrollPhysics` stutters.

### Performance profiling approach
To profile on a mid-range device (e.g., a Redmi Note 11 equivalent):
```bash
flutter run --profile
# Then open DevTools: flutter pub global run devtools
```
Key metrics to watch:
- **Frame build time** < 16ms (60fps target)
- **Widget rebuild count** during quiz interaction
- **Memory** — check for leaks with `AnimationController.dispose()` calls (all controllers are disposed in `_QuizWidgetState.dispose()` and `_BuddyCharacterState.dispose()`)

---

## AI Usage & Judgment

I used AI assistance (Claude) at several points:

**Where AI helped:**
- Scaffolding the `TweenSequence` for the shake animation — getting the left/right oscillation weights right on first try.
- Drafting the `CustomPainter` mouth path for Pip's expressions.

**One suggestion I rejected:**
AI suggested using `flutter_animate` for all animations instead of raw `AnimationController`. I rejected this because:
- `flutter_animate` is a convenience layer that adds another dependency.
- For a children's app targeting low-RAM devices, I want full control over when controllers are disposed and how animations share `TickerProviderStateMixin` state. Explicit controllers are more predictable and easier to debug in DevTools.

**What didn't work initially:**
The `_tts.setCompletionHandler` was firing immediately on Android in some emulator configurations before audio actually played. I fixed this by checking that `_audioState == AudioState.playing` before accepting the completion signal, and adding the 300ms loading delay to give the TTS engine time to initialise.

---

## Running the App

```bash
# 1. Clone the repo
git clone https://github.com/<your-username>/peblo-story-buddy.git
cd peblo-story-buddy

# 2. Install dependencies
flutter pub get

# 3. Run on connected device / emulator
flutter run

# 4. Run in release mode (closer to real-device performance)
flutter run --release
```

**Minimum requirements:**
- Flutter 3.19+
- Dart 3.0+
- Android API 21+ (Android 5.0 Lollipop and above)
- iOS 13+

---

## Project Structure

```
lib/
├── main.dart                    # App entry point, Provider setup
├── models/
│   └── quiz_question.dart       # Data model — JSON ↔ QuizQuestion
├── providers/
│   └── story_provider.dart      # All state: TTS, audio, quiz
├── screens/
│   └── story_screen.dart        # Single-screen UI layout
├── utils/
│   └── app_theme.dart           # Colors, typography, spacing constants
└── widgets/
    ├── buddy_character.dart      # Pip the Robot (CustomPainter + animations)
    ├── story_card.dart           # Story text + TTS button, all audio states
    └── quiz_widget.dart          # Data-driven quiz, shake, confetti
```

---

## What I'd Add With More Time

1. **ElevenLabs integration** with the caching strategy above — richer, more expressive narration voice for children.
2. **Local persistence** of XP/score across sessions using `shared_preferences`.
3. **Accessibility**: `Semantics` labels on all interactive elements for screen readers.
4. **Localization**: Hindi and regional language support — `flutter_localizations` + ARB files.
5. **Golden tests** for widget snapshots, and integration tests using `flutter_test`.

---

*Built with care for Peblo's mission: making learning joyful for every child.* 🚀
