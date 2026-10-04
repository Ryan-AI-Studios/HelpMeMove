import 'dart:convert';

import 'package:helpmemove/src/rust/api/bridge.dart';

class LocalProgramException implements Exception {
  const LocalProgramException(this.code);

  final String code;

  @override
  String toString() => 'LocalProgramException: $code';
}

class ProgramReason {
  const ProgramReason({
    required this.code,
    this.region,
    this.equipment,
    this.goal,
  });

  final String code;
  final String? region;
  final String? equipment;
  final String? goal;
}

class ProgramTempo {
  const ProgramTempo({
    required this.eccentric,
    required this.pause,
    required this.concentric,
  });

  final int eccentric;
  final int pause;
  final int concentric;
}

class ProgramExercise {
  const ProgramExercise({
    required this.exerciseId,
    required this.exerciseVersion,
    required this.regions,
    required this.sets,
    required this.reps,
    required this.tempo,
    required this.reasons,
  });

  final String exerciseId;
  final int exerciseVersion;
  final List<String> regions;
  final int sets;
  final int reps;
  final ProgramTempo tempo;
  final List<ProgramReason> reasons;

  void validate() {
    if (exerciseId.isEmpty || exerciseVersion != 1) {
      throw const LocalProgramException('exercise');
    }
    if (regions.isEmpty) {
      throw const LocalProgramException('regions');
    }
    for (final String region in regions) {
      _acceptRegion(region);
    }
    _count(sets);
    _count(reps);
    _count(tempo.eccentric);
    _count(tempo.pause);
    _count(tempo.concentric);
    const List<String> codes = <String>[
      'region_match',
      'equipment_match',
      'goal_match',
      'screen_clear',
      'fixture_defaults',
    ];
    if (reasons.length != codes.length) {
      throw const LocalProgramException('reason');
    }
    for (int index = 0; index < codes.length; index++) {
      _checkReason(reasons[index], codes[index]);
    }
  }
}

/// Stored starting plan. Not a Drift row and not an intake document.
class LocalProgram {
  LocalProgram({
    required this.recordVersion,
    required this.ruleId,
    required this.ruleVersion,
    required this.safetyRuleId,
    required this.safetyRuleVersion,
    required this.sessionMinutes,
    required this.exercises,
  });

  final int recordVersion;
  final String ruleId;
  final int ruleVersion;
  final String safetyRuleId;
  final int safetyRuleVersion;
  final int sessionMinutes;
  final List<ProgramExercise> exercises;

  void validate() {
    if (recordVersion != 1) {
      throw const LocalProgramException('record-version');
    }
    if (ruleId != 'syn-program-core' || ruleVersion != 1) {
      throw const LocalProgramException('rule');
    }
    if (safetyRuleId != 'syn-safety-core' || safetyRuleVersion != 1) {
      throw const LocalProgramException('rule');
    }
    if (sessionMinutes != 15) {
      throw const LocalProgramException('session');
    }
    if (exercises.isEmpty) {
      throw const LocalProgramException('exercises');
    }
    for (final ProgramExercise exercise in exercises) {
      exercise.validate();
    }
  }

  static LocalProgram decode(String raw) {
    final Object? parsed;
    try {
      parsed = jsonDecode(raw);
    } catch (_) {
      throw const LocalProgramException('document');
    }
    if (parsed is! Map) {
      throw const LocalProgramException('document');
    }
    final Map<String, Object?> json = _stringKeyMap(parsed, 'document');
    const Set<String> allowed = <String>{
      'record_version',
      'rule_id',
      'rule_version',
      'safety_rule_id',
      'safety_rule_version',
      'session_minutes',
      'exercises',
    };
    if (json.length != allowed.length || !allowed.containsAll(json.keys)) {
      throw const LocalProgramException('document');
    }
    final LocalProgram program = LocalProgram(
      recordVersion: _int(json['record_version'], 'record-version'),
      ruleId: _string(json['rule_id'], 'rule'),
      ruleVersion: _int(json['rule_version'], 'rule'),
      safetyRuleId: _string(json['safety_rule_id'], 'rule'),
      safetyRuleVersion: _int(json['safety_rule_version'], 'rule'),
      sessionMinutes: _int(json['session_minutes'], 'session'),
      exercises: _exercises(json['exercises']),
    );
    program.validate();
    return program;
  }
}

const String programNotice =
    'syn-program-core is a synthetic fixture. It is not a medical program.';

const String programSessionLine = 'About 15 minutes/session';

String programCounts(ProgramExercise exercise) {
  return '${exercise.sets} \u00D7 ${exercise.reps}';
}

String programTokenLabel(String token) {
  if (token == 'head_neck') {
    return 'Head and neck';
  }
  final String spaced = token.replaceAll('_', ' ');
  if (spaced.isEmpty) {
    return token;
  }
  return spaced[0].toUpperCase() + spaced.substring(1);
}

List<String> programReasonSentences(ProgramExercise exercise) {
  if (exercise.reasons.length != 5) {
    return const <String>[];
  }
  final String? region = exercise.reasons[0].region;
  final String? equipment = exercise.reasons[1].equipment;
  final String? goal = exercise.reasons[2].goal;
  if (region == null || equipment == null || goal == null) {
    return const <String>[];
  }
  return <String>[
    'Included because the saved check lists ${programTokenLabel(region)}.',
    'Included because the saved equipment includes ${programTokenLabel(equipment)}.',
    'Included because the saved goal includes ${programTokenLabel(goal)}.',
    'The synthetic rule did not reject this exercise.',
    'The counts are the synthetic fixture defaults, not a prescription.',
  ];
}

Map<String, Object?> _stringKeyMap(Map<dynamic, dynamic> parsed, String code) {
  final Map<String, Object?> json = <String, Object?>{};
  for (final MapEntry<Object?, Object?> entry in parsed.entries) {
    if (entry.key is! String) {
      throw LocalProgramException(code);
    }
    json[entry.key as String] = entry.value;
  }
  return json;
}

String _string(Object? value, String code) {
  if (value is! String) {
    throw LocalProgramException(code);
  }
  return value;
}

int _int(Object? value, String code) {
  if (value is! int) {
    throw LocalProgramException(code);
  }
  return value;
}

void _count(int value) {
  if (value < 0) {
    throw const LocalProgramException('count');
  }
}

List<ProgramExercise> _exercises(Object? value) {
  if (value is! List) {
    throw const LocalProgramException('exercises');
  }
  final List<ProgramExercise> exercises = <ProgramExercise>[];
  for (final Object? item in value) {
    if (item is! Map) {
      throw const LocalProgramException('exercise');
    }
    final Map<String, Object?> json = _stringKeyMap(item, 'exercise');
    const Set<String> allowed = <String>{
      'exercise_id',
      'exercise_version',
      'regions',
      'sets',
      'reps',
      'tempo',
      'reasons',
    };
    if (json.length != allowed.length || !allowed.containsAll(json.keys)) {
      throw const LocalProgramException('exercise');
    }
    final String exerciseId = _string(json['exercise_id'], 'exercise');
    if (exerciseId.isEmpty) {
      throw const LocalProgramException('exercise');
    }
    exercises.add(
      ProgramExercise(
        exerciseId: exerciseId,
        exerciseVersion: _int(json['exercise_version'], 'exercise'),
        regions: _regions(json['regions']),
        sets: _int(json['sets'], 'count'),
        reps: _int(json['reps'], 'count'),
        tempo: _tempo(json['tempo']),
        reasons: _reasons(json['reasons']),
      ),
    );
  }
  return exercises;
}

List<String> _regions(Object? value) {
  if (value is! List || value.isEmpty) {
    throw const LocalProgramException('regions');
  }
  final List<String> regions = <String>[];
  for (final Object? item in value) {
    if (item is! String) {
      throw const LocalProgramException('regions');
    }
    regions.add(_acceptRegion(item));
  }
  return regions;
}

ProgramTempo _tempo(Object? value) {
  if (value is! Map) {
    throw const LocalProgramException('tempo');
  }
  final Map<String, Object?> json = _stringKeyMap(value, 'tempo');
  const Set<String> allowed = <String>{'eccentric', 'pause', 'concentric'};
  if (json.length != allowed.length || !allowed.containsAll(json.keys)) {
    throw const LocalProgramException('tempo');
  }
  return ProgramTempo(
    eccentric: _int(json['eccentric'], 'count'),
    pause: _int(json['pause'], 'count'),
    concentric: _int(json['concentric'], 'count'),
  );
}

List<ProgramReason> _reasons(Object? value) {
  if (value is! List) {
    throw const LocalProgramException('reason');
  }
  final List<ProgramReason> reasons = <ProgramReason>[];
  for (final Object? item in value) {
    if (item is! Map) {
      throw const LocalProgramException('reason');
    }
    final Map<String, Object?> json = _stringKeyMap(item, 'reason');
    const Set<String> allowed = <String>{'code', 'region', 'equipment', 'goal'};
    if (json.length != allowed.length || !allowed.containsAll(json.keys)) {
      throw const LocalProgramException('reason');
    }
    final String? code = json['code'] is String ? json['code'] as String : null;
    if (code == null) {
      throw const LocalProgramException('reason');
    }
    reasons.add(
      ProgramReason(
        code: code,
        region: _nullableString(json['region']),
        equipment: _nullableString(json['equipment']),
        goal: _nullableString(json['goal']),
      ),
    );
  }
  return reasons;
}

String? _nullableString(Object? value) {
  if (value == null) {
    return null;
  }
  if (value is! String) {
    throw const LocalProgramException('reason');
  }
  return value;
}

void _checkReason(ProgramReason reason, String expected) {
  if (reason.code != expected) {
    throw const LocalProgramException('reason');
  }
  switch (expected) {
    case 'region_match':
      if (reason.region == null ||
          reason.equipment != null ||
          reason.goal != null) {
        throw const LocalProgramException('reason');
      }
      _acceptRegion(reason.region!);
      break;
    case 'equipment_match':
      if (reason.equipment == null ||
          reason.region != null ||
          reason.goal != null) {
        throw const LocalProgramException('reason');
      }
      _acceptEquipment(reason.equipment!);
      break;
    case 'goal_match':
      if (reason.goal == null ||
          reason.region != null ||
          reason.equipment != null) {
        throw const LocalProgramException('reason');
      }
      _acceptGoal(reason.goal!);
      break;
    case 'screen_clear':
    case 'fixture_defaults':
      if (reason.region != null ||
          reason.equipment != null ||
          reason.goal != null) {
        throw const LocalProgramException('reason');
      }
      break;
    default:
      throw const LocalProgramException('reason');
  }
}

String _acceptRegion(String token) {
  try {
    return acceptRegion(raw: token);
  } on BridgeError {
    throw const LocalProgramException('region');
  }
}

String _acceptEquipment(String token) {
  try {
    return acceptEquipment(raw: token);
  } on BridgeError {
    throw const LocalProgramException('equipment');
  }
}

String _acceptGoal(String token) {
  try {
    return acceptGoal(raw: token);
  } on BridgeError {
    throw const LocalProgramException('goal');
  }
}
