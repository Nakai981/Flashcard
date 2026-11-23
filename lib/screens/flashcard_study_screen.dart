import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import '../models/flashcard_model.dart';
import '../services/audio_speech_service.dart';
import '../theme/chibi_theme.dart';

class FlashcardStudyScreen extends StatefulWidget {
  final List<FlashcardItem> flashcards;
  final int initialIndex;

  const FlashcardStudyScreen({
    super.key,
    required this.flashcards,
    this.initialIndex = 0,
  });

  @override
  State<FlashcardStudyScreen> createState() => _FlashcardStudyScreenState();
}

class _FlashcardStudyScreenState extends State<FlashcardStudyScreen> {
  late PageController _pageController;
  late int _currentIndex;
  bool _isFlipped = false;
  bool _showRawJson = false;

  // Nhận diện giọng nói (Thu âm kiểm tra phát âm đúng hay chưa)
  final stt.SpeechToText _speechToText = stt.SpeechToText();
  bool _speechAvailable = false;
  bool _isListening = false;
  String _recognizedWords = '';
  bool? _isPronouncedRight; // true = Phát âm đúng, false = Chưa đúng
  String? _speechStatusHint;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _pageController = PageController(initialPage: widget.initialIndex);
    // Không gọi _initSpeech() tự động trong initState để tránh crash iOS ngay khi mở thẻ Flashcard
    // (Chỉ khởi tạo khi người dùng thực sự bấm vào nút "Bấm để thu âm giọng đọc").
  }

  Future<void> _initSpeech() async {
    try {
      final available = await _speechToText.initialize(
        onStatus: (status) {
          if (status == 'done' || status == 'notListening') {
            if (mounted && _isListening) {
              setState(() {
                _isListening = false;
              });
            }
          }
        },
        onError: (error) {
          if (mounted) {
            setState(() {
              _isListening = false;
              _speechStatusHint =
                  'Không nhận diện được giọng nói, bạn hãy bấm Mic và đọc to rõ hơn nhé!';
            });
          }
        },
      );
      if (mounted) {
        setState(() {
          _speechAvailable = available;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _speechAvailable = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _speechToText.stop();
    _pageController.dispose();
    super.dispose();
  }

  void _resetSpeechFeedback() {
    setState(() {
      _isListening = false;
      _recognizedWords = '';
      _isPronouncedRight = null;
      _speechStatusHint = null;
      _showRawJson = false;
    });
  }

  String _normalizeText(String input) {
    return input
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9\s]'), '')
        .trim();
  }

  Future<void> _toggleRecording(String targetWord) async {
    if (_isListening) {
      await _speechToText.stop();
      setState(() {
        _isListening = false;
      });
      return;
    }

    if (!_speechAvailable) {
      await _initSpeech();
    }

    if (!_speechAvailable) {
      setState(() {
        _speechStatusHint =
            'Thiết bị chưa cấp quyền Micro hoặc chưa bật dịch vụ nhận diện giọng nói của Google.';
      });
      return;
    }

    setState(() {
      _isListening = true;
      _recognizedWords = '';
      _isPronouncedRight = null;
      _speechStatusHint = 'Đang lắng nghe giọng của bạn... Hãy đọc từ "$targetWord"';
    });

    await _speechToText.listen(
      listenOptions: stt.SpeechListenOptions(
        localeId: 'en_US',
        listenFor: const Duration(seconds: 6),
        pauseFor: const Duration(seconds: 2),
        cancelOnError: true,
        partialResults: true,
      ),
      onResult: (result) {
        final spoken = result.recognizedWords.trim();
        final normSpoken = _normalizeText(spoken);
        final normTarget = _normalizeText(targetWord);

        final isMatch = normSpoken == normTarget ||
            normSpoken.split(' ').contains(normTarget);

        if (mounted) {
          setState(() {
            _recognizedWords = spoken;
            _isPronouncedRight = isMatch;
            if (result.finalResult) {
              _isListening = false;
              _speechStatusHint = null;
            }
          });
        }
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.flashcards.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('Học Flashcard')),
        body: const Center(
          child: Text('Chưa có Flashcard nào để học!'),
        ),
      );
    }

    final currentCard = widget.flashcards[_currentIndex];

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Thẻ #${currentCard.indexNumber} / ${widget.flashcards.length}',
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Thanh tiến độ pastel dễ thương
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 6),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: LinearProgressIndicator(
                  value: (_currentIndex + 1) / widget.flashcards.length,
                  minHeight: 10,
                  backgroundColor: ChibiTheme.softPink,
                  valueColor: const AlwaysStoppedAnimation<Color>(
                    ChibiTheme.pastelPink,
                  ),
                ),
              ),
            ),

            // Vùng lật thẻ Flashcard
            Expanded(
              child: PageView.builder(
                controller: _pageController,
                itemCount: widget.flashcards.length,
                onPageChanged: (index) {
                  _speechToText.stop();
                  setState(() {
                    _currentIndex = index;
                    _isFlipped = false;
                  });
                  _resetSpeechFeedback();
                },
                itemBuilder: (context, index) {
                  final card = widget.flashcards[index];
                  return SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(20, 10, 20, 16),
                    child: Column(
                      children: [
                        // Thẻ Flashcard chính (Chạm để lật Mặt trước / Mặt sau)
                        GestureDetector(
                          onTap: () {
                            setState(() {
                              _isFlipped = !_isFlipped;
                            });
                          },
                          child: AnimatedSwitcher(
                            duration: const Duration(milliseconds: 350),
                            transitionBuilder: (child, animation) {
                              final rotate =
                                  Tween(begin: math.pi, end: 0.0).animate(animation);
                              return AnimatedBuilder(
                                animation: rotate,
                                child: child,
                                builder: (context, widgetChild) {
                                  final isUnder =
                                      (ValueKey(_isFlipped) != widgetChild?.key);
                                  final value = isUnder
                                      ? math.min(rotate.value, math.pi / 2)
                                      : rotate.value;
                                  return Transform(
                                    transform: Matrix4.rotationY(value),
                                    alignment: Alignment.center,
                                    child: widgetChild,
                                  );
                                },
                              );
                            },
                            child: _isFlipped
                                ? _buildBackCard(card)
                                : _buildFrontCard(card),
                          ),
                        ),
                        const SizedBox(height: 16),

                        // Khung Thu Âm kiểm tra phát âm với nhân vật Chibi
                        _buildPronunciationPracticeBox(card),
                      ],
                    ),
                  );
                },
              ),
            ),

            // Thanh điều hướng Trước / Lật thẻ / Tiếp theo
            Container(
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 16),
              decoration: BoxDecoration(
                color: Colors.white,
                boxShadow: [
                  BoxShadow(
                    color: ChibiTheme.softPink.withValues(alpha: 0.4),
                    blurRadius: 12,
                    offset: const Offset(0, -4),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _currentIndex > 0
                          ? () {
                              _pageController.previousPage(
                                duration: const Duration(milliseconds: 300),
                                curve: Curves.easeOut,
                              );
                            }
                          : null,
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        side: const BorderSide(
                            color: ChibiTheme.pastelPink, width: 2),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(18),
                        ),
                      ),
                      icon: const Icon(Icons.arrow_back_rounded),
                      label: const Text(
                        'Từ trước',
                        style: TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  ElevatedButton.icon(
                    onPressed: () {
                      setState(() {
                        _isFlipped = !_isFlipped;
                      });
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: ChibiTheme.softLavender,
                      foregroundColor: ChibiTheme.textDark,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 13),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(18),
                      ),
                    ),
                    icon: const Icon(Icons.flip_rounded),
                    label: Text(
                      _isFlipped ? 'Mặt trước' : 'Xem nghĩa',
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _currentIndex < widget.flashcards.length - 1
                          ? () {
                              _pageController.nextPage(
                                duration: const Duration(milliseconds: 300),
                                curve: Curves.easeOut,
                              );
                            }
                          : null,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: ChibiTheme.pastelPink,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(18),
                        ),
                      ),
                      icon: const Icon(Icons.arrow_forward_rounded),
                      label: const Text(
                        'Từ tiếp',
                        style: TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Mặt trước của thẻ Flashcard: Hiển thị STT, nhân vật Chibi, Từ tiếng Anh, Phiên âm & Nút nghe phát âm
  Widget _buildFrontCard(FlashcardItem card) {
    return Container(
      key: const ValueKey(false),
      width: double.infinity,
      padding: const EdgeInsets.all(22),
      decoration: ChibiTheme.kawaiiCardDecoration(
        color: Colors.white,
        borderColor: ChibiTheme.softPink,
        radius: 30,
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                decoration: BoxDecoration(
                  color: ChibiTheme.softPink,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Text(
                  'STT #${card.indexNumber}',
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    color: ChibiTheme.deepPink,
                  ),
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                decoration: BoxDecoration(
                  color: ChibiTheme.softLavender,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.touch_app_rounded,
                        size: 15, color: ChibiTheme.textDark),
                    SizedBox(width: 4),
                    Text(
                      'Chạm để lật xem nghĩa',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ClipRRect(
            borderRadius: BorderRadius.circular(22),
            child: Image.asset(
              'assets/images/chibi_study.jpg',
              height: 115,
              width: 115,
              fit: BoxFit.cover,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            card.englishWord,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 34,
              fontWeight: FontWeight.w900,
              color: ChibiTheme.deepPink,
            ),
          ),
          if (card.phonetic.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              '/${card.phonetic}/',
              style: const TextStyle(
                fontSize: 17,
                fontStyle: FontStyle.italic,
                color: ChibiTheme.textMuted,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: () =>
                AudioSpeechService.speakEnglishWord(card.englishWord),
            style: ElevatedButton.styleFrom(
              backgroundColor: ChibiTheme.softPink,
              foregroundColor: ChibiTheme.deepPink,
              elevation: 0,
              padding:
                  const EdgeInsets.symmetric(horizontal: 20, vertical: 11),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
            ),
            icon: const Icon(Icons.volume_up_rounded),
            label: const Text(
              'Nghe phát âm Google Dịch',
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
    );
  }

  /// Mặt sau của thẻ Flashcard: Hiển thị toàn bộ dữ liệu Google Dịch đã lưu
  Widget _buildBackCard(FlashcardItem card) {
    return Container(
      key: const ValueKey(true),
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: ChibiTheme.kawaiiCardDecoration(
        color: Colors.white,
        borderColor: ChibiTheme.pastelLavender,
        radius: 30,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                decoration: BoxDecoration(
                  color: ChibiTheme.softLavender,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Text(
                  'STT #${card.indexNumber} • ${card.englishWord}',
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    color: ChibiTheme.textDark,
                  ),
                ),
              ),
              IconButton.filledTonal(
                onPressed: () =>
                    AudioSpeechService.speakEnglishWord(card.englishWord),
                style: IconButton.styleFrom(
                  backgroundColor: ChibiTheme.softPink,
                  foregroundColor: ChibiTheme.deepPink,
                ),
                icon: const Icon(Icons.volume_up_rounded, size: 20),
              ),
            ],
          ),
          const SizedBox(height: 10),
          const Text(
            'Nghĩa tiếng Việt:',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: ChibiTheme.textMuted,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            card.primaryVietnamese,
            style: const TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.w900,
              color: ChibiTheme.deepPink,
            ),
          ),
          if (card.alternativeTranslations.isNotEmpty) ...[
            const SizedBox(height: 12),
            const Text(
              'Nghĩa thay thế khác:',
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: ChibiTheme.textMuted,
              ),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: card.alternativeTranslations
                  .map(
                    (alt) => Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: ChibiTheme.softLavender,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        alt,
                        style: const TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  )
                  .toList(),
            ),
          ],
          if (card.wordTypes.isNotEmpty) ...[
            const SizedBox(height: 12),
            const Text(
              'Từ loại & Từ vựng liên quan (Google Dịch):',
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: ChibiTheme.textMuted,
              ),
            ),
            const SizedBox(height: 6),
            ...card.wordTypes.map(
              (wt) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: ChibiTheme.bgCream,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: ChibiTheme.softPink),
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
                      const SizedBox(height: 2),
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
                          wt.reverseTranslations.take(5).join(' • '),
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
          if (card.definitions.isNotEmpty) ...[
            const SizedBox(height: 8),
            const Text(
              'Định nghĩa tiếng Anh:',
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: ChibiTheme.textMuted,
              ),
            ),
            const SizedBox(height: 4),
            ...card.definitions.take(3).map(
                  (def) => Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Text(
                      '(${def.pos}) ${def.gloss}',
                      style: const TextStyle(fontSize: 12.5),
                    ),
                  ),
                ),
          ],
          if (card.examples.isNotEmpty) ...[
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
            ...card.examples.take(3).map(
                  (ex) => Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text(
                      '“$ex”',
                      style: const TextStyle(
                        fontSize: 12.5,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ),
                ),
          ],
          const SizedBox(height: 6),
          TextButton.icon(
            onPressed: () {
              setState(() {
                _showRawJson = !_showRawJson;
              });
            },
            icon: Icon(
              _showRawJson
                  ? Icons.expand_less_rounded
                  : Icons.code_rounded,
              size: 18,
            ),
            label: Text(
              _showRawJson
                  ? 'Ẩn dữ liệu JSON gốc của Google Dịch'
                  : 'Xem toàn bộ JSON gốc từ Google Dịch',
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          if (_showRawJson)
            Container(
              constraints: const BoxConstraints(maxHeight: 150),
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFFF6F2F8),
                borderRadius: BorderRadius.circular(14),
              ),
              child: SingleChildScrollView(
                child: Text(
                  card.rawGoogleResponseJson,
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 11,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// Khung thu âm giọng người dùng để kiểm tra xem phát âm đã đúng từ chưa
  Widget _buildPronunciationPracticeBox(FlashcardItem card) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: ChibiTheme.kawaiiCardDecoration(
        color: Colors.white,
        borderColor: _isPronouncedRight == null
            ? ChibiTheme.pastelMint
            : (_isPronouncedRight!
                ? ChibiTheme.pastelMatcha
                : ChibiTheme.pastelPink),
        radius: 26,
      ),
      child: Column(
        children: [
          Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: Image.asset(
                  'assets/images/chibi_listen.jpg',
                  width: 56,
                  height: 56,
                  fit: BoxFit.cover,
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Luyện phát âm cùng Chibi 🎙️',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                        color: ChibiTheme.textDark,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'Bấm nút Thu âm và đọc từ tiếng Anh để xem Google nhận diện bạn phát âm đúng từ chưa nhé!',
                      style: TextStyle(
                        fontSize: 12,
                        color: ChibiTheme.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          ElevatedButton.icon(
            onPressed: () => _toggleRecording(card.englishWord),
            style: ElevatedButton.styleFrom(
              backgroundColor:
                  _isListening ? ChibiTheme.deepPink : ChibiTheme.pastelPink,
              foregroundColor: Colors.white,
              padding:
                  const EdgeInsets.symmetric(horizontal: 24, vertical: 13),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(22),
              ),
            ),
            icon: Icon(
              _isListening ? Icons.stop_circle_rounded : Icons.mic_rounded,
            ),
            label: Text(
              _isListening ? 'Đang thu âm... (Bấm để dừng)' : 'Bấm để thu âm giọng đọc',
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          if (_speechStatusHint != null) ...[
            const SizedBox(height: 10),
            Text(
              _speechStatusHint!,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: ChibiTheme.deepPink,
              ),
            ),
          ],
          if (_recognizedWords.isNotEmpty) ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: (_isPronouncedRight ?? false)
                    ? const Color(0xFFE8FBF5)
                    : const Color(0xFFFFEDF2),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: (_isPronouncedRight ?? false)
                      ? ChibiTheme.pastelMatcha
                      : ChibiTheme.pastelPink,
                  width: 2,
                ),
              ),
              child: Column(
                children: [
                  Text(
                    'Giọng bạn vừa đọc: "$_recognizedWords"',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        (_isPronouncedRight ?? false)
                            ? Icons.check_circle_rounded
                            : Icons.info_rounded,
                        color: (_isPronouncedRight ?? false)
                            ? const Color(0xFF1F9D73)
                            : ChibiTheme.deepPink,
                        size: 20,
                      ),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          (_isPronouncedRight ?? false)
                              ? 'Tuyệt vời! Bạn đã phát âm đúng từ "${card.englishWord}"!'
                              : 'Chưa khớp với từ "${card.englishWord}", bạn thử đọc lại nhé!',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w800,
                            color: (_isPronouncedRight ?? false)
                                ? const Color(0xFF1F9D73)
                                : ChibiTheme.deepPink,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
