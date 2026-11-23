import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import '../models/flashcard_model.dart';
import 'storage_service.dart';

class DailyReminderWidgetService {
  static final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();
  static const MethodChannel _widgetChannel =
      MethodChannel('com.chibi.flashcard/widget');

  static const int _dailyReminderNotifId = 1001;
  static const int _lockScreenWidgetNotifId = 1002;

  static const String _prefDailyReminderEnabledKey =
      'chibi_daily_reminder_enabled_v1';
  static const String _prefDailyReminderHourKey =
      'chibi_daily_reminder_hour_v1';
  static const String _prefDailyReminderMinuteKey =
      'chibi_daily_reminder_minute_v1';
  static const String _prefLockScreenWidgetEnabledKey =
      'chibi_lock_screen_widget_enabled_v1';
  static const String _prefLastActiveDateKey = 'chibi_last_active_date_v1';

  // Các khóa dùng chung với Native Android AppWidget (`FlashcardWidgetProvider.kt`)
  static const String _widgetWordKey = 'chibi_widget_word';
  static const String _widgetPhoneticKey = 'chibi_widget_phonetic';
  static const String _widgetMeaningKey = 'chibi_widget_meaning';
  static const String _widgetSummaryKey = 'chibi_widget_summary';

  static bool _initialized = false;
  static bool _dailyReminderEnabled = true;
  static int _reminderHour = 8;
  static int _reminderMinute = 30;
  static bool _lockScreenWidgetEnabled = true;

  static bool get dailyReminderEnabled => _dailyReminderEnabled;
  static int get reminderHour => _reminderHour;
  static int get reminderMinute => _reminderMinute;
  static bool get lockScreenWidgetEnabled => _lockScreenWidgetEnabled;

  /// Khởi tạo hệ thống Thông báo, Lịch nhắc ôn tập qua ngày & Tiện ích màn hình khóa
  static Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;

    try {
      tz.initializeTimeZones();
      try {
        tz.setLocalLocation(tz.getLocation('Asia/Ho_Chi_Minh'));
      } catch (_) {}

      const androidSettings =
          AndroidInitializationSettings('@mipmap/ic_launcher');
      const iosSettings = DarwinInitializationSettings(
        requestAlertPermission: true,
        requestBadgePermission: true,
        requestSoundPermission: true,
      );
      const initSettings = InitializationSettings(
        android: androidSettings,
        iOS: iosSettings,
      );

      await _notifications.initialize(settings: initSettings);

      if (Platform.isAndroid) {
        final androidPlugin =
            _notifications.resolvePlatformSpecificImplementation<
                AndroidFlutterLocalNotificationsPlugin>();
        await androidPlugin?.requestNotificationsPermission();
      } else if (Platform.isIOS) {
        final iosPlugin =
            _notifications.resolvePlatformSpecificImplementation<
                IOSFlutterLocalNotificationsPlugin>();
        await iosPlugin?.requestPermissions(
          alert: true,
          badge: true,
          sound: true,
        );
      }
    } catch (_) {}

    await loadSettings();
  }

  static Future<void> loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    _dailyReminderEnabled =
        prefs.getBool(_prefDailyReminderEnabledKey) ?? true;
    _reminderHour = prefs.getInt(_prefDailyReminderHourKey) ?? 8;
    _reminderMinute = prefs.getInt(_prefDailyReminderMinuteKey) ?? 30;
    _lockScreenWidgetEnabled =
        prefs.getBool(_prefLockScreenWidgetEnabledKey) ?? true;
  }

  /// Kiểm tra xem đã bước sang ngày mới chưa:
  /// - Nếu đã qua ngày mới và còn các từ mới chưa ôn tập (`!isReviewed` hoặc `isNotRemembered`),
  ///   trả về số lượng từ cần ôn tập hôm nay để nhắc người dùng ngay khi mở app
  ///   đồng thời đặt lịch thông báo nhắc ôn tập hàng ngày và cập nhật Tiện ích màn hình khóa.
  static Future<int> checkNewDayAndSyncWidget(
      List<FlashcardItem> flashcards) async {
    await initialize();
    final prefs = await SharedPreferences.getInstance();

    final now = DateTime.now();
    final todayStr =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    final lastDateStr = prefs.getString(_prefLastActiveDateKey);

    final isNewDay = (lastDateStr != null && lastDateStr != todayStr);
    await prefs.setString(_prefLastActiveDateKey, todayStr);

    // Cập nhật Tiện ích màn hình khóa & Home Widget với từ mới trong ngày
    await updateDailyWordWidgetAndLockScreen(flashcards);

    // Đặt lịch nhắc ôn tập hàng ngày khi qua ngày mới
    await scheduleDailyReviewReminder(flashcards);

    if (isNewDay) {
      final unreviewedCount =
          flashcards.where((c) => !c.isReviewed || c.isNotRemembered).length;
      if (unreviewedCount > 0) {
        await showImmediateNewDayReminder(unreviewedCount, flashcards);
        return unreviewedCount;
      }
    }
    return 0;
  }

  /// Chọn danh sách các từ mới tạo trong ngày hôm nay (hoặc từ mới chưa ôn tập gần nhất)
  static List<FlashcardItem> getTodayNewWords(List<FlashcardItem> flashcards) {
    if (flashcards.isEmpty) return [];
    final now = DateTime.now();
    final todayCards = flashcards.where((c) {
      return c.createdAt.year == now.year &&
          c.createdAt.month == now.month &&
          c.createdAt.day == now.day;
    }).toList();

    if (todayCards.isNotEmpty) {
      return todayCards.reversed.toList();
    }

    // Nếu hôm nay chưa thêm từ mới thì lấy các từ mới chưa được ôn tập gần nhất
    final unreviewed = flashcards.where((c) => !c.isReviewed).toList();
    if (unreviewed.isNotEmpty) {
      return unreviewed.reversed.toList();
    }

    // Dự phòng: lấy các từ mới nhất trong danh sách
    return flashcards.reversed.take(5).toList();
  }

  /// Cập nhật cả:
  /// 1. Native Android Home/Lock Screen AppWidget (`FlashcardWidgetProvider`)
  /// 2. Tiện ích thông báo ghim trên Màn hình khóa (Lock Screen Widget Card trên cả iOS & Android)
  static Future<void> updateDailyWordWidgetAndLockScreen([
    List<FlashcardItem>? cardsInput,
  ]) async {
    await initialize();
    final flashcards = cardsInput ?? await StorageService.loadFlashcards();
    final todayWords = getTodayNewWords(flashcards);
    final prefs = await SharedPreferences.getInstance();

    String widgetWord = 'Chưa có từ mới';
    String widgetPhonetic = '';
    String widgetMeaning = 'Hãy thêm từ mới vào Chibi Flashcard nhé!';
    String widgetSummary = '💎 TỪ MỚI TRONG NGÀY • CHIBI FLASHCARD';

    if (todayWords.isNotEmpty) {
      final featured = todayWords.first;
      final extraCount = todayWords.length - 1;
      widgetWord = featured.englishWord;
      widgetPhonetic = featured.phonetic;
      widgetMeaning = featured.primaryVietnamese;
      widgetSummary = extraCount > 0
          ? '💎 TỪ MỚI HÔM NAY (${todayWords.length} TỪ) • CHIBI FLASHCARD'
          : '💎 TỪ MỚI TRONG NGÀY • CHIBI FLASHCARD';
    }

    await prefs.setString(_widgetWordKey, widgetWord);
    await prefs.setString(_widgetPhoneticKey, widgetPhonetic);
    await prefs.setString(_widgetMeaningKey, widgetMeaning);
    await prefs.setString(_widgetSummaryKey, widgetSummary);

    // 1. Yêu cầu cả iOS (WidgetKit Lock Screen / Home Screen) và Android (AppWidget) cập nhật ngay
    try {
      await _widgetChannel.invokeMethod('updateWidget', {
        'word': widgetWord,
        'phonetic': widgetPhonetic,
        'meaning': widgetMeaning,
        'summary': widgetSummary,
      });
    } catch (_) {}

    // 2. Hiển thị / Cập nhật Tiện ích Từ Mới Trong Ngày trên Màn hình khóa (Lock Screen)
    if (!_lockScreenWidgetEnabled || todayWords.isEmpty) {
      try {
        await _notifications.cancel(id: _lockScreenWidgetNotifId);
      } catch (_) {}
      return;
    }

    final topWord = todayWords.first;
    final phoneticPart =
        topWord.phonetic.isNotEmpty ? ' /${topWord.phonetic}/' : '';
    final title =
        '💎 Từ mới trong ngày: ${topWord.englishWord}$phoneticPart';

    final listPreview = todayWords
        .take(4)
        .map((c) =>
            '• ${c.englishWord}${c.phonetic.isNotEmpty ? " /${c.phonetic}/" : ""}: ${c.primaryVietnamese}')
        .join('\n');

    final androidDetails = AndroidNotificationDetails(
      'chibi_lockscreen_daily_word',
      'Tiện ích Từ Mới Màn Hình Khóa',
      channelDescription:
          'Hiển thị tiện ích từ vựng mới trong ngày ngay trên màn hình khóa',
      importance: Importance.low,
      priority: Priority.low,
      ongoing: true,
      autoCancel: false,
      onlyAlertOnce: true,
      playSound: false,
      enableVibration: false,
      visibility: NotificationVisibility.public,
      styleInformation: BigTextStyleInformation(
        listPreview,
        contentTitle: title,
        summaryText: 'Tiện ích từ mới Chibi (${todayWords.length} từ hôm nay)',
      ),
    );

    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBanner: true,
      presentList: true,
      presentSound: false,
      interruptionLevel: InterruptionLevel.active,
    );

    try {
      await _notifications.show(
        id: _lockScreenWidgetNotifId,
        title: title,
        body: listPreview,
        notificationDetails: NotificationDetails(
          android: androidDetails,
          iOS: iosDetails,
        ),
      );
    } catch (_) {}
  }

  /// Gửi thông báo nhắc nhở ngay khi bước qua ngày mới mà còn từ mới chưa ôn tập
  static Future<void> showImmediateNewDayReminder(
    int unreviewedCount,
    List<FlashcardItem> flashcards,
  ) async {
    if (!_dailyReminderEnabled) return;
    final sampleWords = flashcards
        .where((c) => !c.isReviewed || c.isNotRemembered)
        .take(3)
        .map((c) => c.englishWord)
        .join(', ');

    const androidDetails = AndroidNotificationDetails(
      'chibi_daily_review_reminder',
      'Nhắc Ôn Tập Từ Mới Qua Ngày',
      channelDescription: 'Nhắc nhở ôn tập các từ vựng mới khi bước qua ngày mới',
      importance: Importance.high,
      priority: Priority.high,
      visibility: NotificationVisibility.public,
    );
    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBanner: true,
      presentSound: true,
    );

    try {
      await _notifications.show(
        id: _dailyReminderNotifId + 10,
        title: '🌅 Ngày mới rồi! Cùng ôn tập $unreviewedCount từ mới nhé',
        body: sampleWords.isNotEmpty
            ? 'Các từ đang chờ bạn: $sampleWords...'
            : 'Mở Chibi Flashcard để ôn tập từ mới hôm nay nhé!',
        notificationDetails: const NotificationDetails(
          android: androidDetails,
          iOS: iosDetails,
        ),
      );
    } catch (_) {}
  }

  /// Đặt lịch tự động nhắc ôn tập từ mới hàng ngày vào khung giờ người dùng chọn (Mặc định 08:30 sáng mỗi ngày)
  static Future<void> scheduleDailyReviewReminder([
    List<FlashcardItem>? cardsInput,
  ]) async {
    await initialize();
    try {
      await _notifications.cancel(id: _dailyReminderNotifId);
    } catch (_) {}

    if (!_dailyReminderEnabled) return;

    final flashcards = cardsInput ?? await StorageService.loadFlashcards();
    final unreviewed =
        flashcards.where((c) => !c.isReviewed || c.isNotRemembered).toList();
    final count = unreviewed.isNotEmpty ? unreviewed.length : flashcards.length;
    final sampleWords = (unreviewed.isNotEmpty ? unreviewed : flashcards)
        .take(4)
        .map((c) => c.englishWord)
        .join(', ');

    final now = tz.TZDateTime.now(tz.local);
    var scheduledDate = tz.TZDateTime(
      tz.local,
      now.year,
      now.month,
      now.day,
      _reminderHour,
      _reminderMinute,
    );
    if (scheduledDate.isBefore(now)) {
      scheduledDate = scheduledDate.add(const Duration(days: 1));
    }

    const androidDetails = AndroidNotificationDetails(
      'chibi_daily_review_reminder',
      'Nhắc Ôn Tập Từ Mới Qua Ngày',
      channelDescription: 'Nhắc nhở ôn tập các từ vựng mới khi bước qua ngày mới',
      importance: Importance.high,
      priority: Priority.high,
      visibility: NotificationVisibility.public,
    );
    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBanner: true,
      presentSound: true,
    );

    try {
      await _notifications.zonedSchedule(
        id: _dailyReminderNotifId,
        title: count > 0
            ? '⏰ Nhắc ôn tập: Bạn có $count từ vựng cần ôn hôm nay!'
            : '⏰ Đã qua ngày mới! Cùng học từ vựng với Chibi nhé!',
        body: sampleWords.isNotEmpty
            ? 'Từ mới cần ôn: $sampleWords...'
            : 'Mở Chibi Flashcard để thêm và ôn tập từ mới trong ngày nhé!',
        scheduledDate: scheduledDate,
        notificationDetails: const NotificationDetails(
          android: androidDetails,
          iOS: iosDetails,
        ),
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        matchDateTimeComponents: DateTimeComponents.time,
      );
    } catch (_) {}
  }

  static Future<void> setDailyReminderEnabled(bool enabled) async {
    _dailyReminderEnabled = enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefDailyReminderEnabledKey, enabled);
    await scheduleDailyReviewReminder();
  }

  static Future<void> setDailyReminderTime(int hour, int minute) async {
    _reminderHour = hour;
    _reminderMinute = minute;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_prefDailyReminderHourKey, hour);
    await prefs.setInt(_prefDailyReminderMinuteKey, minute);
    await scheduleDailyReviewReminder();
  }

  static Future<void> setLockScreenWidgetEnabled(bool enabled) async {
    _lockScreenWidgetEnabled = enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefLockScreenWidgetEnabledKey, enabled);
    await updateDailyWordWidgetAndLockScreen();
  }
}
