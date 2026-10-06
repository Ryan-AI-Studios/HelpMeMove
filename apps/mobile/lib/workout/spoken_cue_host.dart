import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_tts/flutter_tts.dart';

/// Speech seam. Widget tests supply a fake and never construct [FlutterTts].
abstract class SpokenCueHost {
  Future<void> speak(String text);

  Future<void> stop();
}

/// One [FlutterTts] for the three session titles.
///
/// A speak result other than 1, an engine error, or any thrown [Object] is
/// ignored here. The caption and the session stay as the workout left them.
class FlutterSpokenCueHost implements SpokenCueHost {
  FlutterSpokenCueHost({this._configure, this._speakText});

  /// Test seam. Production leaves this null and configures one [FlutterTts].
  ///
  /// A list is the shared-instance result and then the category result.
  /// Null stands for a swallowed platform error.
  final Future<List<Object?>?> Function()? _configure;

  /// Test seam. Production leaves this null and speaks through [FlutterTts].
  final Future<Object?> Function(String text)? _speakText;

  FlutterTts? _engine;
  Future<void>? _opening;
  int _generation = 0;

  Future<void> _engineOnce() {
    final Future<void>? existing = _opening;
    if (existing != null) {
      return existing;
    }
    final Future<void> created = _open();
    _opening = created;
    return created;
  }

  Future<void> _open() async {
    if (_configure != null) {
      final List<Object?>? results = await _configure();
      if (!_accepted(results)) {
        throw StateError('setup');
      }
      return;
    }
    final FlutterTts created = FlutterTts();
    created.setErrorHandler((dynamic _) {});
    if (!kIsWeb && Platform.isIOS) {
      final Object? shared = await created.setSharedInstance(true);
      final Object? category = await created.setIosAudioCategory(
        IosTextToSpeechAudioCategory.playback,
        <IosTextToSpeechAudioCategoryOptions>[
          IosTextToSpeechAudioCategoryOptions.duckOthers,
          IosTextToSpeechAudioCategoryOptions
              .interruptSpokenAudioAndMixWithOthers,
        ],
        IosTextToSpeechAudioMode.voicePrompt,
      );
      if (shared != 1 || category != 1) {
        throw StateError('setup');
      }
    }
    _engine = created;
  }

  bool _accepted(List<Object?>? results) {
    return results != null &&
        results.length == 2 &&
        results[0] == 1 &&
        results[1] == 1;
  }

  @override
  Future<void> speak(String text) async {
    final int generation = ++_generation;
    try {
      await _engineOnce();
      if (generation != _generation) {
        return;
      }
      if (_speakText != null) {
        final Object? result = await _speakText(text);
        if (result != 1) {
          return;
        }
        return;
      }
      final FlutterTts? engine = _engine;
      if (engine == null || generation != _generation) {
        return;
      }
      await engine.stop();
      if (generation != _generation) {
        return;
      }
      final Object? result = (!kIsWeb && Platform.isAndroid)
          ? await engine.speak(text, focus: true)
          : await engine.speak(text);
      if (result != 1) {
        return;
      }
    } catch (_) {
      return;
    }
  }

  @override
  Future<void> stop() async {
    _generation++;
    final FlutterTts? engine = _engine;
    if (engine == null) {
      return;
    }
    try {
      await engine.stop();
    } catch (_) {
      return;
    }
  }
}
