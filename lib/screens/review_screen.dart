import 'dart:math';
import 'package:flutter/material.dart';
import '../models/flashcard_model.dart';
import '../services/audio_speech_service.dart';
import '../services/storage_service.dart';
import '../theme/chibi_theme.dart';

enum ReviewQuestionMode {
  vietnameseToEnglish, // Hiển thị nghĩa tiếng Việt -> Gõ chữ tiếng Anh
  audioToEnglish, // Phát âm thanh -> Gõ chữ tiếng Anh
}

enum ReviewSelectionOption {
  newWordsOnly, // Mặc định: Học các từ mới chưa được ôn tập
  customRange, // Chọn theo khoảng số thứ tự từ điểm đầu đến điểm kết thúc
}

class ReviewQuestion {
  final FlashcardItem card;
  final ReviewQuestionMode mode;
  final bool isAgain; // Đã từng bấm Again để đẩy xuống cuối bài ôn chưa

  ReviewQuestion({
    required this.card,
    required this.mode,
    this.isAgain = false,
  });

  ReviewQuestion copyWith({
    FlashcardItem? card,
    ReviewQuestionMode? mode,
    bool? isAgain,
  }) {
    return ReviewQuestion(
      card: card ?? this.card,
      mode: mode ?? this.mode,
      isAgain: isAgain ?? this.isAgain,
    );
  }
}

class ReviewScreen extends StatefulWidget {
  final List<FlashcardItem> allFlashcards;
  final ValueChanged<List<FlashcardItem>> onFlashcardsUpdated;

  const ReviewScreen({
    super.key,
    required this.allFlashcards,
    required this.onFlashcardsUpdated,
  });

  @override
  State<ReviewScreen> createState() => _ReviewScreenState();
}

class _ReviewScreenState extends State<ReviewScreen> {
  // Mặc định chọn option: Học các từ mới của flashcard chưa được ôn tập
  ReviewSelectionOption _selectionOption = ReviewSelectionOption.newWordsOnly;

  // Cấu hình thanh kéo khi người dùng chọn Option "Khoảng từ"
  late RangeValues _selectedRange;

  // Trạng thái đang ở màn hình chọn hay đang làm bài Ôn tập
  bool _isQuizRunning = false;
  bool _isQuizFinished = false;
  bool _isReviewingNotRememberedList = false;

  List<ReviewQuestion> _questions = [];
  int _currentQuestionIndex = 0;
  int _correctCount = 0;

  final TextEditingController _answerController = TextEditingController();
  bool _hasCheckedCurrent = false;
  bool _isCurrentCorrect = false;

  @override
  void initState() {
    super.initState();
    _initFullRange();
  }

  void _initFullRange() {
    final total = widget.allFlashcards.length;
    if (total > 0) {
      _selectedRange = RangeValues(1, total.toDouble());
    } else {
      _selectedRange = const RangeValues(1, 1);
    }
  }

  @override
  void didUpdateWidget(covariant ReviewScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.allFlashcards.length != widget.allFlashcards.length &&
        !_isQuizRunning) {
      _initFullRange();
    }
  }

  @override
  void dispose() {
    _answerController.dispose();
    super.dispose();
  }

  List<FlashcardItem> get _unreviewedNewCards =>
      widget.allFlashcards.where((c) => !c.isReviewed).toList();

  List<FlashcardItem> get _notRememberedCards =>
      widget.allFlashcards.where((c) => c.isNotRemembered).toList();

  void _startReviewWithCards(
    List<FlashcardItem> selectedCards, {
    bool isFromNotRemembered = false,
  }) {
    if (selectedCards.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: ChibiTheme.deepPink,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          content: const Text(
            'Không có thẻ nào trong mục bạn chọn. Hãy chọn "Khoảng từ" hoặc thêm từ mới nhé!',
            style: TextStyle(fontWeight: FontWeight.w800),
          ),
        ),
      );
      return;
    }

    final random = Random();
    final List<ReviewQuestion> builtQuestions = selectedCards.map((card) {
      final mode = random.nextBool()
          ? ReviewQuestionMode.vietnameseToEnglish
          : ReviewQuestionMode.audioToEnglish;
      return ReviewQuestion(
        card: card,
        mode: mode,
        isAgain: false,
      );
    }).toList();

    builtQuestions.shuffle(random);

    setState(() {
      _questions = builtQuestions;
      _currentQuestionIndex = 0;
      _correctCount = 0;
      _isQuizRunning = true;
      _isQuizFinished = false;
      _isReviewingNotRememberedList = isFromNotRemembered;
      _hasCheckedCurrent = false;
      _isCurrentCorrect = false;
      _answerController.clear();
    });

    _playAudioIfCurrentIsAudioQuestion();
  }

  void _startStandardReviewSession() {
    if (_selectionOption == ReviewSelectionOption.newWordsOnly) {
      final newCards = _unreviewedNewCards;
      // Nếu tất cả từ đều đã từng ôn tập thì lấy toàn bộ danh sách để người dùng không bị kẹt
      final targetCards =
          newCards.isNotEmpty ? newCards : widget.allFlashcards;
      _startReviewWithCards(targetCards, isFromNotRemembered: false);
    } else {
      final total = widget.allFlashcards.length;
      final startIdx = _selectedRange.start.round().clamp(1, total);
      final endIdx = _selectedRange.end.round().clamp(startIdx, total);
      final rangeCards = widget.allFlashcards
          .where((c) => c.indexNumber >= startIdx && c.indexNumber <= endIdx)
          .toList();
      _startReviewWithCards(rangeCards, isFromNotRemembered: false);
    }
  }

  void _playAudioIfCurrentIsAudioQuestion() {
    if (_questions.isEmpty || _currentQuestionIndex >= _questions.length) {
      return;
    }
    final q = _questions[_currentQuestionIndex];
    if (q.mode == ReviewQuestionMode.audioToEnglish) {
      Future.delayed(const Duration(milliseconds: 300), () {
        if (mounted && _isQuizRunning && !_isQuizFinished) {
          AudioSpeechService.speakEnglishWord(q.card.englishWord);
        }
      });
    }
  }

  /// Chức năng Check (Kiểm tra đáp án):
  /// - Đánh dấu thẻ này là đã được ôn tập (`isReviewed: true`)
  /// - Nếu trả lời đúng và thẻ này đang nằm trong danh sách "Không nhớ", tự động xóa khỏi danh sách "Không nhớ" (`isNotRemembered: false`)
  Future<void> _handleCheckAnswer() async {
    if (_hasCheckedCurrent) return;
    final typed = _answerController.text.trim();
    if (typed.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: ChibiTheme.deepPink,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          content: const Text(
            'Bạn hãy gõ từ tiếng Anh trước khi bấm Check, hoặc bấm Again nếu chưa nhớ nhé!',
            style: TextStyle(fontWeight: FontWeight.w800),
          ),
        ),
      );
      return;
    }

    final currentQ = _questions[_currentQuestionIndex];
    final target = currentQ.card.englishWord.trim();
    final isCorrect = typed.toLowerCase() == target.toLowerCase();

    // Cập nhật trạng thái xuống Storage:
    // Đã ôn tập = true; nếu trả lời đúng thì xóa khỏi danh sách Không nhớ (isNotRemembered = false)
    final updatedList = await StorageService.updateCardReviewStatus(
      cardId: currentQ.card.id,
      isReviewed: true,
      isNotRemembered: isCorrect ? false : currentQ.card.isNotRemembered,
    );
    widget.onFlashcardsUpdated(updatedList);

    if (!mounted) return;
    setState(() {
      _hasCheckedCurrent = true;
      _isCurrentCorrect = isCorrect;
      if (isCorrect) {
        _correctCount++;
      }
    });
  }

  /// Chức năng Again:
  /// Đẩy thẻ hiện tại xuống cuối bài ôn tập (`isAgain: true`) và chuyển ngay sang thẻ tiếp theo.
  void _handleAgain() {
    if (_questions.isEmpty || _currentQuestionIndex >= _questions.length) {
      return;
    }
    final currentQ = _questions[_currentQuestionIndex];

    setState(() {
      // Đưa bản sao có đánh dấu isAgain = true xuống cuối danh sách câu hỏi
      _questions.removeAt(_currentQuestionIndex);
      _questions.add(currentQ.copyWith(isAgain: true));
      _hasCheckedCurrent = false;
      _isCurrentCorrect = false;
      _answerController.clear();
    });

    _playAudioIfCurrentIsAudioQuestion();
  }

  /// Chức năng Không nhớ (hiển thị khi thẻ ở cuối bài ôn đã được đánh dấu là Again):
  /// Lưu thẻ này vào danh sách "Không nhớ" (`isNotRemembered: true`, `isReviewed: true`) và chuyển sang câu tiếp theo.
  Future<void> _handleMarkNotRemembered() async {
    if (_questions.isEmpty || _currentQuestionIndex >= _questions.length) {
      return;
    }
    final currentQ = _questions[_currentQuestionIndex];

    final updatedList = await StorageService.updateCardReviewStatus(
      cardId: currentQ.card.id,
      isReviewed: true,
      isNotRemembered: true,
    );
    widget.onFlashcardsUpdated(updatedList);

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: ChibiTheme.deepPink,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
        ),
        content: Text(
          'Đã lưu "${currentQ.card.englishWord}" vào danh sách Không nhớ 📌',
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
    );

    _nextQuestion();
  }

  void _nextQuestion() {
    if (_currentQuestionIndex < _questions.length - 1) {
      setState(() {
        _currentQuestionIndex++;
        _hasCheckedCurrent = false;
        _isCurrentCorrect = false;
        _answerController.clear();
      });
      _playAudioIfCurrentIsAudioQuestion();
    } else {
      setState(() {
        _isQuizFinished = true;
      });
    }
  }

  void _backToSetup() {
    setState(() {
      _isQuizRunning = false;
      _isQuizFinished = false;
      _isReviewingNotRememberedList = false;
      _initFullRange();
    });
  }

  void _openNotRememberedBottomSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final notRemembered = _notRememberedCards;
        return Container(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(ctx).size.height * 0.78,
          ),
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          decoration: const BoxDecoration(
            color: ChibiTheme.bgCream,
            borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
          ),
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
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Danh sách Không nhớ (${notRemembered.length})',
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w900,
                            color: ChibiTheme.textDark,
                          ),
                        ),
                        const SizedBox(height: 2),
                        const Text(
                          'Khi bạn ôn tập và trả lời đúng (Check), thẻ sẽ tự động xóa khỏi danh sách này.',
                          style: TextStyle(
                            fontSize: 12.5,
                            color: ChibiTheme.textMuted,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(ctx).pop(),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              if (notRemembered.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 32),
                  child: Column(
                    children: [
                      const Icon(
                        Icons.sentiment_very_satisfied_rounded,
                        size: 54,
                        color: ChibiTheme.deepPink,
                      ),
                      const SizedBox(height: 10),
                      const Text(
                        'Chưa có thẻ nào trong danh sách Không nhớ!',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: ChibiTheme.textDark,
                        ),
                      ),
                    ],
                  ),
                )
              else ...[
                Flexible(
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: notRemembered.length,
                    itemBuilder: (_, idx) {
                      final card = notRemembered[idx];
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Container(
                          padding: const EdgeInsets.all(14),
                          decoration: ChibiTheme.kawaiiCardDecoration(
                            color: Colors.white,
                            borderColor: ChibiTheme.softPink,
                            radius: 20,
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 42,
                                height: 42,
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  color: ChibiTheme.softPink,
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                child: Text(
                                  '#${card.indexNumber}',
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
                                    Text(
                                      card.englishWord,
                                      style: const TextStyle(
                                        fontSize: 17,
                                        fontWeight: FontWeight.w900,
                                        color: ChibiTheme.textDark,
                                      ),
                                    ),
                                    Text(
                                      card.primaryVietnamese,
                                      style: const TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w700,
                                        color: ChibiTheme.deepPink,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              IconButton(
                                onPressed: () =>
                                    AudioSpeechService.speakEnglishWord(
                                        card.englishWord),
                                icon: const Icon(
                                  Icons.volume_up_rounded,
                                  color: ChibiTheme.deepPink,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 12),
                ElevatedButton.icon(
                  onPressed: () {
                    Navigator.of(ctx).pop();
                    _startReviewWithCards(
                      notRemembered,
                      isFromNotRemembered: true,
                    );
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: ChibiTheme.deepPink,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 15),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                    ),
                  ),
                  icon: const Icon(Icons.play_arrow_rounded),
                  label: Text(
                    'Tạo bài ôn tập cho ${notRemembered.length} thẻ Không nhớ',
                    style: const TextStyle(
                      fontSize: 15.5,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final totalCards = widget.allFlashcards.length;

    // 1. Chưa đủ 10 Flashcard -> Hiển thị màn hình khóa
    if (totalCards < 10) {
      return _buildLockedView(totalCards);
    }

    // 2. Đã hoàn thành lượt Ôn tập
    if (_isQuizRunning && _isQuizFinished) {
      return _buildResultView();
    }

    // 3. Đang trong lượt làm bài Ôn tập
    if (_isQuizRunning) {
      return _buildActiveQuizView();
    }

    // 4. Màn hình thiết lập Ôn tập
    return _buildSetupView(totalCards);
  }

  Widget _buildLockedView(int currentCount) {
    final remaining = 10 - currentCount;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: ChibiTheme.kawaiiCardDecoration(
            color: Colors.white,
            borderColor: ChibiTheme.softPink,
            radius: 30,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(24),
                child: Image.asset(
                  'assets/images/chibi_review.jpg',
                  width: 150,
                  height: 150,
                  fit: BoxFit.cover,
                ),
              ),
              const SizedBox(height: 18),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                decoration: BoxDecoration(
                  color: ChibiTheme.softPink,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Text(
                  'Hiện có $currentCount / 10 Flashcard',
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    color: ChibiTheme.deepPink,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'Cần đủ 10 Flashcard để mở Ôn Tập ✨',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                  color: ChibiTheme.textDark,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Bạn hãy thêm $remaining từ vựng nữa ở mục Flashcard hoặc Topic để bắt đầu chế độ Ôn Tập nhé!',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 14,
                  color: ChibiTheme.textMuted,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 18),
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: LinearProgressIndicator(
                  value: currentCount / 10.0,
                  minHeight: 12,
                  backgroundColor: ChibiTheme.softPink,
                  valueColor: const AlwaysStoppedAnimation<Color>(
                    ChibiTheme.pastelPink,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSetupView(int totalCards) {
    final startNum = _selectedRange.start.round().clamp(1, totalCards);
    final endNum = _selectedRange.end.round().clamp(startNum, totalCards);
    final selectedRangeCount = endNum - startNum + 1;
    final newWordsCount = _unreviewedNewCards.length;
    final notRememberedCount = _notRememberedCards.length;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.all(22),
            decoration: ChibiTheme.kawaiiCardDecoration(
              color: Colors.white,
              borderColor: ChibiTheme.pastelLavender,
              radius: 30,
            ),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: ChibiTheme.softPink,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Text(
                        'Tổng: $totalCards thẻ',
                        style: const TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w900,
                          color: ChibiTheme.deepPink,
                        ),
                      ),
                    ),
                    // Nút mở danh sách các Flashcard được đánh dấu là Không nhớ
                    OutlinedButton.icon(
                      onPressed: _openNotRememberedBottomSheet,
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(
                            color: ChibiTheme.deepPink, width: 1.8),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                      ),
                      icon: const Icon(
                        Icons.bookmark_remove_rounded,
                        size: 18,
                        color: ChibiTheme.deepPink,
                      ),
                      label: Text(
                        'Không nhớ ($notRememberedCount)',
                        style: const TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w900,
                          color: ChibiTheme.deepPink,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                ClipRRect(
                  borderRadius: BorderRadius.circular(24),
                  child: Image.asset(
                    'assets/images/chibi_review.jpg',
                    width: 125,
                    height: 125,
                    fit: BoxFit.cover,
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Chế Độ Ôn Tập Từ Vựng ✍️',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 21,
                    fontWeight: FontWeight.w900,
                    color: ChibiTheme.textDark,
                  ),
                ),
                const SizedBox(height: 16),

                // Option 1 (Mặc định): Học các từ mới của flashcard chưa được ôn tập
                InkWell(
                  borderRadius: BorderRadius.circular(20),
                  onTap: () {
                    setState(() {
                      _selectionOption = ReviewSelectionOption.newWordsOnly;
                    });
                  },
                  child: Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: _selectionOption ==
                              ReviewSelectionOption.newWordsOnly
                          ? const Color(0xFFEAF3FF)
                          : ChibiTheme.bgCream,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: _selectionOption ==
                                ReviewSelectionOption.newWordsOnly
                            ? ChibiTheme.deepPink
                            : ChibiTheme.softPink,
                        width: 2,
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          _selectionOption ==
                                  ReviewSelectionOption.newWordsOnly
                              ? Icons.radio_button_checked_rounded
                              : Icons.radio_button_off_rounded,
                          color: ChibiTheme.deepPink,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Từ mới chưa được ôn tập (Mặc định)',
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w900,
                                  color: ChibiTheme.textDark,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                newWordsCount > 0
                                    ? 'Hiện có $newWordsCount từ mới chưa ôn tập'
                                    : 'Tất cả từ đều đã được ôn tập (Sẽ ôn toàn bộ $totalCards từ)',
                                style: const TextStyle(
                                  fontSize: 12.5,
                                  color: ChibiTheme.textMuted,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 10),

                // Option 2: Chọn theo khoảng từ (Điểm đầu -> Điểm kết thúc)
                InkWell(
                  borderRadius: BorderRadius.circular(20),
                  onTap: () {
                    setState(() {
                      _selectionOption = ReviewSelectionOption.customRange;
                    });
                  },
                  child: Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color:
                          _selectionOption == ReviewSelectionOption.customRange
                              ? const Color(0xFFEAF3FF)
                              : ChibiTheme.bgCream,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: _selectionOption ==
                                ReviewSelectionOption.customRange
                            ? ChibiTheme.deepPink
                            : ChibiTheme.softPink,
                        width: 2,
                      ),
                    ),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            Icon(
                              _selectionOption ==
                                      ReviewSelectionOption.customRange
                                  ? Icons.radio_button_checked_rounded
                                  : Icons.radio_button_off_rounded,
                              color: ChibiTheme.deepPink,
                            ),
                            const SizedBox(width: 12),
                            const Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Chọn theo khoảng từ (STT)',
                                    style: TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w900,
                                      color: ChibiTheme.textDark,
                                    ),
                                  ),
                                  SizedBox(height: 2),
                                  Text(
                                    'Kéo chọn điểm đầu và điểm kết thúc',
                                    style: TextStyle(
                                      fontSize: 12.5,
                                      color: ChibiTheme.textMuted,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            if (_selectionOption ==
                                ReviewSelectionOption.customRange)
                              TextButton(
                                onPressed: () {
                                  setState(() {
                                    _selectedRange =
                                        RangeValues(1, totalCards.toDouble());
                                  });
                                },
                                child: const Text(
                                  'Chọn All',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w900,
                                    color: ChibiTheme.deepPink,
                                  ),
                                ),
                              ),
                          ],
                        ),
                        if (_selectionOption ==
                            ReviewSelectionOption.customRange) ...[
                          const SizedBox(height: 12),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceAround,
                            children: [
                              _buildRangeBadge('Điểm đầu', 'Thẻ #$startNum'),
                              const Icon(Icons.arrow_forward_rounded,
                                  color: ChibiTheme.pastelPink),
                              _buildRangeBadge('Điểm cuối', 'Thẻ #$endNum'),
                            ],
                          ),
                          SliderTheme(
                            data: SliderTheme.of(context).copyWith(
                              activeTrackColor: ChibiTheme.pastelPink,
                              inactiveTrackColor: ChibiTheme.softPink,
                              thumbColor: ChibiTheme.deepPink,
                              overlayColor:
                                  ChibiTheme.pastelPink.withValues(alpha: 0.2),
                              trackHeight: 8,
                            ),
                            child: RangeSlider(
                              values: RangeValues(
                                startNum.toDouble(),
                                endNum.toDouble(),
                              ),
                              min: 1,
                              max: totalCards.toDouble(),
                              divisions: totalCards > 1 ? totalCards - 1 : 1,
                              labels: RangeLabels(
                                '#$startNum',
                                '#$endNum',
                              ),
                              onChanged: (values) {
                                setState(() {
                                  _selectedRange = RangeValues(
                                    values.start.roundToDouble(),
                                    values.end.roundToDouble(),
                                  );
                                });
                              },
                            ),
                          ),
                          Text(
                            'Khoảng đã chọn: $selectedRangeCount từ (Từ #$startNum đến #$endNum)',
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w800,
                              color: ChibiTheme.deepPink,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 20),
                // Nút "Ôn tập" theo đúng yêu cầu: Bắt đầu ôn tập (10 từ) -> Ôn tập
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _startStandardReviewSession,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: ChibiTheme.deepPink,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(22),
                      ),
                    ),
                    icon: const Icon(Icons.play_arrow_rounded, size: 26),
                    label: const Text(
                      'Ôn tập',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRangeBadge(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: ChibiTheme.softPink, width: 1.8),
      ),
      child: Column(
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 11.5,
              color: ChibiTheme.textMuted,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w900,
              color: ChibiTheme.deepPink,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActiveQuizView() {
    final currentQ = _questions[_currentQuestionIndex];
    final isAudioMode = currentQ.mode == ReviewQuestionMode.audioToEnglish;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Thanh trạng thái câu hỏi hiện tại
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              TextButton.icon(
                onPressed: _backToSetup,
                icon: const Icon(Icons.arrow_back_rounded),
                label: Text(
                  _isReviewingNotRememberedList
                      ? 'Thoát ôn Không nhớ'
                      : 'Quay lại',
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                decoration: BoxDecoration(
                  color: ChibiTheme.softPink,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Text(
                  'Câu ${_currentQuestionIndex + 1} / ${_questions.length}',
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    color: ChibiTheme.deepPink,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: LinearProgressIndicator(
              value: (_currentQuestionIndex + 1) / _questions.length,
              minHeight: 10,
              backgroundColor: ChibiTheme.softPink,
              valueColor: const AlwaysStoppedAnimation<Color>(
                ChibiTheme.pastelPink,
              ),
            ),
          ),
          const SizedBox(height: 18),

          // Thẻ câu hỏi Ôn tập
          Container(
            padding: const EdgeInsets.all(22),
            decoration: ChibiTheme.kawaiiCardDecoration(
              color: Colors.white,
              borderColor: isAudioMode
                  ? ChibiTheme.pastelMint
                  : ChibiTheme.pastelLavender,
              radius: 28,
            ),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 5),
                          decoration: BoxDecoration(
                            color: ChibiTheme.softLavender,
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Text(
                            'Thẻ #${currentQ.card.indexNumber}',
                            style: const TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                        if (currentQ.isAgain) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 5),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFFE5EC),
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: const Text(
                              'Again',
                              style: TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w900,
                                color: Colors.redAccent,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 5),
                      decoration: BoxDecoration(
                        color: isAudioMode
                            ? ChibiTheme.softMint
                            : ChibiTheme.softPink,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Text(
                        isAudioMode
                            ? '🎧 Nghe -> Gõ tiếng Anh'
                            : '🇻🇳 Nghĩa -> Gõ tiếng Anh',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          color: ChibiTheme.textDark,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                ClipRRect(
                  borderRadius: BorderRadius.circular(20),
                  child: Image.asset(
                    isAudioMode
                        ? 'assets/images/chibi_listen.jpg'
                        : 'assets/images/chibi_review.jpg',
                    width: 110,
                    height: 110,
                    fit: BoxFit.cover,
                  ),
                ),
                const SizedBox(height: 16),

                // Nội dung gợi ý tùy theo dạng câu hỏi
                if (isAudioMode) ...[
                  const Text(
                    'Bấm vào nút loa để nghe phát âm và gõ lại từ tiếng Anh:',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 14,
                      color: ChibiTheme.textMuted,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 12),
                  ElevatedButton.icon(
                    onPressed: () => AudioSpeechService.speakEnglishWord(
                        currentQ.card.englishWord),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: ChibiTheme.pastelPink,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 24, vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(22),
                      ),
                    ),
                    icon: const Icon(Icons.volume_up_rounded, size: 26),
                    label: const Text(
                      'Phát âm thanh từ vựng',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ] else ...[
                  const Text(
                    'Nghĩa tiếng Việt của từ này là:',
                    style: TextStyle(
                      fontSize: 13.5,
                      color: ChibiTheme.textMuted,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    currentQ.card.primaryVietnamese,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w900,
                      color: ChibiTheme.deepPink,
                    ),
                  ),
                  if (currentQ.card.wordTypes.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(
                      '(${currentQ.card.wordTypes.first.pos}: ${currentQ.card.wordTypes.first.terms.take(3).join(", ")})',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 13,
                        color: ChibiTheme.textMuted,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ],

                const SizedBox(height: 20),
                TextField(
                  controller: _answerController,
                  enabled: !_hasCheckedCurrent,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => _handleCheckAnswer(),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                  ),
                  decoration: InputDecoration(
                    hintText: 'Gõ từ tiếng Anh vào đây...',
                    filled: true,
                    fillColor: ChibiTheme.bgCream,
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 18, vertical: 16),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(20),
                      borderSide: const BorderSide(
                          color: ChibiTheme.softPink, width: 2),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(20),
                      borderSide: const BorderSide(
                          color: ChibiTheme.softPink, width: 2),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(20),
                      borderSide: const BorderSide(
                          color: ChibiTheme.deepPink, width: 2.5),
                    ),
                  ),
                ),

                if (_hasCheckedCurrent) ...[
                  const SizedBox(height: 16),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: _isCurrentCorrect
                          ? const Color(0xFFE8FBF5)
                          : const Color(0xFFFFEDF2),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(
                        color: _isCurrentCorrect
                            ? ChibiTheme.pastelMatcha
                            : Colors.redAccent,
                        width: 2,
                      ),
                    ),
                    child: Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              _isCurrentCorrect
                                  ? Icons.check_circle_rounded
                                  : Icons.cancel_rounded,
                              color: _isCurrentCorrect
                                  ? const Color(0xFF15803D)
                                  : Colors.redAccent,
                            ),
                            const SizedBox(width: 6),
                            Flexible(
                              child: Text(
                                _isCurrentCorrect
                                    ? 'Chính xác tuyệt đối! 🎉'
                                    : 'Chưa chính xác rồi!',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w900,
                                  color: _isCurrentCorrect
                                      ? const Color(0xFF15803D)
                                      : Colors.redAccent,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Đáp án đúng: ${currentQ.card.englishWord}',
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                            color: ChibiTheme.textDark,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Nghĩa: ${currentQ.card.primaryVietnamese}',
                          style: const TextStyle(
                            fontSize: 14,
                            color: ChibiTheme.textMuted,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],

                const SizedBox(height: 18),

                // Hàng nút hành động:
                // - Nếu chưa bấm Check:
                //   + Bên trái: Nếu thẻ chưa từng bấm Again (`!currentQ.isAgain`) -> Hiển thị nút "Again" (đẩy xuống cuối bài ôn).
                //     Nếu thẻ đã từng được đánh dấu Again (`currentQ.isAgain`) ở cuối bài -> Hiển thị nút "Không nhớ" (đưa vào danh sách Không nhớ).
                //   + Bên phải: Nút "Check" (kiểm tra đáp án).
                // - Nếu đã bấm Check:
                //   + Nếu trả lời chưa đúng và thẻ đã là `isAgain` (hoặc người dùng muốn lưu vào Không nhớ), vẫn có nút "Không nhớ" bên cạnh nút "Câu tiếp theo".
                if (!_hasCheckedCurrent)
                  Row(
                    children: [
                      Expanded(
                        child: currentQ.isAgain
                            ? OutlinedButton.icon(
                                onPressed: _handleMarkNotRemembered,
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: Colors.redAccent,
                                  side: const BorderSide(
                                      color: Colors.redAccent, width: 2),
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 15),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                ),
                                icon: const Icon(
                                    Icons.bookmark_add_outlined),
                                label: const Text(
                                  'Không nhớ',
                                  style: TextStyle(
                                    fontSize: 15.5,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                              )
                            : OutlinedButton.icon(
                                onPressed: _handleAgain,
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: ChibiTheme.deepPink,
                                  side: const BorderSide(
                                      color: ChibiTheme.pastelPink, width: 2),
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 15),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                ),
                                icon: const Icon(Icons.replay_rounded),
                                label: const Text(
                                  'Again',
                                  style: TextStyle(
                                    fontSize: 15.5,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                              ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: _handleCheckAnswer,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: ChibiTheme.deepPink,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 15),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(20),
                            ),
                          ),
                          icon: const Icon(Icons.check_rounded),
                          label: const Text(
                            'Check',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                      ),
                    ],
                  )
                else
                  Row(
                    children: [
                      if (!_isCurrentCorrect && currentQ.isAgain) ...[
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _handleMarkNotRemembered,
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.redAccent,
                              side: const BorderSide(
                                  color: Colors.redAccent, width: 2),
                              padding:
                                  const EdgeInsets.symmetric(vertical: 15),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(20),
                              ),
                            ),
                            icon: const Icon(Icons.bookmark_add_outlined),
                            label: const Text(
                              'Không nhớ',
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                      ],
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: _nextQuestion,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: ChibiTheme.pastelPink,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 15),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(20),
                            ),
                          ),
                          icon: const Icon(Icons.arrow_forward_rounded),
                          label: Text(
                            _currentQuestionIndex < _questions.length - 1
                                ? 'Câu tiếp theo'
                                : 'Xem kết quả',
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildResultView() {
    final total = _questions.length;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Container(
          padding: const EdgeInsets.all(26),
          decoration: ChibiTheme.kawaiiCardDecoration(
            color: Colors.white,
            borderColor: ChibiTheme.pastelPink,
            radius: 32,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(24),
                child: Image.asset(
                  'assets/images/chibi_success.jpg',
                  width: 155,
                  height: 155,
                  fit: BoxFit.cover,
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Hoàn Thành Ôn Tập! 🎉',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w900,
                  color: ChibiTheme.deepPink,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'Bạn đã trả lời đúng $_correctCount / $total từ vựng!',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: ChibiTheme.textDark,
                ),
              ),
              const SizedBox(height: 22),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _backToSetup,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: ChibiTheme.deepPink,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18),
                    ),
                  ),
                  icon: const Icon(Icons.replay_rounded),
                  label: const Text(
                    'Quay về màn hình Ôn tập',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
