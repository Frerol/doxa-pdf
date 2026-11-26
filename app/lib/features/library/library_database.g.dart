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

abstract class _$LibraryDatabase extends GeneratedDatabase {
  _$LibraryDatabase(QueryExecutor e) : super(e);
  $LibraryDatabaseManager get managers => $LibraryDatabaseManager(this);
  late final $DocumentsTable documents = $DocumentsTable(this);
  late final $FoldersTable folders = $FoldersTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [documents, folders];
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

class $LibraryDatabaseManager {
  final _$LibraryDatabase _db;
  $LibraryDatabaseManager(this._db);
  $$DocumentsTableTableManager get documents =>
      $$DocumentsTableTableManager(_db, _db.documents);
  $$FoldersTableTableManager get folders =>
      $$FoldersTableTableManager(_db, _db.folders);
}
