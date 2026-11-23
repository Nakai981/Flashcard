import 'package:flutter/material.dart';
import '../models/note_model.dart';
import '../services/note_storage_service.dart';
import '../theme/chibi_theme.dart';

/// Bộ phân tích cú pháp Highlight màu sắc:
/// - `[r]...[/r]` -> Màu Đỏ nổi bật (#C92A2A) giống "Chủ ngữ", "chia động từ", "hành động", "trạng thái", "bổ trợ"
/// - `[g]...[/g]` -> Màu Xanh lá (#2B8A3E) giống "Động từ"
/// - `[b]...[/b]` -> Màu Xanh dương (#1D64C8)
/// - `[o]...[/o]` -> Màu Cam tím (#D9480F)
/// - Tự động in nghiêng phần nằm trong dấu ngoặc đơn `(...)` ở phần Ghi chú giống hệt hình mẫu!
class NoteRichTextFormatter {
  static const Color highlightRed = Color(0xFFC92A2A);
  static const Color highlightGreen = Color(0xFF2B8A3E);
  static const Color highlightBlue = Color(0xFF1D64C8);
  static const Color highlightOrange = Color(0xFFD9480F);

  /// Xóa các thẻ `[r]`, `[/r]`... để hiển thị văn bản tóm tắt ở danh sách ngoài
  static String stripTags(String input) {
    return input.replaceAll(RegExp(r'\[/?(r|g|b|o|i)\]'), '');
  }

  /// Dựng TextSpan cho phần **Khái niệm** (cỡ chữ to rõ 18.5, khoảng cách dòng thoáng, highlight từ khóa màu Đỏ/Xanh lá/Xanh dương)
  static TextSpan buildConceptSpan(String rawText) {
    final baseStyle = const TextStyle(
      fontSize: 18.5,
      height: 1.48,
      fontWeight: FontWeight.w500,
      color: Color(0xFF222222),
    );
    return TextSpan(
      style: baseStyle,
      children: _parseTaggedSpans(rawText, baseStyle, isConcept: true),
    );
  }

  /// Dựng TextSpan cho phần **Ghi chú** (cỡ chữ 15.5, tự động in nghiêng nội dung trong ngoặc đơn `(...)` và dòng bắt đầu bằng `*` giống hình mẫu)
  static Widget buildNoteFormattedWidget(String rawText) {
    final lines = rawText.split('\n');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: lines.map((line) {
        final trimmed = line.trim();
        if (trimmed.isEmpty) {
          return const SizedBox(height: 6);
        }
        final isStarHeader = trimmed.startsWith('*');
        final lineBaseStyle = TextStyle(
          fontSize: 15.5,
          height: 1.52,
          fontWeight: isStarHeader ? FontWeight.w600 : FontWeight.w500,
          fontStyle: isStarHeader ? FontStyle.italic : FontStyle.normal,
          color: const Color(0xFF2B2B2B),
        );

        return Padding(
          padding: const EdgeInsets.only(bottom: 3),
          child: RichText(
            text: TextSpan(
              style: lineBaseStyle,
              children: _parseLineWithParenthesesAndTags(line, lineBaseStyle),
            ),
          ),
        );
      }).toList(),
    );
  }

  static List<InlineSpan> _parseLineWithParenthesesAndTags(
    String text,
    TextStyle baseStyle,
  ) {
    // Tách các cụm nằm trong dấu ngoặc đơn (...) để tự động in nghiêng giống hình mẫu:
    // VD: Danh từ / Cụm danh từ (Noun / Noun Phrase)
    //     The + Tính từ ([r]chỉ nhóm người[/r]: the rich, the poor...)
    final List<InlineSpan> result = [];
    final parenRegex = RegExp(r'\([^()]+\)');
    int lastIdx = 0;

    for (final match in parenRegex.allMatches(text)) {
      if (match.start > lastIdx) {
        final before = text.substring(lastIdx, match.start);
        result.addAll(_parseTaggedSpans(before, baseStyle, isConcept: false));
      }
      final insideParen = match.group(0)!;
      final italicStyle = baseStyle.copyWith(fontStyle: FontStyle.italic);
      result.addAll(
          _parseTaggedSpans(insideParen, italicStyle, isConcept: false));
      lastIdx = match.end;
    }

    if (lastIdx < text.length) {
      result.addAll(
        _parseTaggedSpans(text.substring(lastIdx), baseStyle, isConcept: false),
      );
    }
    return result;
  }

  static List<InlineSpan> _parseTaggedSpans(
    String input,
    TextStyle currentStyle, {
    required bool isConcept,
  }) {
    final List<InlineSpan> spans = [];
    final tagRegex = RegExp(r'\[(r|g|b|o|i)\](.*?)\[/\1\]', dotAll: true);
    int lastEnd = 0;

    for (final match in tagRegex.allMatches(input)) {
      if (match.start > lastEnd) {
        spans.add(
          TextSpan(
            text: input.substring(lastEnd, match.start),
            style: currentStyle,
          ),
        );
      }

      final tag = match.group(1)!;
      final content = match.group(2) ?? '';
      TextStyle highlightStyle = currentStyle;

      switch (tag) {
        case 'r':
          highlightStyle = currentStyle.copyWith(
            color: highlightRed,
            fontWeight: isConcept ? FontWeight.w700 : FontWeight.w600,
          );
          break;
        case 'g':
          highlightStyle = currentStyle.copyWith(
            color: highlightGreen,
            fontWeight: isConcept ? FontWeight.w700 : FontWeight.w600,
          );
          break;
        case 'b':
          highlightStyle = currentStyle.copyWith(
            color: highlightBlue,
            fontWeight: isConcept ? FontWeight.w700 : FontWeight.w600,
          );
          break;
        case 'o':
          highlightStyle = currentStyle.copyWith(
            color: highlightOrange,
            fontWeight: isConcept ? FontWeight.w700 : FontWeight.w600,
          );
          break;
        case 'i':
          highlightStyle = currentStyle.copyWith(
            fontStyle: FontStyle.italic,
          );
          break;
      }

      spans.add(TextSpan(text: content, style: highlightStyle));
      lastEnd = match.end;
    }

    if (lastEnd < input.length) {
      spans.add(
        TextSpan(
          text: input.substring(lastEnd),
          style: currentStyle,
        ),
      );
    }

    return spans;
  }
}

class NotesScreen extends StatefulWidget {
  const NotesScreen({super.key});

  @override
  State<NotesScreen> createState() => _NotesScreenState();
}

class _NotesScreenState extends State<NotesScreen> {
  List<StudyNoteItem> _notes = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadNotes();
  }

  Future<void> _loadNotes() async {
    final loaded = await NoteStorageService.loadNotes();
    if (!mounted) return;
    setState(() {
      _notes = loaded;
      _isLoading = false;
    });
  }

  Future<void> _openCreateOrEditNote({StudyNoteItem? existing}) async {
    final savedNote = await Navigator.of(context).push<StudyNoteItem>(
      MaterialPageRoute(
        builder: (_) => NoteEditorScreen(existingNote: existing),
      ),
    );

    if (savedNote != null) {
      final updated = await NoteStorageService.upsertNote(savedNote);
      if (!mounted) return;
      setState(() {
        _notes = updated;
      });
    }
  }

  void _openNoteDetail(StudyNoteItem note) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => NoteDetailScreen(
          note: note,
          onNoteUpdated: (updatedList) {
            setState(() {
              _notes = updatedList;
            });
          },
        ),
      ),
    );
  }

  Future<void> _confirmDeleteNote(StudyNoteItem note) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
        ),
        title: const Text(
          'Xóa bài ghi chú này?',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
        content: Text('Bạn có chắc muốn xóa ghi chú "${note.title}" không?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Hủy'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: ChibiTheme.deepPink,
              foregroundColor: Colors.white,
            ),
            child: const Text('Xóa'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      final updated = await NoteStorageService.deleteNote(note.id);
      if (!mounted) return;
      setState(() {
        _notes = updated;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: ChibiTheme.pastelPink),
      );
    }

    return Scaffold(
      backgroundColor: ChibiTheme.bgCream,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openCreateOrEditNote(),
        backgroundColor: ChibiTheme.deepPink,
        foregroundColor: Colors.white,
        elevation: 4,
        icon: const Icon(Icons.note_add_rounded),
        label: const Text(
          'Tạo ghi chú mới',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
      ),
      body: Column(
        children: [
          // Header giới thiệu tính năng Ghi chú (Khái niệm + Ghi chú có Highlight màu)
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 8, 18, 10),
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: ChibiTheme.kawaiiCardDecoration(
                color: Colors.white,
                borderColor: ChibiTheme.softPink,
                radius: 26,
              ),
              child: Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(18),
                    child: Image.asset(
                      'assets/images/chibi_review.jpg',
                      width: 72,
                      height: 72,
                      fit: BoxFit.cover,
                    ),
                  ),
                  const SizedBox(width: 14),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Sổ Tay Khái Niệm & Ghi Chú 📝',
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w900,
                            color: ChibiTheme.textDark,
                          ),
                        ),
                        SizedBox(height: 4),
                        Text(
                          'Khi nhập tách riêng ô Khái niệm và ô Ghi chú (hỗ trợ bôi màu từ khóa Đỏ, Xanh lá, Xanh dương). Khi xem chi tiết sẽ gộp thành trang bài học chuẩn!',
                          style: TextStyle(
                            fontSize: 12.2,
                            color: ChibiTheme.textMuted,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          Expanded(
            child: _notes.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Container(
                        padding: const EdgeInsets.all(24),
                        decoration: ChibiTheme.kawaiiCardDecoration(
                          color: Colors.white,
                          borderColor: ChibiTheme.softPink,
                          radius: 28,
                        ),
                        child: const Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.menu_book_rounded,
                              size: 52,
                              color: ChibiTheme.deepPink,
                            ),
                            SizedBox(height: 12),
                            Text(
                              'Chưa có bài ghi chú nào!',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            SizedBox(height: 6),
                            Text(
                              'Bấm nút "Tạo ghi chú mới" bên dưới để thêm Khái niệm và Ghi chú nhé!',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 13.5,
                                color: ChibiTheme.textMuted,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(18, 4, 18, 96),
                    itemCount: _notes.length,
                    itemBuilder: (context, index) {
                      final note = _notes[index];
                      final previewConcept = note.blocks.isNotEmpty
                          ? NoteRichTextFormatter.stripTags(
                              note.blocks.first.conceptText)
                          : '';

                      return Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(24),
                          onTap: () => _openNoteDetail(note),
                          child: Container(
                            padding: const EdgeInsets.all(16),
                            decoration: ChibiTheme.kawaiiCardDecoration(
                              color: Colors.white,
                              borderColor: index.isEven
                                  ? ChibiTheme.softPink
                                  : ChibiTheme.pastelLavender,
                              radius: 24,
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Container(
                                  width: 46,
                                  height: 46,
                                  alignment: Alignment.center,
                                  decoration: BoxDecoration(
                                    color: ChibiTheme.softPink,
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                  child: const Icon(
                                    Icons.article_rounded,
                                    color: ChibiTheme.deepPink,
                                  ),
                                ),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        note.title.toUpperCase(),
                                        style: const TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w900,
                                          color: ChibiTheme.textDark,
                                        ),
                                      ),
                                      if (note.subtitle.trim().isNotEmpty) ...[
                                        const SizedBox(height: 3),
                                        Text(
                                          note.subtitle,
                                          style: const TextStyle(
                                            fontSize: 13,
                                            fontStyle: FontStyle.italic,
                                            color: ChibiTheme.deepPink,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                      ],
                                      if (previewConcept.isNotEmpty) ...[
                                        const SizedBox(height: 6),
                                        Text(
                                          previewConcept,
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            fontSize: 13.5,
                                            color: ChibiTheme.textMuted,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ],
                                      const SizedBox(height: 8),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 10, vertical: 4),
                                        decoration: BoxDecoration(
                                          color: ChibiTheme.softLavender,
                                          borderRadius:
                                              BorderRadius.circular(10),
                                        ),
                                        child: Text(
                                          '${note.blocks.length} mục Khái niệm & Ghi chú • Chạm để xem chi tiết',
                                          style: const TextStyle(
                                            fontSize: 11.5,
                                            fontWeight: FontWeight.w800,
                                            color: ChibiTheme.deepPink,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Column(
                                  children: [
                                    IconButton(
                                      onPressed: () => _openCreateOrEditNote(
                                          existing: note),
                                      icon: const Icon(
                                        Icons.edit_outlined,
                                        color: ChibiTheme.deepPink,
                                        size: 20,
                                      ),
                                      tooltip: 'Chỉnh sửa',
                                    ),
                                    IconButton(
                                      onPressed: () =>
                                          _confirmDeleteNote(note),
                                      icon: const Icon(
                                        Icons.delete_outline_rounded,
                                        color: ChibiTheme.textMuted,
                                        size: 20,
                                      ),
                                      tooltip: 'Xóa',
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

/// Màn hình XEM CHI TIẾT GHI CHÚ:
/// Gộp các phần Khái niệm và Ghi chú thành một trang tài liệu liền mạch, sạch đẹp,
/// có highlight màu Đỏ / Xanh lá / Xanh dương và chữ nghiêng trong ngoặc đơn giống hệt hình mẫu.
class NoteDetailScreen extends StatefulWidget {
  final StudyNoteItem note;
  final ValueChanged<List<StudyNoteItem>> onNoteUpdated;

  const NoteDetailScreen({
    super.key,
    required this.note,
    required this.onNoteUpdated,
  });

  @override
  State<NoteDetailScreen> createState() => _NoteDetailScreenState();
}

class _NoteDetailScreenState extends State<NoteDetailScreen> {
  late StudyNoteItem _currentNote;

  @override
  void initState() {
    super.initState();
    _currentNote = widget.note;
  }

  Future<void> _editCurrentNote() async {
    final edited = await Navigator.of(context).push<StudyNoteItem>(
      MaterialPageRoute(
        builder: (_) => NoteEditorScreen(existingNote: _currentNote),
      ),
    );

    if (edited != null) {
      final updatedList = await NoteStorageService.upsertNote(edited);
      widget.onNoteUpdated(updatedList);
      if (!mounted) return;
      setState(() {
        _currentNote = edited;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        title: const Text('Chi Tiết Ghi Chú'),
        actions: [
          TextButton.icon(
            onPressed: _editCurrentNote,
            icon: const Icon(Icons.edit_rounded,
                size: 18, color: ChibiTheme.deepPink),
            label: const Text(
              'Chỉnh sửa',
              style: TextStyle(
                fontWeight: FontWeight.w900,
                color: ChibiTheme.deepPink,
              ),
            ),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 48),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 1. Tiêu đề chính in hoa giống hình mẫu: "THÀNH PHẦN CÂU TRONG TIẾNG ANH"
            Text(
              _currentNote.title.toUpperCase(),
              style: const TextStyle(
                fontSize: 21,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.3,
                color: Color(0xFF1A1A1A),
              ),
            ),

            // 2. Dòng khái niệm bao quát in nghiêng giống hình mẫu: "* Khái niệm bao quát: Vị trí, bản chất, chức năng"
            if (_currentNote.subtitle.trim().isNotEmpty) ...[
              const SizedBox(height: 18),
              Text(
                _currentNote.subtitle.trim().startsWith('*')
                    ? _currentNote.subtitle.trim()
                    : '* ${_currentNote.subtitle.trim()}',
                style: const TextStyle(
                  fontSize: 16.5,
                  fontStyle: FontStyle.italic,
                  fontWeight: FontWeight.w500,
                  color: Color(0xFF2B2B2B),
                ),
              ),
            ],

            const SizedBox(height: 24),

            // 3. Gộp từng cặp (Khái niệm + Ghi chú) liền mạch theo đúng bố cục hình mẫu
            ..._currentNote.blocks.map((block) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 30),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Khối KHÁI NIỆM (Chữ lớn 18.5, từ khóa highlight màu Đỏ / Xanh lá)
                    if (block.conceptText.trim().isNotEmpty)
                      RichText(
                        text: NoteRichTextFormatter.buildConceptSpan(
                          block.conceptText.trim(),
                        ),
                      ),

                    // Khoảng cách giữa Khái niệm và Ghi chú bên dưới
                    if (block.conceptText.trim().isNotEmpty &&
                        block.noteText.trim().isNotEmpty)
                      const SizedBox(height: 18),

                    // Khối GHI CHÚ (Chữ vừa 15.5, dòng * tiêu đề phụ & chữ trong ngoặc (...) tự động in nghiêng + highlight màu)
                    if (block.noteText.trim().isNotEmpty)
                      NoteRichTextFormatter.buildNoteFormattedWidget(
                        block.noteText.trim(),
                      ),
                  ],
                ),
              );
            }),
          ],
        ),
      ),
    );
  }
}

/// Màn hình NHẬP / CHỈNH SỬA GHI CHÚ:
/// Phần "Khái niệm" và "Ghi chú" được tách thành 2 ô nhập riêng biệt,
/// kèm thanh công cụ bôi màu Highlight (Đỏ, Xanh lá, Xanh dương, Cam, In nghiêng) chỉ với 1 chạm.
class _BlockControllers {
  final String id;
  final TextEditingController conceptCtrl;
  final TextEditingController noteCtrl;

  _BlockControllers({
    required this.id,
    required String concept,
    required String note,
  })  : conceptCtrl = TextEditingController(text: concept),
        noteCtrl = TextEditingController(text: note);

  void dispose() {
    conceptCtrl.dispose();
    noteCtrl.dispose();
  }
}

class NoteEditorScreen extends StatefulWidget {
  final StudyNoteItem? existingNote;

  const NoteEditorScreen({
    super.key,
    this.existingNote,
  });

  @override
  State<NoteEditorScreen> createState() => _NoteEditorScreenState();
}

class _NoteEditorScreenState extends State<NoteEditorScreen> {
  late TextEditingController _titleController;
  late TextEditingController _subtitleController;
  final List<_BlockControllers> _blockCtrls = [];

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(
      text: widget.existingNote?.title ?? '',
    );
    _subtitleController = TextEditingController(
      text: widget.existingNote?.subtitle ?? '',
    );

    if (widget.existingNote != null &&
        widget.existingNote!.blocks.isNotEmpty) {
      for (final b in widget.existingNote!.blocks) {
        _blockCtrls.add(
          _BlockControllers(
            id: b.id,
            concept: b.conceptText,
            note: b.noteText,
          ),
        );
      }
    } else {
      _addEmptyBlock();
    }
  }

  void _addEmptyBlock() {
    setState(() {
      _blockCtrls.add(
        _BlockControllers(
          id: DateTime.now().microsecondsSinceEpoch.toString(),
          concept: '',
          note: '',
        ),
      );
    });
  }

  void _removeBlock(int index) {
    if (_blockCtrls.length <= 1) return;
    setState(() {
      final removed = _blockCtrls.removeAt(index);
      removed.dispose();
    });
  }

  @override
  void dispose() {
    _titleController.dispose();
    _subtitleController.dispose();
    for (final b in _blockCtrls) {
      b.dispose();
    }
    super.dispose();
  }

  /// Chèn thẻ highlight màu sắc `[r]...[/r]`, `[g]...[/g]`, `[b]...[/b]` vào đoạn văn bản đang bôi đen
  /// (hoặc chèn tại vị trí con trỏ nếu chưa bôi đen)
  void _applyHighlightTag(TextEditingController controller, String tag) {
    final text = controller.text;
    final selection = controller.selection;
    final openTag = '[$tag]';
    final closeTag = '[/$tag]';

    if (selection.isValid && !selection.isCollapsed) {
      final selectedText = text.substring(selection.start, selection.end);
      final replacement = '$openTag$selectedText$closeTag';
      final newText =
          text.replaceRange(selection.start, selection.end, replacement);
      controller.value = TextEditingValue(
        text: newText,
        selection: TextSelection.collapsed(
          offset: selection.start + replacement.length,
        ),
      );
    } else {
      final cursor = selection.isValid ? selection.baseOffset : text.length;
      const sample = 'từ khóa';
      final insert = '$openTag$sample$closeTag';
      final newText = text.replaceRange(cursor, cursor, insert);
      controller.value = TextEditingValue(
        text: newText,
        selection: TextSelection(
          baseOffset: cursor + openTag.length,
          extentOffset: cursor + openTag.length + sample.length,
        ),
      );
    }
    setState(() {});
  }

  void _saveNote() {
    final title = _titleController.text.trim();
    if (title.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: ChibiTheme.deepPink,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          content: const Text(
            'Bạn hãy nhập Tiêu đề bài ghi chú nhé!',
            style: TextStyle(fontWeight: FontWeight.w800),
          ),
        ),
      );
      return;
    }

    final blocks = _blockCtrls
        .where((b) =>
            b.conceptCtrl.text.trim().isNotEmpty ||
            b.noteCtrl.text.trim().isNotEmpty)
        .map(
          (b) => NoteConceptBlock(
            id: b.id,
            conceptText: b.conceptCtrl.text.trim(),
            noteText: b.noteCtrl.text.trim(),
          ),
        )
        .toList();

    if (blocks.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: ChibiTheme.deepPink,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          content: const Text(
            'Bạn hãy nhập ít nhất 1 mục Khái niệm hoặc Ghi chú nhé!',
            style: TextStyle(fontWeight: FontWeight.w800),
          ),
        ),
      );
      return;
    }

    final noteItem = StudyNoteItem(
      id: widget.existingNote?.id ??
          DateTime.now().millisecondsSinceEpoch.toString(),
      title: title,
      subtitle: _subtitleController.text.trim(),
      blocks: blocks,
      updatedAt: DateTime.now(),
    );

    Navigator.of(context).pop(noteItem);
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.existingNote != null;
    return Scaffold(
      backgroundColor: ChibiTheme.bgCream,
      appBar: AppBar(
        title: Text(isEditing ? 'Chỉnh Sửa Ghi Chú' : 'Tạo Ghi Chú Mới'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: ElevatedButton.icon(
              onPressed: _saveNote,
              style: ElevatedButton.styleFrom(
                backgroundColor: ChibiTheme.deepPink,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              icon: const Icon(Icons.check_rounded, size: 18),
              label: const Text(
                'Lưu',
                style: TextStyle(fontWeight: FontWeight.w900),
              ),
            ),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(18, 10, 18, 40),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Khung nhập Tiêu đề & Khái niệm bao quát
            Container(
              padding: const EdgeInsets.all(16),
              decoration: ChibiTheme.kawaiiCardDecoration(
                color: Colors.white,
                borderColor: ChibiTheme.softPink,
                radius: 24,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Tiêu đề bài học:',
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w900,
                      color: ChibiTheme.deepPink,
                    ),
                  ),
                  const SizedBox(height: 6),
                  TextField(
                    controller: _titleController,
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w900,
                    ),
                    decoration: InputDecoration(
                      hintText: 'VD: THÀNH PHẦN CÂU TRONG TIẾNG ANH',
                      filled: true,
                      fillColor: ChibiTheme.bgCream,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Mô tả / Khái niệm bao quát (Tùy chọn):',
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w800,
                      color: ChibiTheme.textMuted,
                    ),
                  ),
                  const SizedBox(height: 6),
                  TextField(
                    controller: _subtitleController,
                    style: const TextStyle(
                      fontSize: 14.5,
                      fontStyle: FontStyle.italic,
                      fontWeight: FontWeight.w600,
                    ),
                    decoration: InputDecoration(
                      hintText:
                          'VD: * Khái niệm bao quát: Vị trí, bản chất, chức năng',
                      filled: true,
                      fillColor: ChibiTheme.bgCream,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),

            // Hướng dẫn bôi màu
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: ChibiTheme.softLavender,
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Row(
                children: [
                  Icon(Icons.palette_rounded,
                      color: ChibiTheme.deepPink, size: 20),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Mẹo: Bôi đen từ bất kỳ trong ô Khái niệm hoặc ô Ghi chú rồi bấm nút màu (Đỏ, Xanh lá, Xanh dương) để highlight. Các chữ trong ngoặc đơn (...) sẽ tự động in nghiêng khi xem chi tiết!',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: ChibiTheme.textDark,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),

            // Danh sách các cặp (Ô Khái niệm tách riêng + Ô Ghi chú tách riêng)
            ...List.generate(_blockCtrls.length, (index) {
              final block = _blockCtrls[index];
              return Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: ChibiTheme.kawaiiCardDecoration(
                    color: Colors.white,
                    borderColor: ChibiTheme.pastelLavender,
                    radius: 24,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 5),
                            decoration: BoxDecoration(
                              color: ChibiTheme.softPink,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              'Mục #${index + 1}',
                              style: const TextStyle(
                                fontWeight: FontWeight.w900,
                                color: ChibiTheme.deepPink,
                              ),
                            ),
                          ),
                          if (_blockCtrls.length > 1)
                            TextButton.icon(
                              onPressed: () => _removeBlock(index),
                              icon: const Icon(Icons.delete_outline_rounded,
                                  color: Colors.redAccent, size: 18),
                              label: const Text(
                                'Xóa mục này',
                                style: TextStyle(
                                  color: Colors.redAccent,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 12.5,
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 12),

                      // Ô 1: KHÁI NIỆM (Nhập tách riêng)
                      const Text(
                        '1. Phần Khái niệm (Nhập riêng):',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w900,
                          color: ChibiTheme.textDark,
                        ),
                      ),
                      const SizedBox(height: 6),
                      _buildColorToolbar(block.conceptCtrl),
                      const SizedBox(height: 6),
                      TextField(
                        controller: block.conceptCtrl,
                        maxLines: 4,
                        onChanged: (_) => setState(() {}),
                        style: const TextStyle(
                          fontSize: 15.5,
                          fontWeight: FontWeight.w600,
                        ),
                        decoration: InputDecoration(
                          hintText:
                              'VD: [r]Chủ ngữ[/r] là những từ thường đứng trước động từ, quyết định [r]chia động từ[/r] đó hay không...',
                          filled: true,
                          fillColor: ChibiTheme.bgCream,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                            borderSide: BorderSide.none,
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Ô 2: GHI CHÚ (Nhập tách riêng)
                      const Text(
                        '2. Phần Ghi chú chi tiết (Nhập riêng):',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w900,
                          color: ChibiTheme.textDark,
                        ),
                      ),
                      const SizedBox(height: 6),
                      _buildColorToolbar(block.noteCtrl),
                      const SizedBox(height: 6),
                      TextField(
                        controller: block.noteCtrl,
                        maxLines: 6,
                        onChanged: (_) => setState(() {}),
                        style: const TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w600,
                        ),
                        decoration: InputDecoration(
                          hintText: '* Từ loại đóng vai trò chủ ngữ:\n'
                              'Danh từ / Cụm danh từ (Noun / Noun Phrase)\n'
                              'The + Tính từ ([r]chỉ nhóm người[/r]: the rich, the poor...)',
                          filled: true,
                          fillColor: ChibiTheme.bgCream,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                            borderSide: BorderSide.none,
                          ),
                        ),
                      ),

                      // Xem trước trực tiếp khi gộp Khái niệm + Ghi chú
                      if (block.conceptCtrl.text.trim().isNotEmpty ||
                          block.noteCtrl.text.trim().isNotEmpty) ...[
                        const Divider(height: 24, color: ChibiTheme.softPink),
                        const Text(
                          'Xem trước khi gộp (Chi tiết):',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            color: ChibiTheme.textMuted,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: ChibiTheme.softPink),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (block.conceptCtrl.text.trim().isNotEmpty)
                                RichText(
                                  text: NoteRichTextFormatter.buildConceptSpan(
                                    block.conceptCtrl.text.trim(),
                                  ),
                                ),
                              if (block.conceptCtrl.text.trim().isNotEmpty &&
                                  block.noteCtrl.text.trim().isNotEmpty)
                                const SizedBox(height: 12),
                              if (block.noteCtrl.text.trim().isNotEmpty)
                                NoteRichTextFormatter.buildNoteFormattedWidget(
                                  block.noteCtrl.text.trim(),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              );
            }),

            OutlinedButton.icon(
              onPressed: _addEmptyBlock,
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
                side:
                    const BorderSide(color: ChibiTheme.deepPink, width: 2),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
              ),
              icon: const Icon(Icons.add_circle_outline_rounded,
                  color: ChibiTheme.deepPink),
              label: const Text(
                'Thêm cặp Khái niệm & Ghi chú tiếp theo',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w900,
                  color: ChibiTheme.deepPink,
                ),
              ),
            ),
            const SizedBox(height: 14),
            ElevatedButton.icon(
              onPressed: _saveNote,
              style: ElevatedButton.styleFrom(
                backgroundColor: ChibiTheme.deepPink,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
              ),
              icon: const Icon(Icons.save_rounded),
              label: const Text(
                'Lưu bài ghi chú',
                style: TextStyle(
                  fontSize: 16.5,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildColorToolbar(TextEditingController controller) {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        _buildColorChip(
          label: 'Chữ Đỏ',
          color: NoteRichTextFormatter.highlightRed,
          onTap: () => _applyHighlightTag(controller, 'r'),
        ),
        _buildColorChip(
          label: 'Chữ Xanh lá',
          color: NoteRichTextFormatter.highlightGreen,
          onTap: () => _applyHighlightTag(controller, 'g'),
        ),
        _buildColorChip(
          label: 'Chữ Xanh dương',
          color: NoteRichTextFormatter.highlightBlue,
          onTap: () => _applyHighlightTag(controller, 'b'),
        ),
        _buildColorChip(
          label: 'Chữ Cam',
          color: NoteRichTextFormatter.highlightOrange,
          onTap: () => _applyHighlightTag(controller, 'o'),
        ),
        _buildColorChip(
          label: 'In nghiêng',
          color: ChibiTheme.textMuted,
          onTap: () => _applyHighlightTag(controller, 'i'),
        ),
      ],
    );
  }

  Widget _buildColorChip({
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.5)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 5),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
