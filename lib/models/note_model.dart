import 'dart:convert';

class NoteConceptBlock {
  final String id;
  final String conceptText; // Phần "Khái niệm" (nhập riêng, cỡ chữ lớn hơn, có highlight màu)
  final String noteText; // Phần "Ghi chú" (nhập riêng, hiển thị bên dưới Khái niệm khi xem chi tiết)

  NoteConceptBlock({
    required this.id,
    required this.conceptText,
    required this.noteText,
  });

  NoteConceptBlock copyWith({
    String? id,
    String? conceptText,
    String? noteText,
  }) {
    return NoteConceptBlock(
      id: id ?? this.id,
      conceptText: conceptText ?? this.conceptText,
      noteText: noteText ?? this.noteText,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'conceptText': conceptText,
        'noteText': noteText,
      };

  factory NoteConceptBlock.fromJson(Map<String, dynamic> json) {
    return NoteConceptBlock(
      id: json['id']?.toString() ??
          DateTime.now().microsecondsSinceEpoch.toString(),
      conceptText: json['conceptText']?.toString() ?? '',
      noteText: json['noteText']?.toString() ?? '',
    );
  }
}

class StudyNoteItem {
  final String id;
  final String title; // VD: THÀNH PHẦN CÂU TRONG TIẾNG ANH
  final String subtitle; // VD: * Khái niệm bao quát: Vị trí, bản chất, chức năng
  final List<NoteConceptBlock> blocks; // Danh sách các cặp (Khái niệm + Ghi chú)
  final DateTime updatedAt;

  StudyNoteItem({
    required this.id,
    required this.title,
    this.subtitle = '',
    required this.blocks,
    required this.updatedAt,
  });

  StudyNoteItem copyWith({
    String? id,
    String? title,
    String? subtitle,
    List<NoteConceptBlock>? blocks,
    DateTime? updatedAt,
  }) {
    return StudyNoteItem(
      id: id ?? this.id,
      title: title ?? this.title,
      subtitle: subtitle ?? this.subtitle,
      blocks: blocks ?? this.blocks,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'subtitle': subtitle,
        'blocks': blocks.map((b) => b.toJson()).toList(),
        'updatedAt': updatedAt.toIso8601String(),
      };

  factory StudyNoteItem.fromJson(Map<String, dynamic> json) {
    return StudyNoteItem(
      id: json['id']?.toString() ?? '',
      title: json['title']?.toString() ?? '',
      subtitle: json['subtitle']?.toString() ?? '',
      blocks: (json['blocks'] as List?)
              ?.map((e) =>
                  NoteConceptBlock.fromJson(Map<String, dynamic>.from(e)))
              .toList() ??
          [],
      updatedAt: DateTime.tryParse(json['updatedAt']?.toString() ?? '') ??
          DateTime.now(),
    );
  }

  static String encodeList(List<StudyNoteItem> list) =>
      jsonEncode(list.map((e) => e.toJson()).toList());

  static List<StudyNoteItem> decodeList(String raw) {
    final decoded = jsonDecode(raw) as List;
    return decoded
        .map((e) => StudyNoteItem.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }
}
