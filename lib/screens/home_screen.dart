import 'package:flutter/material.dart';
import '../models/flashcard_model.dart';
import '../services/audio_speech_service.dart';
import '../services/daily_reminder_widget_service.dart';
import '../services/lan_sync_service.dart';
import '../services/storage_service.dart';
import '../theme/chibi_theme.dart';
import 'add_flashcard_sheet.dart';
import 'flashcard_study_screen.dart';
import 'notes_screen.dart';
import 'review_screen.dart';
import 'settings_screen.dart';
import 'topic_vocab_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  // Thứ tự 4 tab:
  // 0 = Flashcard
  // 1 = Ôn tập
  // 2 = Topic (vị trí thứ 3)
  // 3 = Cài đặt (vị trí thứ 4)
  int _selectedTabIndex = 0;
  List<FlashcardItem> _flashcards = [];
  bool _isLoading = true;
  bool _sortNewestFirst = true;
  int _syncRefreshVersion = 0;

  @override
  void initState() {
    super.initState();
    _loadData();
    _initAutoLanSync();
  }

  @override
  void dispose() {
    LanSyncService.removeDataSyncedListener(_reloadAfterLanSync);
    LanSyncService.removeSyncCompletedListener(_onAutoLanSyncCompleted);
    super.dispose();
  }

  Future<void> _reloadAfterLanSync() async {
    final loaded = await StorageService.loadFlashcards();
    await DailyReminderWidgetService.updateDailyWordWidgetAndLockScreen(loaded);
    if (!mounted) return;
    setState(() {
      _flashcards = loaded;
      _syncRefreshVersion++;
    });
  }

  void _onAutoLanSyncCompleted(LanSyncResult result) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: const Color(0xFF15803D),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        content: Text(
          '📲 ${result.message}',
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
    );
  }

  Future<void> _initAutoLanSync() async {
    await LanSyncService.initAutoSyncOnAppStart(
      onDataSynced: _reloadAfterLanSync,
      onAutoSyncSuccess: _onAutoLanSyncCompleted,
    );
  }

  Future<void> _loadData() async {
    await AudioSpeechService.loadVoiceSettings();
    final loaded = await StorageService.loadFlashcards();
    if (!mounted) return;
    setState(() {
      _flashcards = loaded;
      _isLoading = false;
    });

    final newDayPendingCount =
        await DailyReminderWidgetService.checkNewDayAndSyncWidget(loaded);
    if (!mounted) return;
    if (newDayPendingCount > 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: ChibiTheme.deepPink,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 4),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          action: SnackBarAction(
            label: 'Ôn ngay',
            textColor: Colors.white,
            onPressed: () {
              if (mounted) {
                setState(() {
                  _selectedTabIndex = 2; // Tab Ôn tập
                });
              }
            },
          ),
          content: Text(
            '🌅 Đã qua ngày mới! Bạn có $newDayPendingCount từ mới chờ ôn tập hôm nay.',
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
        ),
      );
    }
  }

  Future<void> _handleAddFlashcard(FlashcardItem newCard) async {
    final updated = await StorageService.addFlashcard(newCard);
    await DailyReminderWidgetService.updateDailyWordWidgetAndLockScreen(updated);
    await DailyReminderWidgetService.scheduleDailyReviewReminder(updated);
    if (!mounted) return;
    setState(() {
      _flashcards = updated;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: ChibiTheme.deepPink,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        content: Text(
          'Đã lưu Flashcard #${updated.length}: ${newCard.englishWord} ✨',
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
    );
  }

  void _openAddFlashcardModal() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => AddFlashcardSheet(
        nextIndexNumber: _flashcards.length + 1,
        onCardAdded: _handleAddFlashcard,
      ),
    );
  }

  Future<void> _confirmDelete(FlashcardItem item) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
        ),
        title: const Text(
          'Xóa Flashcard này?',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
        content: Text(
          'Bạn có muốn xóa thẻ #${item.indexNumber} "${item.englishWord}" không? Các thẻ sau sẽ tự động cập nhật lại số thứ tự.',
        ),
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
            child: const Text('Xóa thẻ'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      final updated = await StorageService.deleteFlashcard(item.id);
      await DailyReminderWidgetService.updateDailyWordWidgetAndLockScreen(updated);
      await DailyReminderWidgetService.scheduleDailyReviewReminder(updated);
      if (!mounted) return;
      setState(() {
        _flashcards = updated;
      });
    }
  }

  String _getAppBarTitle() {
    switch (_selectedTabIndex) {
      case 0:
        return 'Chibi Flashcard Tiếng Anh';
      case 1:
        return 'Ghi Chú & Khái Niệm';
      case 2:
        return 'Ôn Tập Từ Vựng';
      case 3:
        return 'Topic Từ Vựng';
      case 4:
        return 'Cài Đặt';
      default:
        return 'Chibi Flashcard Tiếng Anh';
    }
  }

  List<FlashcardItem> _getSortedFlashcards() {
    final copy = List<FlashcardItem>.from(_flashcards);
    if (_sortNewestFirst) {
      copy.sort((a, b) => b.indexNumber.compareTo(a.indexNumber));
    } else {
      copy.sort((a, b) => a.indexNumber.compareTo(b.indexNumber));
    }
    return copy;
  }

  @override
  Widget build(BuildContext context) {
    final canReview = _flashcards.length >= 10;

    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Image.asset(
                'assets/images/app_logo.png',
                width: 32,
                height: 32,
                fit: BoxFit.cover,
              ),
            ),
            const SizedBox(width: 8),
            Text(_getAppBarTitle()),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: ChibiTheme.pastelPink),
            )
          : IndexedStack(
              index: _selectedTabIndex,
              children: [
                _buildFlashcardListTab(canReview),
                NotesScreen(key: ValueKey('notes_$_syncRefreshVersion')),
                ReviewScreen(
                  allFlashcards: _flashcards,
                  onFlashcardsUpdated: (updated) {
                    setState(() {
                      _flashcards = updated;
                    });
                    DailyReminderWidgetService
                        .updateDailyWordWidgetAndLockScreen(updated);
                    DailyReminderWidgetService.scheduleDailyReviewReminder(
                        updated);
                  },
                ),
                TopicVocabScreen(
                  key: ValueKey('topic_$_syncRefreshVersion'),
                  userFlashcards: _flashcards,
                  onAddWordToFlashcards: _handleAddFlashcard,
                ),
                SettingsScreen(
                  onDataSynced: () async {
                    final loaded = await StorageService.loadFlashcards();
                    if (!mounted) return;
                    setState(() {
                      _flashcards = loaded;
                      _syncRefreshVersion++;
                    });
                  },
                ),
              ],
            ),
      floatingActionButton: _selectedTabIndex == 0
          ? FloatingActionButton.extended(
              onPressed: _openAddFlashcardModal,
              backgroundColor: ChibiTheme.deepPink,
              foregroundColor: Colors.white,
              elevation: 4,
              icon: const Icon(Icons.add_rounded),
              label: const Text(
                'Thêm từ mới',
                style: TextStyle(fontWeight: FontWeight.w900),
              ),
            )
          : null,
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          boxShadow: [
            BoxShadow(
              color: ChibiTheme.softPink.withValues(alpha: 0.6),
              blurRadius: 16,
              offset: const Offset(0, -4),
            ),
          ],
        ),
        child: NavigationBar(
          selectedIndex: _selectedTabIndex,
          onDestinationSelected: (idx) {
            setState(() {
              _selectedTabIndex = idx;
            });
          },
          backgroundColor: Colors.white,
          indicatorColor: ChibiTheme.softPink,
          destinations: [
            const NavigationDestination(
              icon: Icon(Icons.style_outlined),
              selectedIcon: Icon(
                Icons.style_rounded,
                color: ChibiTheme.deepPink,
              ),
              label: 'Flashcard',
            ),
            const NavigationDestination(
              icon: Icon(Icons.edit_note_outlined),
              selectedIcon: Icon(
                Icons.edit_note_rounded,
                color: ChibiTheme.deepPink,
              ),
              label: 'Ghi chú',
            ),
            NavigationDestination(
              icon: Badge(
                backgroundColor:
                    canReview ? const Color(0xFF15803D) : ChibiTheme.deepPink,
                label: Text(
                  canReview ? 'Sẵn sàng' : '${_flashcards.length}/10',
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                child: const Icon(Icons.quiz_outlined),
              ),
              selectedIcon: const Icon(
                Icons.quiz_rounded,
                color: ChibiTheme.deepPink,
              ),
              label: 'Ôn tập',
            ),
            const NavigationDestination(
              icon: Icon(Icons.library_books_outlined),
              selectedIcon: Icon(
                Icons.library_books_rounded,
                color: ChibiTheme.deepPink,
              ),
              label: 'Topic',
            ),
            const NavigationDestination(
              icon: Icon(Icons.settings_outlined),
              selectedIcon: Icon(
                Icons.settings_rounded,
                color: ChibiTheme.deepPink,
              ),
              label: 'Cài đặt',
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFlashcardListTab(bool canReview) {
    final sortedFlashcards = _getSortedFlashcards();

    return Column(
      children: [
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
                    'assets/images/chibi_study.jpg',
                    width: 74,
                    height: 74,
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
                            horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: canReview
                              ? const Color(0xFFE6F7EE)
                              : ChibiTheme.softPink,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          canReview
                              ? 'Đã mở khóa Ôn Tập 🎉'
                              : 'Tiến độ mở Ôn tập: ${_flashcards.length}/10 thẻ',
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w900,
                            color: canReview
                                ? const Color(0xFF15803D)
                                : ChibiTheme.deepPink,
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        'Sổ Tay Từ Vựng Chibi 💎',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w900,
                          color: ChibiTheme.textDark,
                        ),
                      ),
                      const SizedBox(height: 2),
                      const Text(
                        'Chạm vào từ bất kỳ để lật xem nghĩa tiếng Việt và thu âm kiểm tra phát âm!',
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

        if (_flashcards.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 4),
            child: Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => FlashcardStudyScreen(
                            flashcards: sortedFlashcards,
                            initialIndex: 0,
                          ),
                        ),
                      );
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: ChibiTheme.deepPink,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(18),
                      ),
                    ),
                    icon: const Icon(Icons.menu_book_rounded),
                    label: const Text(
                      'Học flashcard',
                      style: TextStyle(fontWeight: FontWeight.w900),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () {
                      setState(() {
                        _selectedTabIndex = 2;
                      });
                    },
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      side: const BorderSide(
                          color: ChibiTheme.pastelPink, width: 2),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(18),
                      ),
                    ),
                    icon: Icon(
                      canReview
                          ? Icons.quiz_rounded
                          : Icons.lock_clock_rounded,
                      color: ChibiTheme.deepPink,
                    ),
                    label: Text(
                      canReview
                          ? 'Vào Ôn Tập ngay'
                          : 'Ôn Tập (${_flashcards.length}/10)',
                      style: const TextStyle(
                        fontWeight: FontWeight.w900,
                        color: ChibiTheme.deepPink,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Thanh chọn sắp xếp: Mới nhất / Cũ nhất
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 6, 20, 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Danh sách từ vựng (${_flashcards.length})',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: ChibiTheme.textMuted,
                  ),
                ),
                Row(
                  children: [
                    ChoiceChip(
                      label: const Text('Mới nhất'),
                      selected: _sortNewestFirst,
                      onSelected: (val) {
                        if (val) {
                          setState(() {
                            _sortNewestFirst = true;
                          });
                        }
                      },
                      selectedColor: ChibiTheme.deepPink,
                      backgroundColor: Colors.white,
                      side: const BorderSide(color: ChibiTheme.softPink),
                      labelStyle: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: _sortNewestFirst
                            ? Colors.white
                            : ChibiTheme.textDark,
                      ),
                      visualDensity: VisualDensity.compact,
                    ),
                    const SizedBox(width: 6),
                    ChoiceChip(
                      label: const Text('Cũ nhất'),
                      selected: !_sortNewestFirst,
                      onSelected: (val) {
                        if (val) {
                          setState(() {
                            _sortNewestFirst = false;
                          });
                        }
                      },
                      selectedColor: ChibiTheme.deepPink,
                      backgroundColor: Colors.white,
                      side: const BorderSide(color: ChibiTheme.softPink),
                      labelStyle: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: !_sortNewestFirst
                            ? Colors.white
                            : ChibiTheme.textDark,
                      ),
                      visualDensity: VisualDensity.compact,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],

        // Danh sách các thẻ Flashcard ở Home: Chỉ hiển thị Từ tiếng Anh và Phiên âm/Cách phát âm
        Expanded(
          child: sortedFlashcards.isEmpty
              ? _buildEmptyState()
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(18, 6, 18, 96),
                  itemCount: sortedFlashcards.length,
                  itemBuilder: (context, index) {
                    final item = sortedFlashcards[index];
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(24),
                        onTap: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => FlashcardStudyScreen(
                                flashcards: sortedFlashcards,
                                initialIndex: index,
                              ),
                            ),
                          );
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 14),
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
                                width: 46,
                                height: 46,
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  color: index.isEven
                                      ? ChibiTheme.softPink
                                      : ChibiTheme.softLavender,
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                child: Text(
                                  '#${item.indexNumber}',
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w900,
                                    color: ChibiTheme.deepPink,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      item.englishWord,
                                      style: const TextStyle(
                                        fontSize: 20,
                                        fontWeight: FontWeight.w900,
                                        color: ChibiTheme.textDark,
                                      ),
                                    ),
                                    const SizedBox(height: 3),
                                    Text(
                                      item.phonetic.isNotEmpty
                                          ? '/${item.phonetic}/'
                                          : 'Bấm loa để nghe phát âm',
                                      style: const TextStyle(
                                        fontSize: 14,
                                        fontStyle: FontStyle.italic,
                                        color: ChibiTheme.deepPink,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              IconButton(
                                onPressed: () =>
                                    AudioSpeechService.speakEnglishWord(
                                        item.englishWord),
                                icon: const Icon(
                                  Icons.volume_up_rounded,
                                  color: ChibiTheme.deepPink,
                                ),
                                tooltip: 'Nghe phát âm',
                              ),
                              IconButton(
                                onPressed: () => _confirmDelete(item),
                                icon: const Icon(
                                  Icons.delete_outline_rounded,
                                  color: ChibiTheme.textMuted,
                                ),
                                tooltip: 'Xóa thẻ',
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
    );
  }

  Widget _buildEmptyState() {
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
                borderRadius: BorderRadius.circular(22),
                child: Image.asset(
                  'assets/images/chibi_study.jpg',
                  width: 130,
                  height: 130,
                  fit: BoxFit.cover,
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Chưa có Flashcard nào!',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                  color: ChibiTheme.textDark,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'Hãy bấm nút "Thêm từ mới" bên dưới (ứng dụng sẽ tìm trong Topic trước, nếu chưa có sẽ gọi Google Dịch) hoặc chọn từ trực tiếp ở tab "Topic"!',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13.5,
                  color: ChibiTheme.textMuted,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 14),
              OutlinedButton.icon(
                onPressed: () {
                  setState(() {
                    _selectedTabIndex = 3;
                  });
                },
                style: OutlinedButton.styleFrom(
                  side:
                      const BorderSide(color: ChibiTheme.pastelPink, width: 2),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                icon: const Icon(Icons.library_books_rounded),
                label: const Text(
                  'Mở kho Topic từ vựng (3.000 từ)',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
