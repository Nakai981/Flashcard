import 'package:shared_preferences/shared_preferences.dart';
import '../models/note_model.dart';

class NoteStorageService {
  static const String _notesKey = 'chibi_study_notes_v1';
  static const String _seededKey = 'chibi_study_notes_seeded_v1';

  /// Khởi tạo bài ghi chú mẫu y hệt hình ảnh của người dùng ("THÀNH PHẦN CÂU TRONG TIẾNG ANH")
  /// để người dùng có thể xem trực tiếp ngay lần đầu mở tab Ghi chú.
  static StudyNoteItem _buildSampleNote() {
    return StudyNoteItem(
      id: 'sample_sentence_components',
      title: 'THÀNH PHẦN CÂU TRONG TIẾNG ANH',
      subtitle: '* Khái niệm bao quát: Vị trí, bản chất, chức năng',
      updatedAt: DateTime.now(),
      blocks: [
        NoteConceptBlock(
          id: 'block_subject',
          conceptText:
              '[r]Chủ ngữ[/r] là những từ thường đứng trước động từ, chỉ người, vật, sự việc và quyết định [r]chia động từ[/r] đó hay không (Ví dụ câu bị động chẳng hạn).',
          noteText: '* Từ loại đóng vai trò chủ ngữ:\n'
              'Danh từ / Cụm danh từ (Noun / Noun Phrase)\n'
              'Đại từ (Pronoun: I, you, he, she, it, we, they, everyone, this...)\n'
              'Danh động từ (V-ing)\n'
              'Động từ nguyên mẫu có "To" (To + V)\n'
              'Mệnh đề danh từ (What/That/Whether... + S + V)\n'
              'The + Tính từ ([r]chỉ nhóm người[/r]: the rich, the poor...)',
        ),
        NoteConceptBlock(
          id: 'block_verb',
          conceptText:
              '[g]Động từ[/g] là những từ biểu thị [r]hành động[/r] hay [r]trạng thái[/r] của chủ ngữ hoặc dùng để [r]bổ trợ[/r] ngữ pháp, thường đứng sau chủ ngữ.',
          noteText: '* Từ loại đóng vai trò động từ:\n'
              'Động từ / Trợ động từ + động từ:',
        ),
      ],
    );
  }

  static Future<List<StudyNoteItem>> loadNotes() async {
    final prefs = await SharedPreferences.getInstance();
    final isSeeded = prefs.getBool(_seededKey) ?? false;
    final raw = prefs.getString(_notesKey);

    if (!isSeeded && (raw == null || raw.isEmpty)) {
      final sampleList = [_buildSampleNote()];
      await prefs.setBool(_seededKey, true);
      await prefs.setString(_notesKey, StudyNoteItem.encodeList(sampleList));
      return sampleList;
    }

    if (raw == null || raw.isEmpty) {
      return [];
    }

    try {
      return StudyNoteItem.decodeList(raw);
    } catch (_) {
      return [];
    }
  }

  static Future<List<StudyNoteItem>> saveNotes(
      List<StudyNoteItem> notes) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_seededKey, true);
    await prefs.setString(_notesKey, StudyNoteItem.encodeList(notes));
    return notes;
  }

  static Future<List<StudyNoteItem>> upsertNote(StudyNoteItem note) async {
    final current = await loadNotes();
    final idx = current.indexWhere((n) => n.id == note.id);
    if (idx >= 0) {
      current[idx] = note;
    } else {
      current.insert(0, note);
    }
    return saveNotes(current);
  }

  static Future<List<StudyNoteItem>> deleteNote(String id) async {
    final current = await loadNotes();
    current.removeWhere((n) => n.id == id);
    return saveNotes(current);
  }
}
