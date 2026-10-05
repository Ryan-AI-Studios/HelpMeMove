import 'dart:convert';

class AdaptationDocumentException implements Exception {
  const AdaptationDocumentException();
}

const String maintainReason = "Today's check keeps the same exercises.";
const String pauseReason =
    "Today's check says to wait. The exercises stay the same.";

class StoredAdaptation {
  const StoredAdaptation({
    required this.action,
    required this.reason,
    required this.sessionId,
  });

  final String action;
  final String reason;
  final String sessionId;

  static StoredAdaptation decode(String raw) {
    final Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } on FormatException {
      throw const AdaptationDocumentException();
    }
    if (decoded is! Map) {
      throw const AdaptationDocumentException();
    }
    const Set<String> keys = <String>{
      'action',
      'exercises',
      'reason',
      'record_version',
      'reported_pain',
      'rule_id',
      'rule_version',
      'session_id',
    };
    if (decoded.length != keys.length ||
        decoded.keys.any(
          (Object? key) => key is! String || !keys.contains(key),
        )) {
      throw const AdaptationDocumentException();
    }
    if (decoded['record_version'] != 1 ||
        decoded['rule_version'] != 1 ||
        decoded['rule_id'] != 'syn-adaptation-core') {
      throw const AdaptationDocumentException();
    }
    final Object? action = decoded['action'];
    final Object? reason = decoded['reason'];
    final Object? sessionId = decoded['session_id'];
    if (action is! String || reason is! String || sessionId is! String) {
      throw const AdaptationDocumentException();
    }
    if (sessionId.isEmpty) {
      throw const AdaptationDocumentException();
    }
    if (action == 'maintain' && reason != maintainReason) {
      throw const AdaptationDocumentException();
    }
    if (action == 'pause_today' && reason != pauseReason) {
      throw const AdaptationDocumentException();
    }
    if (action != 'maintain' && action != 'pause_today') {
      throw const AdaptationDocumentException();
    }
    _requireExercises(decoded['exercises']);
    final Object? pain = decoded['reported_pain'];
    if (pain != null && (pain is! int || pain < 0 || pain > 10)) {
      throw const AdaptationDocumentException();
    }
    return StoredAdaptation(
      action: action,
      reason: reason,
      sessionId: sessionId,
    );
  }
}

void _requireExercises(Object? exercises) {
  if (exercises is! List) {
    throw const AdaptationDocumentException();
  }
  const Set<String> keys = <String>{'exercise_id', 'reps', 'sets', 'tempo'};
  const Set<String> tempoKeys = <String>{'concentric', 'eccentric', 'pause'};
  for (final Object? entry in exercises) {
    if (entry is! Map ||
        entry.length != keys.length ||
        entry.keys.any(
          (Object? key) => key is! String || !keys.contains(key),
        )) {
      throw const AdaptationDocumentException();
    }
    final Object? exerciseId = entry['exercise_id'];
    if (exerciseId is! String || exerciseId.isEmpty) {
      throw const AdaptationDocumentException();
    }
    _nonNegative(entry['sets']);
    _nonNegative(entry['reps']);
    final Object? tempo = entry['tempo'];
    if (tempo is! Map ||
        tempo.length != tempoKeys.length ||
        tempo.keys.any(
          (Object? key) => key is! String || !tempoKeys.contains(key),
        )) {
      throw const AdaptationDocumentException();
    }
    _nonNegative(tempo['eccentric']);
    _nonNegative(tempo['pause']);
    _nonNegative(tempo['concentric']);
  }
}

void _nonNegative(Object? value) {
  if (value is! int || value < 0) {
    throw const AdaptationDocumentException();
  }
}

void decodeReadiness(String raw, {required String sessionId}) {
  final Object? decoded;
  try {
    decoded = jsonDecode(raw);
  } on FormatException {
    throw const AdaptationDocumentException();
  }
  if (decoded is! Map) {
    throw const AdaptationDocumentException();
  }
  const Set<String> keys = <String>{
    'record_version',
    'recorded_at_ms',
    'rule_id',
    'rule_version',
    'session_id',
    'soreness',
  };
  if (decoded.length != keys.length ||
      decoded.keys.any(
        (Object? key) => key is! String || !keys.contains(key),
      )) {
    throw const AdaptationDocumentException();
  }
  final Object? recordedAt = decoded['recorded_at_ms'];
  final Object? storedSession = decoded['session_id'];
  final Object? soreness = decoded['soreness'];
  if (decoded['record_version'] != 1 ||
      decoded['rule_version'] != 1 ||
      decoded['rule_id'] != 'syn-adaptation-core' ||
      recordedAt is! int ||
      recordedAt < 0 ||
      storedSession != sessionId ||
      (soreness != 'low' && soreness != 'moderate' && soreness != 'high')) {
    throw const AdaptationDocumentException();
  }
}
