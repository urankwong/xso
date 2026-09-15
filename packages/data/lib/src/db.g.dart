// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'db.dart';

// ignore_for_file: type=lint
class $FavoritesTable extends Favorites
    with TableInfo<$FavoritesTable, Favorite> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $FavoritesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
      'id', aliasedName, false,
      hasAutoIncrement: true,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('PRIMARY KEY AUTOINCREMENT'));
  static const VerificationMeta _sourceIdMeta =
      const VerificationMeta('sourceId');
  @override
  late final GeneratedColumn<String> sourceId = GeneratedColumn<String>(
      'source_id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _sourceNameMeta =
      const VerificationMeta('sourceName');
  @override
  late final GeneratedColumn<String> sourceName = GeneratedColumn<String>(
      'source_name', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _typeMeta = const VerificationMeta('type');
  @override
  late final GeneratedColumn<String> type = GeneratedColumn<String>(
      'type', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _titleMeta = const VerificationMeta('title');
  @override
  late final GeneratedColumn<String> title = GeneratedColumn<String>(
      'title', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _urlMeta = const VerificationMeta('url');
  @override
  late final GeneratedColumn<String> url = GeneratedColumn<String>(
      'url', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _extractCodeMeta =
      const VerificationMeta('extractCode');
  @override
  late final GeneratedColumn<String> extractCode = GeneratedColumn<String>(
      'extract_code', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _createdAtMeta =
      const VerificationMeta('createdAt');
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
      'created_at', aliasedName, false,
      type: DriftSqlType.dateTime,
      requiredDuringInsert: false,
      defaultValue: currentDateAndTime);
  static const VerificationMeta _isDeadMeta = const VerificationMeta('isDead');
  @override
  late final GeneratedColumn<bool> isDead = GeneratedColumn<bool>(
      'is_dead', aliasedName, false,
      type: DriftSqlType.bool,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('CHECK ("is_dead" IN (0, 1))'),
      defaultValue: const Constant(false));
  @override
  List<GeneratedColumn> get $columns => [
        id,
        sourceId,
        sourceName,
        type,
        title,
        url,
        extractCode,
        createdAt,
        isDead
      ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'favorites';
  @override
  VerificationContext validateIntegrity(Insertable<Favorite> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('source_id')) {
      context.handle(_sourceIdMeta,
          sourceId.isAcceptableOrUnknown(data['source_id']!, _sourceIdMeta));
    } else if (isInserting) {
      context.missing(_sourceIdMeta);
    }
    if (data.containsKey('source_name')) {
      context.handle(
          _sourceNameMeta,
          sourceName.isAcceptableOrUnknown(
              data['source_name']!, _sourceNameMeta));
    } else if (isInserting) {
      context.missing(_sourceNameMeta);
    }
    if (data.containsKey('type')) {
      context.handle(
          _typeMeta, type.isAcceptableOrUnknown(data['type']!, _typeMeta));
    } else if (isInserting) {
      context.missing(_typeMeta);
    }
    if (data.containsKey('title')) {
      context.handle(
          _titleMeta, title.isAcceptableOrUnknown(data['title']!, _titleMeta));
    } else if (isInserting) {
      context.missing(_titleMeta);
    }
    if (data.containsKey('url')) {
      context.handle(
          _urlMeta, url.isAcceptableOrUnknown(data['url']!, _urlMeta));
    } else if (isInserting) {
      context.missing(_urlMeta);
    }
    if (data.containsKey('extract_code')) {
      context.handle(
          _extractCodeMeta,
          extractCode.isAcceptableOrUnknown(
              data['extract_code']!, _extractCodeMeta));
    }
    if (data.containsKey('created_at')) {
      context.handle(_createdAtMeta,
          createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta));
    }
    if (data.containsKey('is_dead')) {
      context.handle(_isDeadMeta,
          isDead.isAcceptableOrUnknown(data['is_dead']!, _isDeadMeta));
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Favorite map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Favorite(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}id'])!,
      sourceId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}source_id'])!,
      sourceName: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}source_name'])!,
      type: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}type'])!,
      title: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}title'])!,
      url: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}url'])!,
      extractCode: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}extract_code']),
      createdAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}created_at'])!,
      isDead: attachedDatabase.typeMapping
          .read(DriftSqlType.bool, data['${effectivePrefix}is_dead'])!,
    );
  }

  @override
  $FavoritesTable createAlias(String alias) {
    return $FavoritesTable(attachedDatabase, alias);
  }
}

class Favorite extends DataClass implements Insertable<Favorite> {
  final int id;
  final String sourceId;
  final String sourceName;
  final String type;
  final String title;
  final String url;
  final String? extractCode;
  final DateTime createdAt;
  final bool isDead;
  const Favorite(
      {required this.id,
      required this.sourceId,
      required this.sourceName,
      required this.type,
      required this.title,
      required this.url,
      this.extractCode,
      required this.createdAt,
      required this.isDead});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['source_id'] = Variable<String>(sourceId);
    map['source_name'] = Variable<String>(sourceName);
    map['type'] = Variable<String>(type);
    map['title'] = Variable<String>(title);
    map['url'] = Variable<String>(url);
    if (!nullToAbsent || extractCode != null) {
      map['extract_code'] = Variable<String>(extractCode);
    }
    map['created_at'] = Variable<DateTime>(createdAt);
    map['is_dead'] = Variable<bool>(isDead);
    return map;
  }

  FavoritesCompanion toCompanion(bool nullToAbsent) {
    return FavoritesCompanion(
      id: Value(id),
      sourceId: Value(sourceId),
      sourceName: Value(sourceName),
      type: Value(type),
      title: Value(title),
      url: Value(url),
      extractCode: extractCode == null && nullToAbsent
          ? const Value.absent()
          : Value(extractCode),
      createdAt: Value(createdAt),
      isDead: Value(isDead),
    );
  }

  factory Favorite.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Favorite(
      id: serializer.fromJson<int>(json['id']),
      sourceId: serializer.fromJson<String>(json['sourceId']),
      sourceName: serializer.fromJson<String>(json['sourceName']),
      type: serializer.fromJson<String>(json['type']),
      title: serializer.fromJson<String>(json['title']),
      url: serializer.fromJson<String>(json['url']),
      extractCode: serializer.fromJson<String?>(json['extractCode']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      isDead: serializer.fromJson<bool>(json['isDead']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'sourceId': serializer.toJson<String>(sourceId),
      'sourceName': serializer.toJson<String>(sourceName),
      'type': serializer.toJson<String>(type),
      'title': serializer.toJson<String>(title),
      'url': serializer.toJson<String>(url),
      'extractCode': serializer.toJson<String?>(extractCode),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'isDead': serializer.toJson<bool>(isDead),
    };
  }

  Favorite copyWith(
          {int? id,
          String? sourceId,
          String? sourceName,
          String? type,
          String? title,
          String? url,
          Value<String?> extractCode = const Value.absent(),
          DateTime? createdAt,
          bool? isDead}) =>
      Favorite(
        id: id ?? this.id,
        sourceId: sourceId ?? this.sourceId,
        sourceName: sourceName ?? this.sourceName,
        type: type ?? this.type,
        title: title ?? this.title,
        url: url ?? this.url,
        extractCode: extractCode.present ? extractCode.value : this.extractCode,
        createdAt: createdAt ?? this.createdAt,
        isDead: isDead ?? this.isDead,
      );
  Favorite copyWithCompanion(FavoritesCompanion data) {
    return Favorite(
      id: data.id.present ? data.id.value : this.id,
      sourceId: data.sourceId.present ? data.sourceId.value : this.sourceId,
      sourceName:
          data.sourceName.present ? data.sourceName.value : this.sourceName,
      type: data.type.present ? data.type.value : this.type,
      title: data.title.present ? data.title.value : this.title,
      url: data.url.present ? data.url.value : this.url,
      extractCode:
          data.extractCode.present ? data.extractCode.value : this.extractCode,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      isDead: data.isDead.present ? data.isDead.value : this.isDead,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Favorite(')
          ..write('id: $id, ')
          ..write('sourceId: $sourceId, ')
          ..write('sourceName: $sourceName, ')
          ..write('type: $type, ')
          ..write('title: $title, ')
          ..write('url: $url, ')
          ..write('extractCode: $extractCode, ')
          ..write('createdAt: $createdAt, ')
          ..write('isDead: $isDead')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, sourceId, sourceName, type, title, url,
      extractCode, createdAt, isDead);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Favorite &&
          other.id == this.id &&
          other.sourceId == this.sourceId &&
          other.sourceName == this.sourceName &&
          other.type == this.type &&
          other.title == this.title &&
          other.url == this.url &&
          other.extractCode == this.extractCode &&
          other.createdAt == this.createdAt &&
          other.isDead == this.isDead);
}

class FavoritesCompanion extends UpdateCompanion<Favorite> {
  final Value<int> id;
  final Value<String> sourceId;
  final Value<String> sourceName;
  final Value<String> type;
  final Value<String> title;
  final Value<String> url;
  final Value<String?> extractCode;
  final Value<DateTime> createdAt;
  final Value<bool> isDead;
  const FavoritesCompanion({
    this.id = const Value.absent(),
    this.sourceId = const Value.absent(),
    this.sourceName = const Value.absent(),
    this.type = const Value.absent(),
    this.title = const Value.absent(),
    this.url = const Value.absent(),
    this.extractCode = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.isDead = const Value.absent(),
  });
  FavoritesCompanion.insert({
    this.id = const Value.absent(),
    required String sourceId,
    required String sourceName,
    required String type,
    required String title,
    required String url,
    this.extractCode = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.isDead = const Value.absent(),
  })  : sourceId = Value(sourceId),
        sourceName = Value(sourceName),
        type = Value(type),
        title = Value(title),
        url = Value(url);
  static Insertable<Favorite> custom({
    Expression<int>? id,
    Expression<String>? sourceId,
    Expression<String>? sourceName,
    Expression<String>? type,
    Expression<String>? title,
    Expression<String>? url,
    Expression<String>? extractCode,
    Expression<DateTime>? createdAt,
    Expression<bool>? isDead,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (sourceId != null) 'source_id': sourceId,
      if (sourceName != null) 'source_name': sourceName,
      if (type != null) 'type': type,
      if (title != null) 'title': title,
      if (url != null) 'url': url,
      if (extractCode != null) 'extract_code': extractCode,
      if (createdAt != null) 'created_at': createdAt,
      if (isDead != null) 'is_dead': isDead,
    });
  }

  FavoritesCompanion copyWith(
      {Value<int>? id,
      Value<String>? sourceId,
      Value<String>? sourceName,
      Value<String>? type,
      Value<String>? title,
      Value<String>? url,
      Value<String?>? extractCode,
      Value<DateTime>? createdAt,
      Value<bool>? isDead}) {
    return FavoritesCompanion(
      id: id ?? this.id,
      sourceId: sourceId ?? this.sourceId,
      sourceName: sourceName ?? this.sourceName,
      type: type ?? this.type,
      title: title ?? this.title,
      url: url ?? this.url,
      extractCode: extractCode ?? this.extractCode,
      createdAt: createdAt ?? this.createdAt,
      isDead: isDead ?? this.isDead,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (sourceId.present) {
      map['source_id'] = Variable<String>(sourceId.value);
    }
    if (sourceName.present) {
      map['source_name'] = Variable<String>(sourceName.value);
    }
    if (type.present) {
      map['type'] = Variable<String>(type.value);
    }
    if (title.present) {
      map['title'] = Variable<String>(title.value);
    }
    if (url.present) {
      map['url'] = Variable<String>(url.value);
    }
    if (extractCode.present) {
      map['extract_code'] = Variable<String>(extractCode.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (isDead.present) {
      map['is_dead'] = Variable<bool>(isDead.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('FavoritesCompanion(')
          ..write('id: $id, ')
          ..write('sourceId: $sourceId, ')
          ..write('sourceName: $sourceName, ')
          ..write('type: $type, ')
          ..write('title: $title, ')
          ..write('url: $url, ')
          ..write('extractCode: $extractCode, ')
          ..write('createdAt: $createdAt, ')
          ..write('isDead: $isDead')
          ..write(')'))
        .toString();
  }
}

class $HistoriesTable extends Histories
    with TableInfo<$HistoriesTable, History> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $HistoriesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
      'id', aliasedName, false,
      hasAutoIncrement: true,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('PRIMARY KEY AUTOINCREMENT'));
  static const VerificationMeta _keywordMeta =
      const VerificationMeta('keyword');
  @override
  late final GeneratedColumn<String> keyword = GeneratedColumn<String>(
      'keyword', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _searchedAtMeta =
      const VerificationMeta('searchedAt');
  @override
  late final GeneratedColumn<DateTime> searchedAt = GeneratedColumn<DateTime>(
      'searched_at', aliasedName, false,
      type: DriftSqlType.dateTime,
      requiredDuringInsert: false,
      defaultValue: currentDateAndTime);
  @override
  List<GeneratedColumn> get $columns => [id, keyword, searchedAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'histories';
  @override
  VerificationContext validateIntegrity(Insertable<History> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('keyword')) {
      context.handle(_keywordMeta,
          keyword.isAcceptableOrUnknown(data['keyword']!, _keywordMeta));
    } else if (isInserting) {
      context.missing(_keywordMeta);
    }
    if (data.containsKey('searched_at')) {
      context.handle(
          _searchedAtMeta,
          searchedAt.isAcceptableOrUnknown(
              data['searched_at']!, _searchedAtMeta));
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  History map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return History(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}id'])!,
      keyword: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}keyword'])!,
      searchedAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}searched_at'])!,
    );
  }

  @override
  $HistoriesTable createAlias(String alias) {
    return $HistoriesTable(attachedDatabase, alias);
  }
}

class History extends DataClass implements Insertable<History> {
  final int id;
  final String keyword;
  final DateTime searchedAt;
  const History(
      {required this.id, required this.keyword, required this.searchedAt});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['keyword'] = Variable<String>(keyword);
    map['searched_at'] = Variable<DateTime>(searchedAt);
    return map;
  }

  HistoriesCompanion toCompanion(bool nullToAbsent) {
    return HistoriesCompanion(
      id: Value(id),
      keyword: Value(keyword),
      searchedAt: Value(searchedAt),
    );
  }

  factory History.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return History(
      id: serializer.fromJson<int>(json['id']),
      keyword: serializer.fromJson<String>(json['keyword']),
      searchedAt: serializer.fromJson<DateTime>(json['searchedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'keyword': serializer.toJson<String>(keyword),
      'searchedAt': serializer.toJson<DateTime>(searchedAt),
    };
  }

  History copyWith({int? id, String? keyword, DateTime? searchedAt}) => History(
        id: id ?? this.id,
        keyword: keyword ?? this.keyword,
        searchedAt: searchedAt ?? this.searchedAt,
      );
  History copyWithCompanion(HistoriesCompanion data) {
    return History(
      id: data.id.present ? data.id.value : this.id,
      keyword: data.keyword.present ? data.keyword.value : this.keyword,
      searchedAt:
          data.searchedAt.present ? data.searchedAt.value : this.searchedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('History(')
          ..write('id: $id, ')
          ..write('keyword: $keyword, ')
          ..write('searchedAt: $searchedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, keyword, searchedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is History &&
          other.id == this.id &&
          other.keyword == this.keyword &&
          other.searchedAt == this.searchedAt);
}

class HistoriesCompanion extends UpdateCompanion<History> {
  final Value<int> id;
  final Value<String> keyword;
  final Value<DateTime> searchedAt;
  const HistoriesCompanion({
    this.id = const Value.absent(),
    this.keyword = const Value.absent(),
    this.searchedAt = const Value.absent(),
  });
  HistoriesCompanion.insert({
    this.id = const Value.absent(),
    required String keyword,
    this.searchedAt = const Value.absent(),
  }) : keyword = Value(keyword);
  static Insertable<History> custom({
    Expression<int>? id,
    Expression<String>? keyword,
    Expression<DateTime>? searchedAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (keyword != null) 'keyword': keyword,
      if (searchedAt != null) 'searched_at': searchedAt,
    });
  }

  HistoriesCompanion copyWith(
      {Value<int>? id, Value<String>? keyword, Value<DateTime>? searchedAt}) {
    return HistoriesCompanion(
      id: id ?? this.id,
      keyword: keyword ?? this.keyword,
      searchedAt: searchedAt ?? this.searchedAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (keyword.present) {
      map['keyword'] = Variable<String>(keyword.value);
    }
    if (searchedAt.present) {
      map['searched_at'] = Variable<DateTime>(searchedAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('HistoriesCompanion(')
          ..write('id: $id, ')
          ..write('keyword: $keyword, ')
          ..write('searchedAt: $searchedAt')
          ..write(')'))
        .toString();
  }
}

class $RecentItemsTable extends RecentItems
    with TableInfo<$RecentItemsTable, RecentItem> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $RecentItemsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
      'id', aliasedName, false,
      hasAutoIncrement: true,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('PRIMARY KEY AUTOINCREMENT'));
  static const VerificationMeta _sourceIdMeta =
      const VerificationMeta('sourceId');
  @override
  late final GeneratedColumn<String> sourceId = GeneratedColumn<String>(
      'source_id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _sourceNameMeta =
      const VerificationMeta('sourceName');
  @override
  late final GeneratedColumn<String> sourceName = GeneratedColumn<String>(
      'source_name', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _kindMeta = const VerificationMeta('kind');
  @override
  late final GeneratedColumn<String> kind = GeneratedColumn<String>(
      'kind', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _titleMeta = const VerificationMeta('title');
  @override
  late final GeneratedColumn<String> title = GeneratedColumn<String>(
      'title', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _urlMeta = const VerificationMeta('url');
  @override
  late final GeneratedColumn<String> url = GeneratedColumn<String>(
      'url', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _extractCodeMeta =
      const VerificationMeta('extractCode');
  @override
  late final GeneratedColumn<String> extractCode = GeneratedColumn<String>(
      'extract_code', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _usedAtMeta = const VerificationMeta('usedAt');
  @override
  late final GeneratedColumn<DateTime> usedAt = GeneratedColumn<DateTime>(
      'used_at', aliasedName, false,
      type: DriftSqlType.dateTime,
      requiredDuringInsert: false,
      defaultValue: currentDateAndTime);
  @override
  List<GeneratedColumn> get $columns =>
      [id, sourceId, sourceName, kind, title, url, extractCode, usedAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'recent_items';
  @override
  VerificationContext validateIntegrity(Insertable<RecentItem> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('source_id')) {
      context.handle(_sourceIdMeta,
          sourceId.isAcceptableOrUnknown(data['source_id']!, _sourceIdMeta));
    } else if (isInserting) {
      context.missing(_sourceIdMeta);
    }
    if (data.containsKey('source_name')) {
      context.handle(
          _sourceNameMeta,
          sourceName.isAcceptableOrUnknown(
              data['source_name']!, _sourceNameMeta));
    } else if (isInserting) {
      context.missing(_sourceNameMeta);
    }
    if (data.containsKey('kind')) {
      context.handle(
          _kindMeta, kind.isAcceptableOrUnknown(data['kind']!, _kindMeta));
    } else if (isInserting) {
      context.missing(_kindMeta);
    }
    if (data.containsKey('title')) {
      context.handle(
          _titleMeta, title.isAcceptableOrUnknown(data['title']!, _titleMeta));
    } else if (isInserting) {
      context.missing(_titleMeta);
    }
    if (data.containsKey('url')) {
      context.handle(
          _urlMeta, url.isAcceptableOrUnknown(data['url']!, _urlMeta));
    } else if (isInserting) {
      context.missing(_urlMeta);
    }
    if (data.containsKey('extract_code')) {
      context.handle(
          _extractCodeMeta,
          extractCode.isAcceptableOrUnknown(
              data['extract_code']!, _extractCodeMeta));
    }
    if (data.containsKey('used_at')) {
      context.handle(_usedAtMeta,
          usedAt.isAcceptableOrUnknown(data['used_at']!, _usedAtMeta));
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  RecentItem map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return RecentItem(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}id'])!,
      sourceId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}source_id'])!,
      sourceName: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}source_name'])!,
      kind: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}kind'])!,
      title: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}title'])!,
      url: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}url'])!,
      extractCode: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}extract_code']),
      usedAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}used_at'])!,
    );
  }

  @override
  $RecentItemsTable createAlias(String alias) {
    return $RecentItemsTable(attachedDatabase, alias);
  }
}

class RecentItem extends DataClass implements Insertable<RecentItem> {
  final int id;
  final String sourceId;
  final String sourceName;

  /// 'read'（阅读）| 'play'（播放）
  final String kind;
  final String title;
  final String url;
  final String? extractCode;
  final DateTime usedAt;
  const RecentItem(
      {required this.id,
      required this.sourceId,
      required this.sourceName,
      required this.kind,
      required this.title,
      required this.url,
      this.extractCode,
      required this.usedAt});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['source_id'] = Variable<String>(sourceId);
    map['source_name'] = Variable<String>(sourceName);
    map['kind'] = Variable<String>(kind);
    map['title'] = Variable<String>(title);
    map['url'] = Variable<String>(url);
    if (!nullToAbsent || extractCode != null) {
      map['extract_code'] = Variable<String>(extractCode);
    }
    map['used_at'] = Variable<DateTime>(usedAt);
    return map;
  }

  RecentItemsCompanion toCompanion(bool nullToAbsent) {
    return RecentItemsCompanion(
      id: Value(id),
      sourceId: Value(sourceId),
      sourceName: Value(sourceName),
      kind: Value(kind),
      title: Value(title),
      url: Value(url),
      extractCode: extractCode == null && nullToAbsent
          ? const Value.absent()
          : Value(extractCode),
      usedAt: Value(usedAt),
    );
  }

  factory RecentItem.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return RecentItem(
      id: serializer.fromJson<int>(json['id']),
      sourceId: serializer.fromJson<String>(json['sourceId']),
      sourceName: serializer.fromJson<String>(json['sourceName']),
      kind: serializer.fromJson<String>(json['kind']),
      title: serializer.fromJson<String>(json['title']),
      url: serializer.fromJson<String>(json['url']),
      extractCode: serializer.fromJson<String?>(json['extractCode']),
      usedAt: serializer.fromJson<DateTime>(json['usedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'sourceId': serializer.toJson<String>(sourceId),
      'sourceName': serializer.toJson<String>(sourceName),
      'kind': serializer.toJson<String>(kind),
      'title': serializer.toJson<String>(title),
      'url': serializer.toJson<String>(url),
      'extractCode': serializer.toJson<String?>(extractCode),
      'usedAt': serializer.toJson<DateTime>(usedAt),
    };
  }

  RecentItem copyWith(
          {int? id,
          String? sourceId,
          String? sourceName,
          String? kind,
          String? title,
          String? url,
          Value<String?> extractCode = const Value.absent(),
          DateTime? usedAt}) =>
      RecentItem(
        id: id ?? this.id,
        sourceId: sourceId ?? this.sourceId,
        sourceName: sourceName ?? this.sourceName,
        kind: kind ?? this.kind,
        title: title ?? this.title,
        url: url ?? this.url,
        extractCode: extractCode.present ? extractCode.value : this.extractCode,
        usedAt: usedAt ?? this.usedAt,
      );
  RecentItem copyWithCompanion(RecentItemsCompanion data) {
    return RecentItem(
      id: data.id.present ? data.id.value : this.id,
      sourceId: data.sourceId.present ? data.sourceId.value : this.sourceId,
      sourceName:
          data.sourceName.present ? data.sourceName.value : this.sourceName,
      kind: data.kind.present ? data.kind.value : this.kind,
      title: data.title.present ? data.title.value : this.title,
      url: data.url.present ? data.url.value : this.url,
      extractCode:
          data.extractCode.present ? data.extractCode.value : this.extractCode,
      usedAt: data.usedAt.present ? data.usedAt.value : this.usedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('RecentItem(')
          ..write('id: $id, ')
          ..write('sourceId: $sourceId, ')
          ..write('sourceName: $sourceName, ')
          ..write('kind: $kind, ')
          ..write('title: $title, ')
          ..write('url: $url, ')
          ..write('extractCode: $extractCode, ')
          ..write('usedAt: $usedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
      id, sourceId, sourceName, kind, title, url, extractCode, usedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is RecentItem &&
          other.id == this.id &&
          other.sourceId == this.sourceId &&
          other.sourceName == this.sourceName &&
          other.kind == this.kind &&
          other.title == this.title &&
          other.url == this.url &&
          other.extractCode == this.extractCode &&
          other.usedAt == this.usedAt);
}

class RecentItemsCompanion extends UpdateCompanion<RecentItem> {
  final Value<int> id;
  final Value<String> sourceId;
  final Value<String> sourceName;
  final Value<String> kind;
  final Value<String> title;
  final Value<String> url;
  final Value<String?> extractCode;
  final Value<DateTime> usedAt;
  const RecentItemsCompanion({
    this.id = const Value.absent(),
    this.sourceId = const Value.absent(),
    this.sourceName = const Value.absent(),
    this.kind = const Value.absent(),
    this.title = const Value.absent(),
    this.url = const Value.absent(),
    this.extractCode = const Value.absent(),
    this.usedAt = const Value.absent(),
  });
  RecentItemsCompanion.insert({
    this.id = const Value.absent(),
    required String sourceId,
    required String sourceName,
    required String kind,
    required String title,
    required String url,
    this.extractCode = const Value.absent(),
    this.usedAt = const Value.absent(),
  })  : sourceId = Value(sourceId),
        sourceName = Value(sourceName),
        kind = Value(kind),
        title = Value(title),
        url = Value(url);
  static Insertable<RecentItem> custom({
    Expression<int>? id,
    Expression<String>? sourceId,
    Expression<String>? sourceName,
    Expression<String>? kind,
    Expression<String>? title,
    Expression<String>? url,
    Expression<String>? extractCode,
    Expression<DateTime>? usedAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (sourceId != null) 'source_id': sourceId,
      if (sourceName != null) 'source_name': sourceName,
      if (kind != null) 'kind': kind,
      if (title != null) 'title': title,
      if (url != null) 'url': url,
      if (extractCode != null) 'extract_code': extractCode,
      if (usedAt != null) 'used_at': usedAt,
    });
  }

  RecentItemsCompanion copyWith(
      {Value<int>? id,
      Value<String>? sourceId,
      Value<String>? sourceName,
      Value<String>? kind,
      Value<String>? title,
      Value<String>? url,
      Value<String?>? extractCode,
      Value<DateTime>? usedAt}) {
    return RecentItemsCompanion(
      id: id ?? this.id,
      sourceId: sourceId ?? this.sourceId,
      sourceName: sourceName ?? this.sourceName,
      kind: kind ?? this.kind,
      title: title ?? this.title,
      url: url ?? this.url,
      extractCode: extractCode ?? this.extractCode,
      usedAt: usedAt ?? this.usedAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (sourceId.present) {
      map['source_id'] = Variable<String>(sourceId.value);
    }
    if (sourceName.present) {
      map['source_name'] = Variable<String>(sourceName.value);
    }
    if (kind.present) {
      map['kind'] = Variable<String>(kind.value);
    }
    if (title.present) {
      map['title'] = Variable<String>(title.value);
    }
    if (url.present) {
      map['url'] = Variable<String>(url.value);
    }
    if (extractCode.present) {
      map['extract_code'] = Variable<String>(extractCode.value);
    }
    if (usedAt.present) {
      map['used_at'] = Variable<DateTime>(usedAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('RecentItemsCompanion(')
          ..write('id: $id, ')
          ..write('sourceId: $sourceId, ')
          ..write('sourceName: $sourceName, ')
          ..write('kind: $kind, ')
          ..write('title: $title, ')
          ..write('url: $url, ')
          ..write('extractCode: $extractCode, ')
          ..write('usedAt: $usedAt')
          ..write(')'))
        .toString();
  }
}

abstract class _$AppDb extends GeneratedDatabase {
  _$AppDb(QueryExecutor e) : super(e);
  $AppDbManager get managers => $AppDbManager(this);
  late final $FavoritesTable favorites = $FavoritesTable(this);
  late final $HistoriesTable histories = $HistoriesTable(this);
  late final $RecentItemsTable recentItems = $RecentItemsTable(this);
  late final FavoriteDao favoriteDao = FavoriteDao(this as AppDb);
  late final HistoryDao historyDao = HistoryDao(this as AppDb);
  late final RecentDao recentDao = RecentDao(this as AppDb);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities =>
      [favorites, histories, recentItems];
}

typedef $$FavoritesTableCreateCompanionBuilder = FavoritesCompanion Function({
  Value<int> id,
  required String sourceId,
  required String sourceName,
  required String type,
  required String title,
  required String url,
  Value<String?> extractCode,
  Value<DateTime> createdAt,
  Value<bool> isDead,
});
typedef $$FavoritesTableUpdateCompanionBuilder = FavoritesCompanion Function({
  Value<int> id,
  Value<String> sourceId,
  Value<String> sourceName,
  Value<String> type,
  Value<String> title,
  Value<String> url,
  Value<String?> extractCode,
  Value<DateTime> createdAt,
  Value<bool> isDead,
});

class $$FavoritesTableFilterComposer
    extends Composer<_$AppDb, $FavoritesTable> {
  $$FavoritesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get sourceId => $composableBuilder(
      column: $table.sourceId, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get sourceName => $composableBuilder(
      column: $table.sourceName, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get type => $composableBuilder(
      column: $table.type, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get title => $composableBuilder(
      column: $table.title, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get url => $composableBuilder(
      column: $table.url, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get extractCode => $composableBuilder(
      column: $table.extractCode, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnFilters(column));

  ColumnFilters<bool> get isDead => $composableBuilder(
      column: $table.isDead, builder: (column) => ColumnFilters(column));
}

class $$FavoritesTableOrderingComposer
    extends Composer<_$AppDb, $FavoritesTable> {
  $$FavoritesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get sourceId => $composableBuilder(
      column: $table.sourceId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get sourceName => $composableBuilder(
      column: $table.sourceName, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get type => $composableBuilder(
      column: $table.type, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get title => $composableBuilder(
      column: $table.title, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get url => $composableBuilder(
      column: $table.url, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get extractCode => $composableBuilder(
      column: $table.extractCode, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<bool> get isDead => $composableBuilder(
      column: $table.isDead, builder: (column) => ColumnOrderings(column));
}

class $$FavoritesTableAnnotationComposer
    extends Composer<_$AppDb, $FavoritesTable> {
  $$FavoritesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get sourceId =>
      $composableBuilder(column: $table.sourceId, builder: (column) => column);

  GeneratedColumn<String> get sourceName => $composableBuilder(
      column: $table.sourceName, builder: (column) => column);

  GeneratedColumn<String> get type =>
      $composableBuilder(column: $table.type, builder: (column) => column);

  GeneratedColumn<String> get title =>
      $composableBuilder(column: $table.title, builder: (column) => column);

  GeneratedColumn<String> get url =>
      $composableBuilder(column: $table.url, builder: (column) => column);

  GeneratedColumn<String> get extractCode => $composableBuilder(
      column: $table.extractCode, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<bool> get isDead =>
      $composableBuilder(column: $table.isDead, builder: (column) => column);
}

class $$FavoritesTableTableManager extends RootTableManager<
    _$AppDb,
    $FavoritesTable,
    Favorite,
    $$FavoritesTableFilterComposer,
    $$FavoritesTableOrderingComposer,
    $$FavoritesTableAnnotationComposer,
    $$FavoritesTableCreateCompanionBuilder,
    $$FavoritesTableUpdateCompanionBuilder,
    (Favorite, BaseReferences<_$AppDb, $FavoritesTable, Favorite>),
    Favorite,
    PrefetchHooks Function()> {
  $$FavoritesTableTableManager(_$AppDb db, $FavoritesTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$FavoritesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$FavoritesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$FavoritesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<int> id = const Value.absent(),
            Value<String> sourceId = const Value.absent(),
            Value<String> sourceName = const Value.absent(),
            Value<String> type = const Value.absent(),
            Value<String> title = const Value.absent(),
            Value<String> url = const Value.absent(),
            Value<String?> extractCode = const Value.absent(),
            Value<DateTime> createdAt = const Value.absent(),
            Value<bool> isDead = const Value.absent(),
          }) =>
              FavoritesCompanion(
            id: id,
            sourceId: sourceId,
            sourceName: sourceName,
            type: type,
            title: title,
            url: url,
            extractCode: extractCode,
            createdAt: createdAt,
            isDead: isDead,
          ),
          createCompanionCallback: ({
            Value<int> id = const Value.absent(),
            required String sourceId,
            required String sourceName,
            required String type,
            required String title,
            required String url,
            Value<String?> extractCode = const Value.absent(),
            Value<DateTime> createdAt = const Value.absent(),
            Value<bool> isDead = const Value.absent(),
          }) =>
              FavoritesCompanion.insert(
            id: id,
            sourceId: sourceId,
            sourceName: sourceName,
            type: type,
            title: title,
            url: url,
            extractCode: extractCode,
            createdAt: createdAt,
            isDead: isDead,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (
                    e.readTable<$FavoritesTable, Favorite>(table),
                    BaseReferences<_$AppDb, $FavoritesTable, Favorite>(
                        db, table, e)
                  ))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$FavoritesTableProcessedTableManager = ProcessedTableManager<
    _$AppDb,
    $FavoritesTable,
    Favorite,
    $$FavoritesTableFilterComposer,
    $$FavoritesTableOrderingComposer,
    $$FavoritesTableAnnotationComposer,
    $$FavoritesTableCreateCompanionBuilder,
    $$FavoritesTableUpdateCompanionBuilder,
    (Favorite, BaseReferences<_$AppDb, $FavoritesTable, Favorite>),
    Favorite,
    PrefetchHooks Function()>;
typedef $$HistoriesTableCreateCompanionBuilder = HistoriesCompanion Function({
  Value<int> id,
  required String keyword,
  Value<DateTime> searchedAt,
});
typedef $$HistoriesTableUpdateCompanionBuilder = HistoriesCompanion Function({
  Value<int> id,
  Value<String> keyword,
  Value<DateTime> searchedAt,
});

class $$HistoriesTableFilterComposer
    extends Composer<_$AppDb, $HistoriesTable> {
  $$HistoriesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get keyword => $composableBuilder(
      column: $table.keyword, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get searchedAt => $composableBuilder(
      column: $table.searchedAt, builder: (column) => ColumnFilters(column));
}

class $$HistoriesTableOrderingComposer
    extends Composer<_$AppDb, $HistoriesTable> {
  $$HistoriesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get keyword => $composableBuilder(
      column: $table.keyword, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get searchedAt => $composableBuilder(
      column: $table.searchedAt, builder: (column) => ColumnOrderings(column));
}

class $$HistoriesTableAnnotationComposer
    extends Composer<_$AppDb, $HistoriesTable> {
  $$HistoriesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get keyword =>
      $composableBuilder(column: $table.keyword, builder: (column) => column);

  GeneratedColumn<DateTime> get searchedAt => $composableBuilder(
      column: $table.searchedAt, builder: (column) => column);
}

class $$HistoriesTableTableManager extends RootTableManager<
    _$AppDb,
    $HistoriesTable,
    History,
    $$HistoriesTableFilterComposer,
    $$HistoriesTableOrderingComposer,
    $$HistoriesTableAnnotationComposer,
    $$HistoriesTableCreateCompanionBuilder,
    $$HistoriesTableUpdateCompanionBuilder,
    (History, BaseReferences<_$AppDb, $HistoriesTable, History>),
    History,
    PrefetchHooks Function()> {
  $$HistoriesTableTableManager(_$AppDb db, $HistoriesTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$HistoriesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$HistoriesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$HistoriesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<int> id = const Value.absent(),
            Value<String> keyword = const Value.absent(),
            Value<DateTime> searchedAt = const Value.absent(),
          }) =>
              HistoriesCompanion(
            id: id,
            keyword: keyword,
            searchedAt: searchedAt,
          ),
          createCompanionCallback: ({
            Value<int> id = const Value.absent(),
            required String keyword,
            Value<DateTime> searchedAt = const Value.absent(),
          }) =>
              HistoriesCompanion.insert(
            id: id,
            keyword: keyword,
            searchedAt: searchedAt,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (
                    e.readTable<$HistoriesTable, History>(table),
                    BaseReferences<_$AppDb, $HistoriesTable, History>(
                        db, table, e)
                  ))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$HistoriesTableProcessedTableManager = ProcessedTableManager<
    _$AppDb,
    $HistoriesTable,
    History,
    $$HistoriesTableFilterComposer,
    $$HistoriesTableOrderingComposer,
    $$HistoriesTableAnnotationComposer,
    $$HistoriesTableCreateCompanionBuilder,
    $$HistoriesTableUpdateCompanionBuilder,
    (History, BaseReferences<_$AppDb, $HistoriesTable, History>),
    History,
    PrefetchHooks Function()>;
typedef $$RecentItemsTableCreateCompanionBuilder = RecentItemsCompanion
    Function({
  Value<int> id,
  required String sourceId,
  required String sourceName,
  required String kind,
  required String title,
  required String url,
  Value<String?> extractCode,
  Value<DateTime> usedAt,
});
typedef $$RecentItemsTableUpdateCompanionBuilder = RecentItemsCompanion
    Function({
  Value<int> id,
  Value<String> sourceId,
  Value<String> sourceName,
  Value<String> kind,
  Value<String> title,
  Value<String> url,
  Value<String?> extractCode,
  Value<DateTime> usedAt,
});

class $$RecentItemsTableFilterComposer
    extends Composer<_$AppDb, $RecentItemsTable> {
  $$RecentItemsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get sourceId => $composableBuilder(
      column: $table.sourceId, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get sourceName => $composableBuilder(
      column: $table.sourceName, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get kind => $composableBuilder(
      column: $table.kind, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get title => $composableBuilder(
      column: $table.title, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get url => $composableBuilder(
      column: $table.url, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get extractCode => $composableBuilder(
      column: $table.extractCode, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get usedAt => $composableBuilder(
      column: $table.usedAt, builder: (column) => ColumnFilters(column));
}

class $$RecentItemsTableOrderingComposer
    extends Composer<_$AppDb, $RecentItemsTable> {
  $$RecentItemsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get sourceId => $composableBuilder(
      column: $table.sourceId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get sourceName => $composableBuilder(
      column: $table.sourceName, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get kind => $composableBuilder(
      column: $table.kind, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get title => $composableBuilder(
      column: $table.title, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get url => $composableBuilder(
      column: $table.url, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get extractCode => $composableBuilder(
      column: $table.extractCode, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get usedAt => $composableBuilder(
      column: $table.usedAt, builder: (column) => ColumnOrderings(column));
}

class $$RecentItemsTableAnnotationComposer
    extends Composer<_$AppDb, $RecentItemsTable> {
  $$RecentItemsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get sourceId =>
      $composableBuilder(column: $table.sourceId, builder: (column) => column);

  GeneratedColumn<String> get sourceName => $composableBuilder(
      column: $table.sourceName, builder: (column) => column);

  GeneratedColumn<String> get kind =>
      $composableBuilder(column: $table.kind, builder: (column) => column);

  GeneratedColumn<String> get title =>
      $composableBuilder(column: $table.title, builder: (column) => column);

  GeneratedColumn<String> get url =>
      $composableBuilder(column: $table.url, builder: (column) => column);

  GeneratedColumn<String> get extractCode => $composableBuilder(
      column: $table.extractCode, builder: (column) => column);

  GeneratedColumn<DateTime> get usedAt =>
      $composableBuilder(column: $table.usedAt, builder: (column) => column);
}

class $$RecentItemsTableTableManager extends RootTableManager<
    _$AppDb,
    $RecentItemsTable,
    RecentItem,
    $$RecentItemsTableFilterComposer,
    $$RecentItemsTableOrderingComposer,
    $$RecentItemsTableAnnotationComposer,
    $$RecentItemsTableCreateCompanionBuilder,
    $$RecentItemsTableUpdateCompanionBuilder,
    (RecentItem, BaseReferences<_$AppDb, $RecentItemsTable, RecentItem>),
    RecentItem,
    PrefetchHooks Function()> {
  $$RecentItemsTableTableManager(_$AppDb db, $RecentItemsTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$RecentItemsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$RecentItemsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$RecentItemsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<int> id = const Value.absent(),
            Value<String> sourceId = const Value.absent(),
            Value<String> sourceName = const Value.absent(),
            Value<String> kind = const Value.absent(),
            Value<String> title = const Value.absent(),
            Value<String> url = const Value.absent(),
            Value<String?> extractCode = const Value.absent(),
            Value<DateTime> usedAt = const Value.absent(),
          }) =>
              RecentItemsCompanion(
            id: id,
            sourceId: sourceId,
            sourceName: sourceName,
            kind: kind,
            title: title,
            url: url,
            extractCode: extractCode,
            usedAt: usedAt,
          ),
          createCompanionCallback: ({
            Value<int> id = const Value.absent(),
            required String sourceId,
            required String sourceName,
            required String kind,
            required String title,
            required String url,
            Value<String?> extractCode = const Value.absent(),
            Value<DateTime> usedAt = const Value.absent(),
          }) =>
              RecentItemsCompanion.insert(
            id: id,
            sourceId: sourceId,
            sourceName: sourceName,
            kind: kind,
            title: title,
            url: url,
            extractCode: extractCode,
            usedAt: usedAt,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (
                    e.readTable<$RecentItemsTable, RecentItem>(table),
                    BaseReferences<_$AppDb, $RecentItemsTable, RecentItem>(
                        db, table, e)
                  ))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$RecentItemsTableProcessedTableManager = ProcessedTableManager<
    _$AppDb,
    $RecentItemsTable,
    RecentItem,
    $$RecentItemsTableFilterComposer,
    $$RecentItemsTableOrderingComposer,
    $$RecentItemsTableAnnotationComposer,
    $$RecentItemsTableCreateCompanionBuilder,
    $$RecentItemsTableUpdateCompanionBuilder,
    (RecentItem, BaseReferences<_$AppDb, $RecentItemsTable, RecentItem>),
    RecentItem,
    PrefetchHooks Function()>;

class $AppDbManager {
  final _$AppDb _db;
  $AppDbManager(this._db);
  $$FavoritesTableTableManager get favorites =>
      $$FavoritesTableTableManager(_db, _db.favorites);
  $$HistoriesTableTableManager get histories =>
      $$HistoriesTableTableManager(_db, _db.histories);
  $$RecentItemsTableTableManager get recentItems =>
      $$RecentItemsTableTableManager(_db, _db.recentItems);
}
