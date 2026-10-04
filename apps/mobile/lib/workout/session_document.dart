import 'dart:convert';

class LocalSessionException implements Exception {
  const LocalSessionException(this.code);

  final String code;

  @override
  String toString() => 'LocalSessionException: $code';
}

class SessionTempo {
  const SessionTempo({
    required this.eccentric,
    required this.pause,
    required this.concentric,
  });

  final int eccentric;
  final int pause;
  final int concentric;
}

class SessionExercise {
  const SessionExercise({
    required this.exerciseId,
    required this.repsDone,
    required this.setIndex,
    required this.sets,
    required this.reps,
    required this.skipped,
    required this.tempo,
  });

  final String exerciseId;
  final int repsDone;
  final int setIndex;
  final int sets;
  final int reps;
  final bool skipped;
  final SessionTempo tempo;
}

/// Stored manual session. Not a Drift row and not a clinical record.
class LocalSession {
  const LocalSession({
    required this.elapsedMs,
    required this.exercises,
    required this.monotonicMs,
    required this.outcome,
    required this.recordVersion,
    required this.reportedPain,
    required this.restUntilMs,
    required this.ruleId,
    required this.sessionId,
    required this.state,
    required this.symptom,
  });

  final int elapsedMs;
  final List<SessionExercise> exercises;
  final int monotonicMs;
  final String? outcome;
  final int recordVersion;
  final int? reportedPain;
  final int? restUntilMs;
  final String ruleId;
  final String sessionId;
  final String state;
  final String? symptom;

  static LocalSession decode(String raw) {
    final Object? parsed;
    try {
      parsed = jsonDecode(raw);
    } catch (_) {
      throw const LocalSessionException('document');
    }
    if (parsed is! Map) {
      throw const LocalSessionException('document');
    }
    final Map<String, Object?> json = _stringKeyMap(parsed, 'document');
    const Set<String> allowed = <String>{
      'elapsed_ms',
      'exercises',
      'monotonic_ms',
      'outcome',
      'record_version',
      'reported_pain',
      'rest_until_ms',
      'rule_id',
      'session_id',
      'state',
      'symptom',
    };
    if (json.length != allowed.length || !allowed.containsAll(json.keys)) {
      throw const LocalSessionException('document');
    }
    final String state = _string(json['state'], 'state');
    const Set<String> reachable = <String>{
      'preparing',
      'demonstrating',
      'active',
      'resting',
      'paused',
      'pain_check',
      'completed',
      'abandoned',
      'safety_stopped',
    };
    if (!reachable.contains(state)) {
      throw const LocalSessionException('state');
    }
    final String? outcome = _optionalString(json['outcome'], 'outcome');
    if (!_outcomeMatches(state, outcome)) {
      throw const LocalSessionException('outcome');
    }
    final int? pain = _optionalInt(json['reported_pain'], 'pain');
    if (pain != null && (pain < 0 || pain > 10)) {
      throw const LocalSessionException('pain');
    }
    final String? symptom = _optionalString(json['symptom'], 'symptom');
    const Set<String> symptoms = <String>{
      'mild_discomfort',
      'sharp_pain',
      'increased',
      'numbness_tingling',
      'weakness',
    };
    if (symptom != null && !symptoms.contains(symptom)) {
      throw const LocalSessionException('symptom');
    }
    final String sessionId = _string(json['session_id'], 'session');
    if (sessionId.isEmpty) {
      throw const LocalSessionException('session');
    }
    final List<SessionExercise> exercises = _exercises(json['exercises']);
    if (exercises.isEmpty) {
      throw const LocalSessionException('exercises');
    }
    final LocalSession session = LocalSession(
      elapsedMs: _nonNegative(json['elapsed_ms'], 'clock'),
      exercises: exercises,
      monotonicMs: _nonNegative(json['monotonic_ms'], 'clock'),
      outcome: outcome,
      recordVersion: _int(json['record_version'], 'record-version'),
      reportedPain: pain,
      restUntilMs: _optionalInt(json['rest_until_ms'], 'rest'),
      ruleId: _string(json['rule_id'], 'rule'),
      sessionId: sessionId,
      state: state,
      symptom: symptom,
    );
    if (session.recordVersion != 1 || session.ruleId != 'syn-program-core') {
      throw const LocalSessionException('rule');
    }
    final int? rest = session.restUntilMs;
    if (rest != null && rest < 0) {
      throw const LocalSessionException('rest');
    }
    return session;
  }
}

bool _outcomeMatches(String state, String? outcome) {
  const Map<String, String> terminal = <String, String>{
    'completed': 'completed',
    'abandoned': 'abandoned',
    'safety_stopped': 'safety_stopped',
  };
  final String? expected = terminal[state];
  if (expected == null) {
    return outcome == null;
  }
  return outcome == expected;
}

Map<String, Object?> _stringKeyMap(Map<dynamic, dynamic> parsed, String code) {
  final Map<String, Object?> json = <String, Object?>{};
  for (final MapEntry<Object?, Object?> entry in parsed.entries) {
    if (entry.key is! String) {
      throw LocalSessionException(code);
    }
    json[entry.key as String] = entry.value;
  }
  return json;
}

String _string(Object? value, String code) {
  if (value is! String) {
    throw LocalSessionException(code);
  }
  return value;
}

String? _optionalString(Object? value, String code) {
  if (value == null) {
    return null;
  }
  if (value is! String || value.isEmpty) {
    throw LocalSessionException(code);
  }
  return value;
}

int _int(Object? value, String code) {
  if (value is! int) {
    throw LocalSessionException(code);
  }
  return value;
}

int _nonNegative(Object? value, String code) {
  final int number = _int(value, code);
  if (number < 0) {
    throw LocalSessionException(code);
  }
  return number;
}

int? _optionalInt(Object? value, String code) {
  if (value == null) {
    return null;
  }
  return _int(value, code);
}

List<SessionExercise> _exercises(Object? value) {
  if (value is! List || value.isEmpty) {
    throw const LocalSessionException('exercises');
  }
  final List<SessionExercise> exercises = <SessionExercise>[];
  for (final Object? item in value) {
    if (item is! Map) {
      throw const LocalSessionException('exercise');
    }
    final Map<String, Object?> json = _stringKeyMap(item, 'exercise');
    const Set<String> allowed = <String>{
      'exercise_id',
      'reps',
      'reps_done',
      'set_index',
      'sets',
      'skipped',
      'tempo',
    };
    if (json.length != allowed.length || !allowed.containsAll(json.keys)) {
      throw const LocalSessionException('exercise');
    }
    final String exerciseId = _string(json['exercise_id'], 'exercise');
    final (int, int, int, int, int)? dose = _fixtureDoses[exerciseId];
    if (dose == null) {
      throw const LocalSessionException('exercise');
    }
    final Object? tempoValue = json['tempo'];
    if (tempoValue is! Map) {
      throw const LocalSessionException('tempo');
    }
    final Map<String, Object?> tempo = _stringKeyMap(tempoValue, 'tempo');
    const Set<String> tempoKeys = <String>{'concentric', 'eccentric', 'pause'};
    if (tempo.length != tempoKeys.length ||
        !tempoKeys.containsAll(tempo.keys)) {
      throw const LocalSessionException('tempo');
    }
    final Object? skipped = json['skipped'];
    if (skipped is! bool) {
      throw const LocalSessionException('exercise');
    }
    final int sets = _nonNegative(json['sets'], 'count');
    final int reps = _nonNegative(json['reps'], 'count');
    if (sets == 0 || reps == 0 || sets != dose.$1 || reps != dose.$2) {
      throw const LocalSessionException('count');
    }
    exercises.add(
      SessionExercise(
        exerciseId: exerciseId,
        repsDone: _u32(json['reps_done'], 'count'),
        setIndex: _u32(json['set_index'], 'count'),
        sets: sets,
        reps: reps,
        skipped: skipped,
        tempo: SessionTempo(
          eccentric: _matchingDose(tempo['eccentric'], dose.$3),
          pause: _matchingDose(tempo['pause'], dose.$4),
          concentric: _matchingDose(tempo['concentric'], dose.$5),
        ),
      ),
    );
  }
  return exercises;
}

/// Sets, reps, and tempo copied from the four committed fixtures.
const Map<String, (int, int, int, int, int)> _fixtureDoses =
    <String, (int, int, int, int, int)>{
      'syn-knee-sit-to-stand': (1, 1, 2, 1, 2),
      'syn-shoulder-band': (1, 1, 2, 1, 2),
      'syn-shoulder-isometric': (1, 1, 2, 1, 2),
      'syn-torso-pelvic-tilt': (1, 1, 2, 1, 2),
    };

int _u32(Object? value, String code) {
  final int number = _nonNegative(value, code);
  if (number > 4294967295) {
    throw LocalSessionException(code);
  }
  return number;
}

int _matchingDose(Object? value, int expected) {
  final int number = _nonNegative(value, 'tempo');
  if (number != expected) {
    throw const LocalSessionException('tempo');
  }
  return number;
}
