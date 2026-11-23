import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart' show rootBundle;
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
import '../models/flashcard_model.dart';
import 'google_translate_service.dart';

class TopicWordItem {
  final int order;
  final String englishWord;
  final String primaryVietnamese;
  final String phonetic;
  final String definition;
  final List<String> examples;
  final List<WordTypeEntry> wordTypes;
  final String fullVietnamese;
  final int bookNumber;
  final String topicName;

  TopicWordItem({
    required this.order,
    required this.englishWord,
    required this.primaryVietnamese,
    required this.phonetic,
    required this.definition,
    required this.examples,
    required this.wordTypes,
    required this.fullVietnamese,
    required this.bookNumber,
    required this.topicName,
  });

  factory TopicWordItem.fromJson(Map<String, dynamic> json) {
    return TopicWordItem(
      order: json['order'] is int
          ? json['order'] as int
          : int.tryParse(json['order']?.toString() ?? '0') ?? 0,
      englishWord: json['englishWord']?.toString() ?? '',
      primaryVietnamese: json['primaryVietnamese']?.toString() ?? '',
      phonetic: json['phonetic']?.toString() ?? '',
      definition: json['definition']?.toString() ?? '',
      examples:
          (json['examples'] as List?)?.map((e) => e.toString()).toList() ?? [],
      wordTypes: (json['wordTypes'] as List?)
              ?.map((e) => WordTypeEntry.fromJson(Map<String, dynamic>.from(e)))
              .toList() ??
          [],
      fullVietnamese: json['fullVietnamese']?.toString() ?? '',
      bookNumber: json['bookNumber'] is int
          ? json['bookNumber'] as int
          : int.tryParse(json['bookNumber']?.toString() ?? '1') ?? 1,
      topicName: json['topicName']?.toString() ?? '',
    );
  }

  /// Chuyển một từ trong Topic thành FlashcardItem đầy đủ
  FlashcardItem toFlashcardItem({required int indexNumber}) {
    final defs = <DefinitionEntry>[];
    if (definition.trim().isNotEmpty) {
      defs.add(
        DefinitionEntry(
          pos: topicName,
          gloss: definition,
          example: examples.isNotEmpty ? examples.first : null,
        ),
      );
    }

    final rawMap = {
      'source': 'Dữ liệu SQLite gốc từ docs ($topicName)',
      'englishWord': englishWord,
      'primaryVietnamese': primaryVietnamese,
      'phonetic': phonetic,
      'definition': definition,
      'examples': examples,
      'fullVietnamese': fullVietnamese,
    };

    return FlashcardItem(
      id: '${DateTime.now().microsecondsSinceEpoch}_$englishWord',
      indexNumber: indexNumber,
      englishWord: englishWord,
      primaryVietnamese: primaryVietnamese,
      phonetic: phonetic,
      wordTypes: wordTypes,
      definitions: defs,
      examples: examples,
      alternativeTranslations: const [],
      rawGoogleResponseJson:
          const JsonEncoder.withIndent('  ').convert(rawMap),
      createdAt: DateTime.now(),
    );
  }
}

class VocabTopicUnit {
  final String id;
  final int bookNumber;
  final String unitName;
  final String title;
  final List<TopicWordItem> words;

  VocabTopicUnit({
    required this.id,
    required this.bookNumber,
    required this.unitName,
    required this.title,
    required this.words,
  });

  factory VocabTopicUnit.fromJson(Map<String, dynamic> json) {
    return VocabTopicUnit(
      id: json['id']?.toString() ?? '',
      bookNumber: json['bookNumber'] is int ? json['bookNumber'] as int : 1,
      unitName: json['unitName']?.toString() ?? '',
      title: json['title']?.toString() ?? '',
      words: (json['words'] as List?)
              ?.map((e) => TopicWordItem.fromJson(Map<String, dynamic>.from(e)))
              .toList() ??
          [],
    );
  }
}

class VocabBookGroup {
  final int bookNumber;
  final String bookTitle;
  final List<VocabTopicUnit> topics;

  VocabBookGroup({
    required this.bookNumber,
    required this.bookTitle,
    required this.topics,
  });

  int get totalWords =>
      topics.fold<int>(0, (sum, unit) => sum + unit.words.length);

  factory VocabBookGroup.fromJson(Map<String, dynamic> json) {
    return VocabBookGroup(
      bookNumber: json['bookNumber'] is int ? json['bookNumber'] as int : 1,
      bookTitle: json['bookTitle']?.toString() ?? '',
      topics: (json['topics'] as List?)
              ?.map(
                  (e) => VocabTopicUnit.fromJson(Map<String, dynamic>.from(e)))
              .toList() ??
          [],
    );
  }
}

class LookupResult {
  final FlashcardItem card;
  final bool fromLocalTopic;
  final String sourceLabel;

  LookupResult({
    required this.card,
    required this.fromLocalTopic,
    required this.sourceLabel,
  });
}

class TopicVocabService {
  static List<VocabBookGroup>? _cachedBooks;
  static final Map<String, TopicWordItem> _wordIndex = {};
  static final List<TopicWordItem> _allWordsFlat = [];

  /// Làm sạch mã HTML trong trường dữ liệu của Anki SQLite DB
  static String _cleanHtml(String rawHtml) {
    if (rawHtml.isEmpty) return '';
    var text = rawHtml.replaceAllMapped(
      RegExp(r'\{\{c\d+::(.*?)\}\}'),
      (m) => m.group(1) ?? '',
    );
    text = text.replaceAll(
        RegExp(r'<br\s*/?>', caseSensitive: false), '\n');
    text = text.replaceAll(
        RegExp(r'</div>|</li>|</p>|</ul>', caseSensitive: false), '\n');
    text = text.replaceAll(RegExp(r'<[^>]+>'), '');
    text = text
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&amp;', '&')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'")
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>');

    final lines = text
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList();
    return lines.join('\n');
  }

  /// Phân tích trường Full Vietnamese của Anki thành danh sách WordTypeEntry
  static List<WordTypeEntry> _parseFullVietnamese(String fullViHtml) {
    if (fullViHtml.isEmpty) return [];
    final cleaned = _cleanHtml(fullViHtml);
    final lines = cleaned.split('\n');
    final List<WordTypeEntry> wordTypes = [];

    String currentPos = 'Từ điển';
    List<String> currentTerms = [];
    List<String> currentExamples = [];

    const posPrefixes = [
      'danh từ',
      'động từ',
      'tính từ',
      'phó từ',
      'trạng từ',
      'giới từ',
      'nội động từ',
      'ngoại động từ',
      'liên từ',
      'thán từ',
    ];

    for (final line in lines) {
      final lower = line.toLowerCase();
      final isPos = posPrefixes.any((p) => lower.startsWith(p));
      if (isPos) {
        if (currentTerms.isNotEmpty || currentExamples.isNotEmpty) {
          wordTypes.add(
            WordTypeEntry(
              pos: currentPos,
              terms: List<String>.from(currentTerms),
              reverseTranslations: List<String>.from(currentExamples),
            ),
          );
        }
        currentPos = line;
        currentTerms = [];
        currentExamples = [];
      } else if (line.contains(':')) {
        currentExamples.add(line);
      } else {
        if (line.contains('/') &&
            currentTerms.isEmpty &&
            wordTypes.isEmpty) {
          continue;
        }
        currentTerms.add(line);
      }
    }

    if (currentTerms.isNotEmpty || currentExamples.isNotEmpty) {
      wordTypes.add(
        WordTypeEntry(
          pos: currentPos,
          terms: currentTerms.isNotEmpty ? currentTerms : [currentPos],
          reverseTranslations: currentExamples,
        ),
      );
    }
    return wordTypes;
  }

  /// Chương trình nạp dữ liệu trực tiếp bằng code Dart từ 5 cơ sở dữ liệu Anki SQLite
  /// (`assets/anki_dbs/book_1.sqlite` .. `book_5.sqlite`) được trích xuất từ thư mục `docs/`.
  static Future<List<VocabBookGroup>> _loadDirectlyFromAnkiSqliteDbs() async {
    final dbFolder = await getDatabasesPath();
    await Directory(dbFolder).create(recursive: true);
    final List<VocabBookGroup> books = [];

    for (int bookIdx = 1; bookIdx <= 5; bookIdx++) {
      final assetPath = 'assets/anki_dbs/book_$bookIdx.sqlite';
      final byteData = await rootBundle.load(assetPath);
      final bytes = byteData.buffer.asUint8List(
        byteData.offsetInBytes,
        byteData.lengthInBytes,
      );

      final localDbPath = p.join(dbFolder, 'anki_docs_book_$bookIdx.sqlite');
      final localFile = File(localDbPath);
      if (!localFile.existsSync() || localFile.lengthSync() != bytes.length) {
        await localFile.writeAsBytes(bytes, flush: true);
      }

      final db = await openDatabase(localDbPath, readOnly: true);
      try {
        final colRows = await db.query('col', columns: ['models', 'decks']);
        if (colRows.isEmpty) continue;

        final modelsMap = jsonDecode(colRows.first['models'] as String)
            as Map<String, dynamic>;
        final decksMap = jsonDecode(colRows.first['decks'] as String)
            as Map<String, dynamic>;

        // Ánh xạ modelId -> danh sách tên cột
        final Map<int, List<String>> modelFields = {};
        modelsMap.forEach((midStr, mVal) {
          final mid = int.tryParse(midStr) ?? 0;
          final flds = (mVal['flds'] as List?)
                  ?.map((f) => f['name'].toString())
                  .toList() ??
              [];
          modelFields[mid] = flds;
        });

        // Ánh xạ deckId -> tên Topic (Unit)
        final Map<int, String> deckNames = {};
        decksMap.forEach((didStr, dVal) {
          final did = int.tryParse(didStr) ?? 0;
          deckNames[did] = dVal['name']?.toString() ?? 'Unit 01';
        });

        // Truy vấn toàn bộ bảng notes kết hợp với cards
        final rows = await db.rawQuery('''
          SELECT n.id, n.mid, n.flds, MIN(c.did) as did
          FROM notes n
          LEFT JOIN cards c ON c.nid = n.id
          GROUP BY n.id
        ''');

        final Map<String, List<TopicWordItem>> topicsMap = {};

        for (final row in rows) {
          final mid = (row['mid'] as num?)?.toInt() ?? 0;
          final did = (row['did'] as num?)?.toInt() ?? 0;
          final fldsStr = row['flds']?.toString() ?? '';
          final values = fldsStr.split('\x1f');
          final fieldNames = modelFields[mid] ?? [];

          final Map<String, String> fieldDict = {};
          for (int i = 0; i < fieldNames.length && i < values.length; i++) {
            fieldDict[fieldNames[i]] = values[i];
          }

          final deckFullName =
              deckNames[did] ?? '4000 Essential English Words - Book $bookIdx::Unit 01';
          final unitName = deckFullName.contains('::')
              ? deckFullName.split('::').last.trim()
              : 'Unit 01';

          final numRaw = fieldDict['№'] ?? '0';
          final orderNum =
              int.tryParse(numRaw.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;

          final keyword = _cleanHtml(fieldDict['Keyword'] ?? '').trim();
          if (keyword.isEmpty) continue;

          final shortVi =
              _cleanHtml(fieldDict['Short Vietnamese'] ?? '').trim();
          final transcription = _cleanHtml(fieldDict['Transcription'] ?? '')
              .replaceAll(RegExp(r'[\[\]/]'), '')
              .trim();

          final explanationClean =
              _cleanHtml(fieldDict['Explanation'] ?? '');
          String definitionLine = '';
          final List<String> exampleLines = [];

          for (final line in explanationClean.split('\n')) {
            if (line.startsWith('→')) {
              exampleLines.add(line.replaceFirst('→', '').trim());
            } else if (definitionLine.isEmpty) {
              definitionLine = line;
            } else {
              exampleLines.add(line);
            }
          }

          final fullViRaw = fieldDict['Full Vietnamese'] ?? '';
          final fullViClean = _cleanHtml(fullViRaw);
          final wordTypes = _parseFullVietnamese(fullViRaw);

          final item = TopicWordItem(
            order: orderNum,
            englishWord: keyword,
            primaryVietnamese: shortVi,
            phonetic: transcription,
            definition: definitionLine,
            examples: exampleLines,
            wordTypes: wordTypes,
            fullVietnamese: fullViClean,
            bookNumber: bookIdx,
            topicName: 'Tập $bookIdx - $unitName',
          );

          topicsMap.putIfAbsent(unitName, () => []).add(item);
        }

        final sortedUnitKeys = topicsMap.keys.toList()..sort();
        final List<VocabTopicUnit> topicUnits = [];

        for (final unitKey in sortedUnitKeys) {
          final words = topicsMap[unitKey]!
            ..sort((a, b) => a.order.compareTo(b.order));
          final numMatch =
              int.tryParse(unitKey.replaceAll(RegExp(r'[^0-9]'), '')) ?? 1;
          final numFormatted = numMatch.toString().padLeft(2, '0');
          topicUnits.add(
            VocabTopicUnit(
              id: 'b${bookIdx}_u$numFormatted',
              bookNumber: bookIdx,
              unitName: 'Topic $numFormatted ($unitKey)',
              title: 'Tập $bookIdx • Topic $numFormatted',
              words: words,
            ),
          );
        }

        books.add(
          VocabBookGroup(
            bookNumber: bookIdx,
            bookTitle: '4000 Essential English Words - Tập $bookIdx',
            topics: topicUnits,
          ),
        );
      } finally {
        await db.close();
      }
    }

    return books;
  }

  /// Tải toàn bộ danh sách 5 Tập (150 Topic / 3.000 từ vựng) từ cơ sở dữ liệu trong docs
  static Future<List<VocabBookGroup>> loadAllBooks() async {
    if (_cachedBooks != null && _cachedBooks!.isNotEmpty) {
      return _cachedBooks!;
    }

    List<VocabBookGroup> books = [];
    try {
      // 1. Nạp trực tiếp từ 5 file SQLite DB trích xuất từ docs/*.apkg bằng chương trình Dart
      books = await _loadDirectlyFromAnkiSqliteDbs();
    } catch (_) {
      books = [];
    }

    // 2. Dự phòng từ JSON nếu đang chạy trên môi trường test không có SQLite native
    if (books.isEmpty) {
      try {
        final jsonStr =
            await rootBundle.loadString('assets/data/topics_vocab.json');
        final decoded = jsonDecode(jsonStr) as List;
        books = decoded
            .map((e) => VocabBookGroup.fromJson(Map<String, dynamic>.from(e)))
            .toList();
      } catch (_) {}
    }

    _wordIndex.clear();
    _allWordsFlat.clear();
    for (final b in books) {
      for (final t in b.topics) {
        for (final w in t.words) {
          _allWordsFlat.add(w);
          final key = w.englishWord.trim().toLowerCase();
          if (key.isNotEmpty && !_wordIndex.containsKey(key)) {
            _wordIndex[key] = w;
          }
        }
      }
    }

    _cachedBooks = books;
    return books;
  }

  static List<TopicWordItem> get allWords => _allWordsFlat;

  /// Tìm từ chính xác hoặc gợi ý gần đúng trong toàn bộ 3.000 từ vựng của 150 Topic
  static Future<List<TopicWordItem>> searchWordsInTopics(
    String query, {
    int limit = 50,
  }) async {
    await loadAllBooks();
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return [];

    final exact = <TopicWordItem>[];
    final prefix = <TopicWordItem>[];
    final contains = <TopicWordItem>[];

    for (final item in _allWordsFlat) {
      final wordKey = item.englishWord.trim().toLowerCase();
      if (wordKey == q) {
        exact.add(item);
      } else if (wordKey.startsWith(q)) {
        prefix.add(item);
      } else if (wordKey.contains(q) ||
          item.primaryVietnamese.toLowerCase().contains(q)) {
        contains.add(item);
      }
    }

    return [...exact, ...prefix, ...contains].take(limit).toList();
  }

  /// Ưu tiên tìm từ tiếng Anh trong kho Topic (folder docs) trước;
  /// Nếu không có trong các Topic thì mới gọi API Google Dịch.
  static Future<LookupResult> lookupWordPreferTopics({
    required String englishWord,
    required int indexNumber,
  }) async {
    final cleanWord = englishWord.trim();
    if (cleanWord.isEmpty) {
      throw Exception('Vui lòng nhập từ tiếng Anh!');
    }

    await loadAllBooks();
    final key = cleanWord.toLowerCase();
    final foundInTopic = _wordIndex[key];

    if (foundInTopic != null) {
      return LookupResult(
        card: foundInTopic.toFlashcardItem(indexNumber: indexNumber),
        fromLocalTopic: true,
        sourceLabel: 'Lấy từ Topic (${foundInTopic.topicName})',
      );
    }

    final googleCard =
        await GoogleTranslateService.translateAndBuildFlashcard(
      englishWord: cleanWord,
      indexNumber: indexNumber,
    );
    return LookupResult(
      card: googleCard,
      fromLocalTopic: false,
      sourceLabel: 'Không có trong Topic -> Đã lấy từ Google Dịch',
    );
  }
}
