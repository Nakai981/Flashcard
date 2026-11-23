import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/flashcard_model.dart';
import '../services/audio_speech_service.dart';
import '../services/topic_vocab_service.dart';
import '../theme/chibi_theme.dart';
import 'flashcard_study_screen.dart';

class TopicVocabScreen extends StatefulWidget {
  final List<FlashcardItem> userFlashcards;
  final ValueChanged<FlashcardItem> onAddWordToFlashcards;

  const TopicVocabScreen({
    super.key,
    required this.userFlashcards,
    required this.onAddWordToFlashcards,
  });

  @override
  State<TopicVocabScreen> createState() => _TopicVocabScreenState();
}

class _TopicVocabScreenState extends State<TopicVocabScreen> {
  static const String _skippedWordsPrefKey = 'chibi_topic_skipped_words_v1';

  List<VocabBookGroup> _books = [];
  bool _isLoading = true;
  // -1 = Hiển thị tất cả 150 Topic (3.000 từ) của cả 5 Tập; 0..4 = Lọc riêng từng Tập
  int _selectedBookFilter = -1;
  final TextEditingController _searchController = TextEditingController();
  List<TopicWordItem> _searchResults = [];
  bool _isSearching = false;
  Set<String> _skippedWords = {};

  @override
  void initState() {
    super.initState();
    _loadTopics();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadTopics() async {
    final prefs = await SharedPreferences.getInstance();
    final skippedList = prefs.getStringList(_skippedWordsPrefKey) ?? [];
    final books = await TopicVocabService.loadAllBooks();
    if (!mounted) return;
    setState(() {
      _skippedWords = skippedList.map((e) => e.toLowerCase()).toSet();
      _books = books;
      _isLoading = false;
    });
  }

  Future<void> _toggleSkipWord(String englishWord) async {
    final key = englishWord.trim().toLowerCase();
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      if (_skippedWords.contains(key)) {
        _skippedWords.remove(key);
      } else {
        _skippedWords.add(key);
      }
    });
    await prefs.setStringList(_skippedWordsPrefKey, _skippedWords.toList());
  }

  Future<void> _onSearchChanged(String query) async {
    final clean = query.trim();
    if (clean.isEmpty) {
      setState(() {
        _isSearching = false;
        _searchResults = [];
      });
      return;
    }
    final res = await TopicVocabService.searchWordsInTopics(clean, limit: 100);
    if (!mounted) return;
    setState(() {
      _isSearching = true;
      _searchResults = res;
    });
  }

  bool _isAlreadyInUserFlashcards(String englishWord) {
    final key = englishWord.trim().toLowerCase();
    return widget.userFlashcards
        .any((item) => item.englishWord.trim().toLowerCase() == key);
  }

  void _openTopicDetail(VocabTopicUnit topic) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => TopicUnitDetailScreen(
          topic: topic,
          userFlashcards: widget.userFlashcards,
          onAddWordToFlashcards: widget.onAddWordToFlashcards,
          skippedWords: _skippedWords,
          onToggleSkipWord: _toggleSkipWord,
        ),
      ),
    );
  }

  List<VocabTopicUnit> _getFilteredTopics() {
    if (_selectedBookFilter == -1) {
      return _books.expand((b) => b.topics).toList();
    }
    if (_selectedBookFilter >= 0 && _selectedBookFilter < _books.length) {
      return _books[_selectedBookFilter].topics;
    }
    return [];
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: ChibiTheme.pastelPink),
      );
    }

    if (_books.isEmpty) {
      return const Center(
        child: Text('Không tìm thấy dữ liệu Topic từ thư mục docs.'),
      );
    }

    final totalTopicsCount =
        _books.fold<int>(0, (sum, b) => sum + b.topics.length);
    final totalWordsCount =
        _books.fold<int>(0, (sum, b) => sum + b.totalWords);
    final displayedTopics = _getFilteredTopics();

    return Column(
      children: [
        // Thanh tìm kiếm từ vựng trong toàn bộ 150 Topic (3.000 từ)
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 8, 18, 8),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
            decoration: ChibiTheme.kawaiiCardDecoration(
              color: Colors.white,
              borderColor: ChibiTheme.softPink,
              radius: 22,
            ),
            child: TextField(
              controller: _searchController,
              onChanged: _onSearchChanged,
              decoration: InputDecoration(
                icon: const Icon(Icons.search_rounded,
                    color: ChibiTheme.deepPink),
                hintText:
                    'Tìm từ trong $totalTopicsCount Topic ($totalWordsCount từ vựng)...',
                hintStyle: const TextStyle(
                  fontSize: 13.5,
                  color: ChibiTheme.textMuted,
                ),
                border: InputBorder.none,
                suffixIcon: _isSearching
                    ? IconButton(
                        onPressed: () {
                          _searchController.clear();
                          _onSearchChanged('');
                        },
                        icon: const Icon(Icons.clear_rounded),
                      )
                    : null,
              ),
            ),
          ),
        ),

        if (_isSearching)
          Expanded(child: _buildSearchResultsView())
        else ...[
          // Thanh lọc: Tất cả (150 Topic - 3.000 từ) hoặc từng Tập 1..5
          SizedBox(
            height: 46,
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 18),
              scrollDirection: Axis.horizontal,
              itemCount: _books.length + 1,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (context, idx) {
                if (idx == 0) {
                  final isAllSelected = _selectedBookFilter == -1;
                  return ChoiceChip(
                    selected: isAllSelected,
                    onSelected: (_) {
                      setState(() {
                        _selectedBookFilter = -1;
                      });
                    },
                    selectedColor: ChibiTheme.deepPink,
                    backgroundColor: Colors.white,
                    side: const BorderSide(
                        color: ChibiTheme.softPink, width: 1.5),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18),
                    ),
                    label: Text(
                      'Tất cả ($totalTopicsCount Topic • $totalWordsCount từ)',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        color:
                            isAllSelected ? Colors.white : ChibiTheme.textDark,
                      ),
                    ),
                  );
                }

                final bookIdx = idx - 1;
                final book = _books[bookIdx];
                final isSelected = _selectedBookFilter == bookIdx;
                return ChoiceChip(
                  selected: isSelected,
                  onSelected: (_) {
                    setState(() {
                      _selectedBookFilter = bookIdx;
                    });
                  },
                  selectedColor: ChibiTheme.deepPink,
                  backgroundColor: Colors.white,
                  side:
                      const BorderSide(color: ChibiTheme.softPink, width: 1.5),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18),
                  ),
                  label: Text(
                    'Tập ${book.bookNumber} (${book.topics.length} Topic • ${book.totalWords} từ)',
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      color: isSelected ? Colors.white : ChibiTheme.textDark,
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 8),

          // Danh sách toàn bộ các Topic (150 Topic / 3.000 từ vựng nạp từ SQLite docs)
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.fromLTRB(18, 4, 18, 24),
              itemCount: displayedTopics.length,
              itemBuilder: (context, index) {
                final topic = displayedTopics[index];
                final sampleWords = topic.words
                    .take(5)
                    .map((w) => w.englishWord)
                    .join(', ');

                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(24),
                    onTap: () => _openTopicDetail(topic),
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
                        children: [
                          Container(
                            width: 54,
                            height: 54,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: ChibiTheme.softPink,
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  'Tập ${topic.bookNumber}',
                                  style: const TextStyle(
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.w800,
                                    color: ChibiTheme.textMuted,
                                  ),
                                ),
                                Text(
                                  '#${index + 1}',
                                  style: const TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w900,
                                    color: ChibiTheme.deepPink,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Tập ${topic.bookNumber} • ${topic.unitName}',
                                  style: const TextStyle(
                                    fontSize: 16.5,
                                    fontWeight: FontWeight.w900,
                                    color: ChibiTheme.textDark,
                                  ),
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  '${topic.words.length} từ vựng: $sampleWords...',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                    color: ChibiTheme.textMuted,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const Icon(
                            Icons.chevron_right_rounded,
                            color: ChibiTheme.deepPink,
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
      ],
    );
  }

  Widget _buildSearchResultsView() {
    if (_searchResults.isEmpty) {
      return const Center(
        child: Text(
          'Không tìm thấy từ này trong 3.000 từ của Topic.\nBạn có thể bấm "Thêm từ mới" ở tab Flashcard để tự động lấy từ Google Dịch!',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 14,
            color: ChibiTheme.textMuted,
            fontWeight: FontWeight.w700,
          ),
        ),
      );
    }

    // Sắp xếp đưa các từ đã bấm "Bỏ qua" xuống cuối danh sách tìm kiếm
    final sortedResults = List<TopicWordItem>.from(_searchResults)
      ..sort((a, b) {
        final aSkipped =
            _skippedWords.contains(a.englishWord.trim().toLowerCase());
        final bSkipped =
            _skippedWords.contains(b.englishWord.trim().toLowerCase());
        if (aSkipped != bSkipped) {
          return aSkipped ? 1 : -1;
        }
        return 0;
      });

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(18, 4, 18, 24),
      itemCount: sortedResults.length,
      itemBuilder: (context, index) {
        final word = sortedResults[index];
        final added = _isAlreadyInUserFlashcards(word.englishWord);
        final isSkipped =
            _skippedWords.contains(word.englishWord.trim().toLowerCase());

        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Opacity(
            opacity: isSkipped ? 0.55 : 1.0,
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: ChibiTheme.kawaiiCardDecoration(
                color: Colors.white,
                borderColor: ChibiTheme.softPink,
                radius: 22,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              word.englishWord,
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w900,
                                color: ChibiTheme.deepPink,
                                decoration: isSkipped
                                    ? TextDecoration.lineThrough
                                    : null,
                              ),
                            ),
                            if (word.phonetic.isNotEmpty) ...[
                              const SizedBox(width: 8),
                              Flexible(
                                child: Text(
                                  '/${word.phonetic}/',
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 12.5,
                                    fontStyle: FontStyle.italic,
                                    color: ChibiTheme.textMuted,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          word.primaryVietnamese,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            color: ChibiTheme.textDark,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          word.topicName,
                          style: const TextStyle(
                            fontSize: 11.5,
                            color: ChibiTheme.textMuted,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () =>
                        AudioSpeechService.speakEnglishWord(word.englishWord),
                    icon: const Icon(
                      Icons.volume_up_rounded,
                      color: ChibiTheme.deepPink,
                    ),
                    visualDensity: VisualDensity.compact,
                  ),
                  TextButton(
                    onPressed: () => _toggleSkipWord(word.englishWord),
                    style: TextButton.styleFrom(
                      foregroundColor: ChibiTheme.textMuted,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 6),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: Text(
                      isSkipped ? 'Khôi phục' : 'Bỏ qua',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  ElevatedButton.icon(
                    onPressed: added
                        ? null
                        : () {
                            final card = word.toFlashcardItem(
                              indexNumber: widget.userFlashcards.length + 1,
                            );
                            widget.onAddWordToFlashcards(card);
                            setState(() {});
                          },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: ChibiTheme.deepPink,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 8),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    icon: Icon(
                      added ? Icons.check_rounded : Icons.add_rounded,
                      size: 16,
                    ),
                    label: Text(
                      added ? 'Đã có' : 'Thêm',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class TopicUnitDetailScreen extends StatefulWidget {
  final VocabTopicUnit topic;
  final List<FlashcardItem> userFlashcards;
  final ValueChanged<FlashcardItem> onAddWordToFlashcards;
  final Set<String> skippedWords;
  final Future<void> Function(String englishWord) onToggleSkipWord;

  const TopicUnitDetailScreen({
    super.key,
    required this.topic,
    required this.userFlashcards,
    required this.onAddWordToFlashcards,
    required this.skippedWords,
    required this.onToggleSkipWord,
  });

  @override
  State<TopicUnitDetailScreen> createState() => _TopicUnitDetailScreenState();
}

class _TopicUnitDetailScreenState extends State<TopicUnitDetailScreen> {
  final Set<String> _locallyAddedWords = {};

  bool _isAdded(String englishWord) {
    final key = englishWord.trim().toLowerCase();
    if (_locallyAddedWords.contains(key)) return true;
    return widget.userFlashcards
        .any((item) => item.englishWord.trim().toLowerCase() == key);
  }

  bool _isSkipped(String englishWord) {
    final key = englishWord.trim().toLowerCase();
    return widget.skippedWords.contains(key);
  }

  /// Danh sách các từ trong Topic được sắp xếp sao cho những từ bấm "Bỏ qua" tự động chuyển xuống cuối danh sách
  List<TopicWordItem> _getOrderedTopicWords() {
    final activeWords = <TopicWordItem>[];
    final skippedWords = <TopicWordItem>[];
    for (final w in widget.topic.words) {
      if (_isSkipped(w.englishWord)) {
        skippedWords.add(w);
      } else {
        activeWords.add(w);
      }
    }
    return [...activeWords, ...skippedWords];
  }

  List<FlashcardItem> _buildTopicFlashcardList(
      List<TopicWordItem> orderedWords) {
    final List<FlashcardItem> list = [];
    for (int i = 0; i < orderedWords.length; i++) {
      list.add(orderedWords[i].toFlashcardItem(indexNumber: i + 1));
    }
    return list;
  }

  @override
  Widget build(BuildContext context) {
    final orderedWords = _getOrderedTopicWords();
    final topicFlashcards = _buildTopicFlashcardList(orderedWords);

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.topic.title),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 6, 18, 10),
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: ChibiTheme.kawaiiCardDecoration(
                color: Colors.white,
                borderColor: ChibiTheme.softPink,
                radius: 24,
              ),
              child: Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: Image.asset(
                      'assets/images/chibi_study.jpg',
                      width: 64,
                      height: 64,
                      fit: BoxFit.cover,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.topic.unitName,
                          style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w900,
                            color: ChibiTheme.textDark,
                          ),
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          'Chạm vào từ để học hoặc bấm "Bỏ qua" để đẩy từ xuống cuối danh sách!',
                          style: TextStyle(
                            fontSize: 12.5,
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
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 4),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => FlashcardStudyScreen(
                        flashcards: topicFlashcards,
                        initialIndex: 0,
                      ),
                    ),
                  );
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: ChibiTheme.deepPink,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18),
                  ),
                ),
                icon: const Icon(Icons.menu_book_rounded),
                label: Text(
                  'Học flashcard (${topicFlashcards.length} từ)',
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ),
          ),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.fromLTRB(18, 8, 18, 24),
              itemCount: orderedWords.length,
              itemBuilder: (context, index) {
                final word = orderedWords[index];
                final added = _isAdded(word.englishWord);
                final skipped = _isSkipped(word.englishWord);

                return Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Opacity(
                    opacity: skipped ? 0.55 : 1.0,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(22),
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => FlashcardStudyScreen(
                              flashcards: topicFlashcards,
                              initialIndex: index,
                            ),
                          ),
                        );
                      },
                      child: Container(
                        padding: const EdgeInsets.all(14),
                        decoration: ChibiTheme.kawaiiCardDecoration(
                          color: Colors.white,
                          borderColor: index.isEven
                              ? ChibiTheme.softPink
                              : ChibiTheme.pastelLavender,
                          radius: 22,
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 40,
                              height: 40,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: ChibiTheme.softPink,
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: Text(
                                '#${index + 1}',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w900,
                                  color: ChibiTheme.deepPink,
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Text(
                                        word.englishWord,
                                        style: TextStyle(
                                          fontSize: 18,
                                          fontWeight: FontWeight.w900,
                                          color: ChibiTheme.textDark,
                                          decoration: skipped
                                              ? TextDecoration.lineThrough
                                              : null,
                                        ),
                                      ),
                                      if (word.phonetic.isNotEmpty) ...[
                                        const SizedBox(width: 8),
                                        Flexible(
                                          child: Text(
                                            '/${word.phonetic}/',
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                              fontSize: 12.5,
                                              fontStyle: FontStyle.italic,
                                              color: ChibiTheme.textMuted,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    word.primaryVietnamese,
                                    style: const TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w800,
                                      color: ChibiTheme.deepPink,
                                    ),
                                  ),
                                  if (word.definition.isNotEmpty) ...[
                                    const SizedBox(height: 2),
                                    Text(
                                      word.definition,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontSize: 12,
                                        color: ChibiTheme.textMuted,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                            IconButton(
                              onPressed: () =>
                                  AudioSpeechService.speakEnglishWord(
                                      word.englishWord),
                              icon: const Icon(
                                Icons.volume_up_rounded,
                                color: ChibiTheme.deepPink,
                              ),
                              visualDensity: VisualDensity.compact,
                              tooltip: 'Nghe phát âm',
                            ),
                            // Nút Bỏ qua -> Đẩy từ đó xuống cuối danh sách (bấm lại để khôi phục)
                            TextButton(
                              onPressed: () async {
                                await widget
                                    .onToggleSkipWord(word.englishWord);
                                if (!mounted) return;
                                setState(() {});
                              },
                              style: TextButton.styleFrom(
                                foregroundColor: skipped
                                    ? ChibiTheme.deepPink
                                    : ChibiTheme.textMuted,
                                backgroundColor: skipped
                                    ? ChibiTheme.softPink
                                    : const Color(0xFFF1F5F9),
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 6),
                                minimumSize: Size.zero,
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              child: Text(
                                skipped ? 'Khôi phục' : 'Bỏ qua',
                                style: const TextStyle(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                            IconButton.filledTonal(
                              onPressed: added
                                  ? null
                                  : () {
                                      final card = word.toFlashcardItem(
                                        indexNumber:
                                            widget.userFlashcards.length + 1,
                                      );
                                      widget.onAddWordToFlashcards(card);
                                      setState(() {
                                        _locallyAddedWords.add(word.englishWord
                                            .trim()
                                            .toLowerCase());
                                      });
                                    },
                              style: IconButton.styleFrom(
                                backgroundColor: added
                                    ? const Color(0xFFE6F7EE)
                                    : ChibiTheme.softPink,
                                foregroundColor: added
                                    ? const Color(0xFF15803D)
                                    : ChibiTheme.deepPink,
                              ),
                              icon: Icon(
                                added
                                    ? Icons.check_rounded
                                    : Icons.bookmark_add_rounded,
                                size: 20,
                              ),
                              visualDensity: VisualDensity.compact,
                              tooltip: added
                                  ? 'Đã có trong Flashcard của bạn'
                                  : 'Thêm vào Flashcard của bạn',
                            ),
                          ],
                        ),
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
