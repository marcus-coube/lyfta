// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'workout_database.dart';

// ignore_for_file: type=lint
class $TodayCacheTable extends TodayCache
    with TableInfo<$TodayCacheTable, TodayCacheData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $TodayCacheTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _studentIdMeta =
      const VerificationMeta('studentId');
  @override
  late final GeneratedColumn<String> studentId = GeneratedColumn<String>(
      'student_id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _payloadMeta =
      const VerificationMeta('payload');
  @override
  late final GeneratedColumn<String> payload = GeneratedColumn<String>(
      'payload', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _fetchedAtMeta =
      const VerificationMeta('fetchedAt');
  @override
  late final GeneratedColumn<DateTime> fetchedAt = GeneratedColumn<DateTime>(
      'fetched_at', aliasedName, false,
      type: DriftSqlType.dateTime, requiredDuringInsert: true);
  @override
  List<GeneratedColumn> get $columns => [studentId, payload, fetchedAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'today_cache';
  @override
  VerificationContext validateIntegrity(Insertable<TodayCacheData> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('student_id')) {
      context.handle(_studentIdMeta,
          studentId.isAcceptableOrUnknown(data['student_id']!, _studentIdMeta));
    } else if (isInserting) {
      context.missing(_studentIdMeta);
    }
    if (data.containsKey('payload')) {
      context.handle(_payloadMeta,
          payload.isAcceptableOrUnknown(data['payload']!, _payloadMeta));
    } else if (isInserting) {
      context.missing(_payloadMeta);
    }
    if (data.containsKey('fetched_at')) {
      context.handle(_fetchedAtMeta,
          fetchedAt.isAcceptableOrUnknown(data['fetched_at']!, _fetchedAtMeta));
    } else if (isInserting) {
      context.missing(_fetchedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {studentId};
  @override
  TodayCacheData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return TodayCacheData(
      studentId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}student_id'])!,
      payload: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}payload'])!,
      fetchedAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}fetched_at'])!,
    );
  }

  @override
  $TodayCacheTable createAlias(String alias) {
    return $TodayCacheTable(attachedDatabase, alias);
  }
}

class TodayCacheData extends DataClass implements Insertable<TodayCacheData> {
  final String studentId;
  final String payload;
  final DateTime fetchedAt;
  const TodayCacheData(
      {required this.studentId,
      required this.payload,
      required this.fetchedAt});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['student_id'] = Variable<String>(studentId);
    map['payload'] = Variable<String>(payload);
    map['fetched_at'] = Variable<DateTime>(fetchedAt);
    return map;
  }

  TodayCacheCompanion toCompanion(bool nullToAbsent) {
    return TodayCacheCompanion(
      studentId: Value(studentId),
      payload: Value(payload),
      fetchedAt: Value(fetchedAt),
    );
  }

  factory TodayCacheData.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return TodayCacheData(
      studentId: serializer.fromJson<String>(json['studentId']),
      payload: serializer.fromJson<String>(json['payload']),
      fetchedAt: serializer.fromJson<DateTime>(json['fetchedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'studentId': serializer.toJson<String>(studentId),
      'payload': serializer.toJson<String>(payload),
      'fetchedAt': serializer.toJson<DateTime>(fetchedAt),
    };
  }

  TodayCacheData copyWith(
          {String? studentId, String? payload, DateTime? fetchedAt}) =>
      TodayCacheData(
        studentId: studentId ?? this.studentId,
        payload: payload ?? this.payload,
        fetchedAt: fetchedAt ?? this.fetchedAt,
      );
  TodayCacheData copyWithCompanion(TodayCacheCompanion data) {
    return TodayCacheData(
      studentId: data.studentId.present ? data.studentId.value : this.studentId,
      payload: data.payload.present ? data.payload.value : this.payload,
      fetchedAt: data.fetchedAt.present ? data.fetchedAt.value : this.fetchedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('TodayCacheData(')
          ..write('studentId: $studentId, ')
          ..write('payload: $payload, ')
          ..write('fetchedAt: $fetchedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(studentId, payload, fetchedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is TodayCacheData &&
          other.studentId == this.studentId &&
          other.payload == this.payload &&
          other.fetchedAt == this.fetchedAt);
}

class TodayCacheCompanion extends UpdateCompanion<TodayCacheData> {
  final Value<String> studentId;
  final Value<String> payload;
  final Value<DateTime> fetchedAt;
  final Value<int> rowid;
  const TodayCacheCompanion({
    this.studentId = const Value.absent(),
    this.payload = const Value.absent(),
    this.fetchedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  TodayCacheCompanion.insert({
    required String studentId,
    required String payload,
    required DateTime fetchedAt,
    this.rowid = const Value.absent(),
  })  : studentId = Value(studentId),
        payload = Value(payload),
        fetchedAt = Value(fetchedAt);
  static Insertable<TodayCacheData> custom({
    Expression<String>? studentId,
    Expression<String>? payload,
    Expression<DateTime>? fetchedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (studentId != null) 'student_id': studentId,
      if (payload != null) 'payload': payload,
      if (fetchedAt != null) 'fetched_at': fetchedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  TodayCacheCompanion copyWith(
      {Value<String>? studentId,
      Value<String>? payload,
      Value<DateTime>? fetchedAt,
      Value<int>? rowid}) {
    return TodayCacheCompanion(
      studentId: studentId ?? this.studentId,
      payload: payload ?? this.payload,
      fetchedAt: fetchedAt ?? this.fetchedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (studentId.present) {
      map['student_id'] = Variable<String>(studentId.value);
    }
    if (payload.present) {
      map['payload'] = Variable<String>(payload.value);
    }
    if (fetchedAt.present) {
      map['fetched_at'] = Variable<DateTime>(fetchedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('TodayCacheCompanion(')
          ..write('studentId: $studentId, ')
          ..write('payload: $payload, ')
          ..write('fetchedAt: $fetchedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $PendingEventRowsTable extends PendingEventRows
    with TableInfo<$PendingEventRowsTable, PendingEventRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $PendingEventRowsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _clientIdMeta =
      const VerificationMeta('clientId');
  @override
  late final GeneratedColumn<String> clientId = GeneratedColumn<String>(
      'client_id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _studentIdMeta =
      const VerificationMeta('studentId');
  @override
  late final GeneratedColumn<String> studentId = GeneratedColumn<String>(
      'student_id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _typeMeta = const VerificationMeta('type');
  @override
  late final GeneratedColumn<String> type = GeneratedColumn<String>(
      'type', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _payloadMeta =
      const VerificationMeta('payload');
  @override
  late final GeneratedColumn<String> payload = GeneratedColumn<String>(
      'payload', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _performedAtMeta =
      const VerificationMeta('performedAt');
  @override
  late final GeneratedColumn<DateTime> performedAt = GeneratedColumn<DateTime>(
      'performed_at', aliasedName, false,
      type: DriftSqlType.dateTime, requiredDuringInsert: true);
  static const VerificationMeta _createdAtMeta =
      const VerificationMeta('createdAt');
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
      'created_at', aliasedName, false,
      type: DriftSqlType.dateTime, requiredDuringInsert: true);
  static const VerificationMeta _attemptsMeta =
      const VerificationMeta('attempts');
  @override
  late final GeneratedColumn<int> attempts = GeneratedColumn<int>(
      'attempts', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultValue: const Constant(0));
  @override
  List<GeneratedColumn> get $columns =>
      [clientId, studentId, type, payload, performedAt, createdAt, attempts];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'pending_event_rows';
  @override
  VerificationContext validateIntegrity(Insertable<PendingEventRow> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('client_id')) {
      context.handle(_clientIdMeta,
          clientId.isAcceptableOrUnknown(data['client_id']!, _clientIdMeta));
    } else if (isInserting) {
      context.missing(_clientIdMeta);
    }
    if (data.containsKey('student_id')) {
      context.handle(_studentIdMeta,
          studentId.isAcceptableOrUnknown(data['student_id']!, _studentIdMeta));
    } else if (isInserting) {
      context.missing(_studentIdMeta);
    }
    if (data.containsKey('type')) {
      context.handle(
          _typeMeta, type.isAcceptableOrUnknown(data['type']!, _typeMeta));
    } else if (isInserting) {
      context.missing(_typeMeta);
    }
    if (data.containsKey('payload')) {
      context.handle(_payloadMeta,
          payload.isAcceptableOrUnknown(data['payload']!, _payloadMeta));
    } else if (isInserting) {
      context.missing(_payloadMeta);
    }
    if (data.containsKey('performed_at')) {
      context.handle(
          _performedAtMeta,
          performedAt.isAcceptableOrUnknown(
              data['performed_at']!, _performedAtMeta));
    } else if (isInserting) {
      context.missing(_performedAtMeta);
    }
    if (data.containsKey('created_at')) {
      context.handle(_createdAtMeta,
          createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta));
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('attempts')) {
      context.handle(_attemptsMeta,
          attempts.isAcceptableOrUnknown(data['attempts']!, _attemptsMeta));
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {clientId};
  @override
  PendingEventRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return PendingEventRow(
      clientId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}client_id'])!,
      studentId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}student_id'])!,
      type: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}type'])!,
      payload: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}payload'])!,
      performedAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}performed_at'])!,
      createdAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}created_at'])!,
      attempts: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}attempts'])!,
    );
  }

  @override
  $PendingEventRowsTable createAlias(String alias) {
    return $PendingEventRowsTable(attachedDatabase, alias);
  }
}

class PendingEventRow extends DataClass implements Insertable<PendingEventRow> {
  final String clientId;
  final String studentId;
  final String type;
  final String payload;
  final DateTime performedAt;
  final DateTime createdAt;
  final int attempts;
  const PendingEventRow(
      {required this.clientId,
      required this.studentId,
      required this.type,
      required this.payload,
      required this.performedAt,
      required this.createdAt,
      required this.attempts});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['client_id'] = Variable<String>(clientId);
    map['student_id'] = Variable<String>(studentId);
    map['type'] = Variable<String>(type);
    map['payload'] = Variable<String>(payload);
    map['performed_at'] = Variable<DateTime>(performedAt);
    map['created_at'] = Variable<DateTime>(createdAt);
    map['attempts'] = Variable<int>(attempts);
    return map;
  }

  PendingEventRowsCompanion toCompanion(bool nullToAbsent) {
    return PendingEventRowsCompanion(
      clientId: Value(clientId),
      studentId: Value(studentId),
      type: Value(type),
      payload: Value(payload),
      performedAt: Value(performedAt),
      createdAt: Value(createdAt),
      attempts: Value(attempts),
    );
  }

  factory PendingEventRow.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return PendingEventRow(
      clientId: serializer.fromJson<String>(json['clientId']),
      studentId: serializer.fromJson<String>(json['studentId']),
      type: serializer.fromJson<String>(json['type']),
      payload: serializer.fromJson<String>(json['payload']),
      performedAt: serializer.fromJson<DateTime>(json['performedAt']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      attempts: serializer.fromJson<int>(json['attempts']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'clientId': serializer.toJson<String>(clientId),
      'studentId': serializer.toJson<String>(studentId),
      'type': serializer.toJson<String>(type),
      'payload': serializer.toJson<String>(payload),
      'performedAt': serializer.toJson<DateTime>(performedAt),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'attempts': serializer.toJson<int>(attempts),
    };
  }

  PendingEventRow copyWith(
          {String? clientId,
          String? studentId,
          String? type,
          String? payload,
          DateTime? performedAt,
          DateTime? createdAt,
          int? attempts}) =>
      PendingEventRow(
        clientId: clientId ?? this.clientId,
        studentId: studentId ?? this.studentId,
        type: type ?? this.type,
        payload: payload ?? this.payload,
        performedAt: performedAt ?? this.performedAt,
        createdAt: createdAt ?? this.createdAt,
        attempts: attempts ?? this.attempts,
      );
  PendingEventRow copyWithCompanion(PendingEventRowsCompanion data) {
    return PendingEventRow(
      clientId: data.clientId.present ? data.clientId.value : this.clientId,
      studentId: data.studentId.present ? data.studentId.value : this.studentId,
      type: data.type.present ? data.type.value : this.type,
      payload: data.payload.present ? data.payload.value : this.payload,
      performedAt:
          data.performedAt.present ? data.performedAt.value : this.performedAt,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      attempts: data.attempts.present ? data.attempts.value : this.attempts,
    );
  }

  @override
  String toString() {
    return (StringBuffer('PendingEventRow(')
          ..write('clientId: $clientId, ')
          ..write('studentId: $studentId, ')
          ..write('type: $type, ')
          ..write('payload: $payload, ')
          ..write('performedAt: $performedAt, ')
          ..write('createdAt: $createdAt, ')
          ..write('attempts: $attempts')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
      clientId, studentId, type, payload, performedAt, createdAt, attempts);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is PendingEventRow &&
          other.clientId == this.clientId &&
          other.studentId == this.studentId &&
          other.type == this.type &&
          other.payload == this.payload &&
          other.performedAt == this.performedAt &&
          other.createdAt == this.createdAt &&
          other.attempts == this.attempts);
}

class PendingEventRowsCompanion extends UpdateCompanion<PendingEventRow> {
  final Value<String> clientId;
  final Value<String> studentId;
  final Value<String> type;
  final Value<String> payload;
  final Value<DateTime> performedAt;
  final Value<DateTime> createdAt;
  final Value<int> attempts;
  final Value<int> rowid;
  const PendingEventRowsCompanion({
    this.clientId = const Value.absent(),
    this.studentId = const Value.absent(),
    this.type = const Value.absent(),
    this.payload = const Value.absent(),
    this.performedAt = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.attempts = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  PendingEventRowsCompanion.insert({
    required String clientId,
    required String studentId,
    required String type,
    required String payload,
    required DateTime performedAt,
    required DateTime createdAt,
    this.attempts = const Value.absent(),
    this.rowid = const Value.absent(),
  })  : clientId = Value(clientId),
        studentId = Value(studentId),
        type = Value(type),
        payload = Value(payload),
        performedAt = Value(performedAt),
        createdAt = Value(createdAt);
  static Insertable<PendingEventRow> custom({
    Expression<String>? clientId,
    Expression<String>? studentId,
    Expression<String>? type,
    Expression<String>? payload,
    Expression<DateTime>? performedAt,
    Expression<DateTime>? createdAt,
    Expression<int>? attempts,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (clientId != null) 'client_id': clientId,
      if (studentId != null) 'student_id': studentId,
      if (type != null) 'type': type,
      if (payload != null) 'payload': payload,
      if (performedAt != null) 'performed_at': performedAt,
      if (createdAt != null) 'created_at': createdAt,
      if (attempts != null) 'attempts': attempts,
      if (rowid != null) 'rowid': rowid,
    });
  }

  PendingEventRowsCompanion copyWith(
      {Value<String>? clientId,
      Value<String>? studentId,
      Value<String>? type,
      Value<String>? payload,
      Value<DateTime>? performedAt,
      Value<DateTime>? createdAt,
      Value<int>? attempts,
      Value<int>? rowid}) {
    return PendingEventRowsCompanion(
      clientId: clientId ?? this.clientId,
      studentId: studentId ?? this.studentId,
      type: type ?? this.type,
      payload: payload ?? this.payload,
      performedAt: performedAt ?? this.performedAt,
      createdAt: createdAt ?? this.createdAt,
      attempts: attempts ?? this.attempts,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (clientId.present) {
      map['client_id'] = Variable<String>(clientId.value);
    }
    if (studentId.present) {
      map['student_id'] = Variable<String>(studentId.value);
    }
    if (type.present) {
      map['type'] = Variable<String>(type.value);
    }
    if (payload.present) {
      map['payload'] = Variable<String>(payload.value);
    }
    if (performedAt.present) {
      map['performed_at'] = Variable<DateTime>(performedAt.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (attempts.present) {
      map['attempts'] = Variable<int>(attempts.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('PendingEventRowsCompanion(')
          ..write('clientId: $clientId, ')
          ..write('studentId: $studentId, ')
          ..write('type: $type, ')
          ..write('payload: $payload, ')
          ..write('performedAt: $performedAt, ')
          ..write('createdAt: $createdAt, ')
          ..write('attempts: $attempts, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $LocalSessionRowsTable extends LocalSessionRows
    with TableInfo<$LocalSessionRowsTable, LocalSessionRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $LocalSessionRowsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _clientIdMeta =
      const VerificationMeta('clientId');
  @override
  late final GeneratedColumn<String> clientId = GeneratedColumn<String>(
      'client_id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _studentIdMeta =
      const VerificationMeta('studentId');
  @override
  late final GeneratedColumn<String> studentId = GeneratedColumn<String>(
      'student_id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _dayIdMeta = const VerificationMeta('dayId');
  @override
  late final GeneratedColumn<String> dayId = GeneratedColumn<String>(
      'day_id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _dayLabelMeta =
      const VerificationMeta('dayLabel');
  @override
  late final GeneratedColumn<String> dayLabel = GeneratedColumn<String>(
      'day_label', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _dayTitleMeta =
      const VerificationMeta('dayTitle');
  @override
  late final GeneratedColumn<String> dayTitle = GeneratedColumn<String>(
      'day_title', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _startedAtMeta =
      const VerificationMeta('startedAt');
  @override
  late final GeneratedColumn<DateTime> startedAt = GeneratedColumn<DateTime>(
      'started_at', aliasedName, false,
      type: DriftSqlType.dateTime, requiredDuringInsert: true);
  static const VerificationMeta _finishedAtMeta =
      const VerificationMeta('finishedAt');
  @override
  late final GeneratedColumn<DateTime> finishedAt = GeneratedColumn<DateTime>(
      'finished_at', aliasedName, true,
      type: DriftSqlType.dateTime, requiredDuringInsert: false);
  @override
  List<GeneratedColumn> get $columns =>
      [clientId, studentId, dayId, dayLabel, dayTitle, startedAt, finishedAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'local_session_rows';
  @override
  VerificationContext validateIntegrity(Insertable<LocalSessionRow> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('client_id')) {
      context.handle(_clientIdMeta,
          clientId.isAcceptableOrUnknown(data['client_id']!, _clientIdMeta));
    } else if (isInserting) {
      context.missing(_clientIdMeta);
    }
    if (data.containsKey('student_id')) {
      context.handle(_studentIdMeta,
          studentId.isAcceptableOrUnknown(data['student_id']!, _studentIdMeta));
    } else if (isInserting) {
      context.missing(_studentIdMeta);
    }
    if (data.containsKey('day_id')) {
      context.handle(
          _dayIdMeta, dayId.isAcceptableOrUnknown(data['day_id']!, _dayIdMeta));
    } else if (isInserting) {
      context.missing(_dayIdMeta);
    }
    if (data.containsKey('day_label')) {
      context.handle(_dayLabelMeta,
          dayLabel.isAcceptableOrUnknown(data['day_label']!, _dayLabelMeta));
    } else if (isInserting) {
      context.missing(_dayLabelMeta);
    }
    if (data.containsKey('day_title')) {
      context.handle(_dayTitleMeta,
          dayTitle.isAcceptableOrUnknown(data['day_title']!, _dayTitleMeta));
    } else if (isInserting) {
      context.missing(_dayTitleMeta);
    }
    if (data.containsKey('started_at')) {
      context.handle(_startedAtMeta,
          startedAt.isAcceptableOrUnknown(data['started_at']!, _startedAtMeta));
    } else if (isInserting) {
      context.missing(_startedAtMeta);
    }
    if (data.containsKey('finished_at')) {
      context.handle(
          _finishedAtMeta,
          finishedAt.isAcceptableOrUnknown(
              data['finished_at']!, _finishedAtMeta));
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {clientId};
  @override
  LocalSessionRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return LocalSessionRow(
      clientId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}client_id'])!,
      studentId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}student_id'])!,
      dayId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}day_id'])!,
      dayLabel: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}day_label'])!,
      dayTitle: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}day_title'])!,
      startedAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}started_at'])!,
      finishedAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}finished_at']),
    );
  }

  @override
  $LocalSessionRowsTable createAlias(String alias) {
    return $LocalSessionRowsTable(attachedDatabase, alias);
  }
}

class LocalSessionRow extends DataClass implements Insertable<LocalSessionRow> {
  final String clientId;
  final String studentId;
  final String dayId;
  final String dayLabel;
  final String dayTitle;
  final DateTime startedAt;
  final DateTime? finishedAt;
  const LocalSessionRow(
      {required this.clientId,
      required this.studentId,
      required this.dayId,
      required this.dayLabel,
      required this.dayTitle,
      required this.startedAt,
      this.finishedAt});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['client_id'] = Variable<String>(clientId);
    map['student_id'] = Variable<String>(studentId);
    map['day_id'] = Variable<String>(dayId);
    map['day_label'] = Variable<String>(dayLabel);
    map['day_title'] = Variable<String>(dayTitle);
    map['started_at'] = Variable<DateTime>(startedAt);
    if (!nullToAbsent || finishedAt != null) {
      map['finished_at'] = Variable<DateTime>(finishedAt);
    }
    return map;
  }

  LocalSessionRowsCompanion toCompanion(bool nullToAbsent) {
    return LocalSessionRowsCompanion(
      clientId: Value(clientId),
      studentId: Value(studentId),
      dayId: Value(dayId),
      dayLabel: Value(dayLabel),
      dayTitle: Value(dayTitle),
      startedAt: Value(startedAt),
      finishedAt: finishedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(finishedAt),
    );
  }

  factory LocalSessionRow.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return LocalSessionRow(
      clientId: serializer.fromJson<String>(json['clientId']),
      studentId: serializer.fromJson<String>(json['studentId']),
      dayId: serializer.fromJson<String>(json['dayId']),
      dayLabel: serializer.fromJson<String>(json['dayLabel']),
      dayTitle: serializer.fromJson<String>(json['dayTitle']),
      startedAt: serializer.fromJson<DateTime>(json['startedAt']),
      finishedAt: serializer.fromJson<DateTime?>(json['finishedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'clientId': serializer.toJson<String>(clientId),
      'studentId': serializer.toJson<String>(studentId),
      'dayId': serializer.toJson<String>(dayId),
      'dayLabel': serializer.toJson<String>(dayLabel),
      'dayTitle': serializer.toJson<String>(dayTitle),
      'startedAt': serializer.toJson<DateTime>(startedAt),
      'finishedAt': serializer.toJson<DateTime?>(finishedAt),
    };
  }

  LocalSessionRow copyWith(
          {String? clientId,
          String? studentId,
          String? dayId,
          String? dayLabel,
          String? dayTitle,
          DateTime? startedAt,
          Value<DateTime?> finishedAt = const Value.absent()}) =>
      LocalSessionRow(
        clientId: clientId ?? this.clientId,
        studentId: studentId ?? this.studentId,
        dayId: dayId ?? this.dayId,
        dayLabel: dayLabel ?? this.dayLabel,
        dayTitle: dayTitle ?? this.dayTitle,
        startedAt: startedAt ?? this.startedAt,
        finishedAt: finishedAt.present ? finishedAt.value : this.finishedAt,
      );
  LocalSessionRow copyWithCompanion(LocalSessionRowsCompanion data) {
    return LocalSessionRow(
      clientId: data.clientId.present ? data.clientId.value : this.clientId,
      studentId: data.studentId.present ? data.studentId.value : this.studentId,
      dayId: data.dayId.present ? data.dayId.value : this.dayId,
      dayLabel: data.dayLabel.present ? data.dayLabel.value : this.dayLabel,
      dayTitle: data.dayTitle.present ? data.dayTitle.value : this.dayTitle,
      startedAt: data.startedAt.present ? data.startedAt.value : this.startedAt,
      finishedAt:
          data.finishedAt.present ? data.finishedAt.value : this.finishedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('LocalSessionRow(')
          ..write('clientId: $clientId, ')
          ..write('studentId: $studentId, ')
          ..write('dayId: $dayId, ')
          ..write('dayLabel: $dayLabel, ')
          ..write('dayTitle: $dayTitle, ')
          ..write('startedAt: $startedAt, ')
          ..write('finishedAt: $finishedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
      clientId, studentId, dayId, dayLabel, dayTitle, startedAt, finishedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is LocalSessionRow &&
          other.clientId == this.clientId &&
          other.studentId == this.studentId &&
          other.dayId == this.dayId &&
          other.dayLabel == this.dayLabel &&
          other.dayTitle == this.dayTitle &&
          other.startedAt == this.startedAt &&
          other.finishedAt == this.finishedAt);
}

class LocalSessionRowsCompanion extends UpdateCompanion<LocalSessionRow> {
  final Value<String> clientId;
  final Value<String> studentId;
  final Value<String> dayId;
  final Value<String> dayLabel;
  final Value<String> dayTitle;
  final Value<DateTime> startedAt;
  final Value<DateTime?> finishedAt;
  final Value<int> rowid;
  const LocalSessionRowsCompanion({
    this.clientId = const Value.absent(),
    this.studentId = const Value.absent(),
    this.dayId = const Value.absent(),
    this.dayLabel = const Value.absent(),
    this.dayTitle = const Value.absent(),
    this.startedAt = const Value.absent(),
    this.finishedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  LocalSessionRowsCompanion.insert({
    required String clientId,
    required String studentId,
    required String dayId,
    required String dayLabel,
    required String dayTitle,
    required DateTime startedAt,
    this.finishedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  })  : clientId = Value(clientId),
        studentId = Value(studentId),
        dayId = Value(dayId),
        dayLabel = Value(dayLabel),
        dayTitle = Value(dayTitle),
        startedAt = Value(startedAt);
  static Insertable<LocalSessionRow> custom({
    Expression<String>? clientId,
    Expression<String>? studentId,
    Expression<String>? dayId,
    Expression<String>? dayLabel,
    Expression<String>? dayTitle,
    Expression<DateTime>? startedAt,
    Expression<DateTime>? finishedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (clientId != null) 'client_id': clientId,
      if (studentId != null) 'student_id': studentId,
      if (dayId != null) 'day_id': dayId,
      if (dayLabel != null) 'day_label': dayLabel,
      if (dayTitle != null) 'day_title': dayTitle,
      if (startedAt != null) 'started_at': startedAt,
      if (finishedAt != null) 'finished_at': finishedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  LocalSessionRowsCompanion copyWith(
      {Value<String>? clientId,
      Value<String>? studentId,
      Value<String>? dayId,
      Value<String>? dayLabel,
      Value<String>? dayTitle,
      Value<DateTime>? startedAt,
      Value<DateTime?>? finishedAt,
      Value<int>? rowid}) {
    return LocalSessionRowsCompanion(
      clientId: clientId ?? this.clientId,
      studentId: studentId ?? this.studentId,
      dayId: dayId ?? this.dayId,
      dayLabel: dayLabel ?? this.dayLabel,
      dayTitle: dayTitle ?? this.dayTitle,
      startedAt: startedAt ?? this.startedAt,
      finishedAt: finishedAt ?? this.finishedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (clientId.present) {
      map['client_id'] = Variable<String>(clientId.value);
    }
    if (studentId.present) {
      map['student_id'] = Variable<String>(studentId.value);
    }
    if (dayId.present) {
      map['day_id'] = Variable<String>(dayId.value);
    }
    if (dayLabel.present) {
      map['day_label'] = Variable<String>(dayLabel.value);
    }
    if (dayTitle.present) {
      map['day_title'] = Variable<String>(dayTitle.value);
    }
    if (startedAt.present) {
      map['started_at'] = Variable<DateTime>(startedAt.value);
    }
    if (finishedAt.present) {
      map['finished_at'] = Variable<DateTime>(finishedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('LocalSessionRowsCompanion(')
          ..write('clientId: $clientId, ')
          ..write('studentId: $studentId, ')
          ..write('dayId: $dayId, ')
          ..write('dayLabel: $dayLabel, ')
          ..write('dayTitle: $dayTitle, ')
          ..write('startedAt: $startedAt, ')
          ..write('finishedAt: $finishedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $LocalSetLogRowsTable extends LocalSetLogRows
    with TableInfo<$LocalSetLogRowsTable, LocalSetLogRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $LocalSetLogRowsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _clientIdMeta =
      const VerificationMeta('clientId');
  @override
  late final GeneratedColumn<String> clientId = GeneratedColumn<String>(
      'client_id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _studentIdMeta =
      const VerificationMeta('studentId');
  @override
  late final GeneratedColumn<String> studentId = GeneratedColumn<String>(
      'student_id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _sessionClientIdMeta =
      const VerificationMeta('sessionClientId');
  @override
  late final GeneratedColumn<String> sessionClientId = GeneratedColumn<String>(
      'session_client_id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _exerciseIdMeta =
      const VerificationMeta('exerciseId');
  @override
  late final GeneratedColumn<String> exerciseId = GeneratedColumn<String>(
      'exercise_id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _setNoMeta = const VerificationMeta('setNo');
  @override
  late final GeneratedColumn<int> setNo = GeneratedColumn<int>(
      'set_no', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  static const VerificationMeta _repsDoneMeta =
      const VerificationMeta('repsDone');
  @override
  late final GeneratedColumn<int> repsDone = GeneratedColumn<int>(
      'reps_done', aliasedName, true,
      type: DriftSqlType.int, requiredDuringInsert: false);
  static const VerificationMeta _loadKgMeta = const VerificationMeta('loadKg');
  @override
  late final GeneratedColumn<double> loadKg = GeneratedColumn<double>(
      'load_kg', aliasedName, true,
      type: DriftSqlType.double, requiredDuringInsert: false);
  static const VerificationMeta _rpeMeta = const VerificationMeta('rpe');
  @override
  late final GeneratedColumn<double> rpe = GeneratedColumn<double>(
      'rpe', aliasedName, true,
      type: DriftSqlType.double, requiredDuringInsert: false);
  static const VerificationMeta _performedAtMeta =
      const VerificationMeta('performedAt');
  @override
  late final GeneratedColumn<DateTime> performedAt = GeneratedColumn<DateTime>(
      'performed_at', aliasedName, false,
      type: DriftSqlType.dateTime, requiredDuringInsert: true);
  static const VerificationMeta _revisesMeta =
      const VerificationMeta('revises');
  @override
  late final GeneratedColumn<String> revises = GeneratedColumn<String>(
      'revises', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  @override
  List<GeneratedColumn> get $columns => [
        clientId,
        studentId,
        sessionClientId,
        exerciseId,
        setNo,
        repsDone,
        loadKg,
        rpe,
        performedAt,
        revises
      ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'local_set_log_rows';
  @override
  VerificationContext validateIntegrity(Insertable<LocalSetLogRow> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('client_id')) {
      context.handle(_clientIdMeta,
          clientId.isAcceptableOrUnknown(data['client_id']!, _clientIdMeta));
    } else if (isInserting) {
      context.missing(_clientIdMeta);
    }
    if (data.containsKey('student_id')) {
      context.handle(_studentIdMeta,
          studentId.isAcceptableOrUnknown(data['student_id']!, _studentIdMeta));
    } else if (isInserting) {
      context.missing(_studentIdMeta);
    }
    if (data.containsKey('session_client_id')) {
      context.handle(
          _sessionClientIdMeta,
          sessionClientId.isAcceptableOrUnknown(
              data['session_client_id']!, _sessionClientIdMeta));
    } else if (isInserting) {
      context.missing(_sessionClientIdMeta);
    }
    if (data.containsKey('exercise_id')) {
      context.handle(
          _exerciseIdMeta,
          exerciseId.isAcceptableOrUnknown(
              data['exercise_id']!, _exerciseIdMeta));
    } else if (isInserting) {
      context.missing(_exerciseIdMeta);
    }
    if (data.containsKey('set_no')) {
      context.handle(
          _setNoMeta, setNo.isAcceptableOrUnknown(data['set_no']!, _setNoMeta));
    } else if (isInserting) {
      context.missing(_setNoMeta);
    }
    if (data.containsKey('reps_done')) {
      context.handle(_repsDoneMeta,
          repsDone.isAcceptableOrUnknown(data['reps_done']!, _repsDoneMeta));
    }
    if (data.containsKey('load_kg')) {
      context.handle(_loadKgMeta,
          loadKg.isAcceptableOrUnknown(data['load_kg']!, _loadKgMeta));
    }
    if (data.containsKey('rpe')) {
      context.handle(
          _rpeMeta, rpe.isAcceptableOrUnknown(data['rpe']!, _rpeMeta));
    }
    if (data.containsKey('performed_at')) {
      context.handle(
          _performedAtMeta,
          performedAt.isAcceptableOrUnknown(
              data['performed_at']!, _performedAtMeta));
    } else if (isInserting) {
      context.missing(_performedAtMeta);
    }
    if (data.containsKey('revises')) {
      context.handle(_revisesMeta,
          revises.isAcceptableOrUnknown(data['revises']!, _revisesMeta));
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {clientId};
  @override
  LocalSetLogRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return LocalSetLogRow(
      clientId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}client_id'])!,
      studentId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}student_id'])!,
      sessionClientId: attachedDatabase.typeMapping.read(
          DriftSqlType.string, data['${effectivePrefix}session_client_id'])!,
      exerciseId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}exercise_id'])!,
      setNo: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}set_no'])!,
      repsDone: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}reps_done']),
      loadKg: attachedDatabase.typeMapping
          .read(DriftSqlType.double, data['${effectivePrefix}load_kg']),
      rpe: attachedDatabase.typeMapping
          .read(DriftSqlType.double, data['${effectivePrefix}rpe']),
      performedAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}performed_at'])!,
      revises: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}revises']),
    );
  }

  @override
  $LocalSetLogRowsTable createAlias(String alias) {
    return $LocalSetLogRowsTable(attachedDatabase, alias);
  }
}

class LocalSetLogRow extends DataClass implements Insertable<LocalSetLogRow> {
  final String clientId;
  final String studentId;
  final String sessionClientId;
  final String exerciseId;
  final int setNo;
  final int? repsDone;
  final double? loadKg;
  final double? rpe;
  final DateTime performedAt;
  final String? revises;
  const LocalSetLogRow(
      {required this.clientId,
      required this.studentId,
      required this.sessionClientId,
      required this.exerciseId,
      required this.setNo,
      this.repsDone,
      this.loadKg,
      this.rpe,
      required this.performedAt,
      this.revises});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['client_id'] = Variable<String>(clientId);
    map['student_id'] = Variable<String>(studentId);
    map['session_client_id'] = Variable<String>(sessionClientId);
    map['exercise_id'] = Variable<String>(exerciseId);
    map['set_no'] = Variable<int>(setNo);
    if (!nullToAbsent || repsDone != null) {
      map['reps_done'] = Variable<int>(repsDone);
    }
    if (!nullToAbsent || loadKg != null) {
      map['load_kg'] = Variable<double>(loadKg);
    }
    if (!nullToAbsent || rpe != null) {
      map['rpe'] = Variable<double>(rpe);
    }
    map['performed_at'] = Variable<DateTime>(performedAt);
    if (!nullToAbsent || revises != null) {
      map['revises'] = Variable<String>(revises);
    }
    return map;
  }

  LocalSetLogRowsCompanion toCompanion(bool nullToAbsent) {
    return LocalSetLogRowsCompanion(
      clientId: Value(clientId),
      studentId: Value(studentId),
      sessionClientId: Value(sessionClientId),
      exerciseId: Value(exerciseId),
      setNo: Value(setNo),
      repsDone: repsDone == null && nullToAbsent
          ? const Value.absent()
          : Value(repsDone),
      loadKg:
          loadKg == null && nullToAbsent ? const Value.absent() : Value(loadKg),
      rpe: rpe == null && nullToAbsent ? const Value.absent() : Value(rpe),
      performedAt: Value(performedAt),
      revises: revises == null && nullToAbsent
          ? const Value.absent()
          : Value(revises),
    );
  }

  factory LocalSetLogRow.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return LocalSetLogRow(
      clientId: serializer.fromJson<String>(json['clientId']),
      studentId: serializer.fromJson<String>(json['studentId']),
      sessionClientId: serializer.fromJson<String>(json['sessionClientId']),
      exerciseId: serializer.fromJson<String>(json['exerciseId']),
      setNo: serializer.fromJson<int>(json['setNo']),
      repsDone: serializer.fromJson<int?>(json['repsDone']),
      loadKg: serializer.fromJson<double?>(json['loadKg']),
      rpe: serializer.fromJson<double?>(json['rpe']),
      performedAt: serializer.fromJson<DateTime>(json['performedAt']),
      revises: serializer.fromJson<String?>(json['revises']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'clientId': serializer.toJson<String>(clientId),
      'studentId': serializer.toJson<String>(studentId),
      'sessionClientId': serializer.toJson<String>(sessionClientId),
      'exerciseId': serializer.toJson<String>(exerciseId),
      'setNo': serializer.toJson<int>(setNo),
      'repsDone': serializer.toJson<int?>(repsDone),
      'loadKg': serializer.toJson<double?>(loadKg),
      'rpe': serializer.toJson<double?>(rpe),
      'performedAt': serializer.toJson<DateTime>(performedAt),
      'revises': serializer.toJson<String?>(revises),
    };
  }

  LocalSetLogRow copyWith(
          {String? clientId,
          String? studentId,
          String? sessionClientId,
          String? exerciseId,
          int? setNo,
          Value<int?> repsDone = const Value.absent(),
          Value<double?> loadKg = const Value.absent(),
          Value<double?> rpe = const Value.absent(),
          DateTime? performedAt,
          Value<String?> revises = const Value.absent()}) =>
      LocalSetLogRow(
        clientId: clientId ?? this.clientId,
        studentId: studentId ?? this.studentId,
        sessionClientId: sessionClientId ?? this.sessionClientId,
        exerciseId: exerciseId ?? this.exerciseId,
        setNo: setNo ?? this.setNo,
        repsDone: repsDone.present ? repsDone.value : this.repsDone,
        loadKg: loadKg.present ? loadKg.value : this.loadKg,
        rpe: rpe.present ? rpe.value : this.rpe,
        performedAt: performedAt ?? this.performedAt,
        revises: revises.present ? revises.value : this.revises,
      );
  LocalSetLogRow copyWithCompanion(LocalSetLogRowsCompanion data) {
    return LocalSetLogRow(
      clientId: data.clientId.present ? data.clientId.value : this.clientId,
      studentId: data.studentId.present ? data.studentId.value : this.studentId,
      sessionClientId: data.sessionClientId.present
          ? data.sessionClientId.value
          : this.sessionClientId,
      exerciseId:
          data.exerciseId.present ? data.exerciseId.value : this.exerciseId,
      setNo: data.setNo.present ? data.setNo.value : this.setNo,
      repsDone: data.repsDone.present ? data.repsDone.value : this.repsDone,
      loadKg: data.loadKg.present ? data.loadKg.value : this.loadKg,
      rpe: data.rpe.present ? data.rpe.value : this.rpe,
      performedAt:
          data.performedAt.present ? data.performedAt.value : this.performedAt,
      revises: data.revises.present ? data.revises.value : this.revises,
    );
  }

  @override
  String toString() {
    return (StringBuffer('LocalSetLogRow(')
          ..write('clientId: $clientId, ')
          ..write('studentId: $studentId, ')
          ..write('sessionClientId: $sessionClientId, ')
          ..write('exerciseId: $exerciseId, ')
          ..write('setNo: $setNo, ')
          ..write('repsDone: $repsDone, ')
          ..write('loadKg: $loadKg, ')
          ..write('rpe: $rpe, ')
          ..write('performedAt: $performedAt, ')
          ..write('revises: $revises')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(clientId, studentId, sessionClientId,
      exerciseId, setNo, repsDone, loadKg, rpe, performedAt, revises);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is LocalSetLogRow &&
          other.clientId == this.clientId &&
          other.studentId == this.studentId &&
          other.sessionClientId == this.sessionClientId &&
          other.exerciseId == this.exerciseId &&
          other.setNo == this.setNo &&
          other.repsDone == this.repsDone &&
          other.loadKg == this.loadKg &&
          other.rpe == this.rpe &&
          other.performedAt == this.performedAt &&
          other.revises == this.revises);
}

class LocalSetLogRowsCompanion extends UpdateCompanion<LocalSetLogRow> {
  final Value<String> clientId;
  final Value<String> studentId;
  final Value<String> sessionClientId;
  final Value<String> exerciseId;
  final Value<int> setNo;
  final Value<int?> repsDone;
  final Value<double?> loadKg;
  final Value<double?> rpe;
  final Value<DateTime> performedAt;
  final Value<String?> revises;
  final Value<int> rowid;
  const LocalSetLogRowsCompanion({
    this.clientId = const Value.absent(),
    this.studentId = const Value.absent(),
    this.sessionClientId = const Value.absent(),
    this.exerciseId = const Value.absent(),
    this.setNo = const Value.absent(),
    this.repsDone = const Value.absent(),
    this.loadKg = const Value.absent(),
    this.rpe = const Value.absent(),
    this.performedAt = const Value.absent(),
    this.revises = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  LocalSetLogRowsCompanion.insert({
    required String clientId,
    required String studentId,
    required String sessionClientId,
    required String exerciseId,
    required int setNo,
    this.repsDone = const Value.absent(),
    this.loadKg = const Value.absent(),
    this.rpe = const Value.absent(),
    required DateTime performedAt,
    this.revises = const Value.absent(),
    this.rowid = const Value.absent(),
  })  : clientId = Value(clientId),
        studentId = Value(studentId),
        sessionClientId = Value(sessionClientId),
        exerciseId = Value(exerciseId),
        setNo = Value(setNo),
        performedAt = Value(performedAt);
  static Insertable<LocalSetLogRow> custom({
    Expression<String>? clientId,
    Expression<String>? studentId,
    Expression<String>? sessionClientId,
    Expression<String>? exerciseId,
    Expression<int>? setNo,
    Expression<int>? repsDone,
    Expression<double>? loadKg,
    Expression<double>? rpe,
    Expression<DateTime>? performedAt,
    Expression<String>? revises,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (clientId != null) 'client_id': clientId,
      if (studentId != null) 'student_id': studentId,
      if (sessionClientId != null) 'session_client_id': sessionClientId,
      if (exerciseId != null) 'exercise_id': exerciseId,
      if (setNo != null) 'set_no': setNo,
      if (repsDone != null) 'reps_done': repsDone,
      if (loadKg != null) 'load_kg': loadKg,
      if (rpe != null) 'rpe': rpe,
      if (performedAt != null) 'performed_at': performedAt,
      if (revises != null) 'revises': revises,
      if (rowid != null) 'rowid': rowid,
    });
  }

  LocalSetLogRowsCompanion copyWith(
      {Value<String>? clientId,
      Value<String>? studentId,
      Value<String>? sessionClientId,
      Value<String>? exerciseId,
      Value<int>? setNo,
      Value<int?>? repsDone,
      Value<double?>? loadKg,
      Value<double?>? rpe,
      Value<DateTime>? performedAt,
      Value<String?>? revises,
      Value<int>? rowid}) {
    return LocalSetLogRowsCompanion(
      clientId: clientId ?? this.clientId,
      studentId: studentId ?? this.studentId,
      sessionClientId: sessionClientId ?? this.sessionClientId,
      exerciseId: exerciseId ?? this.exerciseId,
      setNo: setNo ?? this.setNo,
      repsDone: repsDone ?? this.repsDone,
      loadKg: loadKg ?? this.loadKg,
      rpe: rpe ?? this.rpe,
      performedAt: performedAt ?? this.performedAt,
      revises: revises ?? this.revises,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (clientId.present) {
      map['client_id'] = Variable<String>(clientId.value);
    }
    if (studentId.present) {
      map['student_id'] = Variable<String>(studentId.value);
    }
    if (sessionClientId.present) {
      map['session_client_id'] = Variable<String>(sessionClientId.value);
    }
    if (exerciseId.present) {
      map['exercise_id'] = Variable<String>(exerciseId.value);
    }
    if (setNo.present) {
      map['set_no'] = Variable<int>(setNo.value);
    }
    if (repsDone.present) {
      map['reps_done'] = Variable<int>(repsDone.value);
    }
    if (loadKg.present) {
      map['load_kg'] = Variable<double>(loadKg.value);
    }
    if (rpe.present) {
      map['rpe'] = Variable<double>(rpe.value);
    }
    if (performedAt.present) {
      map['performed_at'] = Variable<DateTime>(performedAt.value);
    }
    if (revises.present) {
      map['revises'] = Variable<String>(revises.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('LocalSetLogRowsCompanion(')
          ..write('clientId: $clientId, ')
          ..write('studentId: $studentId, ')
          ..write('sessionClientId: $sessionClientId, ')
          ..write('exerciseId: $exerciseId, ')
          ..write('setNo: $setNo, ')
          ..write('repsDone: $repsDone, ')
          ..write('loadKg: $loadKg, ')
          ..write('rpe: $rpe, ')
          ..write('performedAt: $performedAt, ')
          ..write('revises: $revises, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$WorkoutDatabase extends GeneratedDatabase {
  _$WorkoutDatabase(QueryExecutor e) : super(e);
  $WorkoutDatabaseManager get managers => $WorkoutDatabaseManager(this);
  late final $TodayCacheTable todayCache = $TodayCacheTable(this);
  late final $PendingEventRowsTable pendingEventRows =
      $PendingEventRowsTable(this);
  late final $LocalSessionRowsTable localSessionRows =
      $LocalSessionRowsTable(this);
  late final $LocalSetLogRowsTable localSetLogRows =
      $LocalSetLogRowsTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities =>
      [todayCache, pendingEventRows, localSessionRows, localSetLogRows];
}

typedef $$TodayCacheTableCreateCompanionBuilder = TodayCacheCompanion Function({
  required String studentId,
  required String payload,
  required DateTime fetchedAt,
  Value<int> rowid,
});
typedef $$TodayCacheTableUpdateCompanionBuilder = TodayCacheCompanion Function({
  Value<String> studentId,
  Value<String> payload,
  Value<DateTime> fetchedAt,
  Value<int> rowid,
});

class $$TodayCacheTableFilterComposer
    extends Composer<_$WorkoutDatabase, $TodayCacheTable> {
  $$TodayCacheTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get studentId => $composableBuilder(
      column: $table.studentId, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get payload => $composableBuilder(
      column: $table.payload, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get fetchedAt => $composableBuilder(
      column: $table.fetchedAt, builder: (column) => ColumnFilters(column));
}

class $$TodayCacheTableOrderingComposer
    extends Composer<_$WorkoutDatabase, $TodayCacheTable> {
  $$TodayCacheTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get studentId => $composableBuilder(
      column: $table.studentId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get payload => $composableBuilder(
      column: $table.payload, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get fetchedAt => $composableBuilder(
      column: $table.fetchedAt, builder: (column) => ColumnOrderings(column));
}

class $$TodayCacheTableAnnotationComposer
    extends Composer<_$WorkoutDatabase, $TodayCacheTable> {
  $$TodayCacheTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get studentId =>
      $composableBuilder(column: $table.studentId, builder: (column) => column);

  GeneratedColumn<String> get payload =>
      $composableBuilder(column: $table.payload, builder: (column) => column);

  GeneratedColumn<DateTime> get fetchedAt =>
      $composableBuilder(column: $table.fetchedAt, builder: (column) => column);
}

class $$TodayCacheTableTableManager extends RootTableManager<
    _$WorkoutDatabase,
    $TodayCacheTable,
    TodayCacheData,
    $$TodayCacheTableFilterComposer,
    $$TodayCacheTableOrderingComposer,
    $$TodayCacheTableAnnotationComposer,
    $$TodayCacheTableCreateCompanionBuilder,
    $$TodayCacheTableUpdateCompanionBuilder,
    (
      TodayCacheData,
      BaseReferences<_$WorkoutDatabase, $TodayCacheTable, TodayCacheData>
    ),
    TodayCacheData,
    PrefetchHooks Function()> {
  $$TodayCacheTableTableManager(_$WorkoutDatabase db, $TodayCacheTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$TodayCacheTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$TodayCacheTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$TodayCacheTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> studentId = const Value.absent(),
            Value<String> payload = const Value.absent(),
            Value<DateTime> fetchedAt = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              TodayCacheCompanion(
            studentId: studentId,
            payload: payload,
            fetchedAt: fetchedAt,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String studentId,
            required String payload,
            required DateTime fetchedAt,
            Value<int> rowid = const Value.absent(),
          }) =>
              TodayCacheCompanion.insert(
            studentId: studentId,
            payload: payload,
            fetchedAt: fetchedAt,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$TodayCacheTableProcessedTableManager = ProcessedTableManager<
    _$WorkoutDatabase,
    $TodayCacheTable,
    TodayCacheData,
    $$TodayCacheTableFilterComposer,
    $$TodayCacheTableOrderingComposer,
    $$TodayCacheTableAnnotationComposer,
    $$TodayCacheTableCreateCompanionBuilder,
    $$TodayCacheTableUpdateCompanionBuilder,
    (
      TodayCacheData,
      BaseReferences<_$WorkoutDatabase, $TodayCacheTable, TodayCacheData>
    ),
    TodayCacheData,
    PrefetchHooks Function()>;
typedef $$PendingEventRowsTableCreateCompanionBuilder
    = PendingEventRowsCompanion Function({
  required String clientId,
  required String studentId,
  required String type,
  required String payload,
  required DateTime performedAt,
  required DateTime createdAt,
  Value<int> attempts,
  Value<int> rowid,
});
typedef $$PendingEventRowsTableUpdateCompanionBuilder
    = PendingEventRowsCompanion Function({
  Value<String> clientId,
  Value<String> studentId,
  Value<String> type,
  Value<String> payload,
  Value<DateTime> performedAt,
  Value<DateTime> createdAt,
  Value<int> attempts,
  Value<int> rowid,
});

class $$PendingEventRowsTableFilterComposer
    extends Composer<_$WorkoutDatabase, $PendingEventRowsTable> {
  $$PendingEventRowsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get clientId => $composableBuilder(
      column: $table.clientId, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get studentId => $composableBuilder(
      column: $table.studentId, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get type => $composableBuilder(
      column: $table.type, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get payload => $composableBuilder(
      column: $table.payload, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get performedAt => $composableBuilder(
      column: $table.performedAt, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get attempts => $composableBuilder(
      column: $table.attempts, builder: (column) => ColumnFilters(column));
}

class $$PendingEventRowsTableOrderingComposer
    extends Composer<_$WorkoutDatabase, $PendingEventRowsTable> {
  $$PendingEventRowsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get clientId => $composableBuilder(
      column: $table.clientId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get studentId => $composableBuilder(
      column: $table.studentId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get type => $composableBuilder(
      column: $table.type, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get payload => $composableBuilder(
      column: $table.payload, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get performedAt => $composableBuilder(
      column: $table.performedAt, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get attempts => $composableBuilder(
      column: $table.attempts, builder: (column) => ColumnOrderings(column));
}

class $$PendingEventRowsTableAnnotationComposer
    extends Composer<_$WorkoutDatabase, $PendingEventRowsTable> {
  $$PendingEventRowsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get clientId =>
      $composableBuilder(column: $table.clientId, builder: (column) => column);

  GeneratedColumn<String> get studentId =>
      $composableBuilder(column: $table.studentId, builder: (column) => column);

  GeneratedColumn<String> get type =>
      $composableBuilder(column: $table.type, builder: (column) => column);

  GeneratedColumn<String> get payload =>
      $composableBuilder(column: $table.payload, builder: (column) => column);

  GeneratedColumn<DateTime> get performedAt => $composableBuilder(
      column: $table.performedAt, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<int> get attempts =>
      $composableBuilder(column: $table.attempts, builder: (column) => column);
}

class $$PendingEventRowsTableTableManager extends RootTableManager<
    _$WorkoutDatabase,
    $PendingEventRowsTable,
    PendingEventRow,
    $$PendingEventRowsTableFilterComposer,
    $$PendingEventRowsTableOrderingComposer,
    $$PendingEventRowsTableAnnotationComposer,
    $$PendingEventRowsTableCreateCompanionBuilder,
    $$PendingEventRowsTableUpdateCompanionBuilder,
    (
      PendingEventRow,
      BaseReferences<_$WorkoutDatabase, $PendingEventRowsTable, PendingEventRow>
    ),
    PendingEventRow,
    PrefetchHooks Function()> {
  $$PendingEventRowsTableTableManager(
      _$WorkoutDatabase db, $PendingEventRowsTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$PendingEventRowsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$PendingEventRowsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$PendingEventRowsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> clientId = const Value.absent(),
            Value<String> studentId = const Value.absent(),
            Value<String> type = const Value.absent(),
            Value<String> payload = const Value.absent(),
            Value<DateTime> performedAt = const Value.absent(),
            Value<DateTime> createdAt = const Value.absent(),
            Value<int> attempts = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              PendingEventRowsCompanion(
            clientId: clientId,
            studentId: studentId,
            type: type,
            payload: payload,
            performedAt: performedAt,
            createdAt: createdAt,
            attempts: attempts,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String clientId,
            required String studentId,
            required String type,
            required String payload,
            required DateTime performedAt,
            required DateTime createdAt,
            Value<int> attempts = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              PendingEventRowsCompanion.insert(
            clientId: clientId,
            studentId: studentId,
            type: type,
            payload: payload,
            performedAt: performedAt,
            createdAt: createdAt,
            attempts: attempts,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$PendingEventRowsTableProcessedTableManager = ProcessedTableManager<
    _$WorkoutDatabase,
    $PendingEventRowsTable,
    PendingEventRow,
    $$PendingEventRowsTableFilterComposer,
    $$PendingEventRowsTableOrderingComposer,
    $$PendingEventRowsTableAnnotationComposer,
    $$PendingEventRowsTableCreateCompanionBuilder,
    $$PendingEventRowsTableUpdateCompanionBuilder,
    (
      PendingEventRow,
      BaseReferences<_$WorkoutDatabase, $PendingEventRowsTable, PendingEventRow>
    ),
    PendingEventRow,
    PrefetchHooks Function()>;
typedef $$LocalSessionRowsTableCreateCompanionBuilder
    = LocalSessionRowsCompanion Function({
  required String clientId,
  required String studentId,
  required String dayId,
  required String dayLabel,
  required String dayTitle,
  required DateTime startedAt,
  Value<DateTime?> finishedAt,
  Value<int> rowid,
});
typedef $$LocalSessionRowsTableUpdateCompanionBuilder
    = LocalSessionRowsCompanion Function({
  Value<String> clientId,
  Value<String> studentId,
  Value<String> dayId,
  Value<String> dayLabel,
  Value<String> dayTitle,
  Value<DateTime> startedAt,
  Value<DateTime?> finishedAt,
  Value<int> rowid,
});

class $$LocalSessionRowsTableFilterComposer
    extends Composer<_$WorkoutDatabase, $LocalSessionRowsTable> {
  $$LocalSessionRowsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get clientId => $composableBuilder(
      column: $table.clientId, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get studentId => $composableBuilder(
      column: $table.studentId, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get dayId => $composableBuilder(
      column: $table.dayId, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get dayLabel => $composableBuilder(
      column: $table.dayLabel, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get dayTitle => $composableBuilder(
      column: $table.dayTitle, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get startedAt => $composableBuilder(
      column: $table.startedAt, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get finishedAt => $composableBuilder(
      column: $table.finishedAt, builder: (column) => ColumnFilters(column));
}

class $$LocalSessionRowsTableOrderingComposer
    extends Composer<_$WorkoutDatabase, $LocalSessionRowsTable> {
  $$LocalSessionRowsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get clientId => $composableBuilder(
      column: $table.clientId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get studentId => $composableBuilder(
      column: $table.studentId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get dayId => $composableBuilder(
      column: $table.dayId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get dayLabel => $composableBuilder(
      column: $table.dayLabel, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get dayTitle => $composableBuilder(
      column: $table.dayTitle, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get startedAt => $composableBuilder(
      column: $table.startedAt, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get finishedAt => $composableBuilder(
      column: $table.finishedAt, builder: (column) => ColumnOrderings(column));
}

class $$LocalSessionRowsTableAnnotationComposer
    extends Composer<_$WorkoutDatabase, $LocalSessionRowsTable> {
  $$LocalSessionRowsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get clientId =>
      $composableBuilder(column: $table.clientId, builder: (column) => column);

  GeneratedColumn<String> get studentId =>
      $composableBuilder(column: $table.studentId, builder: (column) => column);

  GeneratedColumn<String> get dayId =>
      $composableBuilder(column: $table.dayId, builder: (column) => column);

  GeneratedColumn<String> get dayLabel =>
      $composableBuilder(column: $table.dayLabel, builder: (column) => column);

  GeneratedColumn<String> get dayTitle =>
      $composableBuilder(column: $table.dayTitle, builder: (column) => column);

  GeneratedColumn<DateTime> get startedAt =>
      $composableBuilder(column: $table.startedAt, builder: (column) => column);

  GeneratedColumn<DateTime> get finishedAt => $composableBuilder(
      column: $table.finishedAt, builder: (column) => column);
}

class $$LocalSessionRowsTableTableManager extends RootTableManager<
    _$WorkoutDatabase,
    $LocalSessionRowsTable,
    LocalSessionRow,
    $$LocalSessionRowsTableFilterComposer,
    $$LocalSessionRowsTableOrderingComposer,
    $$LocalSessionRowsTableAnnotationComposer,
    $$LocalSessionRowsTableCreateCompanionBuilder,
    $$LocalSessionRowsTableUpdateCompanionBuilder,
    (
      LocalSessionRow,
      BaseReferences<_$WorkoutDatabase, $LocalSessionRowsTable, LocalSessionRow>
    ),
    LocalSessionRow,
    PrefetchHooks Function()> {
  $$LocalSessionRowsTableTableManager(
      _$WorkoutDatabase db, $LocalSessionRowsTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$LocalSessionRowsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$LocalSessionRowsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$LocalSessionRowsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> clientId = const Value.absent(),
            Value<String> studentId = const Value.absent(),
            Value<String> dayId = const Value.absent(),
            Value<String> dayLabel = const Value.absent(),
            Value<String> dayTitle = const Value.absent(),
            Value<DateTime> startedAt = const Value.absent(),
            Value<DateTime?> finishedAt = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              LocalSessionRowsCompanion(
            clientId: clientId,
            studentId: studentId,
            dayId: dayId,
            dayLabel: dayLabel,
            dayTitle: dayTitle,
            startedAt: startedAt,
            finishedAt: finishedAt,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String clientId,
            required String studentId,
            required String dayId,
            required String dayLabel,
            required String dayTitle,
            required DateTime startedAt,
            Value<DateTime?> finishedAt = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              LocalSessionRowsCompanion.insert(
            clientId: clientId,
            studentId: studentId,
            dayId: dayId,
            dayLabel: dayLabel,
            dayTitle: dayTitle,
            startedAt: startedAt,
            finishedAt: finishedAt,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$LocalSessionRowsTableProcessedTableManager = ProcessedTableManager<
    _$WorkoutDatabase,
    $LocalSessionRowsTable,
    LocalSessionRow,
    $$LocalSessionRowsTableFilterComposer,
    $$LocalSessionRowsTableOrderingComposer,
    $$LocalSessionRowsTableAnnotationComposer,
    $$LocalSessionRowsTableCreateCompanionBuilder,
    $$LocalSessionRowsTableUpdateCompanionBuilder,
    (
      LocalSessionRow,
      BaseReferences<_$WorkoutDatabase, $LocalSessionRowsTable, LocalSessionRow>
    ),
    LocalSessionRow,
    PrefetchHooks Function()>;
typedef $$LocalSetLogRowsTableCreateCompanionBuilder = LocalSetLogRowsCompanion
    Function({
  required String clientId,
  required String studentId,
  required String sessionClientId,
  required String exerciseId,
  required int setNo,
  Value<int?> repsDone,
  Value<double?> loadKg,
  Value<double?> rpe,
  required DateTime performedAt,
  Value<String?> revises,
  Value<int> rowid,
});
typedef $$LocalSetLogRowsTableUpdateCompanionBuilder = LocalSetLogRowsCompanion
    Function({
  Value<String> clientId,
  Value<String> studentId,
  Value<String> sessionClientId,
  Value<String> exerciseId,
  Value<int> setNo,
  Value<int?> repsDone,
  Value<double?> loadKg,
  Value<double?> rpe,
  Value<DateTime> performedAt,
  Value<String?> revises,
  Value<int> rowid,
});

class $$LocalSetLogRowsTableFilterComposer
    extends Composer<_$WorkoutDatabase, $LocalSetLogRowsTable> {
  $$LocalSetLogRowsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get clientId => $composableBuilder(
      column: $table.clientId, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get studentId => $composableBuilder(
      column: $table.studentId, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get sessionClientId => $composableBuilder(
      column: $table.sessionClientId,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get exerciseId => $composableBuilder(
      column: $table.exerciseId, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get setNo => $composableBuilder(
      column: $table.setNo, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get repsDone => $composableBuilder(
      column: $table.repsDone, builder: (column) => ColumnFilters(column));

  ColumnFilters<double> get loadKg => $composableBuilder(
      column: $table.loadKg, builder: (column) => ColumnFilters(column));

  ColumnFilters<double> get rpe => $composableBuilder(
      column: $table.rpe, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get performedAt => $composableBuilder(
      column: $table.performedAt, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get revises => $composableBuilder(
      column: $table.revises, builder: (column) => ColumnFilters(column));
}

class $$LocalSetLogRowsTableOrderingComposer
    extends Composer<_$WorkoutDatabase, $LocalSetLogRowsTable> {
  $$LocalSetLogRowsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get clientId => $composableBuilder(
      column: $table.clientId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get studentId => $composableBuilder(
      column: $table.studentId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get sessionClientId => $composableBuilder(
      column: $table.sessionClientId,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get exerciseId => $composableBuilder(
      column: $table.exerciseId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get setNo => $composableBuilder(
      column: $table.setNo, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get repsDone => $composableBuilder(
      column: $table.repsDone, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<double> get loadKg => $composableBuilder(
      column: $table.loadKg, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<double> get rpe => $composableBuilder(
      column: $table.rpe, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get performedAt => $composableBuilder(
      column: $table.performedAt, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get revises => $composableBuilder(
      column: $table.revises, builder: (column) => ColumnOrderings(column));
}

class $$LocalSetLogRowsTableAnnotationComposer
    extends Composer<_$WorkoutDatabase, $LocalSetLogRowsTable> {
  $$LocalSetLogRowsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get clientId =>
      $composableBuilder(column: $table.clientId, builder: (column) => column);

  GeneratedColumn<String> get studentId =>
      $composableBuilder(column: $table.studentId, builder: (column) => column);

  GeneratedColumn<String> get sessionClientId => $composableBuilder(
      column: $table.sessionClientId, builder: (column) => column);

  GeneratedColumn<String> get exerciseId => $composableBuilder(
      column: $table.exerciseId, builder: (column) => column);

  GeneratedColumn<int> get setNo =>
      $composableBuilder(column: $table.setNo, builder: (column) => column);

  GeneratedColumn<int> get repsDone =>
      $composableBuilder(column: $table.repsDone, builder: (column) => column);

  GeneratedColumn<double> get loadKg =>
      $composableBuilder(column: $table.loadKg, builder: (column) => column);

  GeneratedColumn<double> get rpe =>
      $composableBuilder(column: $table.rpe, builder: (column) => column);

  GeneratedColumn<DateTime> get performedAt => $composableBuilder(
      column: $table.performedAt, builder: (column) => column);

  GeneratedColumn<String> get revises =>
      $composableBuilder(column: $table.revises, builder: (column) => column);
}

class $$LocalSetLogRowsTableTableManager extends RootTableManager<
    _$WorkoutDatabase,
    $LocalSetLogRowsTable,
    LocalSetLogRow,
    $$LocalSetLogRowsTableFilterComposer,
    $$LocalSetLogRowsTableOrderingComposer,
    $$LocalSetLogRowsTableAnnotationComposer,
    $$LocalSetLogRowsTableCreateCompanionBuilder,
    $$LocalSetLogRowsTableUpdateCompanionBuilder,
    (
      LocalSetLogRow,
      BaseReferences<_$WorkoutDatabase, $LocalSetLogRowsTable, LocalSetLogRow>
    ),
    LocalSetLogRow,
    PrefetchHooks Function()> {
  $$LocalSetLogRowsTableTableManager(
      _$WorkoutDatabase db, $LocalSetLogRowsTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$LocalSetLogRowsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$LocalSetLogRowsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$LocalSetLogRowsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> clientId = const Value.absent(),
            Value<String> studentId = const Value.absent(),
            Value<String> sessionClientId = const Value.absent(),
            Value<String> exerciseId = const Value.absent(),
            Value<int> setNo = const Value.absent(),
            Value<int?> repsDone = const Value.absent(),
            Value<double?> loadKg = const Value.absent(),
            Value<double?> rpe = const Value.absent(),
            Value<DateTime> performedAt = const Value.absent(),
            Value<String?> revises = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              LocalSetLogRowsCompanion(
            clientId: clientId,
            studentId: studentId,
            sessionClientId: sessionClientId,
            exerciseId: exerciseId,
            setNo: setNo,
            repsDone: repsDone,
            loadKg: loadKg,
            rpe: rpe,
            performedAt: performedAt,
            revises: revises,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String clientId,
            required String studentId,
            required String sessionClientId,
            required String exerciseId,
            required int setNo,
            Value<int?> repsDone = const Value.absent(),
            Value<double?> loadKg = const Value.absent(),
            Value<double?> rpe = const Value.absent(),
            required DateTime performedAt,
            Value<String?> revises = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              LocalSetLogRowsCompanion.insert(
            clientId: clientId,
            studentId: studentId,
            sessionClientId: sessionClientId,
            exerciseId: exerciseId,
            setNo: setNo,
            repsDone: repsDone,
            loadKg: loadKg,
            rpe: rpe,
            performedAt: performedAt,
            revises: revises,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$LocalSetLogRowsTableProcessedTableManager = ProcessedTableManager<
    _$WorkoutDatabase,
    $LocalSetLogRowsTable,
    LocalSetLogRow,
    $$LocalSetLogRowsTableFilterComposer,
    $$LocalSetLogRowsTableOrderingComposer,
    $$LocalSetLogRowsTableAnnotationComposer,
    $$LocalSetLogRowsTableCreateCompanionBuilder,
    $$LocalSetLogRowsTableUpdateCompanionBuilder,
    (
      LocalSetLogRow,
      BaseReferences<_$WorkoutDatabase, $LocalSetLogRowsTable, LocalSetLogRow>
    ),
    LocalSetLogRow,
    PrefetchHooks Function()>;

class $WorkoutDatabaseManager {
  final _$WorkoutDatabase _db;
  $WorkoutDatabaseManager(this._db);
  $$TodayCacheTableTableManager get todayCache =>
      $$TodayCacheTableTableManager(_db, _db.todayCache);
  $$PendingEventRowsTableTableManager get pendingEventRows =>
      $$PendingEventRowsTableTableManager(_db, _db.pendingEventRows);
  $$LocalSessionRowsTableTableManager get localSessionRows =>
      $$LocalSessionRowsTableTableManager(_db, _db.localSessionRows);
  $$LocalSetLogRowsTableTableManager get localSetLogRows =>
      $$LocalSetLogRowsTableTableManager(_db, _db.localSetLogRows);
}
