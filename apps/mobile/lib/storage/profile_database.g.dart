// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'profile_database.dart';

// ignore_for_file: type=lint
class $LocalProfilesTable extends LocalProfiles
    with TableInfo<$LocalProfilesTable, LocalProfile> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $LocalProfilesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _subjectIdMeta = const VerificationMeta(
    'subjectId',
  );
  @override
  late final GeneratedColumn<String> subjectId = GeneratedColumn<String>(
    'subject_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _createdAtMsMeta = const VerificationMeta(
    'createdAtMs',
  );
  @override
  late final GeneratedColumn<int> createdAtMs = GeneratedColumn<int>(
    'created_at_ms',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _lastActiveAtMsMeta = const VerificationMeta(
    'lastActiveAtMs',
  );
  @override
  late final GeneratedColumn<int> lastActiveAtMs = GeneratedColumn<int>(
    'last_active_at_ms',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    subjectId,
    createdAtMs,
    lastActiveAtMs,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'local_profiles';
  @override
  VerificationContext validateIntegrity(
    Insertable<LocalProfile> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('subject_id')) {
      context.handle(
        _subjectIdMeta,
        subjectId.isAcceptableOrUnknown(data['subject_id']!, _subjectIdMeta),
      );
    } else if (isInserting) {
      context.missing(_subjectIdMeta);
    }
    if (data.containsKey('created_at_ms')) {
      context.handle(
        _createdAtMsMeta,
        createdAtMs.isAcceptableOrUnknown(
          data['created_at_ms']!,
          _createdAtMsMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_createdAtMsMeta);
    }
    if (data.containsKey('last_active_at_ms')) {
      context.handle(
        _lastActiveAtMsMeta,
        lastActiveAtMs.isAcceptableOrUnknown(
          data['last_active_at_ms']!,
          _lastActiveAtMsMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_lastActiveAtMsMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {subjectId};
  @override
  LocalProfile map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return LocalProfile(
      subjectId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}subject_id'],
      )!,
      createdAtMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}created_at_ms'],
      )!,
      lastActiveAtMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}last_active_at_ms'],
      )!,
    );
  }

  @override
  $LocalProfilesTable createAlias(String alias) {
    return $LocalProfilesTable(attachedDatabase, alias);
  }
}

class LocalProfile extends DataClass implements Insertable<LocalProfile> {
  final String subjectId;
  final int createdAtMs;
  final int lastActiveAtMs;
  const LocalProfile({
    required this.subjectId,
    required this.createdAtMs,
    required this.lastActiveAtMs,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['subject_id'] = Variable<String>(subjectId);
    map['created_at_ms'] = Variable<int>(createdAtMs);
    map['last_active_at_ms'] = Variable<int>(lastActiveAtMs);
    return map;
  }

  LocalProfilesCompanion toCompanion(bool nullToAbsent) {
    return LocalProfilesCompanion(
      subjectId: Value(subjectId),
      createdAtMs: Value(createdAtMs),
      lastActiveAtMs: Value(lastActiveAtMs),
    );
  }

  factory LocalProfile.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return LocalProfile(
      subjectId: serializer.fromJson<String>(json['subjectId']),
      createdAtMs: serializer.fromJson<int>(json['createdAtMs']),
      lastActiveAtMs: serializer.fromJson<int>(json['lastActiveAtMs']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'subjectId': serializer.toJson<String>(subjectId),
      'createdAtMs': serializer.toJson<int>(createdAtMs),
      'lastActiveAtMs': serializer.toJson<int>(lastActiveAtMs),
    };
  }

  LocalProfile copyWith({
    String? subjectId,
    int? createdAtMs,
    int? lastActiveAtMs,
  }) => LocalProfile(
    subjectId: subjectId ?? this.subjectId,
    createdAtMs: createdAtMs ?? this.createdAtMs,
    lastActiveAtMs: lastActiveAtMs ?? this.lastActiveAtMs,
  );
  LocalProfile copyWithCompanion(LocalProfilesCompanion data) {
    return LocalProfile(
      subjectId: data.subjectId.present ? data.subjectId.value : this.subjectId,
      createdAtMs: data.createdAtMs.present
          ? data.createdAtMs.value
          : this.createdAtMs,
      lastActiveAtMs: data.lastActiveAtMs.present
          ? data.lastActiveAtMs.value
          : this.lastActiveAtMs,
    );
  }

  @override
  String toString() {
    return (StringBuffer('LocalProfile(')
          ..write('subjectId: $subjectId, ')
          ..write('createdAtMs: $createdAtMs, ')
          ..write('lastActiveAtMs: $lastActiveAtMs')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(subjectId, createdAtMs, lastActiveAtMs);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is LocalProfile &&
          other.subjectId == this.subjectId &&
          other.createdAtMs == this.createdAtMs &&
          other.lastActiveAtMs == this.lastActiveAtMs);
}

class LocalProfilesCompanion extends UpdateCompanion<LocalProfile> {
  final Value<String> subjectId;
  final Value<int> createdAtMs;
  final Value<int> lastActiveAtMs;
  final Value<int> rowid;
  const LocalProfilesCompanion({
    this.subjectId = const Value.absent(),
    this.createdAtMs = const Value.absent(),
    this.lastActiveAtMs = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  LocalProfilesCompanion.insert({
    required String subjectId,
    required int createdAtMs,
    required int lastActiveAtMs,
    this.rowid = const Value.absent(),
  }) : subjectId = Value(subjectId),
       createdAtMs = Value(createdAtMs),
       lastActiveAtMs = Value(lastActiveAtMs);
  static Insertable<LocalProfile> custom({
    Expression<String>? subjectId,
    Expression<int>? createdAtMs,
    Expression<int>? lastActiveAtMs,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (subjectId != null) 'subject_id': subjectId,
      if (createdAtMs != null) 'created_at_ms': createdAtMs,
      if (lastActiveAtMs != null) 'last_active_at_ms': lastActiveAtMs,
      if (rowid != null) 'rowid': rowid,
    });
  }

  LocalProfilesCompanion copyWith({
    Value<String>? subjectId,
    Value<int>? createdAtMs,
    Value<int>? lastActiveAtMs,
    Value<int>? rowid,
  }) {
    return LocalProfilesCompanion(
      subjectId: subjectId ?? this.subjectId,
      createdAtMs: createdAtMs ?? this.createdAtMs,
      lastActiveAtMs: lastActiveAtMs ?? this.lastActiveAtMs,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (subjectId.present) {
      map['subject_id'] = Variable<String>(subjectId.value);
    }
    if (createdAtMs.present) {
      map['created_at_ms'] = Variable<int>(createdAtMs.value);
    }
    if (lastActiveAtMs.present) {
      map['last_active_at_ms'] = Variable<int>(lastActiveAtMs.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('LocalProfilesCompanion(')
          ..write('subjectId: $subjectId, ')
          ..write('createdAtMs: $createdAtMs, ')
          ..write('lastActiveAtMs: $lastActiveAtMs, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $LocalEventsTable extends LocalEvents
    with TableInfo<$LocalEventsTable, LocalEvent> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $LocalEventsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _eventIdMeta = const VerificationMeta(
    'eventId',
  );
  @override
  late final GeneratedColumn<String> eventId = GeneratedColumn<String>(
    'event_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _subjectIdMeta = const VerificationMeta(
    'subjectId',
  );
  @override
  late final GeneratedColumn<String> subjectId = GeneratedColumn<String>(
    'subject_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _eventTypeMeta = const VerificationMeta(
    'eventType',
  );
  @override
  late final GeneratedColumn<String> eventType = GeneratedColumn<String>(
    'event_type',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _payloadTextMeta = const VerificationMeta(
    'payloadText',
  );
  @override
  late final GeneratedColumn<String> payloadText = GeneratedColumn<String>(
    'payload_text',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _createdAtMsMeta = const VerificationMeta(
    'createdAtMs',
  );
  @override
  late final GeneratedColumn<int> createdAtMs = GeneratedColumn<int>(
    'created_at_ms',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    eventId,
    subjectId,
    eventType,
    payloadText,
    createdAtMs,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'local_events';
  @override
  VerificationContext validateIntegrity(
    Insertable<LocalEvent> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('event_id')) {
      context.handle(
        _eventIdMeta,
        eventId.isAcceptableOrUnknown(data['event_id']!, _eventIdMeta),
      );
    } else if (isInserting) {
      context.missing(_eventIdMeta);
    }
    if (data.containsKey('subject_id')) {
      context.handle(
        _subjectIdMeta,
        subjectId.isAcceptableOrUnknown(data['subject_id']!, _subjectIdMeta),
      );
    } else if (isInserting) {
      context.missing(_subjectIdMeta);
    }
    if (data.containsKey('event_type')) {
      context.handle(
        _eventTypeMeta,
        eventType.isAcceptableOrUnknown(data['event_type']!, _eventTypeMeta),
      );
    } else if (isInserting) {
      context.missing(_eventTypeMeta);
    }
    if (data.containsKey('payload_text')) {
      context.handle(
        _payloadTextMeta,
        payloadText.isAcceptableOrUnknown(
          data['payload_text']!,
          _payloadTextMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_payloadTextMeta);
    }
    if (data.containsKey('created_at_ms')) {
      context.handle(
        _createdAtMsMeta,
        createdAtMs.isAcceptableOrUnknown(
          data['created_at_ms']!,
          _createdAtMsMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_createdAtMsMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {eventId};
  @override
  LocalEvent map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return LocalEvent(
      eventId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}event_id'],
      )!,
      subjectId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}subject_id'],
      )!,
      eventType: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}event_type'],
      )!,
      payloadText: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}payload_text'],
      )!,
      createdAtMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}created_at_ms'],
      )!,
    );
  }

  @override
  $LocalEventsTable createAlias(String alias) {
    return $LocalEventsTable(attachedDatabase, alias);
  }
}

class LocalEvent extends DataClass implements Insertable<LocalEvent> {
  final String eventId;
  final String subjectId;
  final String eventType;
  final String payloadText;
  final int createdAtMs;
  const LocalEvent({
    required this.eventId,
    required this.subjectId,
    required this.eventType,
    required this.payloadText,
    required this.createdAtMs,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['event_id'] = Variable<String>(eventId);
    map['subject_id'] = Variable<String>(subjectId);
    map['event_type'] = Variable<String>(eventType);
    map['payload_text'] = Variable<String>(payloadText);
    map['created_at_ms'] = Variable<int>(createdAtMs);
    return map;
  }

  LocalEventsCompanion toCompanion(bool nullToAbsent) {
    return LocalEventsCompanion(
      eventId: Value(eventId),
      subjectId: Value(subjectId),
      eventType: Value(eventType),
      payloadText: Value(payloadText),
      createdAtMs: Value(createdAtMs),
    );
  }

  factory LocalEvent.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return LocalEvent(
      eventId: serializer.fromJson<String>(json['eventId']),
      subjectId: serializer.fromJson<String>(json['subjectId']),
      eventType: serializer.fromJson<String>(json['eventType']),
      payloadText: serializer.fromJson<String>(json['payloadText']),
      createdAtMs: serializer.fromJson<int>(json['createdAtMs']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'eventId': serializer.toJson<String>(eventId),
      'subjectId': serializer.toJson<String>(subjectId),
      'eventType': serializer.toJson<String>(eventType),
      'payloadText': serializer.toJson<String>(payloadText),
      'createdAtMs': serializer.toJson<int>(createdAtMs),
    };
  }

  LocalEvent copyWith({
    String? eventId,
    String? subjectId,
    String? eventType,
    String? payloadText,
    int? createdAtMs,
  }) => LocalEvent(
    eventId: eventId ?? this.eventId,
    subjectId: subjectId ?? this.subjectId,
    eventType: eventType ?? this.eventType,
    payloadText: payloadText ?? this.payloadText,
    createdAtMs: createdAtMs ?? this.createdAtMs,
  );
  LocalEvent copyWithCompanion(LocalEventsCompanion data) {
    return LocalEvent(
      eventId: data.eventId.present ? data.eventId.value : this.eventId,
      subjectId: data.subjectId.present ? data.subjectId.value : this.subjectId,
      eventType: data.eventType.present ? data.eventType.value : this.eventType,
      payloadText: data.payloadText.present
          ? data.payloadText.value
          : this.payloadText,
      createdAtMs: data.createdAtMs.present
          ? data.createdAtMs.value
          : this.createdAtMs,
    );
  }

  @override
  String toString() {
    return (StringBuffer('LocalEvent(')
          ..write('eventId: $eventId, ')
          ..write('subjectId: $subjectId, ')
          ..write('eventType: $eventType, ')
          ..write('payloadText: $payloadText, ')
          ..write('createdAtMs: $createdAtMs')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(eventId, subjectId, eventType, payloadText, createdAtMs);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is LocalEvent &&
          other.eventId == this.eventId &&
          other.subjectId == this.subjectId &&
          other.eventType == this.eventType &&
          other.payloadText == this.payloadText &&
          other.createdAtMs == this.createdAtMs);
}

class LocalEventsCompanion extends UpdateCompanion<LocalEvent> {
  final Value<String> eventId;
  final Value<String> subjectId;
  final Value<String> eventType;
  final Value<String> payloadText;
  final Value<int> createdAtMs;
  final Value<int> rowid;
  const LocalEventsCompanion({
    this.eventId = const Value.absent(),
    this.subjectId = const Value.absent(),
    this.eventType = const Value.absent(),
    this.payloadText = const Value.absent(),
    this.createdAtMs = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  LocalEventsCompanion.insert({
    required String eventId,
    required String subjectId,
    required String eventType,
    required String payloadText,
    required int createdAtMs,
    this.rowid = const Value.absent(),
  }) : eventId = Value(eventId),
       subjectId = Value(subjectId),
       eventType = Value(eventType),
       payloadText = Value(payloadText),
       createdAtMs = Value(createdAtMs);
  static Insertable<LocalEvent> custom({
    Expression<String>? eventId,
    Expression<String>? subjectId,
    Expression<String>? eventType,
    Expression<String>? payloadText,
    Expression<int>? createdAtMs,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (eventId != null) 'event_id': eventId,
      if (subjectId != null) 'subject_id': subjectId,
      if (eventType != null) 'event_type': eventType,
      if (payloadText != null) 'payload_text': payloadText,
      if (createdAtMs != null) 'created_at_ms': createdAtMs,
      if (rowid != null) 'rowid': rowid,
    });
  }

  LocalEventsCompanion copyWith({
    Value<String>? eventId,
    Value<String>? subjectId,
    Value<String>? eventType,
    Value<String>? payloadText,
    Value<int>? createdAtMs,
    Value<int>? rowid,
  }) {
    return LocalEventsCompanion(
      eventId: eventId ?? this.eventId,
      subjectId: subjectId ?? this.subjectId,
      eventType: eventType ?? this.eventType,
      payloadText: payloadText ?? this.payloadText,
      createdAtMs: createdAtMs ?? this.createdAtMs,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (eventId.present) {
      map['event_id'] = Variable<String>(eventId.value);
    }
    if (subjectId.present) {
      map['subject_id'] = Variable<String>(subjectId.value);
    }
    if (eventType.present) {
      map['event_type'] = Variable<String>(eventType.value);
    }
    if (payloadText.present) {
      map['payload_text'] = Variable<String>(payloadText.value);
    }
    if (createdAtMs.present) {
      map['created_at_ms'] = Variable<int>(createdAtMs.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('LocalEventsCompanion(')
          ..write('eventId: $eventId, ')
          ..write('subjectId: $subjectId, ')
          ..write('eventType: $eventType, ')
          ..write('payloadText: $payloadText, ')
          ..write('createdAtMs: $createdAtMs, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $IntakeDraftsTable extends IntakeDrafts
    with TableInfo<$IntakeDraftsTable, IntakeDraft> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $IntakeDraftsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _subjectIdMeta = const VerificationMeta(
    'subjectId',
  );
  @override
  late final GeneratedColumn<String> subjectId = GeneratedColumn<String>(
    'subject_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _documentJsonMeta = const VerificationMeta(
    'documentJson',
  );
  @override
  late final GeneratedColumn<String> documentJson = GeneratedColumn<String>(
    'document_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMsMeta = const VerificationMeta(
    'updatedAtMs',
  );
  @override
  late final GeneratedColumn<int> updatedAtMs = GeneratedColumn<int>(
    'updated_at_ms',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [subjectId, documentJson, updatedAtMs];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'intake_drafts';
  @override
  VerificationContext validateIntegrity(
    Insertable<IntakeDraft> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('subject_id')) {
      context.handle(
        _subjectIdMeta,
        subjectId.isAcceptableOrUnknown(data['subject_id']!, _subjectIdMeta),
      );
    } else if (isInserting) {
      context.missing(_subjectIdMeta);
    }
    if (data.containsKey('document_json')) {
      context.handle(
        _documentJsonMeta,
        documentJson.isAcceptableOrUnknown(
          data['document_json']!,
          _documentJsonMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_documentJsonMeta);
    }
    if (data.containsKey('updated_at_ms')) {
      context.handle(
        _updatedAtMsMeta,
        updatedAtMs.isAcceptableOrUnknown(
          data['updated_at_ms']!,
          _updatedAtMsMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMsMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {subjectId};
  @override
  IntakeDraft map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return IntakeDraft(
      subjectId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}subject_id'],
      )!,
      documentJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}document_json'],
      )!,
      updatedAtMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}updated_at_ms'],
      )!,
    );
  }

  @override
  $IntakeDraftsTable createAlias(String alias) {
    return $IntakeDraftsTable(attachedDatabase, alias);
  }
}

class IntakeDraft extends DataClass implements Insertable<IntakeDraft> {
  final String subjectId;
  final String documentJson;
  final int updatedAtMs;
  const IntakeDraft({
    required this.subjectId,
    required this.documentJson,
    required this.updatedAtMs,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['subject_id'] = Variable<String>(subjectId);
    map['document_json'] = Variable<String>(documentJson);
    map['updated_at_ms'] = Variable<int>(updatedAtMs);
    return map;
  }

  IntakeDraftsCompanion toCompanion(bool nullToAbsent) {
    return IntakeDraftsCompanion(
      subjectId: Value(subjectId),
      documentJson: Value(documentJson),
      updatedAtMs: Value(updatedAtMs),
    );
  }

  factory IntakeDraft.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return IntakeDraft(
      subjectId: serializer.fromJson<String>(json['subjectId']),
      documentJson: serializer.fromJson<String>(json['documentJson']),
      updatedAtMs: serializer.fromJson<int>(json['updatedAtMs']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'subjectId': serializer.toJson<String>(subjectId),
      'documentJson': serializer.toJson<String>(documentJson),
      'updatedAtMs': serializer.toJson<int>(updatedAtMs),
    };
  }

  IntakeDraft copyWith({
    String? subjectId,
    String? documentJson,
    int? updatedAtMs,
  }) => IntakeDraft(
    subjectId: subjectId ?? this.subjectId,
    documentJson: documentJson ?? this.documentJson,
    updatedAtMs: updatedAtMs ?? this.updatedAtMs,
  );
  IntakeDraft copyWithCompanion(IntakeDraftsCompanion data) {
    return IntakeDraft(
      subjectId: data.subjectId.present ? data.subjectId.value : this.subjectId,
      documentJson: data.documentJson.present
          ? data.documentJson.value
          : this.documentJson,
      updatedAtMs: data.updatedAtMs.present
          ? data.updatedAtMs.value
          : this.updatedAtMs,
    );
  }

  @override
  String toString() {
    return (StringBuffer('IntakeDraft(')
          ..write('subjectId: $subjectId, ')
          ..write('documentJson: $documentJson, ')
          ..write('updatedAtMs: $updatedAtMs')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(subjectId, documentJson, updatedAtMs);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is IntakeDraft &&
          other.subjectId == this.subjectId &&
          other.documentJson == this.documentJson &&
          other.updatedAtMs == this.updatedAtMs);
}

class IntakeDraftsCompanion extends UpdateCompanion<IntakeDraft> {
  final Value<String> subjectId;
  final Value<String> documentJson;
  final Value<int> updatedAtMs;
  final Value<int> rowid;
  const IntakeDraftsCompanion({
    this.subjectId = const Value.absent(),
    this.documentJson = const Value.absent(),
    this.updatedAtMs = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  IntakeDraftsCompanion.insert({
    required String subjectId,
    required String documentJson,
    required int updatedAtMs,
    this.rowid = const Value.absent(),
  }) : subjectId = Value(subjectId),
       documentJson = Value(documentJson),
       updatedAtMs = Value(updatedAtMs);
  static Insertable<IntakeDraft> custom({
    Expression<String>? subjectId,
    Expression<String>? documentJson,
    Expression<int>? updatedAtMs,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (subjectId != null) 'subject_id': subjectId,
      if (documentJson != null) 'document_json': documentJson,
      if (updatedAtMs != null) 'updated_at_ms': updatedAtMs,
      if (rowid != null) 'rowid': rowid,
    });
  }

  IntakeDraftsCompanion copyWith({
    Value<String>? subjectId,
    Value<String>? documentJson,
    Value<int>? updatedAtMs,
    Value<int>? rowid,
  }) {
    return IntakeDraftsCompanion(
      subjectId: subjectId ?? this.subjectId,
      documentJson: documentJson ?? this.documentJson,
      updatedAtMs: updatedAtMs ?? this.updatedAtMs,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (subjectId.present) {
      map['subject_id'] = Variable<String>(subjectId.value);
    }
    if (documentJson.present) {
      map['document_json'] = Variable<String>(documentJson.value);
    }
    if (updatedAtMs.present) {
      map['updated_at_ms'] = Variable<int>(updatedAtMs.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('IntakeDraftsCompanion(')
          ..write('subjectId: $subjectId, ')
          ..write('documentJson: $documentJson, ')
          ..write('updatedAtMs: $updatedAtMs, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $AssessmentDraftsTable extends AssessmentDrafts
    with TableInfo<$AssessmentDraftsTable, AssessmentDraft> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $AssessmentDraftsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _subjectIdMeta = const VerificationMeta(
    'subjectId',
  );
  @override
  late final GeneratedColumn<String> subjectId = GeneratedColumn<String>(
    'subject_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _documentJsonMeta = const VerificationMeta(
    'documentJson',
  );
  @override
  late final GeneratedColumn<String> documentJson = GeneratedColumn<String>(
    'document_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMsMeta = const VerificationMeta(
    'updatedAtMs',
  );
  @override
  late final GeneratedColumn<int> updatedAtMs = GeneratedColumn<int>(
    'updated_at_ms',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [subjectId, documentJson, updatedAtMs];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'assessment_drafts';
  @override
  VerificationContext validateIntegrity(
    Insertable<AssessmentDraft> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('subject_id')) {
      context.handle(
        _subjectIdMeta,
        subjectId.isAcceptableOrUnknown(data['subject_id']!, _subjectIdMeta),
      );
    } else if (isInserting) {
      context.missing(_subjectIdMeta);
    }
    if (data.containsKey('document_json')) {
      context.handle(
        _documentJsonMeta,
        documentJson.isAcceptableOrUnknown(
          data['document_json']!,
          _documentJsonMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_documentJsonMeta);
    }
    if (data.containsKey('updated_at_ms')) {
      context.handle(
        _updatedAtMsMeta,
        updatedAtMs.isAcceptableOrUnknown(
          data['updated_at_ms']!,
          _updatedAtMsMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMsMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {subjectId};
  @override
  AssessmentDraft map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return AssessmentDraft(
      subjectId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}subject_id'],
      )!,
      documentJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}document_json'],
      )!,
      updatedAtMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}updated_at_ms'],
      )!,
    );
  }

  @override
  $AssessmentDraftsTable createAlias(String alias) {
    return $AssessmentDraftsTable(attachedDatabase, alias);
  }
}

class AssessmentDraft extends DataClass implements Insertable<AssessmentDraft> {
  final String subjectId;
  final String documentJson;
  final int updatedAtMs;
  const AssessmentDraft({
    required this.subjectId,
    required this.documentJson,
    required this.updatedAtMs,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['subject_id'] = Variable<String>(subjectId);
    map['document_json'] = Variable<String>(documentJson);
    map['updated_at_ms'] = Variable<int>(updatedAtMs);
    return map;
  }

  AssessmentDraftsCompanion toCompanion(bool nullToAbsent) {
    return AssessmentDraftsCompanion(
      subjectId: Value(subjectId),
      documentJson: Value(documentJson),
      updatedAtMs: Value(updatedAtMs),
    );
  }

  factory AssessmentDraft.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return AssessmentDraft(
      subjectId: serializer.fromJson<String>(json['subjectId']),
      documentJson: serializer.fromJson<String>(json['documentJson']),
      updatedAtMs: serializer.fromJson<int>(json['updatedAtMs']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'subjectId': serializer.toJson<String>(subjectId),
      'documentJson': serializer.toJson<String>(documentJson),
      'updatedAtMs': serializer.toJson<int>(updatedAtMs),
    };
  }

  AssessmentDraft copyWith({
    String? subjectId,
    String? documentJson,
    int? updatedAtMs,
  }) => AssessmentDraft(
    subjectId: subjectId ?? this.subjectId,
    documentJson: documentJson ?? this.documentJson,
    updatedAtMs: updatedAtMs ?? this.updatedAtMs,
  );
  AssessmentDraft copyWithCompanion(AssessmentDraftsCompanion data) {
    return AssessmentDraft(
      subjectId: data.subjectId.present ? data.subjectId.value : this.subjectId,
      documentJson: data.documentJson.present
          ? data.documentJson.value
          : this.documentJson,
      updatedAtMs: data.updatedAtMs.present
          ? data.updatedAtMs.value
          : this.updatedAtMs,
    );
  }

  @override
  String toString() {
    return (StringBuffer('AssessmentDraft(')
          ..write('subjectId: $subjectId, ')
          ..write('documentJson: $documentJson, ')
          ..write('updatedAtMs: $updatedAtMs')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(subjectId, documentJson, updatedAtMs);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is AssessmentDraft &&
          other.subjectId == this.subjectId &&
          other.documentJson == this.documentJson &&
          other.updatedAtMs == this.updatedAtMs);
}

class AssessmentDraftsCompanion extends UpdateCompanion<AssessmentDraft> {
  final Value<String> subjectId;
  final Value<String> documentJson;
  final Value<int> updatedAtMs;
  final Value<int> rowid;
  const AssessmentDraftsCompanion({
    this.subjectId = const Value.absent(),
    this.documentJson = const Value.absent(),
    this.updatedAtMs = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  AssessmentDraftsCompanion.insert({
    required String subjectId,
    required String documentJson,
    required int updatedAtMs,
    this.rowid = const Value.absent(),
  }) : subjectId = Value(subjectId),
       documentJson = Value(documentJson),
       updatedAtMs = Value(updatedAtMs);
  static Insertable<AssessmentDraft> custom({
    Expression<String>? subjectId,
    Expression<String>? documentJson,
    Expression<int>? updatedAtMs,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (subjectId != null) 'subject_id': subjectId,
      if (documentJson != null) 'document_json': documentJson,
      if (updatedAtMs != null) 'updated_at_ms': updatedAtMs,
      if (rowid != null) 'rowid': rowid,
    });
  }

  AssessmentDraftsCompanion copyWith({
    Value<String>? subjectId,
    Value<String>? documentJson,
    Value<int>? updatedAtMs,
    Value<int>? rowid,
  }) {
    return AssessmentDraftsCompanion(
      subjectId: subjectId ?? this.subjectId,
      documentJson: documentJson ?? this.documentJson,
      updatedAtMs: updatedAtMs ?? this.updatedAtMs,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (subjectId.present) {
      map['subject_id'] = Variable<String>(subjectId.value);
    }
    if (documentJson.present) {
      map['document_json'] = Variable<String>(documentJson.value);
    }
    if (updatedAtMs.present) {
      map['updated_at_ms'] = Variable<int>(updatedAtMs.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('AssessmentDraftsCompanion(')
          ..write('subjectId: $subjectId, ')
          ..write('documentJson: $documentJson, ')
          ..write('updatedAtMs: $updatedAtMs, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $AssessmentRecordsTable extends AssessmentRecords
    with TableInfo<$AssessmentRecordsTable, AssessmentRecord> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $AssessmentRecordsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _subjectIdMeta = const VerificationMeta(
    'subjectId',
  );
  @override
  late final GeneratedColumn<String> subjectId = GeneratedColumn<String>(
    'subject_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _documentJsonMeta = const VerificationMeta(
    'documentJson',
  );
  @override
  late final GeneratedColumn<String> documentJson = GeneratedColumn<String>(
    'document_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMsMeta = const VerificationMeta(
    'updatedAtMs',
  );
  @override
  late final GeneratedColumn<int> updatedAtMs = GeneratedColumn<int>(
    'updated_at_ms',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [subjectId, documentJson, updatedAtMs];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'assessment_records';
  @override
  VerificationContext validateIntegrity(
    Insertable<AssessmentRecord> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('subject_id')) {
      context.handle(
        _subjectIdMeta,
        subjectId.isAcceptableOrUnknown(data['subject_id']!, _subjectIdMeta),
      );
    } else if (isInserting) {
      context.missing(_subjectIdMeta);
    }
    if (data.containsKey('document_json')) {
      context.handle(
        _documentJsonMeta,
        documentJson.isAcceptableOrUnknown(
          data['document_json']!,
          _documentJsonMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_documentJsonMeta);
    }
    if (data.containsKey('updated_at_ms')) {
      context.handle(
        _updatedAtMsMeta,
        updatedAtMs.isAcceptableOrUnknown(
          data['updated_at_ms']!,
          _updatedAtMsMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMsMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {subjectId};
  @override
  AssessmentRecord map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return AssessmentRecord(
      subjectId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}subject_id'],
      )!,
      documentJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}document_json'],
      )!,
      updatedAtMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}updated_at_ms'],
      )!,
    );
  }

  @override
  $AssessmentRecordsTable createAlias(String alias) {
    return $AssessmentRecordsTable(attachedDatabase, alias);
  }
}

class AssessmentRecord extends DataClass
    implements Insertable<AssessmentRecord> {
  final String subjectId;
  final String documentJson;
  final int updatedAtMs;
  const AssessmentRecord({
    required this.subjectId,
    required this.documentJson,
    required this.updatedAtMs,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['subject_id'] = Variable<String>(subjectId);
    map['document_json'] = Variable<String>(documentJson);
    map['updated_at_ms'] = Variable<int>(updatedAtMs);
    return map;
  }

  AssessmentRecordsCompanion toCompanion(bool nullToAbsent) {
    return AssessmentRecordsCompanion(
      subjectId: Value(subjectId),
      documentJson: Value(documentJson),
      updatedAtMs: Value(updatedAtMs),
    );
  }

  factory AssessmentRecord.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return AssessmentRecord(
      subjectId: serializer.fromJson<String>(json['subjectId']),
      documentJson: serializer.fromJson<String>(json['documentJson']),
      updatedAtMs: serializer.fromJson<int>(json['updatedAtMs']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'subjectId': serializer.toJson<String>(subjectId),
      'documentJson': serializer.toJson<String>(documentJson),
      'updatedAtMs': serializer.toJson<int>(updatedAtMs),
    };
  }

  AssessmentRecord copyWith({
    String? subjectId,
    String? documentJson,
    int? updatedAtMs,
  }) => AssessmentRecord(
    subjectId: subjectId ?? this.subjectId,
    documentJson: documentJson ?? this.documentJson,
    updatedAtMs: updatedAtMs ?? this.updatedAtMs,
  );
  AssessmentRecord copyWithCompanion(AssessmentRecordsCompanion data) {
    return AssessmentRecord(
      subjectId: data.subjectId.present ? data.subjectId.value : this.subjectId,
      documentJson: data.documentJson.present
          ? data.documentJson.value
          : this.documentJson,
      updatedAtMs: data.updatedAtMs.present
          ? data.updatedAtMs.value
          : this.updatedAtMs,
    );
  }

  @override
  String toString() {
    return (StringBuffer('AssessmentRecord(')
          ..write('subjectId: $subjectId, ')
          ..write('documentJson: $documentJson, ')
          ..write('updatedAtMs: $updatedAtMs')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(subjectId, documentJson, updatedAtMs);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is AssessmentRecord &&
          other.subjectId == this.subjectId &&
          other.documentJson == this.documentJson &&
          other.updatedAtMs == this.updatedAtMs);
}

class AssessmentRecordsCompanion extends UpdateCompanion<AssessmentRecord> {
  final Value<String> subjectId;
  final Value<String> documentJson;
  final Value<int> updatedAtMs;
  final Value<int> rowid;
  const AssessmentRecordsCompanion({
    this.subjectId = const Value.absent(),
    this.documentJson = const Value.absent(),
    this.updatedAtMs = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  AssessmentRecordsCompanion.insert({
    required String subjectId,
    required String documentJson,
    required int updatedAtMs,
    this.rowid = const Value.absent(),
  }) : subjectId = Value(subjectId),
       documentJson = Value(documentJson),
       updatedAtMs = Value(updatedAtMs);
  static Insertable<AssessmentRecord> custom({
    Expression<String>? subjectId,
    Expression<String>? documentJson,
    Expression<int>? updatedAtMs,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (subjectId != null) 'subject_id': subjectId,
      if (documentJson != null) 'document_json': documentJson,
      if (updatedAtMs != null) 'updated_at_ms': updatedAtMs,
      if (rowid != null) 'rowid': rowid,
    });
  }

  AssessmentRecordsCompanion copyWith({
    Value<String>? subjectId,
    Value<String>? documentJson,
    Value<int>? updatedAtMs,
    Value<int>? rowid,
  }) {
    return AssessmentRecordsCompanion(
      subjectId: subjectId ?? this.subjectId,
      documentJson: documentJson ?? this.documentJson,
      updatedAtMs: updatedAtMs ?? this.updatedAtMs,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (subjectId.present) {
      map['subject_id'] = Variable<String>(subjectId.value);
    }
    if (documentJson.present) {
      map['document_json'] = Variable<String>(documentJson.value);
    }
    if (updatedAtMs.present) {
      map['updated_at_ms'] = Variable<int>(updatedAtMs.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('AssessmentRecordsCompanion(')
          ..write('subjectId: $subjectId, ')
          ..write('documentJson: $documentJson, ')
          ..write('updatedAtMs: $updatedAtMs, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $ProgramRecordsTable extends ProgramRecords
    with TableInfo<$ProgramRecordsTable, ProgramRecord> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ProgramRecordsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _subjectIdMeta = const VerificationMeta(
    'subjectId',
  );
  @override
  late final GeneratedColumn<String> subjectId = GeneratedColumn<String>(
    'subject_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _documentJsonMeta = const VerificationMeta(
    'documentJson',
  );
  @override
  late final GeneratedColumn<String> documentJson = GeneratedColumn<String>(
    'document_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMsMeta = const VerificationMeta(
    'updatedAtMs',
  );
  @override
  late final GeneratedColumn<int> updatedAtMs = GeneratedColumn<int>(
    'updated_at_ms',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [subjectId, documentJson, updatedAtMs];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'program_records';
  @override
  VerificationContext validateIntegrity(
    Insertable<ProgramRecord> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('subject_id')) {
      context.handle(
        _subjectIdMeta,
        subjectId.isAcceptableOrUnknown(data['subject_id']!, _subjectIdMeta),
      );
    } else if (isInserting) {
      context.missing(_subjectIdMeta);
    }
    if (data.containsKey('document_json')) {
      context.handle(
        _documentJsonMeta,
        documentJson.isAcceptableOrUnknown(
          data['document_json']!,
          _documentJsonMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_documentJsonMeta);
    }
    if (data.containsKey('updated_at_ms')) {
      context.handle(
        _updatedAtMsMeta,
        updatedAtMs.isAcceptableOrUnknown(
          data['updated_at_ms']!,
          _updatedAtMsMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMsMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {subjectId};
  @override
  ProgramRecord map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ProgramRecord(
      subjectId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}subject_id'],
      )!,
      documentJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}document_json'],
      )!,
      updatedAtMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}updated_at_ms'],
      )!,
    );
  }

  @override
  $ProgramRecordsTable createAlias(String alias) {
    return $ProgramRecordsTable(attachedDatabase, alias);
  }
}

class ProgramRecord extends DataClass implements Insertable<ProgramRecord> {
  final String subjectId;
  final String documentJson;
  final int updatedAtMs;
  const ProgramRecord({
    required this.subjectId,
    required this.documentJson,
    required this.updatedAtMs,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['subject_id'] = Variable<String>(subjectId);
    map['document_json'] = Variable<String>(documentJson);
    map['updated_at_ms'] = Variable<int>(updatedAtMs);
    return map;
  }

  ProgramRecordsCompanion toCompanion(bool nullToAbsent) {
    return ProgramRecordsCompanion(
      subjectId: Value(subjectId),
      documentJson: Value(documentJson),
      updatedAtMs: Value(updatedAtMs),
    );
  }

  factory ProgramRecord.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ProgramRecord(
      subjectId: serializer.fromJson<String>(json['subjectId']),
      documentJson: serializer.fromJson<String>(json['documentJson']),
      updatedAtMs: serializer.fromJson<int>(json['updatedAtMs']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'subjectId': serializer.toJson<String>(subjectId),
      'documentJson': serializer.toJson<String>(documentJson),
      'updatedAtMs': serializer.toJson<int>(updatedAtMs),
    };
  }

  ProgramRecord copyWith({
    String? subjectId,
    String? documentJson,
    int? updatedAtMs,
  }) => ProgramRecord(
    subjectId: subjectId ?? this.subjectId,
    documentJson: documentJson ?? this.documentJson,
    updatedAtMs: updatedAtMs ?? this.updatedAtMs,
  );
  ProgramRecord copyWithCompanion(ProgramRecordsCompanion data) {
    return ProgramRecord(
      subjectId: data.subjectId.present ? data.subjectId.value : this.subjectId,
      documentJson: data.documentJson.present
          ? data.documentJson.value
          : this.documentJson,
      updatedAtMs: data.updatedAtMs.present
          ? data.updatedAtMs.value
          : this.updatedAtMs,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ProgramRecord(')
          ..write('subjectId: $subjectId, ')
          ..write('documentJson: $documentJson, ')
          ..write('updatedAtMs: $updatedAtMs')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(subjectId, documentJson, updatedAtMs);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ProgramRecord &&
          other.subjectId == this.subjectId &&
          other.documentJson == this.documentJson &&
          other.updatedAtMs == this.updatedAtMs);
}

class ProgramRecordsCompanion extends UpdateCompanion<ProgramRecord> {
  final Value<String> subjectId;
  final Value<String> documentJson;
  final Value<int> updatedAtMs;
  final Value<int> rowid;
  const ProgramRecordsCompanion({
    this.subjectId = const Value.absent(),
    this.documentJson = const Value.absent(),
    this.updatedAtMs = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ProgramRecordsCompanion.insert({
    required String subjectId,
    required String documentJson,
    required int updatedAtMs,
    this.rowid = const Value.absent(),
  }) : subjectId = Value(subjectId),
       documentJson = Value(documentJson),
       updatedAtMs = Value(updatedAtMs);
  static Insertable<ProgramRecord> custom({
    Expression<String>? subjectId,
    Expression<String>? documentJson,
    Expression<int>? updatedAtMs,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (subjectId != null) 'subject_id': subjectId,
      if (documentJson != null) 'document_json': documentJson,
      if (updatedAtMs != null) 'updated_at_ms': updatedAtMs,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ProgramRecordsCompanion copyWith({
    Value<String>? subjectId,
    Value<String>? documentJson,
    Value<int>? updatedAtMs,
    Value<int>? rowid,
  }) {
    return ProgramRecordsCompanion(
      subjectId: subjectId ?? this.subjectId,
      documentJson: documentJson ?? this.documentJson,
      updatedAtMs: updatedAtMs ?? this.updatedAtMs,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (subjectId.present) {
      map['subject_id'] = Variable<String>(subjectId.value);
    }
    if (documentJson.present) {
      map['document_json'] = Variable<String>(documentJson.value);
    }
    if (updatedAtMs.present) {
      map['updated_at_ms'] = Variable<int>(updatedAtMs.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ProgramRecordsCompanion(')
          ..write('subjectId: $subjectId, ')
          ..write('documentJson: $documentJson, ')
          ..write('updatedAtMs: $updatedAtMs, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $WorkoutDraftsTable extends WorkoutDrafts
    with TableInfo<$WorkoutDraftsTable, WorkoutDraft> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $WorkoutDraftsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _subjectIdMeta = const VerificationMeta(
    'subjectId',
  );
  @override
  late final GeneratedColumn<String> subjectId = GeneratedColumn<String>(
    'subject_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _documentJsonMeta = const VerificationMeta(
    'documentJson',
  );
  @override
  late final GeneratedColumn<String> documentJson = GeneratedColumn<String>(
    'document_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMsMeta = const VerificationMeta(
    'updatedAtMs',
  );
  @override
  late final GeneratedColumn<int> updatedAtMs = GeneratedColumn<int>(
    'updated_at_ms',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [subjectId, documentJson, updatedAtMs];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'workout_drafts';
  @override
  VerificationContext validateIntegrity(
    Insertable<WorkoutDraft> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('subject_id')) {
      context.handle(
        _subjectIdMeta,
        subjectId.isAcceptableOrUnknown(data['subject_id']!, _subjectIdMeta),
      );
    } else if (isInserting) {
      context.missing(_subjectIdMeta);
    }
    if (data.containsKey('document_json')) {
      context.handle(
        _documentJsonMeta,
        documentJson.isAcceptableOrUnknown(
          data['document_json']!,
          _documentJsonMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_documentJsonMeta);
    }
    if (data.containsKey('updated_at_ms')) {
      context.handle(
        _updatedAtMsMeta,
        updatedAtMs.isAcceptableOrUnknown(
          data['updated_at_ms']!,
          _updatedAtMsMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMsMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {subjectId};
  @override
  WorkoutDraft map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return WorkoutDraft(
      subjectId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}subject_id'],
      )!,
      documentJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}document_json'],
      )!,
      updatedAtMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}updated_at_ms'],
      )!,
    );
  }

  @override
  $WorkoutDraftsTable createAlias(String alias) {
    return $WorkoutDraftsTable(attachedDatabase, alias);
  }
}

class WorkoutDraft extends DataClass implements Insertable<WorkoutDraft> {
  final String subjectId;
  final String documentJson;
  final int updatedAtMs;
  const WorkoutDraft({
    required this.subjectId,
    required this.documentJson,
    required this.updatedAtMs,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['subject_id'] = Variable<String>(subjectId);
    map['document_json'] = Variable<String>(documentJson);
    map['updated_at_ms'] = Variable<int>(updatedAtMs);
    return map;
  }

  WorkoutDraftsCompanion toCompanion(bool nullToAbsent) {
    return WorkoutDraftsCompanion(
      subjectId: Value(subjectId),
      documentJson: Value(documentJson),
      updatedAtMs: Value(updatedAtMs),
    );
  }

  factory WorkoutDraft.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return WorkoutDraft(
      subjectId: serializer.fromJson<String>(json['subjectId']),
      documentJson: serializer.fromJson<String>(json['documentJson']),
      updatedAtMs: serializer.fromJson<int>(json['updatedAtMs']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'subjectId': serializer.toJson<String>(subjectId),
      'documentJson': serializer.toJson<String>(documentJson),
      'updatedAtMs': serializer.toJson<int>(updatedAtMs),
    };
  }

  WorkoutDraft copyWith({
    String? subjectId,
    String? documentJson,
    int? updatedAtMs,
  }) => WorkoutDraft(
    subjectId: subjectId ?? this.subjectId,
    documentJson: documentJson ?? this.documentJson,
    updatedAtMs: updatedAtMs ?? this.updatedAtMs,
  );
  WorkoutDraft copyWithCompanion(WorkoutDraftsCompanion data) {
    return WorkoutDraft(
      subjectId: data.subjectId.present ? data.subjectId.value : this.subjectId,
      documentJson: data.documentJson.present
          ? data.documentJson.value
          : this.documentJson,
      updatedAtMs: data.updatedAtMs.present
          ? data.updatedAtMs.value
          : this.updatedAtMs,
    );
  }

  @override
  String toString() {
    return (StringBuffer('WorkoutDraft(')
          ..write('subjectId: $subjectId, ')
          ..write('documentJson: $documentJson, ')
          ..write('updatedAtMs: $updatedAtMs')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(subjectId, documentJson, updatedAtMs);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is WorkoutDraft &&
          other.subjectId == this.subjectId &&
          other.documentJson == this.documentJson &&
          other.updatedAtMs == this.updatedAtMs);
}

class WorkoutDraftsCompanion extends UpdateCompanion<WorkoutDraft> {
  final Value<String> subjectId;
  final Value<String> documentJson;
  final Value<int> updatedAtMs;
  final Value<int> rowid;
  const WorkoutDraftsCompanion({
    this.subjectId = const Value.absent(),
    this.documentJson = const Value.absent(),
    this.updatedAtMs = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  WorkoutDraftsCompanion.insert({
    required String subjectId,
    required String documentJson,
    required int updatedAtMs,
    this.rowid = const Value.absent(),
  }) : subjectId = Value(subjectId),
       documentJson = Value(documentJson),
       updatedAtMs = Value(updatedAtMs);
  static Insertable<WorkoutDraft> custom({
    Expression<String>? subjectId,
    Expression<String>? documentJson,
    Expression<int>? updatedAtMs,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (subjectId != null) 'subject_id': subjectId,
      if (documentJson != null) 'document_json': documentJson,
      if (updatedAtMs != null) 'updated_at_ms': updatedAtMs,
      if (rowid != null) 'rowid': rowid,
    });
  }

  WorkoutDraftsCompanion copyWith({
    Value<String>? subjectId,
    Value<String>? documentJson,
    Value<int>? updatedAtMs,
    Value<int>? rowid,
  }) {
    return WorkoutDraftsCompanion(
      subjectId: subjectId ?? this.subjectId,
      documentJson: documentJson ?? this.documentJson,
      updatedAtMs: updatedAtMs ?? this.updatedAtMs,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (subjectId.present) {
      map['subject_id'] = Variable<String>(subjectId.value);
    }
    if (documentJson.present) {
      map['document_json'] = Variable<String>(documentJson.value);
    }
    if (updatedAtMs.present) {
      map['updated_at_ms'] = Variable<int>(updatedAtMs.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('WorkoutDraftsCompanion(')
          ..write('subjectId: $subjectId, ')
          ..write('documentJson: $documentJson, ')
          ..write('updatedAtMs: $updatedAtMs, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $WorkoutRecordsTable extends WorkoutRecords
    with TableInfo<$WorkoutRecordsTable, WorkoutRecord> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $WorkoutRecordsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _subjectIdMeta = const VerificationMeta(
    'subjectId',
  );
  @override
  late final GeneratedColumn<String> subjectId = GeneratedColumn<String>(
    'subject_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _sessionIdMeta = const VerificationMeta(
    'sessionId',
  );
  @override
  late final GeneratedColumn<String> sessionId = GeneratedColumn<String>(
    'session_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _documentJsonMeta = const VerificationMeta(
    'documentJson',
  );
  @override
  late final GeneratedColumn<String> documentJson = GeneratedColumn<String>(
    'document_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMsMeta = const VerificationMeta(
    'updatedAtMs',
  );
  @override
  late final GeneratedColumn<int> updatedAtMs = GeneratedColumn<int>(
    'updated_at_ms',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    subjectId,
    sessionId,
    documentJson,
    updatedAtMs,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'workout_records';
  @override
  VerificationContext validateIntegrity(
    Insertable<WorkoutRecord> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('subject_id')) {
      context.handle(
        _subjectIdMeta,
        subjectId.isAcceptableOrUnknown(data['subject_id']!, _subjectIdMeta),
      );
    } else if (isInserting) {
      context.missing(_subjectIdMeta);
    }
    if (data.containsKey('session_id')) {
      context.handle(
        _sessionIdMeta,
        sessionId.isAcceptableOrUnknown(data['session_id']!, _sessionIdMeta),
      );
    } else if (isInserting) {
      context.missing(_sessionIdMeta);
    }
    if (data.containsKey('document_json')) {
      context.handle(
        _documentJsonMeta,
        documentJson.isAcceptableOrUnknown(
          data['document_json']!,
          _documentJsonMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_documentJsonMeta);
    }
    if (data.containsKey('updated_at_ms')) {
      context.handle(
        _updatedAtMsMeta,
        updatedAtMs.isAcceptableOrUnknown(
          data['updated_at_ms']!,
          _updatedAtMsMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMsMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {subjectId, sessionId};
  @override
  WorkoutRecord map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return WorkoutRecord(
      subjectId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}subject_id'],
      )!,
      sessionId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}session_id'],
      )!,
      documentJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}document_json'],
      )!,
      updatedAtMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}updated_at_ms'],
      )!,
    );
  }

  @override
  $WorkoutRecordsTable createAlias(String alias) {
    return $WorkoutRecordsTable(attachedDatabase, alias);
  }
}

class WorkoutRecord extends DataClass implements Insertable<WorkoutRecord> {
  final String subjectId;
  final String sessionId;
  final String documentJson;
  final int updatedAtMs;
  const WorkoutRecord({
    required this.subjectId,
    required this.sessionId,
    required this.documentJson,
    required this.updatedAtMs,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['subject_id'] = Variable<String>(subjectId);
    map['session_id'] = Variable<String>(sessionId);
    map['document_json'] = Variable<String>(documentJson);
    map['updated_at_ms'] = Variable<int>(updatedAtMs);
    return map;
  }

  WorkoutRecordsCompanion toCompanion(bool nullToAbsent) {
    return WorkoutRecordsCompanion(
      subjectId: Value(subjectId),
      sessionId: Value(sessionId),
      documentJson: Value(documentJson),
      updatedAtMs: Value(updatedAtMs),
    );
  }

  factory WorkoutRecord.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return WorkoutRecord(
      subjectId: serializer.fromJson<String>(json['subjectId']),
      sessionId: serializer.fromJson<String>(json['sessionId']),
      documentJson: serializer.fromJson<String>(json['documentJson']),
      updatedAtMs: serializer.fromJson<int>(json['updatedAtMs']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'subjectId': serializer.toJson<String>(subjectId),
      'sessionId': serializer.toJson<String>(sessionId),
      'documentJson': serializer.toJson<String>(documentJson),
      'updatedAtMs': serializer.toJson<int>(updatedAtMs),
    };
  }

  WorkoutRecord copyWith({
    String? subjectId,
    String? sessionId,
    String? documentJson,
    int? updatedAtMs,
  }) => WorkoutRecord(
    subjectId: subjectId ?? this.subjectId,
    sessionId: sessionId ?? this.sessionId,
    documentJson: documentJson ?? this.documentJson,
    updatedAtMs: updatedAtMs ?? this.updatedAtMs,
  );
  WorkoutRecord copyWithCompanion(WorkoutRecordsCompanion data) {
    return WorkoutRecord(
      subjectId: data.subjectId.present ? data.subjectId.value : this.subjectId,
      sessionId: data.sessionId.present ? data.sessionId.value : this.sessionId,
      documentJson: data.documentJson.present
          ? data.documentJson.value
          : this.documentJson,
      updatedAtMs: data.updatedAtMs.present
          ? data.updatedAtMs.value
          : this.updatedAtMs,
    );
  }

  @override
  String toString() {
    return (StringBuffer('WorkoutRecord(')
          ..write('subjectId: $subjectId, ')
          ..write('sessionId: $sessionId, ')
          ..write('documentJson: $documentJson, ')
          ..write('updatedAtMs: $updatedAtMs')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(subjectId, sessionId, documentJson, updatedAtMs);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is WorkoutRecord &&
          other.subjectId == this.subjectId &&
          other.sessionId == this.sessionId &&
          other.documentJson == this.documentJson &&
          other.updatedAtMs == this.updatedAtMs);
}

class WorkoutRecordsCompanion extends UpdateCompanion<WorkoutRecord> {
  final Value<String> subjectId;
  final Value<String> sessionId;
  final Value<String> documentJson;
  final Value<int> updatedAtMs;
  final Value<int> rowid;
  const WorkoutRecordsCompanion({
    this.subjectId = const Value.absent(),
    this.sessionId = const Value.absent(),
    this.documentJson = const Value.absent(),
    this.updatedAtMs = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  WorkoutRecordsCompanion.insert({
    required String subjectId,
    required String sessionId,
    required String documentJson,
    required int updatedAtMs,
    this.rowid = const Value.absent(),
  }) : subjectId = Value(subjectId),
       sessionId = Value(sessionId),
       documentJson = Value(documentJson),
       updatedAtMs = Value(updatedAtMs);
  static Insertable<WorkoutRecord> custom({
    Expression<String>? subjectId,
    Expression<String>? sessionId,
    Expression<String>? documentJson,
    Expression<int>? updatedAtMs,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (subjectId != null) 'subject_id': subjectId,
      if (sessionId != null) 'session_id': sessionId,
      if (documentJson != null) 'document_json': documentJson,
      if (updatedAtMs != null) 'updated_at_ms': updatedAtMs,
      if (rowid != null) 'rowid': rowid,
    });
  }

  WorkoutRecordsCompanion copyWith({
    Value<String>? subjectId,
    Value<String>? sessionId,
    Value<String>? documentJson,
    Value<int>? updatedAtMs,
    Value<int>? rowid,
  }) {
    return WorkoutRecordsCompanion(
      subjectId: subjectId ?? this.subjectId,
      sessionId: sessionId ?? this.sessionId,
      documentJson: documentJson ?? this.documentJson,
      updatedAtMs: updatedAtMs ?? this.updatedAtMs,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (subjectId.present) {
      map['subject_id'] = Variable<String>(subjectId.value);
    }
    if (sessionId.present) {
      map['session_id'] = Variable<String>(sessionId.value);
    }
    if (documentJson.present) {
      map['document_json'] = Variable<String>(documentJson.value);
    }
    if (updatedAtMs.present) {
      map['updated_at_ms'] = Variable<int>(updatedAtMs.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('WorkoutRecordsCompanion(')
          ..write('subjectId: $subjectId, ')
          ..write('sessionId: $sessionId, ')
          ..write('documentJson: $documentJson, ')
          ..write('updatedAtMs: $updatedAtMs, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$ProfileDatabase extends GeneratedDatabase {
  _$ProfileDatabase(QueryExecutor e) : super(e);
  $ProfileDatabaseManager get managers => $ProfileDatabaseManager(this);
  late final $LocalProfilesTable localProfiles = $LocalProfilesTable(this);
  late final $LocalEventsTable localEvents = $LocalEventsTable(this);
  late final $IntakeDraftsTable intakeDrafts = $IntakeDraftsTable(this);
  late final $AssessmentDraftsTable assessmentDrafts = $AssessmentDraftsTable(
    this,
  );
  late final $AssessmentRecordsTable assessmentRecords =
      $AssessmentRecordsTable(this);
  late final $ProgramRecordsTable programRecords = $ProgramRecordsTable(this);
  late final $WorkoutDraftsTable workoutDrafts = $WorkoutDraftsTable(this);
  late final $WorkoutRecordsTable workoutRecords = $WorkoutRecordsTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    localProfiles,
    localEvents,
    intakeDrafts,
    assessmentDrafts,
    assessmentRecords,
    programRecords,
    workoutDrafts,
    workoutRecords,
  ];
}

typedef $$LocalProfilesTableCreateCompanionBuilder =
    LocalProfilesCompanion Function({
      required String subjectId,
      required int createdAtMs,
      required int lastActiveAtMs,
      Value<int> rowid,
    });
typedef $$LocalProfilesTableUpdateCompanionBuilder =
    LocalProfilesCompanion Function({
      Value<String> subjectId,
      Value<int> createdAtMs,
      Value<int> lastActiveAtMs,
      Value<int> rowid,
    });

class $$LocalProfilesTableFilterComposer
    extends Composer<_$ProfileDatabase, $LocalProfilesTable> {
  $$LocalProfilesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get subjectId => $composableBuilder(
    column: $table.subjectId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get createdAtMs => $composableBuilder(
    column: $table.createdAtMs,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get lastActiveAtMs => $composableBuilder(
    column: $table.lastActiveAtMs,
    builder: (column) => ColumnFilters(column),
  );
}

class $$LocalProfilesTableOrderingComposer
    extends Composer<_$ProfileDatabase, $LocalProfilesTable> {
  $$LocalProfilesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get subjectId => $composableBuilder(
    column: $table.subjectId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get createdAtMs => $composableBuilder(
    column: $table.createdAtMs,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get lastActiveAtMs => $composableBuilder(
    column: $table.lastActiveAtMs,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$LocalProfilesTableAnnotationComposer
    extends Composer<_$ProfileDatabase, $LocalProfilesTable> {
  $$LocalProfilesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get subjectId =>
      $composableBuilder(column: $table.subjectId, builder: (column) => column);

  GeneratedColumn<int> get createdAtMs => $composableBuilder(
    column: $table.createdAtMs,
    builder: (column) => column,
  );

  GeneratedColumn<int> get lastActiveAtMs => $composableBuilder(
    column: $table.lastActiveAtMs,
    builder: (column) => column,
  );
}

class $$LocalProfilesTableTableManager
    extends
        RootTableManager<
          _$ProfileDatabase,
          $LocalProfilesTable,
          LocalProfile,
          $$LocalProfilesTableFilterComposer,
          $$LocalProfilesTableOrderingComposer,
          $$LocalProfilesTableAnnotationComposer,
          $$LocalProfilesTableCreateCompanionBuilder,
          $$LocalProfilesTableUpdateCompanionBuilder,
          (
            LocalProfile,
            BaseReferences<
              _$ProfileDatabase,
              $LocalProfilesTable,
              LocalProfile
            >,
          ),
          LocalProfile,
          PrefetchHooks Function()
        > {
  $$LocalProfilesTableTableManager(
    _$ProfileDatabase db,
    $LocalProfilesTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$LocalProfilesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$LocalProfilesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$LocalProfilesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> subjectId = const Value.absent(),
                Value<int> createdAtMs = const Value.absent(),
                Value<int> lastActiveAtMs = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => LocalProfilesCompanion(
                subjectId: subjectId,
                createdAtMs: createdAtMs,
                lastActiveAtMs: lastActiveAtMs,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String subjectId,
                required int createdAtMs,
                required int lastActiveAtMs,
                Value<int> rowid = const Value.absent(),
              }) => LocalProfilesCompanion.insert(
                subjectId: subjectId,
                createdAtMs: createdAtMs,
                lastActiveAtMs: lastActiveAtMs,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$LocalProfilesTable, LocalProfile>(table),
                  BaseReferences<
                    _$ProfileDatabase,
                    $LocalProfilesTable,
                    LocalProfile
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$LocalProfilesTableProcessedTableManager =
    ProcessedTableManager<
      _$ProfileDatabase,
      $LocalProfilesTable,
      LocalProfile,
      $$LocalProfilesTableFilterComposer,
      $$LocalProfilesTableOrderingComposer,
      $$LocalProfilesTableAnnotationComposer,
      $$LocalProfilesTableCreateCompanionBuilder,
      $$LocalProfilesTableUpdateCompanionBuilder,
      (
        LocalProfile,
        BaseReferences<_$ProfileDatabase, $LocalProfilesTable, LocalProfile>,
      ),
      LocalProfile,
      PrefetchHooks Function()
    >;
typedef $$LocalEventsTableCreateCompanionBuilder =
    LocalEventsCompanion Function({
      required String eventId,
      required String subjectId,
      required String eventType,
      required String payloadText,
      required int createdAtMs,
      Value<int> rowid,
    });
typedef $$LocalEventsTableUpdateCompanionBuilder =
    LocalEventsCompanion Function({
      Value<String> eventId,
      Value<String> subjectId,
      Value<String> eventType,
      Value<String> payloadText,
      Value<int> createdAtMs,
      Value<int> rowid,
    });

class $$LocalEventsTableFilterComposer
    extends Composer<_$ProfileDatabase, $LocalEventsTable> {
  $$LocalEventsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get eventId => $composableBuilder(
    column: $table.eventId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get subjectId => $composableBuilder(
    column: $table.subjectId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get eventType => $composableBuilder(
    column: $table.eventType,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get payloadText => $composableBuilder(
    column: $table.payloadText,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get createdAtMs => $composableBuilder(
    column: $table.createdAtMs,
    builder: (column) => ColumnFilters(column),
  );
}

class $$LocalEventsTableOrderingComposer
    extends Composer<_$ProfileDatabase, $LocalEventsTable> {
  $$LocalEventsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get eventId => $composableBuilder(
    column: $table.eventId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get subjectId => $composableBuilder(
    column: $table.subjectId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get eventType => $composableBuilder(
    column: $table.eventType,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get payloadText => $composableBuilder(
    column: $table.payloadText,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get createdAtMs => $composableBuilder(
    column: $table.createdAtMs,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$LocalEventsTableAnnotationComposer
    extends Composer<_$ProfileDatabase, $LocalEventsTable> {
  $$LocalEventsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get eventId =>
      $composableBuilder(column: $table.eventId, builder: (column) => column);

  GeneratedColumn<String> get subjectId =>
      $composableBuilder(column: $table.subjectId, builder: (column) => column);

  GeneratedColumn<String> get eventType =>
      $composableBuilder(column: $table.eventType, builder: (column) => column);

  GeneratedColumn<String> get payloadText => $composableBuilder(
    column: $table.payloadText,
    builder: (column) => column,
  );

  GeneratedColumn<int> get createdAtMs => $composableBuilder(
    column: $table.createdAtMs,
    builder: (column) => column,
  );
}

class $$LocalEventsTableTableManager
    extends
        RootTableManager<
          _$ProfileDatabase,
          $LocalEventsTable,
          LocalEvent,
          $$LocalEventsTableFilterComposer,
          $$LocalEventsTableOrderingComposer,
          $$LocalEventsTableAnnotationComposer,
          $$LocalEventsTableCreateCompanionBuilder,
          $$LocalEventsTableUpdateCompanionBuilder,
          (
            LocalEvent,
            BaseReferences<_$ProfileDatabase, $LocalEventsTable, LocalEvent>,
          ),
          LocalEvent,
          PrefetchHooks Function()
        > {
  $$LocalEventsTableTableManager(_$ProfileDatabase db, $LocalEventsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$LocalEventsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$LocalEventsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$LocalEventsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> eventId = const Value.absent(),
                Value<String> subjectId = const Value.absent(),
                Value<String> eventType = const Value.absent(),
                Value<String> payloadText = const Value.absent(),
                Value<int> createdAtMs = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => LocalEventsCompanion(
                eventId: eventId,
                subjectId: subjectId,
                eventType: eventType,
                payloadText: payloadText,
                createdAtMs: createdAtMs,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String eventId,
                required String subjectId,
                required String eventType,
                required String payloadText,
                required int createdAtMs,
                Value<int> rowid = const Value.absent(),
              }) => LocalEventsCompanion.insert(
                eventId: eventId,
                subjectId: subjectId,
                eventType: eventType,
                payloadText: payloadText,
                createdAtMs: createdAtMs,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$LocalEventsTable, LocalEvent>(table),
                  BaseReferences<
                    _$ProfileDatabase,
                    $LocalEventsTable,
                    LocalEvent
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$LocalEventsTableProcessedTableManager =
    ProcessedTableManager<
      _$ProfileDatabase,
      $LocalEventsTable,
      LocalEvent,
      $$LocalEventsTableFilterComposer,
      $$LocalEventsTableOrderingComposer,
      $$LocalEventsTableAnnotationComposer,
      $$LocalEventsTableCreateCompanionBuilder,
      $$LocalEventsTableUpdateCompanionBuilder,
      (
        LocalEvent,
        BaseReferences<_$ProfileDatabase, $LocalEventsTable, LocalEvent>,
      ),
      LocalEvent,
      PrefetchHooks Function()
    >;
typedef $$IntakeDraftsTableCreateCompanionBuilder =
    IntakeDraftsCompanion Function({
      required String subjectId,
      required String documentJson,
      required int updatedAtMs,
      Value<int> rowid,
    });
typedef $$IntakeDraftsTableUpdateCompanionBuilder =
    IntakeDraftsCompanion Function({
      Value<String> subjectId,
      Value<String> documentJson,
      Value<int> updatedAtMs,
      Value<int> rowid,
    });

class $$IntakeDraftsTableFilterComposer
    extends Composer<_$ProfileDatabase, $IntakeDraftsTable> {
  $$IntakeDraftsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get subjectId => $composableBuilder(
    column: $table.subjectId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get documentJson => $composableBuilder(
    column: $table.documentJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get updatedAtMs => $composableBuilder(
    column: $table.updatedAtMs,
    builder: (column) => ColumnFilters(column),
  );
}

class $$IntakeDraftsTableOrderingComposer
    extends Composer<_$ProfileDatabase, $IntakeDraftsTable> {
  $$IntakeDraftsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get subjectId => $composableBuilder(
    column: $table.subjectId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get documentJson => $composableBuilder(
    column: $table.documentJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get updatedAtMs => $composableBuilder(
    column: $table.updatedAtMs,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$IntakeDraftsTableAnnotationComposer
    extends Composer<_$ProfileDatabase, $IntakeDraftsTable> {
  $$IntakeDraftsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get subjectId =>
      $composableBuilder(column: $table.subjectId, builder: (column) => column);

  GeneratedColumn<String> get documentJson => $composableBuilder(
    column: $table.documentJson,
    builder: (column) => column,
  );

  GeneratedColumn<int> get updatedAtMs => $composableBuilder(
    column: $table.updatedAtMs,
    builder: (column) => column,
  );
}

class $$IntakeDraftsTableTableManager
    extends
        RootTableManager<
          _$ProfileDatabase,
          $IntakeDraftsTable,
          IntakeDraft,
          $$IntakeDraftsTableFilterComposer,
          $$IntakeDraftsTableOrderingComposer,
          $$IntakeDraftsTableAnnotationComposer,
          $$IntakeDraftsTableCreateCompanionBuilder,
          $$IntakeDraftsTableUpdateCompanionBuilder,
          (
            IntakeDraft,
            BaseReferences<_$ProfileDatabase, $IntakeDraftsTable, IntakeDraft>,
          ),
          IntakeDraft,
          PrefetchHooks Function()
        > {
  $$IntakeDraftsTableTableManager(
    _$ProfileDatabase db,
    $IntakeDraftsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$IntakeDraftsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$IntakeDraftsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$IntakeDraftsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> subjectId = const Value.absent(),
                Value<String> documentJson = const Value.absent(),
                Value<int> updatedAtMs = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => IntakeDraftsCompanion(
                subjectId: subjectId,
                documentJson: documentJson,
                updatedAtMs: updatedAtMs,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String subjectId,
                required String documentJson,
                required int updatedAtMs,
                Value<int> rowid = const Value.absent(),
              }) => IntakeDraftsCompanion.insert(
                subjectId: subjectId,
                documentJson: documentJson,
                updatedAtMs: updatedAtMs,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$IntakeDraftsTable, IntakeDraft>(table),
                  BaseReferences<
                    _$ProfileDatabase,
                    $IntakeDraftsTable,
                    IntakeDraft
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$IntakeDraftsTableProcessedTableManager =
    ProcessedTableManager<
      _$ProfileDatabase,
      $IntakeDraftsTable,
      IntakeDraft,
      $$IntakeDraftsTableFilterComposer,
      $$IntakeDraftsTableOrderingComposer,
      $$IntakeDraftsTableAnnotationComposer,
      $$IntakeDraftsTableCreateCompanionBuilder,
      $$IntakeDraftsTableUpdateCompanionBuilder,
      (
        IntakeDraft,
        BaseReferences<_$ProfileDatabase, $IntakeDraftsTable, IntakeDraft>,
      ),
      IntakeDraft,
      PrefetchHooks Function()
    >;
typedef $$AssessmentDraftsTableCreateCompanionBuilder =
    AssessmentDraftsCompanion Function({
      required String subjectId,
      required String documentJson,
      required int updatedAtMs,
      Value<int> rowid,
    });
typedef $$AssessmentDraftsTableUpdateCompanionBuilder =
    AssessmentDraftsCompanion Function({
      Value<String> subjectId,
      Value<String> documentJson,
      Value<int> updatedAtMs,
      Value<int> rowid,
    });

class $$AssessmentDraftsTableFilterComposer
    extends Composer<_$ProfileDatabase, $AssessmentDraftsTable> {
  $$AssessmentDraftsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get subjectId => $composableBuilder(
    column: $table.subjectId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get documentJson => $composableBuilder(
    column: $table.documentJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get updatedAtMs => $composableBuilder(
    column: $table.updatedAtMs,
    builder: (column) => ColumnFilters(column),
  );
}

class $$AssessmentDraftsTableOrderingComposer
    extends Composer<_$ProfileDatabase, $AssessmentDraftsTable> {
  $$AssessmentDraftsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get subjectId => $composableBuilder(
    column: $table.subjectId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get documentJson => $composableBuilder(
    column: $table.documentJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get updatedAtMs => $composableBuilder(
    column: $table.updatedAtMs,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$AssessmentDraftsTableAnnotationComposer
    extends Composer<_$ProfileDatabase, $AssessmentDraftsTable> {
  $$AssessmentDraftsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get subjectId =>
      $composableBuilder(column: $table.subjectId, builder: (column) => column);

  GeneratedColumn<String> get documentJson => $composableBuilder(
    column: $table.documentJson,
    builder: (column) => column,
  );

  GeneratedColumn<int> get updatedAtMs => $composableBuilder(
    column: $table.updatedAtMs,
    builder: (column) => column,
  );
}

class $$AssessmentDraftsTableTableManager
    extends
        RootTableManager<
          _$ProfileDatabase,
          $AssessmentDraftsTable,
          AssessmentDraft,
          $$AssessmentDraftsTableFilterComposer,
          $$AssessmentDraftsTableOrderingComposer,
          $$AssessmentDraftsTableAnnotationComposer,
          $$AssessmentDraftsTableCreateCompanionBuilder,
          $$AssessmentDraftsTableUpdateCompanionBuilder,
          (
            AssessmentDraft,
            BaseReferences<
              _$ProfileDatabase,
              $AssessmentDraftsTable,
              AssessmentDraft
            >,
          ),
          AssessmentDraft,
          PrefetchHooks Function()
        > {
  $$AssessmentDraftsTableTableManager(
    _$ProfileDatabase db,
    $AssessmentDraftsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$AssessmentDraftsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$AssessmentDraftsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$AssessmentDraftsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> subjectId = const Value.absent(),
                Value<String> documentJson = const Value.absent(),
                Value<int> updatedAtMs = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => AssessmentDraftsCompanion(
                subjectId: subjectId,
                documentJson: documentJson,
                updatedAtMs: updatedAtMs,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String subjectId,
                required String documentJson,
                required int updatedAtMs,
                Value<int> rowid = const Value.absent(),
              }) => AssessmentDraftsCompanion.insert(
                subjectId: subjectId,
                documentJson: documentJson,
                updatedAtMs: updatedAtMs,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$AssessmentDraftsTable, AssessmentDraft>(table),
                  BaseReferences<
                    _$ProfileDatabase,
                    $AssessmentDraftsTable,
                    AssessmentDraft
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$AssessmentDraftsTableProcessedTableManager =
    ProcessedTableManager<
      _$ProfileDatabase,
      $AssessmentDraftsTable,
      AssessmentDraft,
      $$AssessmentDraftsTableFilterComposer,
      $$AssessmentDraftsTableOrderingComposer,
      $$AssessmentDraftsTableAnnotationComposer,
      $$AssessmentDraftsTableCreateCompanionBuilder,
      $$AssessmentDraftsTableUpdateCompanionBuilder,
      (
        AssessmentDraft,
        BaseReferences<
          _$ProfileDatabase,
          $AssessmentDraftsTable,
          AssessmentDraft
        >,
      ),
      AssessmentDraft,
      PrefetchHooks Function()
    >;
typedef $$AssessmentRecordsTableCreateCompanionBuilder =
    AssessmentRecordsCompanion Function({
      required String subjectId,
      required String documentJson,
      required int updatedAtMs,
      Value<int> rowid,
    });
typedef $$AssessmentRecordsTableUpdateCompanionBuilder =
    AssessmentRecordsCompanion Function({
      Value<String> subjectId,
      Value<String> documentJson,
      Value<int> updatedAtMs,
      Value<int> rowid,
    });

class $$AssessmentRecordsTableFilterComposer
    extends Composer<_$ProfileDatabase, $AssessmentRecordsTable> {
  $$AssessmentRecordsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get subjectId => $composableBuilder(
    column: $table.subjectId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get documentJson => $composableBuilder(
    column: $table.documentJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get updatedAtMs => $composableBuilder(
    column: $table.updatedAtMs,
    builder: (column) => ColumnFilters(column),
  );
}

class $$AssessmentRecordsTableOrderingComposer
    extends Composer<_$ProfileDatabase, $AssessmentRecordsTable> {
  $$AssessmentRecordsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get subjectId => $composableBuilder(
    column: $table.subjectId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get documentJson => $composableBuilder(
    column: $table.documentJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get updatedAtMs => $composableBuilder(
    column: $table.updatedAtMs,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$AssessmentRecordsTableAnnotationComposer
    extends Composer<_$ProfileDatabase, $AssessmentRecordsTable> {
  $$AssessmentRecordsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get subjectId =>
      $composableBuilder(column: $table.subjectId, builder: (column) => column);

  GeneratedColumn<String> get documentJson => $composableBuilder(
    column: $table.documentJson,
    builder: (column) => column,
  );

  GeneratedColumn<int> get updatedAtMs => $composableBuilder(
    column: $table.updatedAtMs,
    builder: (column) => column,
  );
}

class $$AssessmentRecordsTableTableManager
    extends
        RootTableManager<
          _$ProfileDatabase,
          $AssessmentRecordsTable,
          AssessmentRecord,
          $$AssessmentRecordsTableFilterComposer,
          $$AssessmentRecordsTableOrderingComposer,
          $$AssessmentRecordsTableAnnotationComposer,
          $$AssessmentRecordsTableCreateCompanionBuilder,
          $$AssessmentRecordsTableUpdateCompanionBuilder,
          (
            AssessmentRecord,
            BaseReferences<
              _$ProfileDatabase,
              $AssessmentRecordsTable,
              AssessmentRecord
            >,
          ),
          AssessmentRecord,
          PrefetchHooks Function()
        > {
  $$AssessmentRecordsTableTableManager(
    _$ProfileDatabase db,
    $AssessmentRecordsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$AssessmentRecordsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$AssessmentRecordsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$AssessmentRecordsTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> subjectId = const Value.absent(),
                Value<String> documentJson = const Value.absent(),
                Value<int> updatedAtMs = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => AssessmentRecordsCompanion(
                subjectId: subjectId,
                documentJson: documentJson,
                updatedAtMs: updatedAtMs,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String subjectId,
                required String documentJson,
                required int updatedAtMs,
                Value<int> rowid = const Value.absent(),
              }) => AssessmentRecordsCompanion.insert(
                subjectId: subjectId,
                documentJson: documentJson,
                updatedAtMs: updatedAtMs,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$AssessmentRecordsTable, AssessmentRecord>(table),
                  BaseReferences<
                    _$ProfileDatabase,
                    $AssessmentRecordsTable,
                    AssessmentRecord
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$AssessmentRecordsTableProcessedTableManager =
    ProcessedTableManager<
      _$ProfileDatabase,
      $AssessmentRecordsTable,
      AssessmentRecord,
      $$AssessmentRecordsTableFilterComposer,
      $$AssessmentRecordsTableOrderingComposer,
      $$AssessmentRecordsTableAnnotationComposer,
      $$AssessmentRecordsTableCreateCompanionBuilder,
      $$AssessmentRecordsTableUpdateCompanionBuilder,
      (
        AssessmentRecord,
        BaseReferences<
          _$ProfileDatabase,
          $AssessmentRecordsTable,
          AssessmentRecord
        >,
      ),
      AssessmentRecord,
      PrefetchHooks Function()
    >;
typedef $$ProgramRecordsTableCreateCompanionBuilder =
    ProgramRecordsCompanion Function({
      required String subjectId,
      required String documentJson,
      required int updatedAtMs,
      Value<int> rowid,
    });
typedef $$ProgramRecordsTableUpdateCompanionBuilder =
    ProgramRecordsCompanion Function({
      Value<String> subjectId,
      Value<String> documentJson,
      Value<int> updatedAtMs,
      Value<int> rowid,
    });

class $$ProgramRecordsTableFilterComposer
    extends Composer<_$ProfileDatabase, $ProgramRecordsTable> {
  $$ProgramRecordsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get subjectId => $composableBuilder(
    column: $table.subjectId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get documentJson => $composableBuilder(
    column: $table.documentJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get updatedAtMs => $composableBuilder(
    column: $table.updatedAtMs,
    builder: (column) => ColumnFilters(column),
  );
}

class $$ProgramRecordsTableOrderingComposer
    extends Composer<_$ProfileDatabase, $ProgramRecordsTable> {
  $$ProgramRecordsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get subjectId => $composableBuilder(
    column: $table.subjectId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get documentJson => $composableBuilder(
    column: $table.documentJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get updatedAtMs => $composableBuilder(
    column: $table.updatedAtMs,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$ProgramRecordsTableAnnotationComposer
    extends Composer<_$ProfileDatabase, $ProgramRecordsTable> {
  $$ProgramRecordsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get subjectId =>
      $composableBuilder(column: $table.subjectId, builder: (column) => column);

  GeneratedColumn<String> get documentJson => $composableBuilder(
    column: $table.documentJson,
    builder: (column) => column,
  );

  GeneratedColumn<int> get updatedAtMs => $composableBuilder(
    column: $table.updatedAtMs,
    builder: (column) => column,
  );
}

class $$ProgramRecordsTableTableManager
    extends
        RootTableManager<
          _$ProfileDatabase,
          $ProgramRecordsTable,
          ProgramRecord,
          $$ProgramRecordsTableFilterComposer,
          $$ProgramRecordsTableOrderingComposer,
          $$ProgramRecordsTableAnnotationComposer,
          $$ProgramRecordsTableCreateCompanionBuilder,
          $$ProgramRecordsTableUpdateCompanionBuilder,
          (
            ProgramRecord,
            BaseReferences<
              _$ProfileDatabase,
              $ProgramRecordsTable,
              ProgramRecord
            >,
          ),
          ProgramRecord,
          PrefetchHooks Function()
        > {
  $$ProgramRecordsTableTableManager(
    _$ProfileDatabase db,
    $ProgramRecordsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ProgramRecordsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ProgramRecordsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ProgramRecordsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> subjectId = const Value.absent(),
                Value<String> documentJson = const Value.absent(),
                Value<int> updatedAtMs = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ProgramRecordsCompanion(
                subjectId: subjectId,
                documentJson: documentJson,
                updatedAtMs: updatedAtMs,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String subjectId,
                required String documentJson,
                required int updatedAtMs,
                Value<int> rowid = const Value.absent(),
              }) => ProgramRecordsCompanion.insert(
                subjectId: subjectId,
                documentJson: documentJson,
                updatedAtMs: updatedAtMs,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$ProgramRecordsTable, ProgramRecord>(table),
                  BaseReferences<
                    _$ProfileDatabase,
                    $ProgramRecordsTable,
                    ProgramRecord
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$ProgramRecordsTableProcessedTableManager =
    ProcessedTableManager<
      _$ProfileDatabase,
      $ProgramRecordsTable,
      ProgramRecord,
      $$ProgramRecordsTableFilterComposer,
      $$ProgramRecordsTableOrderingComposer,
      $$ProgramRecordsTableAnnotationComposer,
      $$ProgramRecordsTableCreateCompanionBuilder,
      $$ProgramRecordsTableUpdateCompanionBuilder,
      (
        ProgramRecord,
        BaseReferences<_$ProfileDatabase, $ProgramRecordsTable, ProgramRecord>,
      ),
      ProgramRecord,
      PrefetchHooks Function()
    >;
typedef $$WorkoutDraftsTableCreateCompanionBuilder =
    WorkoutDraftsCompanion Function({
      required String subjectId,
      required String documentJson,
      required int updatedAtMs,
      Value<int> rowid,
    });
typedef $$WorkoutDraftsTableUpdateCompanionBuilder =
    WorkoutDraftsCompanion Function({
      Value<String> subjectId,
      Value<String> documentJson,
      Value<int> updatedAtMs,
      Value<int> rowid,
    });

class $$WorkoutDraftsTableFilterComposer
    extends Composer<_$ProfileDatabase, $WorkoutDraftsTable> {
  $$WorkoutDraftsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get subjectId => $composableBuilder(
    column: $table.subjectId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get documentJson => $composableBuilder(
    column: $table.documentJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get updatedAtMs => $composableBuilder(
    column: $table.updatedAtMs,
    builder: (column) => ColumnFilters(column),
  );
}

class $$WorkoutDraftsTableOrderingComposer
    extends Composer<_$ProfileDatabase, $WorkoutDraftsTable> {
  $$WorkoutDraftsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get subjectId => $composableBuilder(
    column: $table.subjectId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get documentJson => $composableBuilder(
    column: $table.documentJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get updatedAtMs => $composableBuilder(
    column: $table.updatedAtMs,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$WorkoutDraftsTableAnnotationComposer
    extends Composer<_$ProfileDatabase, $WorkoutDraftsTable> {
  $$WorkoutDraftsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get subjectId =>
      $composableBuilder(column: $table.subjectId, builder: (column) => column);

  GeneratedColumn<String> get documentJson => $composableBuilder(
    column: $table.documentJson,
    builder: (column) => column,
  );

  GeneratedColumn<int> get updatedAtMs => $composableBuilder(
    column: $table.updatedAtMs,
    builder: (column) => column,
  );
}

class $$WorkoutDraftsTableTableManager
    extends
        RootTableManager<
          _$ProfileDatabase,
          $WorkoutDraftsTable,
          WorkoutDraft,
          $$WorkoutDraftsTableFilterComposer,
          $$WorkoutDraftsTableOrderingComposer,
          $$WorkoutDraftsTableAnnotationComposer,
          $$WorkoutDraftsTableCreateCompanionBuilder,
          $$WorkoutDraftsTableUpdateCompanionBuilder,
          (
            WorkoutDraft,
            BaseReferences<
              _$ProfileDatabase,
              $WorkoutDraftsTable,
              WorkoutDraft
            >,
          ),
          WorkoutDraft,
          PrefetchHooks Function()
        > {
  $$WorkoutDraftsTableTableManager(
    _$ProfileDatabase db,
    $WorkoutDraftsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$WorkoutDraftsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$WorkoutDraftsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$WorkoutDraftsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> subjectId = const Value.absent(),
                Value<String> documentJson = const Value.absent(),
                Value<int> updatedAtMs = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => WorkoutDraftsCompanion(
                subjectId: subjectId,
                documentJson: documentJson,
                updatedAtMs: updatedAtMs,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String subjectId,
                required String documentJson,
                required int updatedAtMs,
                Value<int> rowid = const Value.absent(),
              }) => WorkoutDraftsCompanion.insert(
                subjectId: subjectId,
                documentJson: documentJson,
                updatedAtMs: updatedAtMs,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$WorkoutDraftsTable, WorkoutDraft>(table),
                  BaseReferences<
                    _$ProfileDatabase,
                    $WorkoutDraftsTable,
                    WorkoutDraft
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$WorkoutDraftsTableProcessedTableManager =
    ProcessedTableManager<
      _$ProfileDatabase,
      $WorkoutDraftsTable,
      WorkoutDraft,
      $$WorkoutDraftsTableFilterComposer,
      $$WorkoutDraftsTableOrderingComposer,
      $$WorkoutDraftsTableAnnotationComposer,
      $$WorkoutDraftsTableCreateCompanionBuilder,
      $$WorkoutDraftsTableUpdateCompanionBuilder,
      (
        WorkoutDraft,
        BaseReferences<_$ProfileDatabase, $WorkoutDraftsTable, WorkoutDraft>,
      ),
      WorkoutDraft,
      PrefetchHooks Function()
    >;
typedef $$WorkoutRecordsTableCreateCompanionBuilder =
    WorkoutRecordsCompanion Function({
      required String subjectId,
      required String sessionId,
      required String documentJson,
      required int updatedAtMs,
      Value<int> rowid,
    });
typedef $$WorkoutRecordsTableUpdateCompanionBuilder =
    WorkoutRecordsCompanion Function({
      Value<String> subjectId,
      Value<String> sessionId,
      Value<String> documentJson,
      Value<int> updatedAtMs,
      Value<int> rowid,
    });

class $$WorkoutRecordsTableFilterComposer
    extends Composer<_$ProfileDatabase, $WorkoutRecordsTable> {
  $$WorkoutRecordsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get subjectId => $composableBuilder(
    column: $table.subjectId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get sessionId => $composableBuilder(
    column: $table.sessionId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get documentJson => $composableBuilder(
    column: $table.documentJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get updatedAtMs => $composableBuilder(
    column: $table.updatedAtMs,
    builder: (column) => ColumnFilters(column),
  );
}

class $$WorkoutRecordsTableOrderingComposer
    extends Composer<_$ProfileDatabase, $WorkoutRecordsTable> {
  $$WorkoutRecordsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get subjectId => $composableBuilder(
    column: $table.subjectId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get sessionId => $composableBuilder(
    column: $table.sessionId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get documentJson => $composableBuilder(
    column: $table.documentJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get updatedAtMs => $composableBuilder(
    column: $table.updatedAtMs,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$WorkoutRecordsTableAnnotationComposer
    extends Composer<_$ProfileDatabase, $WorkoutRecordsTable> {
  $$WorkoutRecordsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get subjectId =>
      $composableBuilder(column: $table.subjectId, builder: (column) => column);

  GeneratedColumn<String> get sessionId =>
      $composableBuilder(column: $table.sessionId, builder: (column) => column);

  GeneratedColumn<String> get documentJson => $composableBuilder(
    column: $table.documentJson,
    builder: (column) => column,
  );

  GeneratedColumn<int> get updatedAtMs => $composableBuilder(
    column: $table.updatedAtMs,
    builder: (column) => column,
  );
}

class $$WorkoutRecordsTableTableManager
    extends
        RootTableManager<
          _$ProfileDatabase,
          $WorkoutRecordsTable,
          WorkoutRecord,
          $$WorkoutRecordsTableFilterComposer,
          $$WorkoutRecordsTableOrderingComposer,
          $$WorkoutRecordsTableAnnotationComposer,
          $$WorkoutRecordsTableCreateCompanionBuilder,
          $$WorkoutRecordsTableUpdateCompanionBuilder,
          (
            WorkoutRecord,
            BaseReferences<
              _$ProfileDatabase,
              $WorkoutRecordsTable,
              WorkoutRecord
            >,
          ),
          WorkoutRecord,
          PrefetchHooks Function()
        > {
  $$WorkoutRecordsTableTableManager(
    _$ProfileDatabase db,
    $WorkoutRecordsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$WorkoutRecordsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$WorkoutRecordsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$WorkoutRecordsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> subjectId = const Value.absent(),
                Value<String> sessionId = const Value.absent(),
                Value<String> documentJson = const Value.absent(),
                Value<int> updatedAtMs = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => WorkoutRecordsCompanion(
                subjectId: subjectId,
                sessionId: sessionId,
                documentJson: documentJson,
                updatedAtMs: updatedAtMs,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String subjectId,
                required String sessionId,
                required String documentJson,
                required int updatedAtMs,
                Value<int> rowid = const Value.absent(),
              }) => WorkoutRecordsCompanion.insert(
                subjectId: subjectId,
                sessionId: sessionId,
                documentJson: documentJson,
                updatedAtMs: updatedAtMs,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$WorkoutRecordsTable, WorkoutRecord>(table),
                  BaseReferences<
                    _$ProfileDatabase,
                    $WorkoutRecordsTable,
                    WorkoutRecord
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$WorkoutRecordsTableProcessedTableManager =
    ProcessedTableManager<
      _$ProfileDatabase,
      $WorkoutRecordsTable,
      WorkoutRecord,
      $$WorkoutRecordsTableFilterComposer,
      $$WorkoutRecordsTableOrderingComposer,
      $$WorkoutRecordsTableAnnotationComposer,
      $$WorkoutRecordsTableCreateCompanionBuilder,
      $$WorkoutRecordsTableUpdateCompanionBuilder,
      (
        WorkoutRecord,
        BaseReferences<_$ProfileDatabase, $WorkoutRecordsTable, WorkoutRecord>,
      ),
      WorkoutRecord,
      PrefetchHooks Function()
    >;

class $ProfileDatabaseManager {
  final _$ProfileDatabase _db;
  $ProfileDatabaseManager(this._db);
  $$LocalProfilesTableTableManager get localProfiles =>
      $$LocalProfilesTableTableManager(_db, _db.localProfiles);
  $$LocalEventsTableTableManager get localEvents =>
      $$LocalEventsTableTableManager(_db, _db.localEvents);
  $$IntakeDraftsTableTableManager get intakeDrafts =>
      $$IntakeDraftsTableTableManager(_db, _db.intakeDrafts);
  $$AssessmentDraftsTableTableManager get assessmentDrafts =>
      $$AssessmentDraftsTableTableManager(_db, _db.assessmentDrafts);
  $$AssessmentRecordsTableTableManager get assessmentRecords =>
      $$AssessmentRecordsTableTableManager(_db, _db.assessmentRecords);
  $$ProgramRecordsTableTableManager get programRecords =>
      $$ProgramRecordsTableTableManager(_db, _db.programRecords);
  $$WorkoutDraftsTableTableManager get workoutDrafts =>
      $$WorkoutDraftsTableTableManager(_db, _db.workoutDrafts);
  $$WorkoutRecordsTableTableManager get workoutRecords =>
      $$WorkoutRecordsTableTableManager(_db, _db.workoutRecords);
}
