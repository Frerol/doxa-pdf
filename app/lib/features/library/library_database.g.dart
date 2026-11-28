// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'library_database.dart';

// ignore_for_file: type=lint
class $DocumentsTable extends Documents
    with TableInfo<$DocumentsTable, DocumentRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $DocumentsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _identityMeta = const VerificationMeta(
    'identity',
  );
  @override
  late final GeneratedColumn<String> identity = GeneratedColumn<String>(
    'identity',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways('UNIQUE'),
  );
  static const VerificationMeta _uriMeta = const VerificationMeta('uri');
  @override
  late final GeneratedColumn<String> uri = GeneratedColumn<String>(
    'uri',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _displayNameMeta = const VerificationMeta(
    'displayName',
  );
  @override
  late final GeneratedColumn<String> displayName = GeneratedColumn<String>(
    'display_name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _pageCountMeta = const VerificationMeta(
    'pageCount',
  );
  @override
  late final GeneratedColumn<int> pageCount = GeneratedColumn<int>(
    'page_count',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _pageMeta = const VerificationMeta('page');
  @override
  late final GeneratedColumn<int> page = GeneratedColumn<int>(
    'page',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _pageXMeta = const VerificationMeta('pageX');
  @override
  late final GeneratedColumn<double> pageX = GeneratedColumn<double>(
    'page_x',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _pageYMeta = const VerificationMeta('pageY');
  @override
  late final GeneratedColumn<double> pageY = GeneratedColumn<double>(
    'page_y',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _zoomMeta = const VerificationMeta('zoom');
  @override
  late final GeneratedColumn<double> zoom = GeneratedColumn<double>(
    'zoom',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
    defaultValue: const Constant(1),
  );
  static const VerificationMeta _rightToLeftMeta = const VerificationMeta(
    'rightToLeft',
  );
  @override
  late final GeneratedColumn<bool> rightToLeft = GeneratedColumn<bool>(
    'right_to_left',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("right_to_left" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _favoriteMeta = const VerificationMeta(
    'favorite',
  );
  @override
  late final GeneratedColumn<bool> favorite = GeneratedColumn<bool>(
    'favorite',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("favorite" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _inRecentsMeta = const VerificationMeta(
    'inRecents',
  );
  @override
  late final GeneratedColumn<bool> inRecents = GeneratedColumn<bool>(
    'in_recents',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("in_recents" IN (0, 1))',
    ),
    defaultValue: const Constant(true),
  );
  static const VerificationMeta _lastOpenedAtMeta = const VerificationMeta(
    'lastOpenedAt',
  );
  @override
  late final GeneratedColumn<DateTime> lastOpenedAt = GeneratedColumn<DateTime>(
    'last_opened_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    identity,
    uri,
    displayName,
    pageCount,
    page,
    pageX,
    pageY,
    zoom,
    rightToLeft,
    favorite,
    inRecents,
    lastOpenedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'documents';
  @override
  VerificationContext validateIntegrity(
    Insertable<DocumentRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('identity')) {
      context.handle(
        _identityMeta,
        identity.isAcceptableOrUnknown(data['identity']!, _identityMeta),
      );
    } else if (isInserting) {
      context.missing(_identityMeta);
    }
    if (data.containsKey('uri')) {
      context.handle(
        _uriMeta,
        uri.isAcceptableOrUnknown(data['uri']!, _uriMeta),
      );
    }
    if (data.containsKey('display_name')) {
      context.handle(
        _displayNameMeta,
        displayName.isAcceptableOrUnknown(
          data['display_name']!,
          _displayNameMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_displayNameMeta);
    }
    if (data.containsKey('page_count')) {
      context.handle(
        _pageCountMeta,
        pageCount.isAcceptableOrUnknown(data['page_count']!, _pageCountMeta),
      );
    }
    if (data.containsKey('page')) {
      context.handle(
        _pageMeta,
        page.isAcceptableOrUnknown(data['page']!, _pageMeta),
      );
    }
    if (data.containsKey('page_x')) {
      context.handle(
        _pageXMeta,
        pageX.isAcceptableOrUnknown(data['page_x']!, _pageXMeta),
      );
    }
    if (data.containsKey('page_y')) {
      context.handle(
        _pageYMeta,
        pageY.isAcceptableOrUnknown(data['page_y']!, _pageYMeta),
      );
    }
    if (data.containsKey('zoom')) {
      context.handle(
        _zoomMeta,
        zoom.isAcceptableOrUnknown(data['zoom']!, _zoomMeta),
      );
    }
    if (data.containsKey('right_to_left')) {
      context.handle(
        _rightToLeftMeta,
        rightToLeft.isAcceptableOrUnknown(
          data['right_to_left']!,
          _rightToLeftMeta,
        ),
      );
    }
    if (data.containsKey('favorite')) {
      context.handle(
        _favoriteMeta,
        favorite.isAcceptableOrUnknown(data['favorite']!, _favoriteMeta),
      );
    }
    if (data.containsKey('in_recents')) {
      context.handle(
        _inRecentsMeta,
        inRecents.isAcceptableOrUnknown(data['in_recents']!, _inRecentsMeta),
      );
    }
    if (data.containsKey('last_opened_at')) {
      context.handle(
        _lastOpenedAtMeta,
        lastOpenedAt.isAcceptableOrUnknown(
          data['last_opened_at']!,
          _lastOpenedAtMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_lastOpenedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  DocumentRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return DocumentRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      identity: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}identity'],
      )!,
      uri: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}uri'],
      ),
      displayName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}display_name'],
      )!,
      pageCount: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}page_count'],
      )!,
      page: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}page'],
      )!,
      pageX: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}page_x'],
      )!,
      pageY: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}page_y'],
      )!,
      zoom: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}zoom'],
      )!,
      rightToLeft: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}right_to_left'],
      )!,
      favorite: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}favorite'],
      )!,
      inRecents: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}in_recents'],
      )!,
      lastOpenedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}last_opened_at'],
      )!,
    );
  }

  @override
  $DocumentsTable createAlias(String alias) {
    return $DocumentsTable(attachedDatabase, alias);
  }
}

class DocumentRow extends DataClass implements Insertable<DocumentRow> {
  final int id;

  /// See `documentIdentity`.
  final String identity;

  /// Where to reopen the file: a `content:` URI with a persisted grant on
  /// Android, or a `file:` URI. Null when the file cannot be reopened
  /// (a shared file without a persistable grant).
  final String? uri;
  final String displayName;

  /// Zero until the document has been opened once.
  final int pageCount;

  /// Reading position: a zero-based page and a point of it, as fractions
  /// of the page size, plus the zoom (see `ReadingState`).
  final int page;
  final double pageX;
  final double pageY;
  final double zoom;

  /// Right-to-left page order is per document (FR-VIEW-019).
  final bool rightToLeft;
  final bool favorite;

  /// False once the user removes the document from recents. The row stays,
  /// so its reading state comes back if the file is opened again.
  final bool inRecents;
  final DateTime lastOpenedAt;
  const DocumentRow({
    required this.id,
    required this.identity,
    this.uri,
    required this.displayName,
    required this.pageCount,
    required this.page,
    required this.pageX,
    required this.pageY,
    required this.zoom,
    required this.rightToLeft,
    required this.favorite,
    required this.inRecents,
    required this.lastOpenedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['identity'] = Variable<String>(identity);
    if (!nullToAbsent || uri != null) {
      map['uri'] = Variable<String>(uri);
    }
    map['display_name'] = Variable<String>(displayName);
    map['page_count'] = Variable<int>(pageCount);
    map['page'] = Variable<int>(page);
    map['page_x'] = Variable<double>(pageX);
    map['page_y'] = Variable<double>(pageY);
    map['zoom'] = Variable<double>(zoom);
    map['right_to_left'] = Variable<bool>(rightToLeft);
    map['favorite'] = Variable<bool>(favorite);
    map['in_recents'] = Variable<bool>(inRecents);
    map['last_opened_at'] = Variable<DateTime>(lastOpenedAt);
    return map;
  }

  DocumentsCompanion toCompanion(bool nullToAbsent) {
    return DocumentsCompanion(
      id: Value(id),
      identity: Value(identity),
      uri: uri == null && nullToAbsent ? const Value.absent() : Value(uri),
      displayName: Value(displayName),
      pageCount: Value(pageCount),
      page: Value(page),
      pageX: Value(pageX),
      pageY: Value(pageY),
      zoom: Value(zoom),
      rightToLeft: Value(rightToLeft),
      favorite: Value(favorite),
      inRecents: Value(inRecents),
      lastOpenedAt: Value(lastOpenedAt),
    );
  }

  factory DocumentRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return DocumentRow(
      id: serializer.fromJson<int>(json['id']),
      identity: serializer.fromJson<String>(json['identity']),
      uri: serializer.fromJson<String?>(json['uri']),
      displayName: serializer.fromJson<String>(json['displayName']),
      pageCount: serializer.fromJson<int>(json['pageCount']),
      page: serializer.fromJson<int>(json['page']),
      pageX: serializer.fromJson<double>(json['pageX']),
      pageY: serializer.fromJson<double>(json['pageY']),
      zoom: serializer.fromJson<double>(json['zoom']),
      rightToLeft: serializer.fromJson<bool>(json['rightToLeft']),
      favorite: serializer.fromJson<bool>(json['favorite']),
      inRecents: serializer.fromJson<bool>(json['inRecents']),
      lastOpenedAt: serializer.fromJson<DateTime>(json['lastOpenedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'identity': serializer.toJson<String>(identity),
      'uri': serializer.toJson<String?>(uri),
      'displayName': serializer.toJson<String>(displayName),
      'pageCount': serializer.toJson<int>(pageCount),
      'page': serializer.toJson<int>(page),
      'pageX': serializer.toJson<double>(pageX),
      'pageY': serializer.toJson<double>(pageY),
      'zoom': serializer.toJson<double>(zoom),
      'rightToLeft': serializer.toJson<bool>(rightToLeft),
      'favorite': serializer.toJson<bool>(favorite),
      'inRecents': serializer.toJson<bool>(inRecents),
      'lastOpenedAt': serializer.toJson<DateTime>(lastOpenedAt),
    };
  }

  DocumentRow copyWith({
    int? id,
    String? identity,
    Value<String?> uri = const Value.absent(),
    String? displayName,
    int? pageCount,
    int? page,
    double? pageX,
    double? pageY,
    double? zoom,
    bool? rightToLeft,
    bool? favorite,
    bool? inRecents,
    DateTime? lastOpenedAt,
  }) => DocumentRow(
    id: id ?? this.id,
    identity: identity ?? this.identity,
    uri: uri.present ? uri.value : this.uri,
    displayName: displayName ?? this.displayName,
    pageCount: pageCount ?? this.pageCount,
    page: page ?? this.page,
    pageX: pageX ?? this.pageX,
    pageY: pageY ?? this.pageY,
    zoom: zoom ?? this.zoom,
    rightToLeft: rightToLeft ?? this.rightToLeft,
    favorite: favorite ?? this.favorite,
    inRecents: inRecents ?? this.inRecents,
    lastOpenedAt: lastOpenedAt ?? this.lastOpenedAt,
  );
  DocumentRow copyWithCompanion(DocumentsCompanion data) {
    return DocumentRow(
      id: data.id.present ? data.id.value : this.id,
      identity: data.identity.present ? data.identity.value : this.identity,
      uri: data.uri.present ? data.uri.value : this.uri,
      displayName: data.displayName.present
          ? data.displayName.value
          : this.displayName,
      pageCount: data.pageCount.present ? data.pageCount.value : this.pageCount,
      page: data.page.present ? data.page.value : this.page,
      pageX: data.pageX.present ? data.pageX.value : this.pageX,
      pageY: data.pageY.present ? data.pageY.value : this.pageY,
      zoom: data.zoom.present ? data.zoom.value : this.zoom,
      rightToLeft: data.rightToLeft.present
          ? data.rightToLeft.value
          : this.rightToLeft,
      favorite: data.favorite.present ? data.favorite.value : this.favorite,
      inRecents: data.inRecents.present ? data.inRecents.value : this.inRecents,
      lastOpenedAt: data.lastOpenedAt.present
          ? data.lastOpenedAt.value
          : this.lastOpenedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('DocumentRow(')
          ..write('id: $id, ')
          ..write('identity: $identity, ')
          ..write('uri: $uri, ')
          ..write('displayName: $displayName, ')
          ..write('pageCount: $pageCount, ')
          ..write('page: $page, ')
          ..write('pageX: $pageX, ')
          ..write('pageY: $pageY, ')
          ..write('zoom: $zoom, ')
          ..write('rightToLeft: $rightToLeft, ')
          ..write('favorite: $favorite, ')
          ..write('inRecents: $inRecents, ')
          ..write('lastOpenedAt: $lastOpenedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    identity,
    uri,
    displayName,
    pageCount,
    page,
    pageX,
    pageY,
    zoom,
    rightToLeft,
    favorite,
    inRecents,
    lastOpenedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is DocumentRow &&
          other.id == this.id &&
          other.identity == this.identity &&
          other.uri == this.uri &&
          other.displayName == this.displayName &&
          other.pageCount == this.pageCount &&
          other.page == this.page &&
          other.pageX == this.pageX &&
          other.pageY == this.pageY &&
          other.zoom == this.zoom &&
          other.rightToLeft == this.rightToLeft &&
          other.favorite == this.favorite &&
          other.inRecents == this.inRecents &&
          other.lastOpenedAt == this.lastOpenedAt);
}

class DocumentsCompanion extends UpdateCompanion<DocumentRow> {
  final Value<int> id;
  final Value<String> identity;
  final Value<String?> uri;
  final Value<String> displayName;
  final Value<int> pageCount;
  final Value<int> page;
  final Value<double> pageX;
  final Value<double> pageY;
  final Value<double> zoom;
  final Value<bool> rightToLeft;
  final Value<bool> favorite;
  final Value<bool> inRecents;
  final Value<DateTime> lastOpenedAt;
  const DocumentsCompanion({
    this.id = const Value.absent(),
    this.identity = const Value.absent(),
    this.uri = const Value.absent(),
    this.displayName = const Value.absent(),
    this.pageCount = const Value.absent(),
    this.page = const Value.absent(),
    this.pageX = const Value.absent(),
    this.pageY = const Value.absent(),
    this.zoom = const Value.absent(),
    this.rightToLeft = const Value.absent(),
    this.favorite = const Value.absent(),
    this.inRecents = const Value.absent(),
    this.lastOpenedAt = const Value.absent(),
  });
  DocumentsCompanion.insert({
    this.id = const Value.absent(),
    required String identity,
    this.uri = const Value.absent(),
    required String displayName,
    this.pageCount = const Value.absent(),
    this.page = const Value.absent(),
    this.pageX = const Value.absent(),
    this.pageY = const Value.absent(),
    this.zoom = const Value.absent(),
    this.rightToLeft = const Value.absent(),
    this.favorite = const Value.absent(),
    this.inRecents = const Value.absent(),
    required DateTime lastOpenedAt,
  }) : identity = Value(identity),
       displayName = Value(displayName),
       lastOpenedAt = Value(lastOpenedAt);
  static Insertable<DocumentRow> custom({
    Expression<int>? id,
    Expression<String>? identity,
    Expression<String>? uri,
    Expression<String>? displayName,
    Expression<int>? pageCount,
    Expression<int>? page,
    Expression<double>? pageX,
    Expression<double>? pageY,
    Expression<double>? zoom,
    Expression<bool>? rightToLeft,
    Expression<bool>? favorite,
    Expression<bool>? inRecents,
    Expression<DateTime>? lastOpenedAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (identity != null) 'identity': identity,
      if (uri != null) 'uri': uri,
      if (displayName != null) 'display_name': displayName,
      if (pageCount != null) 'page_count': pageCount,
      if (page != null) 'page': page,
      if (pageX != null) 'page_x': pageX,
      if (pageY != null) 'page_y': pageY,
      if (zoom != null) 'zoom': zoom,
      if (rightToLeft != null) 'right_to_left': rightToLeft,
      if (favorite != null) 'favorite': favorite,
      if (inRecents != null) 'in_recents': inRecents,
      if (lastOpenedAt != null) 'last_opened_at': lastOpenedAt,
    });
  }

  DocumentsCompanion copyWith({
    Value<int>? id,
    Value<String>? identity,
    Value<String?>? uri,
    Value<String>? displayName,
    Value<int>? pageCount,
    Value<int>? page,
    Value<double>? pageX,
    Value<double>? pageY,
    Value<double>? zoom,
    Value<bool>? rightToLeft,
    Value<bool>? favorite,
    Value<bool>? inRecents,
    Value<DateTime>? lastOpenedAt,
  }) {
    return DocumentsCompanion(
      id: id ?? this.id,
      identity: identity ?? this.identity,
      uri: uri ?? this.uri,
      displayName: displayName ?? this.displayName,
      pageCount: pageCount ?? this.pageCount,
      page: page ?? this.page,
      pageX: pageX ?? this.pageX,
      pageY: pageY ?? this.pageY,
      zoom: zoom ?? this.zoom,
      rightToLeft: rightToLeft ?? this.rightToLeft,
      favorite: favorite ?? this.favorite,
      inRecents: inRecents ?? this.inRecents,
      lastOpenedAt: lastOpenedAt ?? this.lastOpenedAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (identity.present) {
      map['identity'] = Variable<String>(identity.value);
    }
    if (uri.present) {
      map['uri'] = Variable<String>(uri.value);
    }
    if (displayName.present) {
      map['display_name'] = Variable<String>(displayName.value);
    }
    if (pageCount.present) {
      map['page_count'] = Variable<int>(pageCount.value);
    }
    if (page.present) {
      map['page'] = Variable<int>(page.value);
    }
    if (pageX.present) {
      map['page_x'] = Variable<double>(pageX.value);
    }
    if (pageY.present) {
      map['page_y'] = Variable<double>(pageY.value);
    }
    if (zoom.present) {
      map['zoom'] = Variable<double>(zoom.value);
    }
    if (rightToLeft.present) {
      map['right_to_left'] = Variable<bool>(rightToLeft.value);
    }
    if (favorite.present) {
      map['favorite'] = Variable<bool>(favorite.value);
    }
    if (inRecents.present) {
      map['in_recents'] = Variable<bool>(inRecents.value);
    }
    if (lastOpenedAt.present) {
      map['last_opened_at'] = Variable<DateTime>(lastOpenedAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('DocumentsCompanion(')
          ..write('id: $id, ')
          ..write('identity: $identity, ')
          ..write('uri: $uri, ')
          ..write('displayName: $displayName, ')
          ..write('pageCount: $pageCount, ')
          ..write('page: $page, ')
          ..write('pageX: $pageX, ')
          ..write('pageY: $pageY, ')
          ..write('zoom: $zoom, ')
          ..write('rightToLeft: $rightToLeft, ')
          ..write('favorite: $favorite, ')
          ..write('inRecents: $inRecents, ')
          ..write('lastOpenedAt: $lastOpenedAt')
          ..write(')'))
        .toString();
  }
}

class $FoldersTable extends Folders
    with TableInfo<$FoldersTable, LibraryFolderRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $FoldersTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _treeUriMeta = const VerificationMeta(
    'treeUri',
  );
  @override
  late final GeneratedColumn<String> treeUri = GeneratedColumn<String>(
    'tree_uri',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways('UNIQUE'),
  );
  static const VerificationMeta _displayNameMeta = const VerificationMeta(
    'displayName',
  );
  @override
  late final GeneratedColumn<String> displayName = GeneratedColumn<String>(
    'display_name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _addedAtMeta = const VerificationMeta(
    'addedAt',
  );
  @override
  late final GeneratedColumn<DateTime> addedAt = GeneratedColumn<DateTime>(
    'added_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [id, treeUri, displayName, addedAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'library_folders';
  @override
  VerificationContext validateIntegrity(
    Insertable<LibraryFolderRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('tree_uri')) {
      context.handle(
        _treeUriMeta,
        treeUri.isAcceptableOrUnknown(data['tree_uri']!, _treeUriMeta),
      );
    } else if (isInserting) {
      context.missing(_treeUriMeta);
    }
    if (data.containsKey('display_name')) {
      context.handle(
        _displayNameMeta,
        displayName.isAcceptableOrUnknown(
          data['display_name']!,
          _displayNameMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_displayNameMeta);
    }
    if (data.containsKey('added_at')) {
      context.handle(
        _addedAtMeta,
        addedAt.isAcceptableOrUnknown(data['added_at']!, _addedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_addedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  LibraryFolderRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return LibraryFolderRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      treeUri: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}tree_uri'],
      )!,
      displayName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}display_name'],
      )!,
      addedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}added_at'],
      )!,
    );
  }

  @override
  $FoldersTable createAlias(String alias) {
    return $FoldersTable(attachedDatabase, alias);
  }
}

class LibraryFolderRow extends DataClass
    implements Insertable<LibraryFolderRow> {
  final int id;

  /// The tree URI the folder picker returned.
  final String treeUri;
  final String displayName;
  final DateTime addedAt;
  const LibraryFolderRow({
    required this.id,
    required this.treeUri,
    required this.displayName,
    required this.addedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['tree_uri'] = Variable<String>(treeUri);
    map['display_name'] = Variable<String>(displayName);
    map['added_at'] = Variable<DateTime>(addedAt);
    return map;
  }

  FoldersCompanion toCompanion(bool nullToAbsent) {
    return FoldersCompanion(
      id: Value(id),
      treeUri: Value(treeUri),
      displayName: Value(displayName),
      addedAt: Value(addedAt),
    );
  }

  factory LibraryFolderRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return LibraryFolderRow(
      id: serializer.fromJson<int>(json['id']),
      treeUri: serializer.fromJson<String>(json['treeUri']),
      displayName: serializer.fromJson<String>(json['displayName']),
      addedAt: serializer.fromJson<DateTime>(json['addedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'treeUri': serializer.toJson<String>(treeUri),
      'displayName': serializer.toJson<String>(displayName),
      'addedAt': serializer.toJson<DateTime>(addedAt),
    };
  }

  LibraryFolderRow copyWith({
    int? id,
    String? treeUri,
    String? displayName,
    DateTime? addedAt,
  }) => LibraryFolderRow(
    id: id ?? this.id,
    treeUri: treeUri ?? this.treeUri,
    displayName: displayName ?? this.displayName,
    addedAt: addedAt ?? this.addedAt,
  );
  LibraryFolderRow copyWithCompanion(FoldersCompanion data) {
    return LibraryFolderRow(
      id: data.id.present ? data.id.value : this.id,
      treeUri: data.treeUri.present ? data.treeUri.value : this.treeUri,
      displayName: data.displayName.present
          ? data.displayName.value
          : this.displayName,
      addedAt: data.addedAt.present ? data.addedAt.value : this.addedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('LibraryFolderRow(')
          ..write('id: $id, ')
          ..write('treeUri: $treeUri, ')
          ..write('displayName: $displayName, ')
          ..write('addedAt: $addedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, treeUri, displayName, addedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is LibraryFolderRow &&
          other.id == this.id &&
          other.treeUri == this.treeUri &&
          other.displayName == this.displayName &&
          other.addedAt == this.addedAt);
}

class FoldersCompanion extends UpdateCompanion<LibraryFolderRow> {
  final Value<int> id;
  final Value<String> treeUri;
  final Value<String> displayName;
  final Value<DateTime> addedAt;
  const FoldersCompanion({
    this.id = const Value.absent(),
    this.treeUri = const Value.absent(),
    this.displayName = const Value.absent(),
    this.addedAt = const Value.absent(),
  });
  FoldersCompanion.insert({
    this.id = const Value.absent(),
    required String treeUri,
    required String displayName,
    required DateTime addedAt,
  }) : treeUri = Value(treeUri),
       displayName = Value(displayName),
       addedAt = Value(addedAt);
  static Insertable<LibraryFolderRow> custom({
    Expression<int>? id,
    Expression<String>? treeUri,
    Expression<String>? displayName,
    Expression<DateTime>? addedAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (treeUri != null) 'tree_uri': treeUri,
      if (displayName != null) 'display_name': displayName,
      if (addedAt != null) 'added_at': addedAt,
    });
  }

  FoldersCompanion copyWith({
    Value<int>? id,
    Value<String>? treeUri,
    Value<String>? displayName,
    Value<DateTime>? addedAt,
  }) {
    return FoldersCompanion(
      id: id ?? this.id,
      treeUri: treeUri ?? this.treeUri,
      displayName: displayName ?? this.displayName,
      addedAt: addedAt ?? this.addedAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (treeUri.present) {
      map['tree_uri'] = Variable<String>(treeUri.value);
    }
    if (displayName.present) {
      map['display_name'] = Variable<String>(displayName.value);
    }
    if (addedAt.present) {
      map['added_at'] = Variable<DateTime>(addedAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('FoldersCompanion(')
          ..write('id: $id, ')
          ..write('treeUri: $treeUri, ')
          ..write('displayName: $displayName, ')
          ..write('addedAt: $addedAt')
          ..write(')'))
        .toString();
  }
}

class $OpenTabsTable extends OpenTabs
    with TableInfo<$OpenTabsTable, OpenTabRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $OpenTabsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _documentIdMeta = const VerificationMeta(
    'documentId',
  );
  @override
  late final GeneratedColumn<int> documentId = GeneratedColumn<int>(
    'document_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _positionMeta = const VerificationMeta(
    'position',
  );
  @override
  late final GeneratedColumn<int> position = GeneratedColumn<int>(
    'position',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _activeMeta = const VerificationMeta('active');
  @override
  late final GeneratedColumn<bool> active = GeneratedColumn<bool>(
    'active',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("active" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  @override
  List<GeneratedColumn> get $columns => [documentId, position, active];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'open_tabs';
  @override
  VerificationContext validateIntegrity(
    Insertable<OpenTabRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('document_id')) {
      context.handle(
        _documentIdMeta,
        documentId.isAcceptableOrUnknown(data['document_id']!, _documentIdMeta),
      );
    }
    if (data.containsKey('position')) {
      context.handle(
        _positionMeta,
        position.isAcceptableOrUnknown(data['position']!, _positionMeta),
      );
    } else if (isInserting) {
      context.missing(_positionMeta);
    }
    if (data.containsKey('active')) {
      context.handle(
        _activeMeta,
        active.isAcceptableOrUnknown(data['active']!, _activeMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {documentId};
  @override
  OpenTabRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return OpenTabRow(
      documentId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}document_id'],
      )!,
      position: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}position'],
      )!,
      active: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}active'],
      )!,
    );
  }

  @override
  $OpenTabsTable createAlias(String alias) {
    return $OpenTabsTable(attachedDatabase, alias);
  }
}

class OpenTabRow extends DataClass implements Insertable<OpenTabRow> {
  /// The document's [Documents.id].
  final int documentId;

  /// Left to right, from 0.
  final int position;

  /// The tab that was shown.
  final bool active;
  const OpenTabRow({
    required this.documentId,
    required this.position,
    required this.active,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['document_id'] = Variable<int>(documentId);
    map['position'] = Variable<int>(position);
    map['active'] = Variable<bool>(active);
    return map;
  }

  OpenTabsCompanion toCompanion(bool nullToAbsent) {
    return OpenTabsCompanion(
      documentId: Value(documentId),
      position: Value(position),
      active: Value(active),
    );
  }

  factory OpenTabRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return OpenTabRow(
      documentId: serializer.fromJson<int>(json['documentId']),
      position: serializer.fromJson<int>(json['position']),
      active: serializer.fromJson<bool>(json['active']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'documentId': serializer.toJson<int>(documentId),
      'position': serializer.toJson<int>(position),
      'active': serializer.toJson<bool>(active),
    };
  }

  OpenTabRow copyWith({int? documentId, int? position, bool? active}) =>
      OpenTabRow(
        documentId: documentId ?? this.documentId,
        position: position ?? this.position,
        active: active ?? this.active,
      );
  OpenTabRow copyWithCompanion(OpenTabsCompanion data) {
    return OpenTabRow(
      documentId: data.documentId.present
          ? data.documentId.value
          : this.documentId,
      position: data.position.present ? data.position.value : this.position,
      active: data.active.present ? data.active.value : this.active,
    );
  }

  @override
  String toString() {
    return (StringBuffer('OpenTabRow(')
          ..write('documentId: $documentId, ')
          ..write('position: $position, ')
          ..write('active: $active')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(documentId, position, active);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is OpenTabRow &&
          other.documentId == this.documentId &&
          other.position == this.position &&
          other.active == this.active);
}

class OpenTabsCompanion extends UpdateCompanion<OpenTabRow> {
  final Value<int> documentId;
  final Value<int> position;
  final Value<bool> active;
  const OpenTabsCompanion({
    this.documentId = const Value.absent(),
    this.position = const Value.absent(),
    this.active = const Value.absent(),
  });
  OpenTabsCompanion.insert({
    this.documentId = const Value.absent(),
    required int position,
    this.active = const Value.absent(),
  }) : position = Value(position);
  static Insertable<OpenTabRow> custom({
    Expression<int>? documentId,
    Expression<int>? position,
    Expression<bool>? active,
  }) {
    return RawValuesInsertable({
      if (documentId != null) 'document_id': documentId,
      if (position != null) 'position': position,
      if (active != null) 'active': active,
    });
  }

  OpenTabsCompanion copyWith({
    Value<int>? documentId,
    Value<int>? position,
    Value<bool>? active,
  }) {
    return OpenTabsCompanion(
      documentId: documentId ?? this.documentId,
      position: position ?? this.position,
      active: active ?? this.active,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (documentId.present) {
      map['document_id'] = Variable<int>(documentId.value);
    }
    if (position.present) {
      map['position'] = Variable<int>(position.value);
    }
    if (active.present) {
      map['active'] = Variable<bool>(active.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('OpenTabsCompanion(')
          ..write('documentId: $documentId, ')
          ..write('position: $position, ')
          ..write('active: $active')
          ..write(')'))
        .toString();
  }
}

class $JournalSessionsTable extends JournalSessions
    with TableInfo<$JournalSessionsTable, JournalSessionRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $JournalSessionsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _documentIdMeta = const VerificationMeta(
    'documentId',
  );
  @override
  late final GeneratedColumn<int> documentId = GeneratedColumn<int>(
    'document_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _locationMeta = const VerificationMeta(
    'location',
  );
  @override
  late final GeneratedColumn<String> location = GeneratedColumn<String>(
    'location',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _baseIdentityMeta = const VerificationMeta(
    'baseIdentity',
  );
  @override
  late final GeneratedColumn<String> baseIdentity = GeneratedColumn<String>(
    'base_identity',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _displayNameMeta = const VerificationMeta(
    'displayName',
  );
  @override
  late final GeneratedColumn<String> displayName = GeneratedColumn<String>(
    'display_name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _startedAtMeta = const VerificationMeta(
    'startedAt',
  );
  @override
  late final GeneratedColumn<DateTime> startedAt = GeneratedColumn<DateTime>(
    'started_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _formatMeta = const VerificationMeta('format');
  @override
  late final GeneratedColumn<int> format = GeneratedColumn<int>(
    'format',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(1),
  );
  @override
  List<GeneratedColumn> get $columns => [
    documentId,
    location,
    baseIdentity,
    displayName,
    startedAt,
    format,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'journal_sessions';
  @override
  VerificationContext validateIntegrity(
    Insertable<JournalSessionRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('document_id')) {
      context.handle(
        _documentIdMeta,
        documentId.isAcceptableOrUnknown(data['document_id']!, _documentIdMeta),
      );
    }
    if (data.containsKey('location')) {
      context.handle(
        _locationMeta,
        location.isAcceptableOrUnknown(data['location']!, _locationMeta),
      );
    } else if (isInserting) {
      context.missing(_locationMeta);
    }
    if (data.containsKey('base_identity')) {
      context.handle(
        _baseIdentityMeta,
        baseIdentity.isAcceptableOrUnknown(
          data['base_identity']!,
          _baseIdentityMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_baseIdentityMeta);
    }
    if (data.containsKey('display_name')) {
      context.handle(
        _displayNameMeta,
        displayName.isAcceptableOrUnknown(
          data['display_name']!,
          _displayNameMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_displayNameMeta);
    }
    if (data.containsKey('started_at')) {
      context.handle(
        _startedAtMeta,
        startedAt.isAcceptableOrUnknown(data['started_at']!, _startedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_startedAtMeta);
    }
    if (data.containsKey('format')) {
      context.handle(
        _formatMeta,
        format.isAcceptableOrUnknown(data['format']!, _formatMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {documentId};
  @override
  JournalSessionRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return JournalSessionRow(
      documentId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}document_id'],
      )!,
      location: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}location'],
      )!,
      baseIdentity: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}base_identity'],
      )!,
      displayName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}display_name'],
      )!,
      startedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}started_at'],
      )!,
      format: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}format'],
      )!,
    );
  }

  @override
  $JournalSessionsTable createAlias(String alias) {
    return $JournalSessionsTable(attachedDatabase, alias);
  }
}

class JournalSessionRow extends DataClass
    implements Insertable<JournalSessionRow> {
  final int documentId;
  final String location;
  final String baseIdentity;
  final String displayName;
  final DateTime startedAt;
  final int format;
  const JournalSessionRow({
    required this.documentId,
    required this.location,
    required this.baseIdentity,
    required this.displayName,
    required this.startedAt,
    required this.format,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['document_id'] = Variable<int>(documentId);
    map['location'] = Variable<String>(location);
    map['base_identity'] = Variable<String>(baseIdentity);
    map['display_name'] = Variable<String>(displayName);
    map['started_at'] = Variable<DateTime>(startedAt);
    map['format'] = Variable<int>(format);
    return map;
  }

  JournalSessionsCompanion toCompanion(bool nullToAbsent) {
    return JournalSessionsCompanion(
      documentId: Value(documentId),
      location: Value(location),
      baseIdentity: Value(baseIdentity),
      displayName: Value(displayName),
      startedAt: Value(startedAt),
      format: Value(format),
    );
  }

  factory JournalSessionRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return JournalSessionRow(
      documentId: serializer.fromJson<int>(json['documentId']),
      location: serializer.fromJson<String>(json['location']),
      baseIdentity: serializer.fromJson<String>(json['baseIdentity']),
      displayName: serializer.fromJson<String>(json['displayName']),
      startedAt: serializer.fromJson<DateTime>(json['startedAt']),
      format: serializer.fromJson<int>(json['format']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'documentId': serializer.toJson<int>(documentId),
      'location': serializer.toJson<String>(location),
      'baseIdentity': serializer.toJson<String>(baseIdentity),
      'displayName': serializer.toJson<String>(displayName),
      'startedAt': serializer.toJson<DateTime>(startedAt),
      'format': serializer.toJson<int>(format),
    };
  }

  JournalSessionRow copyWith({
    int? documentId,
    String? location,
    String? baseIdentity,
    String? displayName,
    DateTime? startedAt,
    int? format,
  }) => JournalSessionRow(
    documentId: documentId ?? this.documentId,
    location: location ?? this.location,
    baseIdentity: baseIdentity ?? this.baseIdentity,
    displayName: displayName ?? this.displayName,
    startedAt: startedAt ?? this.startedAt,
    format: format ?? this.format,
  );
  JournalSessionRow copyWithCompanion(JournalSessionsCompanion data) {
    return JournalSessionRow(
      documentId: data.documentId.present
          ? data.documentId.value
          : this.documentId,
      location: data.location.present ? data.location.value : this.location,
      baseIdentity: data.baseIdentity.present
          ? data.baseIdentity.value
          : this.baseIdentity,
      displayName: data.displayName.present
          ? data.displayName.value
          : this.displayName,
      startedAt: data.startedAt.present ? data.startedAt.value : this.startedAt,
      format: data.format.present ? data.format.value : this.format,
    );
  }

  @override
  String toString() {
    return (StringBuffer('JournalSessionRow(')
          ..write('documentId: $documentId, ')
          ..write('location: $location, ')
          ..write('baseIdentity: $baseIdentity, ')
          ..write('displayName: $displayName, ')
          ..write('startedAt: $startedAt, ')
          ..write('format: $format')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    documentId,
    location,
    baseIdentity,
    displayName,
    startedAt,
    format,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is JournalSessionRow &&
          other.documentId == this.documentId &&
          other.location == this.location &&
          other.baseIdentity == this.baseIdentity &&
          other.displayName == this.displayName &&
          other.startedAt == this.startedAt &&
          other.format == this.format);
}

class JournalSessionsCompanion extends UpdateCompanion<JournalSessionRow> {
  final Value<int> documentId;
  final Value<String> location;
  final Value<String> baseIdentity;
  final Value<String> displayName;
  final Value<DateTime> startedAt;
  final Value<int> format;
  const JournalSessionsCompanion({
    this.documentId = const Value.absent(),
    this.location = const Value.absent(),
    this.baseIdentity = const Value.absent(),
    this.displayName = const Value.absent(),
    this.startedAt = const Value.absent(),
    this.format = const Value.absent(),
  });
  JournalSessionsCompanion.insert({
    this.documentId = const Value.absent(),
    required String location,
    required String baseIdentity,
    required String displayName,
    required DateTime startedAt,
    this.format = const Value.absent(),
  }) : location = Value(location),
       baseIdentity = Value(baseIdentity),
       displayName = Value(displayName),
       startedAt = Value(startedAt);
  static Insertable<JournalSessionRow> custom({
    Expression<int>? documentId,
    Expression<String>? location,
    Expression<String>? baseIdentity,
    Expression<String>? displayName,
    Expression<DateTime>? startedAt,
    Expression<int>? format,
  }) {
    return RawValuesInsertable({
      if (documentId != null) 'document_id': documentId,
      if (location != null) 'location': location,
      if (baseIdentity != null) 'base_identity': baseIdentity,
      if (displayName != null) 'display_name': displayName,
      if (startedAt != null) 'started_at': startedAt,
      if (format != null) 'format': format,
    });
  }

  JournalSessionsCompanion copyWith({
    Value<int>? documentId,
    Value<String>? location,
    Value<String>? baseIdentity,
    Value<String>? displayName,
    Value<DateTime>? startedAt,
    Value<int>? format,
  }) {
    return JournalSessionsCompanion(
      documentId: documentId ?? this.documentId,
      location: location ?? this.location,
      baseIdentity: baseIdentity ?? this.baseIdentity,
      displayName: displayName ?? this.displayName,
      startedAt: startedAt ?? this.startedAt,
      format: format ?? this.format,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (documentId.present) {
      map['document_id'] = Variable<int>(documentId.value);
    }
    if (location.present) {
      map['location'] = Variable<String>(location.value);
    }
    if (baseIdentity.present) {
      map['base_identity'] = Variable<String>(baseIdentity.value);
    }
    if (displayName.present) {
      map['display_name'] = Variable<String>(displayName.value);
    }
    if (startedAt.present) {
      map['started_at'] = Variable<DateTime>(startedAt.value);
    }
    if (format.present) {
      map['format'] = Variable<int>(format.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('JournalSessionsCompanion(')
          ..write('documentId: $documentId, ')
          ..write('location: $location, ')
          ..write('baseIdentity: $baseIdentity, ')
          ..write('displayName: $displayName, ')
          ..write('startedAt: $startedAt, ')
          ..write('format: $format')
          ..write(')'))
        .toString();
  }
}

class $JournalEntriesTable extends JournalEntries
    with TableInfo<$JournalEntriesTable, JournalEntry> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $JournalEntriesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _sessionIdMeta = const VerificationMeta(
    'sessionId',
  );
  @override
  late final GeneratedColumn<int> sessionId = GeneratedColumn<int>(
    'session_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES journal_sessions (document_id) ON DELETE CASCADE',
    ),
  );
  static const VerificationMeta _sequenceMeta = const VerificationMeta(
    'sequence',
  );
  @override
  late final GeneratedColumn<int> sequence = GeneratedColumn<int>(
    'sequence',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _commandMeta = const VerificationMeta(
    'command',
  );
  @override
  late final GeneratedColumn<String> command = GeneratedColumn<String>(
    'command',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [sessionId, sequence, command];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'journal_entries';
  @override
  VerificationContext validateIntegrity(
    Insertable<JournalEntry> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('session_id')) {
      context.handle(
        _sessionIdMeta,
        sessionId.isAcceptableOrUnknown(data['session_id']!, _sessionIdMeta),
      );
    } else if (isInserting) {
      context.missing(_sessionIdMeta);
    }
    if (data.containsKey('sequence')) {
      context.handle(
        _sequenceMeta,
        sequence.isAcceptableOrUnknown(data['sequence']!, _sequenceMeta),
      );
    } else if (isInserting) {
      context.missing(_sequenceMeta);
    }
    if (data.containsKey('command')) {
      context.handle(
        _commandMeta,
        command.isAcceptableOrUnknown(data['command']!, _commandMeta),
      );
    } else if (isInserting) {
      context.missing(_commandMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {sessionId, sequence};
  @override
  JournalEntry map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return JournalEntry(
      sessionId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}session_id'],
      )!,
      sequence: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}sequence'],
      )!,
      command: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}command'],
      )!,
    );
  }

  @override
  $JournalEntriesTable createAlias(String alias) {
    return $JournalEntriesTable(attachedDatabase, alias);
  }
}

class JournalEntry extends DataClass implements Insertable<JournalEntry> {
  final int sessionId;
  final int sequence;
  final String command;
  const JournalEntry({
    required this.sessionId,
    required this.sequence,
    required this.command,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['session_id'] = Variable<int>(sessionId);
    map['sequence'] = Variable<int>(sequence);
    map['command'] = Variable<String>(command);
    return map;
  }

  JournalEntriesCompanion toCompanion(bool nullToAbsent) {
    return JournalEntriesCompanion(
      sessionId: Value(sessionId),
      sequence: Value(sequence),
      command: Value(command),
    );
  }

  factory JournalEntry.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return JournalEntry(
      sessionId: serializer.fromJson<int>(json['sessionId']),
      sequence: serializer.fromJson<int>(json['sequence']),
      command: serializer.fromJson<String>(json['command']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'sessionId': serializer.toJson<int>(sessionId),
      'sequence': serializer.toJson<int>(sequence),
      'command': serializer.toJson<String>(command),
    };
  }

  JournalEntry copyWith({int? sessionId, int? sequence, String? command}) =>
      JournalEntry(
        sessionId: sessionId ?? this.sessionId,
        sequence: sequence ?? this.sequence,
        command: command ?? this.command,
      );
  JournalEntry copyWithCompanion(JournalEntriesCompanion data) {
    return JournalEntry(
      sessionId: data.sessionId.present ? data.sessionId.value : this.sessionId,
      sequence: data.sequence.present ? data.sequence.value : this.sequence,
      command: data.command.present ? data.command.value : this.command,
    );
  }

  @override
  String toString() {
    return (StringBuffer('JournalEntry(')
          ..write('sessionId: $sessionId, ')
          ..write('sequence: $sequence, ')
          ..write('command: $command')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(sessionId, sequence, command);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is JournalEntry &&
          other.sessionId == this.sessionId &&
          other.sequence == this.sequence &&
          other.command == this.command);
}

class JournalEntriesCompanion extends UpdateCompanion<JournalEntry> {
  final Value<int> sessionId;
  final Value<int> sequence;
  final Value<String> command;
  final Value<int> rowid;
  const JournalEntriesCompanion({
    this.sessionId = const Value.absent(),
    this.sequence = const Value.absent(),
    this.command = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  JournalEntriesCompanion.insert({
    required int sessionId,
    required int sequence,
    required String command,
    this.rowid = const Value.absent(),
  }) : sessionId = Value(sessionId),
       sequence = Value(sequence),
       command = Value(command);
  static Insertable<JournalEntry> custom({
    Expression<int>? sessionId,
    Expression<int>? sequence,
    Expression<String>? command,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (sessionId != null) 'session_id': sessionId,
      if (sequence != null) 'sequence': sequence,
      if (command != null) 'command': command,
      if (rowid != null) 'rowid': rowid,
    });
  }

  JournalEntriesCompanion copyWith({
    Value<int>? sessionId,
    Value<int>? sequence,
    Value<String>? command,
    Value<int>? rowid,
  }) {
    return JournalEntriesCompanion(
      sessionId: sessionId ?? this.sessionId,
      sequence: sequence ?? this.sequence,
      command: command ?? this.command,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (sessionId.present) {
      map['session_id'] = Variable<int>(sessionId.value);
    }
    if (sequence.present) {
      map['sequence'] = Variable<int>(sequence.value);
    }
    if (command.present) {
      map['command'] = Variable<String>(command.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('JournalEntriesCompanion(')
          ..write('sessionId: $sessionId, ')
          ..write('sequence: $sequence, ')
          ..write('command: $command, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$LibraryDatabase extends GeneratedDatabase {
  _$LibraryDatabase(QueryExecutor e) : super(e);
  $LibraryDatabaseManager get managers => $LibraryDatabaseManager(this);
  late final $DocumentsTable documents = $DocumentsTable(this);
  late final $FoldersTable folders = $FoldersTable(this);
  late final $OpenTabsTable openTabs = $OpenTabsTable(this);
  late final $JournalSessionsTable journalSessions = $JournalSessionsTable(
    this,
  );
  late final $JournalEntriesTable journalEntries = $JournalEntriesTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    documents,
    folders,
    openTabs,
    journalSessions,
    journalEntries,
  ];
  @override
  StreamQueryUpdateRules get streamUpdateRules => const StreamQueryUpdateRules([
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'journal_sessions',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('journal_entries', kind: UpdateKind.delete)],
    ),
  ]);
}

typedef $$DocumentsTableCreateCompanionBuilder = DocumentsCompanion Function({
  Value<int> id,
  required String identity,
  Value<String?> uri,
  required String displayName,
  Value<int> pageCount,
  Value<int> page,
  Value<double> pageX,
  Value<double> pageY,
  Value<double> zoom,
  Value<bool> rightToLeft,
  Value<bool> favorite,
  Value<bool> inRecents,
  required DateTime lastOpenedAt,
});
typedef $$DocumentsTableUpdateCompanionBuilder = DocumentsCompanion Function({
  Value<int> id,
  Value<String> identity,
  Value<String?> uri,
  Value<String> displayName,
  Value<int> pageCount,
  Value<int> page,
  Value<double> pageX,
  Value<double> pageY,
  Value<double> zoom,
  Value<bool> rightToLeft,
  Value<bool> favorite,
  Value<bool> inRecents,
  Value<DateTime> lastOpenedAt,
});

class $$DocumentsTableFilterComposer
    extends Composer<_$LibraryDatabase, $DocumentsTable> {
  $$DocumentsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get identity => $composableBuilder(
    column: $table.identity,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get uri => $composableBuilder(
    column: $table.uri,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get displayName => $composableBuilder(
    column: $table.displayName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get pageCount => $composableBuilder(
    column: $table.pageCount,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get page => $composableBuilder(
    column: $table.page,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get pageX => $composableBuilder(
    column: $table.pageX,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get pageY => $composableBuilder(
    column: $table.pageY,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get zoom => $composableBuilder(
    column: $table.zoom,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get rightToLeft => $composableBuilder(
    column: $table.rightToLeft,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get favorite => $composableBuilder(
    column: $table.favorite,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get inRecents => $composableBuilder(
    column: $table.inRecents,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get lastOpenedAt => $composableBuilder(
    column: $table.lastOpenedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$DocumentsTableOrderingComposer
    extends Composer<_$LibraryDatabase, $DocumentsTable> {
  $$DocumentsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get identity => $composableBuilder(
    column: $table.identity,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get uri => $composableBuilder(
    column: $table.uri,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get displayName => $composableBuilder(
    column: $table.displayName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get pageCount => $composableBuilder(
    column: $table.pageCount,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get page => $composableBuilder(
    column: $table.page,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get pageX => $composableBuilder(
    column: $table.pageX,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get pageY => $composableBuilder(
    column: $table.pageY,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get zoom => $composableBuilder(
    column: $table.zoom,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get rightToLeft => $composableBuilder(
    column: $table.rightToLeft,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get favorite => $composableBuilder(
    column: $table.favorite,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get inRecents => $composableBuilder(
    column: $table.inRecents,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get lastOpenedAt => $composableBuilder(
    column: $table.lastOpenedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$DocumentsTableAnnotationComposer
    extends Composer<_$LibraryDatabase, $DocumentsTable> {
  $$DocumentsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get identity =>
      $composableBuilder(column: $table.identity, builder: (column) => column);

  GeneratedColumn<String> get uri =>
      $composableBuilder(column: $table.uri, builder: (column) => column);

  GeneratedColumn<String> get displayName => $composableBuilder(
    column: $table.displayName,
    builder: (column) => column,
  );

  GeneratedColumn<int> get pageCount =>
      $composableBuilder(column: $table.pageCount, builder: (column) => column);

  GeneratedColumn<int> get page =>
      $composableBuilder(column: $table.page, builder: (column) => column);

  GeneratedColumn<double> get pageX =>
      $composableBuilder(column: $table.pageX, builder: (column) => column);

  GeneratedColumn<double> get pageY =>
      $composableBuilder(column: $table.pageY, builder: (column) => column);

  GeneratedColumn<double> get zoom =>
      $composableBuilder(column: $table.zoom, builder: (column) => column);

  GeneratedColumn<bool> get rightToLeft => $composableBuilder(
    column: $table.rightToLeft,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get favorite =>
      $composableBuilder(column: $table.favorite, builder: (column) => column);

  GeneratedColumn<bool> get inRecents =>
      $composableBuilder(column: $table.inRecents, builder: (column) => column);

  GeneratedColumn<DateTime> get lastOpenedAt => $composableBuilder(
    column: $table.lastOpenedAt,
    builder: (column) => column,
  );
}

class $$DocumentsTableTableManager
    extends
        RootTableManager<
          _$LibraryDatabase,
          $DocumentsTable,
          DocumentRow,
          $$DocumentsTableFilterComposer,
          $$DocumentsTableOrderingComposer,
          $$DocumentsTableAnnotationComposer,
          $$DocumentsTableCreateCompanionBuilder,
          $$DocumentsTableUpdateCompanionBuilder,
          (
            DocumentRow,
            BaseReferences<_$LibraryDatabase, $DocumentsTable, DocumentRow>,
          ),
          DocumentRow,
          PrefetchHooks Function()
        > {
  $$DocumentsTableTableManager(_$LibraryDatabase db, $DocumentsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$DocumentsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$DocumentsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$DocumentsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> identity = const Value.absent(),
                Value<String?> uri = const Value.absent(),
                Value<String> displayName = const Value.absent(),
                Value<int> pageCount = const Value.absent(),
                Value<int> page = const Value.absent(),
                Value<double> pageX = const Value.absent(),
                Value<double> pageY = const Value.absent(),
                Value<double> zoom = const Value.absent(),
                Value<bool> rightToLeft = const Value.absent(),
                Value<bool> favorite = const Value.absent(),
                Value<bool> inRecents = const Value.absent(),
                Value<DateTime> lastOpenedAt = const Value.absent(),
              }) => DocumentsCompanion(
                id: id,
                identity: identity,
                uri: uri,
                displayName: displayName,
                pageCount: pageCount,
                page: page,
                pageX: pageX,
                pageY: pageY,
                zoom: zoom,
                rightToLeft: rightToLeft,
                favorite: favorite,
                inRecents: inRecents,
                lastOpenedAt: lastOpenedAt,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String identity,
                Value<String?> uri = const Value.absent(),
                required String displayName,
                Value<int> pageCount = const Value.absent(),
                Value<int> page = const Value.absent(),
                Value<double> pageX = const Value.absent(),
                Value<double> pageY = const Value.absent(),
                Value<double> zoom = const Value.absent(),
                Value<bool> rightToLeft = const Value.absent(),
                Value<bool> favorite = const Value.absent(),
                Value<bool> inRecents = const Value.absent(),
                required DateTime lastOpenedAt,
              }) => DocumentsCompanion.insert(
                id: id,
                identity: identity,
                uri: uri,
                displayName: displayName,
                pageCount: pageCount,
                page: page,
                pageX: pageX,
                pageY: pageY,
                zoom: zoom,
                rightToLeft: rightToLeft,
                favorite: favorite,
                inRecents: inRecents,
                lastOpenedAt: lastOpenedAt,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$DocumentsTable, DocumentRow>(table),
                  BaseReferences<
                    _$LibraryDatabase,
                    $DocumentsTable,
                    DocumentRow
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$DocumentsTableProcessedTableManager =
    ProcessedTableManager<
      _$LibraryDatabase,
      $DocumentsTable,
      DocumentRow,
      $$DocumentsTableFilterComposer,
      $$DocumentsTableOrderingComposer,
      $$DocumentsTableAnnotationComposer,
      $$DocumentsTableCreateCompanionBuilder,
      $$DocumentsTableUpdateCompanionBuilder,
      (
        DocumentRow,
        BaseReferences<_$LibraryDatabase, $DocumentsTable, DocumentRow>,
      ),
      DocumentRow,
      PrefetchHooks Function()
    >;
typedef $$FoldersTableCreateCompanionBuilder = FoldersCompanion Function({
  Value<int> id,
  required String treeUri,
  required String displayName,
  required DateTime addedAt,
});
typedef $$FoldersTableUpdateCompanionBuilder = FoldersCompanion Function({
  Value<int> id,
  Value<String> treeUri,
  Value<String> displayName,
  Value<DateTime> addedAt,
});

class $$FoldersTableFilterComposer
    extends Composer<_$LibraryDatabase, $FoldersTable> {
  $$FoldersTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get treeUri => $composableBuilder(
    column: $table.treeUri,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get displayName => $composableBuilder(
    column: $table.displayName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get addedAt => $composableBuilder(
    column: $table.addedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$FoldersTableOrderingComposer
    extends Composer<_$LibraryDatabase, $FoldersTable> {
  $$FoldersTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get treeUri => $composableBuilder(
    column: $table.treeUri,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get displayName => $composableBuilder(
    column: $table.displayName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get addedAt => $composableBuilder(
    column: $table.addedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$FoldersTableAnnotationComposer
    extends Composer<_$LibraryDatabase, $FoldersTable> {
  $$FoldersTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get treeUri =>
      $composableBuilder(column: $table.treeUri, builder: (column) => column);

  GeneratedColumn<String> get displayName => $composableBuilder(
    column: $table.displayName,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get addedAt =>
      $composableBuilder(column: $table.addedAt, builder: (column) => column);
}

class $$FoldersTableTableManager
    extends
        RootTableManager<
          _$LibraryDatabase,
          $FoldersTable,
          LibraryFolderRow,
          $$FoldersTableFilterComposer,
          $$FoldersTableOrderingComposer,
          $$FoldersTableAnnotationComposer,
          $$FoldersTableCreateCompanionBuilder,
          $$FoldersTableUpdateCompanionBuilder,
          (
            LibraryFolderRow,
            BaseReferences<_$LibraryDatabase, $FoldersTable, LibraryFolderRow>,
          ),
          LibraryFolderRow,
          PrefetchHooks Function()
        > {
  $$FoldersTableTableManager(_$LibraryDatabase db, $FoldersTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$FoldersTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$FoldersTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$FoldersTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> treeUri = const Value.absent(),
                Value<String> displayName = const Value.absent(),
                Value<DateTime> addedAt = const Value.absent(),
              }) => FoldersCompanion(
                id: id,
                treeUri: treeUri,
                displayName: displayName,
                addedAt: addedAt,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String treeUri,
                required String displayName,
                required DateTime addedAt,
              }) => FoldersCompanion.insert(
                id: id,
                treeUri: treeUri,
                displayName: displayName,
                addedAt: addedAt,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$FoldersTable, LibraryFolderRow>(table),
                  BaseReferences<
                    _$LibraryDatabase,
                    $FoldersTable,
                    LibraryFolderRow
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$FoldersTableProcessedTableManager =
    ProcessedTableManager<
      _$LibraryDatabase,
      $FoldersTable,
      LibraryFolderRow,
      $$FoldersTableFilterComposer,
      $$FoldersTableOrderingComposer,
      $$FoldersTableAnnotationComposer,
      $$FoldersTableCreateCompanionBuilder,
      $$FoldersTableUpdateCompanionBuilder,
      (
        LibraryFolderRow,
        BaseReferences<_$LibraryDatabase, $FoldersTable, LibraryFolderRow>,
      ),
      LibraryFolderRow,
      PrefetchHooks Function()
    >;
typedef $$OpenTabsTableCreateCompanionBuilder = OpenTabsCompanion Function({
  Value<int> documentId,
  required int position,
  Value<bool> active,
});
typedef $$OpenTabsTableUpdateCompanionBuilder = OpenTabsCompanion Function({
  Value<int> documentId,
  Value<int> position,
  Value<bool> active,
});

class $$OpenTabsTableFilterComposer
    extends Composer<_$LibraryDatabase, $OpenTabsTable> {
  $$OpenTabsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get documentId => $composableBuilder(
    column: $table.documentId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get position => $composableBuilder(
    column: $table.position,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get active => $composableBuilder(
    column: $table.active,
    builder: (column) => ColumnFilters(column),
  );
}

class $$OpenTabsTableOrderingComposer
    extends Composer<_$LibraryDatabase, $OpenTabsTable> {
  $$OpenTabsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get documentId => $composableBuilder(
    column: $table.documentId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get position => $composableBuilder(
    column: $table.position,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get active => $composableBuilder(
    column: $table.active,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$OpenTabsTableAnnotationComposer
    extends Composer<_$LibraryDatabase, $OpenTabsTable> {
  $$OpenTabsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get documentId => $composableBuilder(
    column: $table.documentId,
    builder: (column) => column,
  );

  GeneratedColumn<int> get position =>
      $composableBuilder(column: $table.position, builder: (column) => column);

  GeneratedColumn<bool> get active =>
      $composableBuilder(column: $table.active, builder: (column) => column);
}

class $$OpenTabsTableTableManager
    extends
        RootTableManager<
          _$LibraryDatabase,
          $OpenTabsTable,
          OpenTabRow,
          $$OpenTabsTableFilterComposer,
          $$OpenTabsTableOrderingComposer,
          $$OpenTabsTableAnnotationComposer,
          $$OpenTabsTableCreateCompanionBuilder,
          $$OpenTabsTableUpdateCompanionBuilder,
          (
            OpenTabRow,
            BaseReferences<_$LibraryDatabase, $OpenTabsTable, OpenTabRow>,
          ),
          OpenTabRow,
          PrefetchHooks Function()
        > {
  $$OpenTabsTableTableManager(_$LibraryDatabase db, $OpenTabsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$OpenTabsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$OpenTabsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$OpenTabsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> documentId = const Value.absent(),
                Value<int> position = const Value.absent(),
                Value<bool> active = const Value.absent(),
              }) => OpenTabsCompanion(
                documentId: documentId,
                position: position,
                active: active,
              ),
          createCompanionCallback:
              ({
                Value<int> documentId = const Value.absent(),
                required int position,
                Value<bool> active = const Value.absent(),
              }) => OpenTabsCompanion.insert(
                documentId: documentId,
                position: position,
                active: active,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$OpenTabsTable, OpenTabRow>(table),
                  BaseReferences<_$LibraryDatabase, $OpenTabsTable, OpenTabRow>(
                    db,
                    table,
                    e,
                  ),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$OpenTabsTableProcessedTableManager =
    ProcessedTableManager<
      _$LibraryDatabase,
      $OpenTabsTable,
      OpenTabRow,
      $$OpenTabsTableFilterComposer,
      $$OpenTabsTableOrderingComposer,
      $$OpenTabsTableAnnotationComposer,
      $$OpenTabsTableCreateCompanionBuilder,
      $$OpenTabsTableUpdateCompanionBuilder,
      (
        OpenTabRow,
        BaseReferences<_$LibraryDatabase, $OpenTabsTable, OpenTabRow>,
      ),
      OpenTabRow,
      PrefetchHooks Function()
    >;
typedef $$JournalSessionsTableCreateCompanionBuilder =
    JournalSessionsCompanion Function({
      Value<int> documentId,
      required String location,
      required String baseIdentity,
      required String displayName,
      required DateTime startedAt,
      Value<int> format,
    });
typedef $$JournalSessionsTableUpdateCompanionBuilder =
    JournalSessionsCompanion Function({
      Value<int> documentId,
      Value<String> location,
      Value<String> baseIdentity,
      Value<String> displayName,
      Value<DateTime> startedAt,
      Value<int> format,
    });

final class $$JournalSessionsTableReferences
    extends
        BaseReferences<
          _$LibraryDatabase,
          $JournalSessionsTable,
          JournalSessionRow
        > {
  $$JournalSessionsTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static MultiTypedResultKey<$JournalEntriesTable, List<JournalEntry>>
  _journalEntriesRefsTable(_$LibraryDatabase db) =>
      MultiTypedResultKey.fromTable(
        db.journalEntries,
        aliasName: 'journal_sessions__document_id__journal_entries__session_id',
      );

  $$JournalEntriesTableProcessedTableManager get journalEntriesRefs {
    final manager = $$JournalEntriesTableTableManager($_db, $_db.journalEntries)
        .filter(
          (f) => f.sessionId.documentId.sqlEquals(
            $_itemColumn<int>('document_id')!,
          ),
        );

    final cache = $_typedResult.readTableOrNull(_journalEntriesRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$JournalSessionsTableFilterComposer
    extends Composer<_$LibraryDatabase, $JournalSessionsTable> {
  $$JournalSessionsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get documentId => $composableBuilder(
    column: $table.documentId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get location => $composableBuilder(
    column: $table.location,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get baseIdentity => $composableBuilder(
    column: $table.baseIdentity,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get displayName => $composableBuilder(
    column: $table.displayName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get startedAt => $composableBuilder(
    column: $table.startedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get format => $composableBuilder(
    column: $table.format,
    builder: (column) => ColumnFilters(column),
  );

  Expression<bool> journalEntriesRefs(
    Expression<bool> Function($$JournalEntriesTableFilterComposer f) f,
  ) {
    final $$JournalEntriesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.documentId,
      referencedTable: $db.journalEntries,
      getReferencedColumn: (t) => t.sessionId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$JournalEntriesTableFilterComposer(
            $db: $db,
            $table: $db.journalEntries,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$JournalSessionsTableOrderingComposer
    extends Composer<_$LibraryDatabase, $JournalSessionsTable> {
  $$JournalSessionsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get documentId => $composableBuilder(
    column: $table.documentId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get location => $composableBuilder(
    column: $table.location,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get baseIdentity => $composableBuilder(
    column: $table.baseIdentity,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get displayName => $composableBuilder(
    column: $table.displayName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get startedAt => $composableBuilder(
    column: $table.startedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get format => $composableBuilder(
    column: $table.format,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$JournalSessionsTableAnnotationComposer
    extends Composer<_$LibraryDatabase, $JournalSessionsTable> {
  $$JournalSessionsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get documentId => $composableBuilder(
    column: $table.documentId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get location =>
      $composableBuilder(column: $table.location, builder: (column) => column);

  GeneratedColumn<String> get baseIdentity => $composableBuilder(
    column: $table.baseIdentity,
    builder: (column) => column,
  );

  GeneratedColumn<String> get displayName => $composableBuilder(
    column: $table.displayName,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get startedAt =>
      $composableBuilder(column: $table.startedAt, builder: (column) => column);

  GeneratedColumn<int> get format =>
      $composableBuilder(column: $table.format, builder: (column) => column);

  Expression<T> journalEntriesRefs<T extends Object>(
    Expression<T> Function($$JournalEntriesTableAnnotationComposer a) f,
  ) {
    final $$JournalEntriesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.documentId,
      referencedTable: $db.journalEntries,
      getReferencedColumn: (t) => t.sessionId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$JournalEntriesTableAnnotationComposer(
            $db: $db,
            $table: $db.journalEntries,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$JournalSessionsTableTableManager
    extends
        RootTableManager<
          _$LibraryDatabase,
          $JournalSessionsTable,
          JournalSessionRow,
          $$JournalSessionsTableFilterComposer,
          $$JournalSessionsTableOrderingComposer,
          $$JournalSessionsTableAnnotationComposer,
          $$JournalSessionsTableCreateCompanionBuilder,
          $$JournalSessionsTableUpdateCompanionBuilder,
          (JournalSessionRow, $$JournalSessionsTableReferences),
          JournalSessionRow,
          PrefetchHooks Function({bool journalEntriesRefs})
        > {
  $$JournalSessionsTableTableManager(
    _$LibraryDatabase db,
    $JournalSessionsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$JournalSessionsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$JournalSessionsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$JournalSessionsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> documentId = const Value.absent(),
                Value<String> location = const Value.absent(),
                Value<String> baseIdentity = const Value.absent(),
                Value<String> displayName = const Value.absent(),
                Value<DateTime> startedAt = const Value.absent(),
                Value<int> format = const Value.absent(),
              }) => JournalSessionsCompanion(
                documentId: documentId,
                location: location,
                baseIdentity: baseIdentity,
                displayName: displayName,
                startedAt: startedAt,
                format: format,
              ),
          createCompanionCallback:
              ({
                Value<int> documentId = const Value.absent(),
                required String location,
                required String baseIdentity,
                required String displayName,
                required DateTime startedAt,
                Value<int> format = const Value.absent(),
              }) => JournalSessionsCompanion.insert(
                documentId: documentId,
                location: location,
                baseIdentity: baseIdentity,
                displayName: displayName,
                startedAt: startedAt,
                format: format,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$JournalSessionsTable, JournalSessionRow>(table),
                  $$JournalSessionsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({journalEntriesRefs = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [
                if (journalEntriesRefs) db.journalEntries,
              ],
              addJoins: null,
              getPrefetchedDataCallback: (items) async {
                return [
                  if (journalEntriesRefs)
                    await $_getPrefetchedDataByColumns<
                      JournalSessionRow,
                      $JournalSessionsTable,
                      JournalEntry,
                      $JournalEntriesTable
                    >(
                      currentTable: table,
                      referencedTable: $$JournalSessionsTableReferences
                          ._journalEntriesRefsTable(db),
                      managerFromTypedResult: (p0) =>
                          $$JournalSessionsTableReferences(
                            db,
                            table,
                            p0,
                          ).journalEntriesRefs,
                      currentColumn: 'document_id',
                      referencedColumn: 'session_id',
                      typedResults: items,
                    ),
                ];
              },
            );
          },
        ),
      );
}

typedef $$JournalSessionsTableProcessedTableManager =
    ProcessedTableManager<
      _$LibraryDatabase,
      $JournalSessionsTable,
      JournalSessionRow,
      $$JournalSessionsTableFilterComposer,
      $$JournalSessionsTableOrderingComposer,
      $$JournalSessionsTableAnnotationComposer,
      $$JournalSessionsTableCreateCompanionBuilder,
      $$JournalSessionsTableUpdateCompanionBuilder,
      (JournalSessionRow, $$JournalSessionsTableReferences),
      JournalSessionRow,
      PrefetchHooks Function({bool journalEntriesRefs})
    >;
typedef $$JournalEntriesTableCreateCompanionBuilder =
    JournalEntriesCompanion Function({
      required int sessionId,
      required int sequence,
      required String command,
      Value<int> rowid,
    });
typedef $$JournalEntriesTableUpdateCompanionBuilder =
    JournalEntriesCompanion Function({
      Value<int> sessionId,
      Value<int> sequence,
      Value<String> command,
      Value<int> rowid,
    });

final class $$JournalEntriesTableReferences
    extends
        BaseReferences<_$LibraryDatabase, $JournalEntriesTable, JournalEntry> {
  $$JournalEntriesTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static $JournalSessionsTable _sessionIdTable(_$LibraryDatabase db) =>
      db.journalSessions.createAlias(
        'journal_entries__session_id__journal_sessions__document_id',
      );

  $$JournalSessionsTableProcessedTableManager get sessionId {
    final $_column = $_itemColumn<int>('session_id')!;

    final manager = $$JournalSessionsTableTableManager(
      $_db,
      $_db.journalSessions,
    ).filter((f) => f.documentId.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_sessionIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$JournalEntriesTableFilterComposer
    extends Composer<_$LibraryDatabase, $JournalEntriesTable> {
  $$JournalEntriesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get sequence => $composableBuilder(
    column: $table.sequence,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get command => $composableBuilder(
    column: $table.command,
    builder: (column) => ColumnFilters(column),
  );

  $$JournalSessionsTableFilterComposer get sessionId {
    final $$JournalSessionsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.sessionId,
      referencedTable: $db.journalSessions,
      getReferencedColumn: (t) => t.documentId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$JournalSessionsTableFilterComposer(
            $db: $db,
            $table: $db.journalSessions,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$JournalEntriesTableOrderingComposer
    extends Composer<_$LibraryDatabase, $JournalEntriesTable> {
  $$JournalEntriesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get sequence => $composableBuilder(
    column: $table.sequence,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get command => $composableBuilder(
    column: $table.command,
    builder: (column) => ColumnOrderings(column),
  );

  $$JournalSessionsTableOrderingComposer get sessionId {
    final $$JournalSessionsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.sessionId,
      referencedTable: $db.journalSessions,
      getReferencedColumn: (t) => t.documentId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$JournalSessionsTableOrderingComposer(
            $db: $db,
            $table: $db.journalSessions,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$JournalEntriesTableAnnotationComposer
    extends Composer<_$LibraryDatabase, $JournalEntriesTable> {
  $$JournalEntriesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get sequence =>
      $composableBuilder(column: $table.sequence, builder: (column) => column);

  GeneratedColumn<String> get command =>
      $composableBuilder(column: $table.command, builder: (column) => column);

  $$JournalSessionsTableAnnotationComposer get sessionId {
    final $$JournalSessionsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.sessionId,
      referencedTable: $db.journalSessions,
      getReferencedColumn: (t) => t.documentId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$JournalSessionsTableAnnotationComposer(
            $db: $db,
            $table: $db.journalSessions,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$JournalEntriesTableTableManager
    extends
        RootTableManager<
          _$LibraryDatabase,
          $JournalEntriesTable,
          JournalEntry,
          $$JournalEntriesTableFilterComposer,
          $$JournalEntriesTableOrderingComposer,
          $$JournalEntriesTableAnnotationComposer,
          $$JournalEntriesTableCreateCompanionBuilder,
          $$JournalEntriesTableUpdateCompanionBuilder,
          (JournalEntry, $$JournalEntriesTableReferences),
          JournalEntry,
          PrefetchHooks Function({bool sessionId})
        > {
  $$JournalEntriesTableTableManager(
    _$LibraryDatabase db,
    $JournalEntriesTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$JournalEntriesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$JournalEntriesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$JournalEntriesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> sessionId = const Value.absent(),
                Value<int> sequence = const Value.absent(),
                Value<String> command = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => JournalEntriesCompanion(
                sessionId: sessionId,
                sequence: sequence,
                command: command,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required int sessionId,
                required int sequence,
                required String command,
                Value<int> rowid = const Value.absent(),
              }) => JournalEntriesCompanion.insert(
                sessionId: sessionId,
                sequence: sequence,
                command: command,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$JournalEntriesTable, JournalEntry>(table),
                  $$JournalEntriesTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({sessionId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (sessionId) {
                      state = state.withJoin(
                        currentTable: table,
                        currentColumn: table.sessionId,
                        referencedTable: $$JournalEntriesTableReferences
                            ._sessionIdTable(db),
                        referencedColumn: $$JournalEntriesTableReferences
                            ._sessionIdTable(db)
                            .documentId,
                      ) as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$JournalEntriesTableProcessedTableManager =
    ProcessedTableManager<
      _$LibraryDatabase,
      $JournalEntriesTable,
      JournalEntry,
      $$JournalEntriesTableFilterComposer,
      $$JournalEntriesTableOrderingComposer,
      $$JournalEntriesTableAnnotationComposer,
      $$JournalEntriesTableCreateCompanionBuilder,
      $$JournalEntriesTableUpdateCompanionBuilder,
      (JournalEntry, $$JournalEntriesTableReferences),
      JournalEntry,
      PrefetchHooks Function({bool sessionId})
    >;

class $LibraryDatabaseManager {
  final _$LibraryDatabase _db;
  $LibraryDatabaseManager(this._db);
  $$DocumentsTableTableManager get documents =>
      $$DocumentsTableTableManager(_db, _db.documents);
  $$FoldersTableTableManager get folders =>
      $$FoldersTableTableManager(_db, _db.folders);
  $$OpenTabsTableTableManager get openTabs =>
      $$OpenTabsTableTableManager(_db, _db.openTabs);
  $$JournalSessionsTableTableManager get journalSessions =>
      $$JournalSessionsTableTableManager(_db, _db.journalSessions);
  $$JournalEntriesTableTableManager get journalEntries =>
      $$JournalEntriesTableTableManager(_db, _db.journalEntries);
}
