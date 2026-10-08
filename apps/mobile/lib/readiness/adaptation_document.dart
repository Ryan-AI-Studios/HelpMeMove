import 'dart:convert';

class AdaptationDocumentException implements Exception {
  const AdaptationDocumentException();
}

const String maintainReason = "Today's check keeps the same exercises.";
const String fitnessWithheldSentence =
    'This synthetic plan is not a general fitness program.';
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

class StoredFlareFollowup {
  const StoredFlareFollowup({
    required this.action,
    required this.reason,
    required this.sessionId,
    required this.choice,
  });

  final String action;
  final String reason;
  final String sessionId;
  final String choice;

  static StoredFlareFollowup decode(String raw) {
    final Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } on FormatException {
      throw const AdaptationDocumentException();
    }
    if (decoded is! Map) {
      throw const AdaptationDocumentException();
    }
    const Set<String> keys = <String>{'decision', 'followup', 'record_version'};
    if (decoded.length != keys.length ||
        decoded.keys.any(
          (Object? key) => key is! String || !keys.contains(key),
        )) {
      throw const AdaptationDocumentException();
    }
    if (decoded['record_version'] != 1) {
      throw const AdaptationDocumentException();
    }
    final String sessionId = _followupSession(decoded['followup']);
    final StoredAdaptation decision = _decision(decoded['decision']);
    if (decision.sessionId != sessionId) {
      throw const AdaptationDocumentException();
    }
    final Object? followup = decoded['followup'];
    if (followup is! Map) {
      throw const AdaptationDocumentException();
    }
    final Object? choice = followup['choice'];
    if (choice is! String) {
      throw const AdaptationDocumentException();
    }
    if (choice == 'worse_today') {
      if (decision.action != 'pause_today') {
        throw const AdaptationDocumentException();
      }
    } else if (decision.action != 'keep_program') {
      throw const AdaptationDocumentException();
    }
    return StoredFlareFollowup(
      action: decision.action,
      reason: decision.reason,
      sessionId: sessionId,
      choice: choice,
    );
  }
}

String _followupSession(Object? followup) {
  if (followup is! Map) {
    throw const AdaptationDocumentException();
  }
  const Set<String> keys = <String>{
    'choice',
    'record_version',
    'recorded_at_ms',
    'rule_id',
    'rule_version',
    'session_id',
  };
  if (followup.length != keys.length ||
      followup.keys.any(
        (Object? key) => key is! String || !keys.contains(key),
      )) {
    throw const AdaptationDocumentException();
  }
  final Object? recordedAt = followup['recorded_at_ms'];
  final Object? sessionId = followup['session_id'];
  final Object? choice = followup['choice'];
  if (followup['record_version'] != 1 ||
      followup['rule_version'] != 1 ||
      followup['rule_id'] != 'syn-flare-core' ||
      recordedAt is! int ||
      recordedAt < 0 ||
      sessionId is! String ||
      sessionId.isEmpty ||
      (choice != 'worse_today' && choice != 'same' && choice != 'settled')) {
    throw const AdaptationDocumentException();
  }
  return sessionId;
}

StoredAdaptation _decision(Object? decision) {
  if (decision is! Map) {
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
  if (decision.length != keys.length ||
      decision.keys.any(
        (Object? key) => key is! String || !keys.contains(key),
      )) {
    throw const AdaptationDocumentException();
  }
  if (decision['record_version'] != 1 ||
      decision['rule_version'] != 1 ||
      decision['rule_id'] != 'syn-flare-core') {
    throw const AdaptationDocumentException();
  }
  final Object? action = decision['action'];
  final Object? reason = decision['reason'];
  final Object? sessionId = decision['session_id'];
  if (action is! String || reason is! String || sessionId is! String) {
    throw const AdaptationDocumentException();
  }
  if (sessionId.isEmpty) {
    throw const AdaptationDocumentException();
  }
  if (action == 'keep_program' && reason != maintainReason) {
    throw const AdaptationDocumentException();
  }
  if (action == 'pause_today' && reason != pauseReason) {
    throw const AdaptationDocumentException();
  }
  if (action != 'keep_program' && action != 'pause_today') {
    throw const AdaptationDocumentException();
  }
  _requireExercises(decision['exercises']);
  final Object? pain = decision['reported_pain'];
  if (pain != null && (pain is! int || pain < 0 || pain > 10)) {
    throw const AdaptationDocumentException();
  }
  return StoredAdaptation(action: action, reason: reason, sessionId: sessionId);
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

class StoredProgressSummary {
  const StoredProgressSummary({
    required this.abandonedCount,
    required this.completedCount,
    required this.copiedPain,
    required this.safetyStoppedCount,
  });

  final int abandonedCount;
  final int completedCount;
  final int? copiedPain;
  final int safetyStoppedCount;

  bool get countsAreZero =>
      abandonedCount == 0 && completedCount == 0 && safetyStoppedCount == 0;

  static StoredProgressSummary decode(String raw) {
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
      'abandoned_count',
      'completed_count',
      'copied_pain',
      'record_version',
      'rule_id',
      'rule_version',
      'safety_stopped_count',
    };
    if (decoded.length != keys.length ||
        decoded.keys.any(
          (Object? key) => key is! String || !keys.contains(key),
        )) {
      throw const AdaptationDocumentException();
    }
    if (decoded['record_version'] != 1 ||
        decoded['rule_version'] != 1 ||
        decoded['rule_id'] != 'syn-progress-core') {
      throw const AdaptationDocumentException();
    }
    return StoredProgressSummary(
      abandonedCount: _progressCount(decoded['abandoned_count']),
      completedCount: _progressCount(decoded['completed_count']),
      copiedPain: _copiedPain(decoded['copied_pain']),
      safetyStoppedCount: _progressCount(decoded['safety_stopped_count']),
    );
  }
}

int _progressCount(Object? value) {
  if (value is! int || value < 0 || value > 2147483647) {
    throw const AdaptationDocumentException();
  }
  return value;
}

int? _copiedPain(Object? value) {
  if (value == null) {
    return null;
  }
  if (value is! int || value < 0 || value > 10) {
    throw const AdaptationDocumentException();
  }
  return value;
}
