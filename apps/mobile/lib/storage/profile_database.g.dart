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

abstract class _$ProfileDatabase extends GeneratedDatabase {
  _$ProfileDatabase(QueryExecutor e) : super(e);
  $ProfileDatabaseManager get managers => $ProfileDatabaseManager(this);
  late final $LocalProfilesTable localProfiles = $LocalProfilesTable(this);
  late final $LocalEventsTable localEvents = $LocalEventsTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    localProfiles,
    localEvents,
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

class $ProfileDatabaseManager {
  final _$ProfileDatabase _db;
  $ProfileDatabaseManager(this._db);
  $$LocalProfilesTableTableManager get localProfiles =>
      $$LocalProfilesTableTableManager(_db, _db.localProfiles);
  $$LocalEventsTableTableManager get localEvents =>
      $$LocalEventsTableTableManager(_db, _db.localEvents);
}
