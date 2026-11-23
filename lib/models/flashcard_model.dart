import 'dart:convert';

class WordTypeEntry {
  final String pos; // Danh từ, Động từ, Tính từ...
  final List<String> terms; // Các nghĩa tiếng Việt của từ loại này
  final List<String> reverseTranslations; // Các từ tiếng Anh đồng nghĩa

  WordTypeEntry({
    required this.pos,
    required this.terms,
    required this.reverseTranslations,
  });

  Map<String, dynamic> toJson() => {
        'pos': pos,
        'terms': terms,
        'reverseTranslations': reverseTranslations,
      };

  factory WordTypeEntry.fromJson(Map<String, dynamic> json) {
    return WordTypeEntry(
      pos: json['pos']?.toString() ?? '',
      terms: (json['terms'] as List?)?.map((e) => e.toString()).toList() ?? [],
      reverseTranslations: (json['reverseTranslations'] as List?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
    );
  }
}

class DefinitionEntry {
  final String pos;
  final String gloss;
  final String? example;

  DefinitionEntry({
    required this.pos,
    required this.gloss,
    this.example,
  });

  Map<String, dynamic> toJson() => {
        'pos': pos,
        'gloss': gloss,
        'example': example,
      };

  factory DefinitionEntry.fromJson(Map<String, dynamic> json) {
    return DefinitionEntry(
      pos: json['pos']?.toString() ?? '',
      gloss: json['gloss']?.toString() ?? '',
      example: json['example']?.toString(),
    );
  }
}

class FlashcardItem {
  final String id;
  final int indexNumber; // Số thứ tự 1, 2, 3...
  final String englishWord;
  final String primaryVietnamese; // Nghĩa chính từ Google Dịch / Topic
  final String phonetic; // Phiên âm
  final List<WordTypeEntry> wordTypes; // Chi tiết các từ loại và nghĩa phụ
  final List<DefinitionEntry> definitions; // Định nghĩa mở rộng và câu ví dụ
  final List<String> examples; // Các câu ví dụ
  final List<String> alternativeTranslations; // Các bản dịch thay thế
  final String rawGoogleResponseJson; // Lưu nguyên bản toàn bộ dữ liệu
  final DateTime createdAt;
  final bool isReviewed; // Đã từng được ôn tập hay chưa (false = từ mới chưa được ôn tập)
  final bool isNotRemembered; // Đánh dấu nằm trong danh sách "Không nhớ"

  FlashcardItem({
    required this.id,
    required this.indexNumber,
    required this.englishWord,
    required this.primaryVietnamese,
    this.phonetic = '',
    this.wordTypes = const [],
    this.definitions = const [],
    this.examples = const [],
    this.alternativeTranslations = const [],
    required this.rawGoogleResponseJson,
    required this.createdAt,
    this.isReviewed = false,
    this.isNotRemembered = false,
  });

  FlashcardItem copyWith({
    String? id,
    int? indexNumber,
    String? englishWord,
    String? primaryVietnamese,
    String? phonetic,
    List<WordTypeEntry>? wordTypes,
    List<DefinitionEntry>? definitions,
    List<String>? examples,
    List<String>? alternativeTranslations,
    String? rawGoogleResponseJson,
    DateTime? createdAt,
    bool? isReviewed,
    bool? isNotRemembered,
  }) {
    return FlashcardItem(
      id: id ?? this.id,
      indexNumber: indexNumber ?? this.indexNumber,
      englishWord: englishWord ?? this.englishWord,
      primaryVietnamese: primaryVietnamese ?? this.primaryVietnamese,
      phonetic: phonetic ?? this.phonetic,
      wordTypes: wordTypes ?? this.wordTypes,
      definitions: definitions ?? this.definitions,
      examples: examples ?? this.examples,
      alternativeTranslations:
          alternativeTranslations ?? this.alternativeTranslations,
      rawGoogleResponseJson:
          rawGoogleResponseJson ?? this.rawGoogleResponseJson,
      createdAt: createdAt ?? this.createdAt,
      isReviewed: isReviewed ?? this.isReviewed,
      isNotRemembered: isNotRemembered ?? this.isNotRemembered,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'indexNumber': indexNumber,
        'englishWord': englishWord,
        'primaryVietnamese': primaryVietnamese,
        'phonetic': phonetic,
        'wordTypes': wordTypes.map((e) => e.toJson()).toList(),
        'definitions': definitions.map((e) => e.toJson()).toList(),
        'examples': examples,
        'alternativeTranslations': alternativeTranslations,
        'rawGoogleResponseJson': rawGoogleResponseJson,
        'createdAt': createdAt.toIso8601String(),
        'isReviewed': isReviewed,
        'isNotRemembered': isNotRemembered,
      };

  factory FlashcardItem.fromJson(Map<String, dynamic> json) {
    return FlashcardItem(
      id: json['id']?.toString() ?? '',
      indexNumber: json['indexNumber'] is int
          ? json['indexNumber'] as int
          : int.tryParse(json['indexNumber']?.toString() ?? '1') ?? 1,
      englishWord: json['englishWord']?.toString() ?? '',
      primaryVietnamese: json['primaryVietnamese']?.toString() ?? '',
      phonetic: json['phonetic']?.toString() ?? '',
      wordTypes: (json['wordTypes'] as List?)
              ?.map((e) => WordTypeEntry.fromJson(Map<String, dynamic>.from(e)))
              .toList() ??
          [],
      definitions: (json['definitions'] as List?)
              ?.map(
                  (e) => DefinitionEntry.fromJson(Map<String, dynamic>.from(e)))
              .toList() ??
          [],
      examples:
          (json['examples'] as List?)?.map((e) => e.toString()).toList() ?? [],
      alternativeTranslations: (json['alternativeTranslations'] as List?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
      rawGoogleResponseJson: json['rawGoogleResponseJson']?.toString() ?? '{}',
      createdAt: DateTime.tryParse(json['createdAt']?.toString() ?? '') ??
          DateTime.now(),
      isReviewed: json['isReviewed'] == true,
      isNotRemembered: json['isNotRemembered'] == true,
    );
  }

  static String encodeList(List<FlashcardItem> list) =>
      jsonEncode(list.map((e) => e.toJson()).toList());

  static List<FlashcardItem> decodeList(String jsonStr) {
    final decoded = jsonDecode(jsonStr) as List;
    return decoded
        .map((e) => FlashcardItem.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }
}
