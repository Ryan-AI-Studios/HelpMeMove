import 'dart:convert';

import 'package:helpmemove/src/rust/api/bridge.dart';

class LocalAssessmentException implements Exception {
  const LocalAssessmentException(this.code);

  final String code;

  @override
  String toString() => 'LocalAssessmentException: $code';
}

class AssessmentArea {
  const AssessmentArea({
    required this.region,
    required this.laterality,
    required this.rating,
  });

  final String region;
  final String laterality;
  final String? rating;
}

/// In-progress or saved movement check. Not a safety view.
class LocalAssessment {
  LocalAssessment({
    List<AssessmentArea>? areas,
    this.stopped = false,
    this.complete = false,
  }) : areas = areas ?? <AssessmentArea>[];

  final List<AssessmentArea> areas;
  bool stopped;
  bool complete;

  void validate() {
    _acceptRegions();
    if (complete &&
        (stopped || areas.any((AssessmentArea area) => area.rating == null))) {
      throw const LocalAssessmentException('complete');
    }
  }

  String encode() {
    validate();
    return jsonEncode(<String, Object?>{
      'record_version': 1,
      'instrument_id': 'syn-assessment-core',
      'instrument_version': 1,
      'areas': <Map<String, Object?>>[
        for (final AssessmentArea area in areas)
          <String, Object?>{
            'region': area.region,
            'laterality': area.laterality,
            'rating': area.rating,
          },
      ],
      'stopped': stopped,
      'complete': complete,
    });
  }

  static LocalAssessment decode(String raw) {
    final Object? parsed;
    try {
      parsed = jsonDecode(raw);
    } catch (_) {
      throw const LocalAssessmentException('document');
    }
    if (parsed is! Map) {
      throw const LocalAssessmentException('document');
    }
    final Map<String, Object?> json = _stringKeyMap(parsed, 'document');
    const Set<String> allowed = <String>{
      'record_version',
      'instrument_id',
      'instrument_version',
      'areas',
      'stopped',
      'complete',
    };
    if (json.length != allowed.length || !allowed.containsAll(json.keys)) {
      throw const LocalAssessmentException('document');
    }
    if (json['record_version'] != 1) {
      throw const LocalAssessmentException('record-version');
    }
    if (json['instrument_id'] != 'syn-assessment-core') {
      throw const LocalAssessmentException('instrument');
    }
    if (json['instrument_version'] != 1) {
      throw const LocalAssessmentException('instrument-version');
    }
    final LocalAssessment document = LocalAssessment(
      areas: _areas(json['areas']),
      stopped: _bool(json['stopped'], 'stopped'),
      complete: _bool(json['complete'], 'complete'),
    );
    document.validate();
    return document;
  }

  void _acceptRegions() {
    final Set<String> seen = <String>{};
    for (final AssessmentArea area in areas) {
      try {
        acceptRegion(raw: area.region);
        acceptLaterality(raw: area.laterality);
        final String? rating = area.rating;
        if (rating != null) {
          acceptRating(raw: rating);
        }
      } on BridgeError {
        throw const LocalAssessmentException('area');
      }
      if (!seen.add(area.region)) {
        throw const LocalAssessmentException('region');
      }
    }
  }
}

Map<String, Object?> _stringKeyMap(Map<dynamic, dynamic> parsed, String code) {
  final Map<String, Object?> json = <String, Object?>{};
  for (final MapEntry<Object?, Object?> entry in parsed.entries) {
    if (entry.key is! String) {
      throw LocalAssessmentException(code);
    }
    json[entry.key as String] = entry.value;
  }
  return json;
}

bool _bool(Object? value, String code) {
  if (value is! bool) {
    throw LocalAssessmentException(code);
  }
  return value;
}

List<AssessmentArea> _areas(Object? value) {
  if (value is! List) {
    throw const LocalAssessmentException('areas');
  }
  final List<AssessmentArea> areas = <AssessmentArea>[];
  for (final Object? item in value) {
    if (item is! Map) {
      throw const LocalAssessmentException('areas');
    }
    final Map<String, Object?> json = _stringKeyMap(item, 'areas');
    const Set<String> allowed = <String>{'region', 'laterality', 'rating'};
    if (json.length != allowed.length || !allowed.containsAll(json.keys)) {
      throw const LocalAssessmentException('areas');
    }
    final Object? region = json['region'];
    final Object? laterality = json['laterality'];
    final Object? rating = json['rating'];
    if (region is! String || laterality is! String) {
      throw const LocalAssessmentException('areas');
    }
    final String? storedRating;
    if (rating == null) {
      storedRating = null;
    } else if (rating is String) {
      storedRating = rating;
    } else {
      throw const LocalAssessmentException('rating');
    }
    areas.add(
      AssessmentArea(
        region: region,
        laterality: laterality,
        rating: storedRating,
      ),
    );
  }
  return areas;
}
