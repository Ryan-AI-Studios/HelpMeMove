import 'dart:convert';

import 'package:helpmemove/src/rust/api/bridge.dart';

const List<String> intakeSteps = <String>[
  'intent',
  'notice',
  'goals',
  'equipment',
  'body',
  'note',
  'severity',
  'check',
];

const List<String> intakeIntents = <String>[
  'pain_or_limit',
  'fitness',
  'not_sure',
];

class LocalIntakeDraftException implements Exception {
  const LocalIntakeDraftException(this.code);

  final String code;

  @override
  String toString() => 'LocalIntakeDraftException: $code';
}

class IntakeArea {
  const IntakeArea({required this.region, required this.laterality});

  final String region;
  final String laterality;
}

class LocalIntakeDraft {
  LocalIntakeDraft({
    this.intent,
    this.noticeId,
    this.schemaAck,
    List<String>? goals,
    List<String>? equipment,
    List<IntakeArea>? areas,
    this.note = '',
    this.severity = 0,
    this.step = 'intent',
  }) : goals = goals ?? <String>[],
       equipment = equipment ?? <String>[],
       areas = areas ?? <IntakeArea>[];

  String? intent;
  String? noticeId;
  String? schemaAck;
  final List<String> goals;
  final List<String> equipment;
  final List<IntakeArea> areas;
  String note;
  int severity;
  String step;

  void validateTokens() {
    if (intent != null && !intakeIntents.contains(intent)) {
      throw const LocalIntakeDraftException('intent');
    }
    if (noticeId != null && noticeId != 'syn-notice-1') {
      throw const LocalIntakeDraftException('notice');
    }
    if (schemaAck != null && schemaAck != 'yes') {
      throw const LocalIntakeDraftException('schema-ack');
    }
    if (!intakeSteps.contains(step)) {
      throw const LocalIntakeDraftException('step');
    }
    if (severity < 0 || severity > 10) {
      throw const LocalIntakeDraftException('severity');
    }
    if (note.runes.length > 200) {
      throw const LocalIntakeDraftException('note');
    }
    _unique(goals, 'goal');
    _unique(equipment, 'equipment');
    for (final String goal in goals) {
      acceptGoal(raw: goal);
    }
    for (final String item in equipment) {
      acceptEquipment(raw: item);
    }
    final Set<String> seen = <String>{};
    for (final IntakeArea area in areas) {
      final String region = acceptRegion(raw: area.region);
      acceptLaterality(raw: area.laterality);
      if (!seen.add(region)) {
        throw const LocalIntakeDraftException('region');
      }
    }
  }

  String encode() {
    validateTokens();
    return jsonEncode(<String, Object?>{
      'draft_version': 1,
      'intent': intent,
      'notice_id': noticeId,
      'schema_ack': schemaAck,
      'goals': goals,
      'equipment': equipment,
      'areas': <Map<String, String>>[
        for (final IntakeArea area in areas)
          <String, String>{
            'region': area.region,
            'laterality': area.laterality,
          },
      ],
      'note': note,
      'severity': severity,
      'step': step,
    });
  }

  static LocalIntakeDraft decode(String raw) {
    final Object? parsed = jsonDecode(raw);
    if (parsed is! Map) {
      throw const LocalIntakeDraftException('document');
    }
    final Map<String, Object?> json = <String, Object?>{};
    for (final MapEntry<Object?, Object?> entry in parsed.entries) {
      if (entry.key is! String) {
        throw const LocalIntakeDraftException('document');
      }
      json[entry.key as String] = entry.value;
    }
    const Set<String> allowed = <String>{
      'draft_version',
      'intent',
      'notice_id',
      'schema_ack',
      'goals',
      'equipment',
      'areas',
      'note',
      'severity',
      'step',
    };
    if (json.length != allowed.length || !allowed.containsAll(json.keys)) {
      throw const LocalIntakeDraftException('document');
    }
    if (json['draft_version'] != 1) {
      throw const LocalIntakeDraftException('draft-version');
    }
    final LocalIntakeDraft draft = LocalIntakeDraft(
      intent: _optionalString(json['intent'], 'intent'),
      noticeId: _optionalString(json['notice_id'], 'notice'),
      schemaAck: _optionalString(json['schema_ack'], 'schema-ack'),
      goals: _stringList(json['goals'], 'goal'),
      equipment: _stringList(json['equipment'], 'equipment'),
      areas: _areas(json['areas']),
      note: _requiredString(json['note'], 'note'),
      severity: _severity(json['severity']),
      step: _requiredString(json['step'], 'step'),
    );
    draft.validateTokens();
    return draft;
  }
}

void _unique(List<String> values, String code) {
  if (values.toSet().length != values.length) {
    throw LocalIntakeDraftException(code);
  }
}

String? _optionalString(Object? value, String code) {
  if (value == null) {
    return null;
  }
  if (value is! String) {
    throw LocalIntakeDraftException(code);
  }
  return value;
}

String _requiredString(Object? value, String code) {
  if (value is! String) {
    throw LocalIntakeDraftException(code);
  }
  return value;
}

int _severity(Object? value) {
  if (value is! int || value < 0 || value > 10) {
    throw const LocalIntakeDraftException('severity');
  }
  return value;
}

List<String> _stringList(Object? value, String code) {
  if (value is! List) {
    throw LocalIntakeDraftException(code);
  }
  final List<String> out = <String>[];
  for (final Object? item in value) {
    if (item is! String) {
      throw LocalIntakeDraftException(code);
    }
    out.add(item);
  }
  return out;
}

List<IntakeArea> _areas(Object? value) {
  if (value is! List) {
    throw const LocalIntakeDraftException('areas');
  }
  final List<IntakeArea> areas = <IntakeArea>[];
  for (final Object? item in value) {
    if (item is! Map) {
      throw const LocalIntakeDraftException('areas');
    }
    final Map<String, Object?> json = <String, Object?>{};
    for (final MapEntry<Object?, Object?> entry in item.entries) {
      if (entry.key is! String) {
        throw const LocalIntakeDraftException('areas');
      }
      json[entry.key as String] = entry.value;
    }
    const Set<String> allowed = <String>{'region', 'laterality'};
    if (json.length != allowed.length || !allowed.containsAll(json.keys)) {
      throw const LocalIntakeDraftException('areas');
    }
    final Object? region = json['region'];
    final Object? laterality = json['laterality'];
    if (region is! String || laterality is! String) {
      throw const LocalIntakeDraftException('areas');
    }
    areas.add(IntakeArea(region: region, laterality: laterality));
  }
  return areas;
}
