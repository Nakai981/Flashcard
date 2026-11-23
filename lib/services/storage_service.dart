import 'package:shared_preferences/shared_preferences.dart';
import '../models/flashcard_model.dart';

class StorageService {
  static const String _storageKey = 'chibi_flashcards_v1';

  /// Tải toàn bộ danh sách Flashcard và đảm bảo đánh số thứ tự liên tục 1..N
  static Future<List<FlashcardItem>> loadFlashcards() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_storageKey);
    if (raw == null || raw.isEmpty) {
      return [];
    }
    try {
      final list = FlashcardItem.decodeList(raw);
      return _reindex(list);
    } catch (_) {
      return [];
    }
  }

  /// Lưu danh sách Flashcard xuống bộ nhớ máy (tự động chuẩn hóa lại STT 1..N)
  static Future<List<FlashcardItem>> saveFlashcards(
      List<FlashcardItem> items) async {
    final prefs = await SharedPreferences.getInstance();
    final reindexed = _reindex(items);
    await prefs.setString(_storageKey, FlashcardItem.encodeList(reindexed));
    return reindexed;
  }

  /// Thêm 1 Flashcard mới vào cuối danh sách
  static Future<List<FlashcardItem>> addFlashcard(
      FlashcardItem newItem) async {
    final current = await loadFlashcards();
    final itemWithOrder = newItem.copyWith(indexNumber: current.length + 1);
    current.add(itemWithOrder);
    return saveFlashcards(current);
  }

  /// Cập nhật trạng thái ôn tập / không nhớ của một thẻ Flashcard theo id
  static Future<List<FlashcardItem>> updateCardReviewStatus({
    required String cardId,
    bool? isReviewed,
    bool? isNotRemembered,
  }) async {
    final current = await loadFlashcards();
    final updated = current.map((item) {
      if (item.id == cardId) {
        return item.copyWith(
          isReviewed: isReviewed ?? item.isReviewed,
          isNotRemembered: isNotRemembered ?? item.isNotRemembered,
        );
      }
      return item;
    }).toList();
    return saveFlashcards(updated);
  }

  /// Xóa 1 Flashcard và cập nhật lại số thứ tự từ 1 đến N
  static Future<List<FlashcardItem>> deleteFlashcard(String id) async {
    final current = await loadFlashcards();
    current.removeWhere((item) => item.id == id);
    return saveFlashcards(current);
  }

  static List<FlashcardItem> _reindex(List<FlashcardItem> list) {
    final List<FlashcardItem> result = [];
    for (int i = 0; i < list.length; i++) {
      result.add(list[i].copyWith(indexNumber: i + 1));
    }
    return result;
  }
}
