import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models/note_model.dart';
import '../services/note_storage_service.dart';
import '../theme/chibi_theme.dart';

/// Lưu thông tin một vùng văn bản được tô màu hoặc in nghiêng theo chỉ số ký tự [start, end)
class StyledRange {
  int start;
  int end;
  final String tag; // 'r' (Đỏ), 'g' (Xanh lá), 'b' (Xanh dương), 'o' (Cam), 'i' (Nghiêng)

  StyledRange({
    required this.start,
    required this.end,
    required this.tag,
  });
}

/// Bộ điều khiển ô nhập văn bản WYSIWYG:
/// - Hiển thị văn bản thuần túy (KHÔNG có ký tự `[r]`, `[/r]` trong ô nhập).
/// - Khi người dùng bôi đen chữ hoặc chọn màu rồi gõ, chữ trong ô nhập hiển thị màu Đỏ / Xanh lá / Xanh dương / Cam / Nghiêng ngay lập tức!
class RichHighlightTextController extends TextEditingController {
  final List<StyledRange> ranges = [];
  String? activeTypingTag; // Nếu người dùng bấm nút màu khi chưa bôi đen -> gõ chữ mới sẽ mang màu này
  String _previousText = '';

  RichHighlightTextController({String? initialTaggedText}) {
    if (initialTaggedText != null && initialTaggedText.isNotEmpty) {
      loadFromTaggedString(initialTaggedText);
    }
    addListener(_onTextChanged);
  }

  @override
  void dispose() {
    removeListener(_onTextChanged);
    super.dispose();
  }

  /// Chuyển chuỗi có thẻ lưu trữ (VD: `[r]Chủ ngữ[/r] là...`) thành chữ thuần + danh sách vùng màu `ranges`
  void loadFromTaggedString(String tagged) {
    ranges.clear();
    final buffer = StringBuffer();
    final tagRegex = RegExp(r'\[(r|g|b|o|i)\](.*?)\[/\1\]', dotAll: true);
    int lastEnd = 0;

    for (final match in tagRegex.allMatches(tagged)) {
      if (match.start > lastEnd) {
        buffer.write(tagged.substring(lastEnd, match.start));
      }
      final tag = match.group(1)!;
      final content = match.group(2) ?? '';
      final startIdx = buffer.length;
      buffer.write(content);
      final endIdx = buffer.length;
      if (endIdx > startIdx) {
        ranges.add(StyledRange(start: startIdx, end: endIdx, tag: tag));
      }
      lastEnd = match.end;
    }

    if (lastEnd < tagged.length) {
      buffer.write(tagged.substring(lastEnd));
    }

    final clean = buffer.toString();
    _previousText = clean;
    value = TextEditingValue(
      text: clean,
      selection: TextSelection.collapsed(offset: clean.length),
    );
  }

  /// Xuất ngược ra chuỗi có thẻ `[r]...[/r]` để lưu vào bộ nhớ
  String toTaggedString() {
    if (text.isEmpty) return '';
    if (ranges.isEmpty) return text;

    final sorted = List<StyledRange>.from(ranges)
      ..removeWhere((r) => r.end <= r.start || r.start >= text.length)
      ..sort((a, b) => a.start.compareTo(b.start));

    final buffer = StringBuffer();
    int cursor = 0;

    for (final r in sorted) {
      final s = r.start.clamp(0, text.length);
      final e = r.end.clamp(0, text.length);
      if (e <= s || s < cursor) continue;

      if (s > cursor) {
        buffer.write(text.substring(cursor, s));
      }
      buffer.write('[${r.tag}]${text.substring(s, e)}[/${r.tag}]');
      cursor = e;
    }

    if (cursor < text.length) {
      buffer.write(text.substring(cursor));
    }
    return buffer.toString();
  }

  void _onTextChanged() {
    final newText = text;
    if (newText == _previousText) return;

    final oldLen = _previousText.length;
    final newLen = newText.length;
    final delta = newLen - oldLen;

    // Tìm vị trí đầu tiên thay đổi giữa chuỗi cũ và chuỗi mới
    int changePos = 0;
    final minLen = math.min(oldLen, newLen);
    while (changePos < minLen &&
        _previousText.codeUnitAt(changePos) == newText.codeUnitAt(changePos)) {
      changePos++;
    }

    // Dịch chuyển các vùng màu phía sau vị trí gõ/xóa
    for (final r in ranges) {
      if (delta > 0) {
        // Người dùng vừa gõ thêm chữ
        if (changePos <= r.start) {
          r.start += delta;
          r.end += delta;
        } else if (changePos < r.end) {
          r.end += delta;
        }
      } else if (delta < 0) {
        // Người dùng vừa xóa chữ
        final delStart = changePos;
        final delEnd = changePos - delta;
        if (delEnd <= r.start) {
          r.start += delta;
          r.end += delta;
        } else if (delStart >= r.end) {
          // Không ảnh hưởng
        } else {
          // Xóa đè vào vùng màu
          if (delStart <= r.start && delEnd >= r.end) {
            r.start = delStart;
            r.end = delStart;
          } else if (delStart <= r.start && delEnd < r.end) {
            r.start = delStart;
            r.end += delta;
          } else if (delStart > r.start && delEnd >= r.end) {
            r.end = delStart;
          } else {
            r.end += delta;
          }
        }
      }
    }

    // Nếu người dùng đang bật chế độ màu (activeTypingTag != null) và vừa gõ thêm chữ -> tô màu luôn chữ vừa gõ
    if (delta > 0 && activeTypingTag != null) {
      final insStart = changePos;
      final insEnd = changePos + delta;
      _applyTagToRange(insStart, insEnd, activeTypingTag!);
    }

    ranges.removeWhere((r) => r.end <= r.start);
    _mergeAdjacentSameTagRanges();
    _previousText = newText;
  }

  void _mergeAdjacentSameTagRanges() {
    if (ranges.length <= 1) return;
    ranges.sort((a, b) => a.start.compareTo(b.start));
    final List<StyledRange> merged = [ranges.first];
    for (int i = 1; i < ranges.length; i++) {
      final prev = merged.last;
      final curr = ranges[i];
      if (curr.tag == prev.tag && curr.start <= prev.end) {
        prev.end = math.max(prev.end, curr.end);
      } else {
        merged.add(curr);
      }
    }
    ranges
      ..clear()
      ..addAll(merged);
  }

  void _applyTagToRange(int selStart, int selEnd, String? tag) {
    if (selEnd <= selStart) return;
    final List<StyledRange> updated = [];

    for (final r in ranges) {
      if (r.end <= selStart || r.start >= selEnd) {
        updated.add(r);
      } else {
        if (r.start < selStart) {
          updated.add(StyledRange(start: r.start, end: selStart, tag: r.tag));
        }
        if (r.end > selEnd) {
          updated.add(StyledRange(start: selEnd, end: r.end, tag: r.tag));
        }
      }
    }

    if (tag != null) {
      updated.add(StyledRange(start: selStart, end: selEnd, tag: tag));
    }

    ranges
      ..clear()
      ..addAll(updated);
    _mergeAdjacentSameTagRanges();
  }

  /// Khi bấm vào 1 nút màu trên thanh công cụ:
  /// - Nếu đang bôi đen chữ: Tô màu ngay đoạn chữ đó (hoặc bỏ màu nếu bấm lại cùng màu).
  /// - Nếu không bôi đen chữ: Bật/tắt màu đó để gõ chữ tiếp theo ra đúng màu đó luôn.
  void toggleStyleTag(String? tag) {
    final sel = selection;
    if (sel.isValid && !sel.isCollapsed) {
      final s = math.min(sel.start, sel.end);
      final e = math.max(sel.start, sel.end);

      // Kiểm tra nếu đoạn đang bôi đen đã mang sẵn màu này rồi thì gỡ màu về mặc định
      final alreadyHasSameTag =
          ranges.any((r) => r.tag == tag && r.start <= s && r.end >= e);
      _applyTagToRange(s, e, alreadyHasSameTag ? null : tag);
      activeTypingTag = tag;
      notifyListeners();
    } else {
      activeTypingTag = (activeTypingTag == tag) ? null : tag;
      notifyListeners();
    }
  }

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    final baseStyle = style ?? const TextStyle();
    if (text.isEmpty || ranges.isEmpty) {
      return TextSpan(text: text, style: baseStyle);
    }

    final sorted = List<StyledRange>.from(ranges)
      ..removeWhere((r) => r.end <= r.start || r.start >= text.length)
      ..sort((a, b) => a.start.compareTo(b.start));

    final List<InlineSpan> children = [];
    int cursor = 0;

    for (final r in sorted) {
      final s = r.start.clamp(0, text.length);
      final e = r.end.clamp(0, text.length);
      if (e <= s || s < cursor) continue;

      if (s > cursor) {
        children.add(
          TextSpan(
            text: text.substring(cursor, s),
            style: baseStyle,
          ),
        );
      }

      children.add(
        TextSpan(
          text: text.substring(s, e),
          style: NoteRichTextFormatter.applyTagStyle(baseStyle, r.tag),
        ),
      );
      cursor = e;
    }

    if (cursor < text.length) {
      children.add(
        TextSpan(
          text: text.substring(cursor),
          style: baseStyle,
        ),
      );
    }

    return TextSpan(style: baseStyle, children: children);
  }
}

class NoteRichTextFormatter {
  static const Color highlightRed = Color(0xFFC92A2A);
  static const Color highlightGreen = Color(0xFF2B8A3E);
  static const Color highlightBlue = Color(0xFF1D64C8);
  static const Color highlightOrange = Color(0xFFD9480F);

  static String stripTags(String input) {
    return input.replaceAll(RegExp(r'\[/?(r|g|b|o|i)\]'), '');
  }

  static TextStyle applyTagStyle(TextStyle base, String tag,
      {bool bold = true}) {
    switch (tag) {
      case 'r':
        return base.copyWith(
          color: highlightRed,
          fontWeight: bold ? FontWeight.w700 : base.fontWeight,
        );
      case 'g':
        return base.copyWith(
          color: highlightGreen,
          fontWeight: bold ? FontWeight.w700 : base.fontWeight,
        );
      case 'b':
        return base.copyWith(
          color: highlightBlue,
          fontWeight: bold ? FontWeight.w700 : base.fontWeight,
        );
      case 'o':
        return base.copyWith(
          color: highlightOrange,
          fontWeight: bold ? FontWeight.w700 : base.fontWeight,
        );
      case 'i':
        return base.copyWith(fontStyle: FontStyle.italic);
      default:
        return base;
    }
  }

  static TextSpan buildConceptSpan(String rawText) {
    final baseStyle = GoogleFonts.comfortaa(
      fontSize: 18,
      height: 1.5,
      fontWeight: FontWeight.w500,
      color: const Color(0xFF222222),
    );
    return TextSpan(
      style: baseStyle,
      children: _parseTaggedSpans(rawText, baseStyle, isConcept: true),
    );
  }

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
        final lineBaseStyle = GoogleFonts.comfortaa(
          fontSize: 15,
          height: 1.55,
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
      spans.add(
        TextSpan(
          text: content,
          style: applyTagStyle(currentStyle, tag, bold: isConcept),
        ),
      );
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
          'Xóa ghi chú này?',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
        content: Text('Bạn có muốn xóa "${note.title}" không?'),
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
        icon: const Icon(Icons.add_rounded),
        label: const Text(
          'Tạo ghi chú',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
      ),
      body: _notes.isEmpty
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
                        Icons.edit_note_rounded,
                        size: 52,
                        color: ChibiTheme.deepPink,
                      ),
                      SizedBox(height: 10),
                      Text(
                        'Chưa có ghi chú nào',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.fromLTRB(18, 10, 18, 96),
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
                            width: 44,
                            height: 44,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: ChibiTheme.softPink,
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: const Icon(
                              Icons.article_rounded,
                              color: ChibiTheme.deepPink,
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
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
                                  const SizedBox(height: 5),
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
                              ],
                            ),
                          ),
                          IconButton(
                            onPressed: () =>
                                _openCreateOrEditNote(existing: note),
                            icon: const Icon(
                              Icons.edit_outlined,
                              color: ChibiTheme.deepPink,
                              size: 20,
                            ),
                          ),
                          IconButton(
                            onPressed: () => _confirmDeleteNote(note),
                            icon: const Icon(
                              Icons.delete_outline_rounded,
                              color: ChibiTheme.textMuted,
                              size: 20,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
    );
  }
}

/// Màn hình XEM CHI TIẾT GHI CHÚ (Gộp Khái niệm & Ghi chú giống hệt hình mẫu)
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
              'Sửa',
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
            Text(
              _currentNote.title.toUpperCase(),
              style: GoogleFonts.comfortaa(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.3,
                color: const Color(0xFF1A1A1A),
              ),
            ),
            if (_currentNote.subtitle.trim().isNotEmpty) ...[
              const SizedBox(height: 18),
              Text(
                _currentNote.subtitle.trim().startsWith('*')
                    ? _currentNote.subtitle.trim()
                    : '* ${_currentNote.subtitle.trim()}',
                style: GoogleFonts.comfortaa(
                  fontSize: 16,
                  fontStyle: FontStyle.italic,
                  fontWeight: FontWeight.w500,
                  color: const Color(0xFF2B2B2B),
                ),
              ),
            ],
            const SizedBox(height: 24),
            ..._currentNote.blocks.map((block) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 30),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (block.conceptText.trim().isNotEmpty)
                      RichText(
                        text: NoteRichTextFormatter.buildConceptSpan(
                          block.conceptText.trim(),
                        ),
                      ),
                    if (block.conceptText.trim().isNotEmpty &&
                        block.noteText.trim().isNotEmpty)
                      const SizedBox(height: 18),
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

/// Bộ điều khiển 1 cặp (Khái niệm + Ghi chú) dùng RichHighlightTextController (hiển thị màu trực tiếp, không hiện [r])
class _BlockControllers {
  final String id;
  final RichHighlightTextController conceptCtrl;
  final RichHighlightTextController noteCtrl;

  _BlockControllers({
    required this.id,
    required String concept,
    required String note,
  })  : conceptCtrl =
            RichHighlightTextController(initialTaggedText: concept),
        noteCtrl = RichHighlightTextController(initialTaggedText: note);

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
            'Vui lòng nhập tiêu đề!',
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
            conceptText: b.conceptCtrl.toTaggedString().trim(),
            noteText: b.noteCtrl.toTaggedString().trim(),
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
            'Vui lòng nhập nội dung Khái niệm hoặc Ghi chú!',
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
        title: Text(isEditing ? 'Sửa Ghi Chú' : 'Tạo Ghi Chú'),
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
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 36),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Khung Tiêu đề gọn gàng
            Container(
              padding: const EdgeInsets.all(14),
              decoration: ChibiTheme.kawaiiCardDecoration(
                color: Colors.white,
                borderColor: ChibiTheme.softPink,
                radius: 22,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: _titleController,
                    style: const TextStyle(
                      fontSize: 16.5,
                      fontWeight: FontWeight.w900,
                    ),
                    decoration: InputDecoration(
                      labelText: 'Tiêu đề',
                      hintText: 'Nhập tiêu đề...',
                      filled: true,
                      fillColor: ChibiTheme.bgCream,
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 12),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _subtitleController,
                    style: const TextStyle(
                      fontSize: 14,
                      fontStyle: FontStyle.italic,
                      fontWeight: FontWeight.w600,
                    ),
                    decoration: InputDecoration(
                      labelText: 'Mô tả ngắn (tùy chọn)',
                      hintText: 'Nhập mô tả...',
                      filled: true,
                      fillColor: ChibiTheme.bgCream,
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 10),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),

            // Các mục Khái niệm & Ghi chú gọn gàng, trực quan
            ...List.generate(_blockCtrls.length, (index) {
              final block = _blockCtrls[index];
              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: ChibiTheme.kawaiiCardDecoration(
                    color: Colors.white,
                    borderColor: ChibiTheme.pastelLavender,
                    radius: 22,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Mục #${index + 1}',
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w900,
                              color: ChibiTheme.deepPink,
                            ),
                          ),
                          if (_blockCtrls.length > 1)
                            IconButton(
                              onPressed: () => _removeBlock(index),
                              icon: const Icon(Icons.close_rounded,
                                  color: Colors.redAccent, size: 20),
                              visualDensity: VisualDensity.compact,
                              tooltip: 'Xóa mục',
                            ),
                        ],
                      ),
                      const SizedBox(height: 6),

                      // Ô 1: Khái niệm
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Khái niệm',
                            style: TextStyle(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w900,
                              color: ChibiTheme.textDark,
                            ),
                          ),
                          _buildColorToolbar(block.conceptCtrl),
                        ],
                      ),
                      const SizedBox(height: 6),
                      TextField(
                        controller: block.conceptCtrl,
                        maxLines: 3,
                        minLines: 2,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                          color: Color(0xFF222222),
                        ),
                        decoration: InputDecoration(
                          hintText: 'Nhập khái niệm...',
                          filled: true,
                          fillColor: ChibiTheme.bgCream,
                          contentPadding: const EdgeInsets.all(12),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: BorderSide.none,
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),

                      // Ô 2: Ghi chú
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Ghi chú',
                            style: TextStyle(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w900,
                              color: ChibiTheme.textDark,
                            ),
                          ),
                          _buildColorToolbar(block.noteCtrl),
                        ],
                      ),
                      const SizedBox(height: 6),
                      TextField(
                        controller: block.noteCtrl,
                        maxLines: 5,
                        minLines: 3,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w500,
                          color: Color(0xFF2B2B2B),
                        ),
                        decoration: InputDecoration(
                          hintText: 'Nhập ghi chú...',
                          filled: true,
                          fillColor: ChibiTheme.bgCream,
                          contentPadding: const EdgeInsets.all(12),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: BorderSide.none,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }),

            OutlinedButton.icon(
              onPressed: _addEmptyBlock,
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 12),
                side: const BorderSide(color: ChibiTheme.deepPink, width: 1.8),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18),
                ),
              ),
              icon: const Icon(Icons.add_rounded, color: ChibiTheme.deepPink),
              label: const Text(
                'Thêm mục',
                style: TextStyle(
                  fontSize: 14.5,
                  fontWeight: FontWeight.w900,
                  color: ChibiTheme.deepPink,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Thanh nút chọn màu nhỏ gọn: Bấm vào là chữ đang bôi đen (hoặc chữ gõ tiếp theo) đổi màu trực tiếp, không hiện ký tự [r]
  Widget _buildColorToolbar(RichHighlightTextController controller) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final active = controller.activeTypingTag;
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildColorDot(
              label: 'Đỏ',
              color: NoteRichTextFormatter.highlightRed,
              isSelected: active == 'r',
              onTap: () {
                controller.toggleStyleTag('r');
                setState(() {});
              },
            ),
            const SizedBox(width: 6),
            _buildColorDot(
              label: 'Xanh lá',
              color: NoteRichTextFormatter.highlightGreen,
              isSelected: active == 'g',
              onTap: () {
                controller.toggleStyleTag('g');
                setState(() {});
              },
            ),
            const SizedBox(width: 6),
            _buildColorDot(
              label: 'Xanh',
              color: NoteRichTextFormatter.highlightBlue,
              isSelected: active == 'b',
              onTap: () {
                controller.toggleStyleTag('b');
                setState(() {});
              },
            ),
            const SizedBox(width: 6),
            _buildColorDot(
              label: 'Cam',
              color: NoteRichTextFormatter.highlightOrange,
              isSelected: active == 'o',
              onTap: () {
                controller.toggleStyleTag('o');
                setState(() {});
              },
            ),
            const SizedBox(width: 6),
            _buildColorDot(
              label: 'Thường',
              color: ChibiTheme.textDark,
              isSelected: active == null,
              onTap: () {
                controller.toggleStyleTag(null);
                setState(() {});
              },
            ),
          ],
        );
      },
    );
  }

  Widget _buildColorDot({
    required String label,
    required Color color,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: isSelected ? color : color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: color,
            width: isSelected ? 1.8 : 1,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w800,
            color: isSelected ? Colors.white : color,
          ),
        ),
      ),
    );
  }
}
