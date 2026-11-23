import 'package:flutter/material.dart';
import '../models/flashcard_model.dart';
import '../services/audio_speech_service.dart';
import '../services/topic_vocab_service.dart';
import '../theme/chibi_theme.dart';

class AddFlashcardSheet extends StatefulWidget {
  final int nextIndexNumber;
  final ValueChanged<FlashcardItem> onCardAdded;

  const AddFlashcardSheet({
    super.key,
    required this.nextIndexNumber,
    required this.onCardAdded,
  });

  @override
  State<AddFlashcardSheet> createState() => _AddFlashcardSheetState();
}

class _AddFlashcardSheetState extends State<AddFlashcardSheet> {
  final TextEditingController _wordController = TextEditingController();
  bool _isLoading = false;
  String? _errorMessage;
  FlashcardItem? _previewCard;
  String? _sourceLabel;
  bool _fromLocalTopic = false;
  bool _showRawJson = false;
  List<TopicWordItem> _topicSuggestions = [];

  @override
  void dispose() {
    _wordController.dispose();
    super.dispose();
  }

  Future<void> _onSearchTextChanged(String value) async {
    final clean = value.trim();
    if (clean.isEmpty) {
      setState(() {
        _topicSuggestions = [];
      });
      return;
    }
    final matches =
        await TopicVocabService.searchWordsInTopics(clean, limit: 6);
    if (!mounted) return;
    setState(() {
      _topicSuggestions = matches;
    });
  }

  void _selectTopicSuggestion(TopicWordItem item) {
    _wordController.text = item.englishWord;
    setState(() {
      _previewCard =
          item.toFlashcardItem(indexNumber: widget.nextIndexNumber);
      _fromLocalTopic = true;
      _sourceLabel = 'Lấy từ Topic có sẵn (${item.topicName})';
      _topicSuggestions = [];
      _errorMessage = null;
    });
  }

  Future<void> _lookupWord() async {
    final text = _wordController.text.trim();
    if (text.isEmpty) {
      setState(() {
        _errorMessage = 'Bạn hãy nhập một từ tiếng Anh nhé!';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _topicSuggestions = [];
    });

    try {
      final result = await TopicVocabService.lookupWordPreferTopics(
        englishWord: text,
        indexNumber: widget.nextIndexNumber,
      );
      if (!mounted) return;
      setState(() {
        _previewCard = result.card;
        _fromLocalTopic = result.fromLocalTopic;
        _sourceLabel = result.sourceLabel;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = e.toString().replaceFirst('Exception: ', '');
        _isLoading = false;
      });
    }
  }

  void _confirmSave() {
    if (_previewCard == null) return;
    widget.onCardAdded(_previewCard!);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return Container(
      padding: EdgeInsets.fromLTRB(20, 16, 20, bottomInset + 24),
      decoration: const BoxDecoration(
        color: ChibiTheme.bgCream,
        borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 48,
                height: 5,
                decoration: BoxDecoration(
                  color: ChibiTheme.softPink,
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(18),
                  child: Image.asset(
                    'assets/images/chibi_study.jpg',
                    width: 60,
                    height: 60,
                    fit: BoxFit.cover,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 3),
                        decoration: BoxDecoration(
                          color: ChibiTheme.softPink,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          'Thẻ số #${widget.nextIndexNumber}',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            color: ChibiTheme.deepPink,
                          ),
                        ),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'Thêm Flashcard Mới 💎',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                          color: ChibiTheme.textDark,
                        ),
                      ),
                      const Text(
                        'Tìm trong Topic có sẵn (docs) trước, nếu chưa có sẽ tự động gọi Google Dịch',
                        style: TextStyle(
                          fontSize: 12.5,
                          color: ChibiTheme.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            Container(
              decoration: ChibiTheme.kawaiiCardDecoration(
                color: Colors.white,
                borderColor: ChibiTheme.softPink,
                radius: 22,
              ),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _wordController,
                      textInputAction: TextInputAction.search,
                      onChanged: _onSearchTextChanged,
                      onSubmitted: (_) => _lookupWord(),
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                      decoration: const InputDecoration(
                        hintText: 'Nhập từ tiếng Anh (VD: afraid, agree)...',
                        hintStyle: TextStyle(
                          fontSize: 14.5,
                          color: ChibiTheme.textMuted,
                        ),
                        border: InputBorder.none,
                      ),
                    ),
                  ),
                  ElevatedButton.icon(
                    onPressed: _isLoading ? null : _lookupWord,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: ChibiTheme.deepPink,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 10),
                    ),
                    icon: _isLoading
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.search_rounded, size: 18),
                    label: Text(
                      _isLoading ? 'Đang tìm...' : 'Tra từ',
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                ],
              ),
            ),

            // Gợi ý nhanh các từ có sẵn trong Topic khi đang gõ
            if (_topicSuggestions.isNotEmpty) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: ChibiTheme.softPink, width: 1.8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      child: Text(
                        'Gợi ý từ có sẵn trong Topic (Bấm để chọn nhanh):',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          color: ChibiTheme.textMuted,
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: _topicSuggestions.map((item) {
                        return ActionChip(
                          onPressed: () => _selectTopicSuggestion(item),
                          backgroundColor: ChibiTheme.softPink,
                          side: BorderSide.none,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                          label: Text(
                            '${item.englishWord} (${item.primaryVietnamese})',
                            style: const TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w800,
                              color: ChibiTheme.deepPink,
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ],
                ),
              ),
            ],

            if (_errorMessage != null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFE5EC),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.redAccent),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.error_outline_rounded,
                        color: Colors.redAccent),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _errorMessage!,
                        style: const TextStyle(
                          color: Colors.redAccent,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            if (_previewCard != null) ...[
              const SizedBox(height: 16),
              if (_sourceLabel != null)
                Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: _fromLocalTopic
                        ? const Color(0xFFE6F7EE)
                        : ChibiTheme.softPink,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        _fromLocalTopic
                            ? Icons.library_books_rounded
                            : Icons.cloud_download_rounded,
                        size: 18,
                        color: _fromLocalTopic
                            ? const Color(0xFF15803D)
                            : ChibiTheme.deepPink,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _sourceLabel!,
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w800,
                            color: _fromLocalTopic
                                ? const Color(0xFF15803D)
                                : ChibiTheme.deepPink,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              Container(
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
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _previewCard!.englishWord,
                                style: const TextStyle(
                                  fontSize: 22,
                                  fontWeight: FontWeight.w900,
                                  color: ChibiTheme.deepPink,
                                ),
                              ),
                              if (_previewCard!.phonetic.isNotEmpty)
                                Text(
                                  '/${_previewCard!.phonetic}/',
                                  style: const TextStyle(
                                    fontSize: 14,
                                    fontStyle: FontStyle.italic,
                                    color: ChibiTheme.textMuted,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                            ],
                          ),
                        ),
                        IconButton.filledTonal(
                          onPressed: () => AudioSpeechService.speakEnglishWord(
                              _previewCard!.englishWord),
                          style: IconButton.styleFrom(
                            backgroundColor: ChibiTheme.softPink,
                            foregroundColor: ChibiTheme.deepPink,
                          ),
                          icon: const Icon(Icons.volume_up_rounded),
                          tooltip: 'Nghe phát âm Google Dịch',
                        ),
                      ],
                    ),
                    const Divider(height: 20, color: ChibiTheme.softPink),
                    const Text(
                      'Nghĩa tiếng Việt:',
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: ChibiTheme.textMuted,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _previewCard!.primaryVietnamese,
                      style: const TextStyle(
                        fontSize: 19,
                        fontWeight: FontWeight.w800,
                        color: ChibiTheme.textDark,
                      ),
                    ),
                    if (_previewCard!.definitions.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      const Text(
                        'Giải thích / Định nghĩa:',
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          color: ChibiTheme.textMuted,
                        ),
                      ),
                      const SizedBox(height: 4),
                      ..._previewCard!.definitions.take(2).map(
                            (d) => Text(
                              d.gloss,
                              style: const TextStyle(
                                fontSize: 13.5,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                    ],
                    if (_previewCard!.wordTypes.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      const Text(
                        'Từ loại & Từ điển chi tiết:',
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          color: ChibiTheme.textMuted,
                        ),
                      ),
                      const SizedBox(height: 6),
                      ..._previewCard!.wordTypes.take(3).map(
                        (wt) => Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: ChibiTheme.bgCream,
                              borderRadius: BorderRadius.circular(14),
                              border:
                                  Border.all(color: ChibiTheme.softPink),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '• ${wt.pos.toUpperCase()}',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w900,
                                    color: ChibiTheme.deepPink,
                                  ),
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  wt.terms.join(', '),
                                  style: const TextStyle(
                                    fontSize: 13.5,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                if (wt.reverseTranslations.isNotEmpty) ...[
                                  const SizedBox(height: 4),
                                  Text(
                                    wt.reverseTranslations.take(4).join(' | '),
                                    style: const TextStyle(
                                      fontSize: 11.5,
                                      color: ChibiTheme.textMuted,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                    if (_previewCard!.examples.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      const Text(
                        'Câu ví dụ:',
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          color: ChibiTheme.textMuted,
                        ),
                      ),
                      const SizedBox(height: 4),
                      ..._previewCard!.examples.take(3).map(
                            (ex) => Padding(
                              padding: const EdgeInsets.only(bottom: 4),
                              child: Text(
                                '“$ex”',
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontStyle: FontStyle.italic,
                                ),
                              ),
                            ),
                          ),
                    ],
                    const SizedBox(height: 8),
                    TextButton.icon(
                      onPressed: () {
                        setState(() {
                          _showRawJson = !_showRawJson;
                        });
                      },
                      icon: Icon(
                        _showRawJson
                            ? Icons.expand_less_rounded
                            : Icons.data_object_rounded,
                        size: 18,
                      ),
                      label: Text(
                        _showRawJson
                            ? 'Ẩn toàn bộ dữ liệu chi tiết'
                            : 'Xem toàn bộ dữ liệu chi tiết đã lưu',
                        style: const TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    if (_showRawJson)
                      Container(
                        constraints: const BoxConstraints(maxHeight: 160),
                        width: double.infinity,
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: ChibiTheme.softLavender,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: SingleChildScrollView(
                          child: Text(
                            _previewCard!.rawGoogleResponseJson,
                            style: const TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 11,
                              color: ChibiTheme.textDark,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: _confirmSave,
                style: ElevatedButton.styleFrom(
                  backgroundColor: ChibiTheme.deepPink,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 15),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                ),
                icon: const Icon(Icons.bookmark_add_rounded),
                label: Text(
                  'Lưu vào Flashcard #${widget.nextIndexNumber}',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
