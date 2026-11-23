import 'package:flutter/material.dart';
import '../services/audio_speech_service.dart';
import '../services/daily_reminder_widget_service.dart';
import '../services/lan_sync_service.dart';
import '../theme/chibi_theme.dart';

class SettingsScreen extends StatefulWidget {
  final VoidCallback? onDataSynced;

  const SettingsScreen({
    super.key,
    this.onDataSynced,
  });

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  String _selectedVoiceId = AudioSpeechService.currentVoiceId;
  double _speechRate = AudioSpeechService.currentSpeechRate;
  bool _isLoading = true;

  // Trạng thái Nhắc ôn tập qua ngày & Tiện ích màn hình khóa
  bool _dailyReminderEnabled = DailyReminderWidgetService.dailyReminderEnabled;
  int _reminderHour = DailyReminderWidgetService.reminderHour;
  int _reminderMinute = DailyReminderWidgetService.reminderMinute;
  bool _lockScreenWidgetEnabled =
      DailyReminderWidgetService.lockScreenWidgetEnabled;

  // Trạng thái Đồng bộ mạng LAN giữa 2 điện thoại
  bool _isLanServerRunning = LanSyncService.isServerRunning;
  bool _autoSyncEnabled = LanSyncService.autoSyncEnabled;
  String? _myLanIp = LanSyncService.localIp;
  String? _savedPeerIp = LanSyncService.savedPeerIp;
  String? _savedPeerName = LanSyncService.savedPeerName;
  bool _isSyncing = false;
  String? _syncStatusMessage;
  bool _isSyncSuccess = true;
  final TextEditingController _peerIpController = TextEditingController();
  final Map<String, DiscoveredLanPeer> _discoveredPeers = {};

  @override
  void initState() {
    super.initState();
    _initSettings();
    LanSyncService.addSyncCompletedListener(_onBackgroundSyncCompleted);
  }

  @override
  void dispose() {
    LanSyncService.removeSyncCompletedListener(_onBackgroundSyncCompleted);
    _peerIpController.dispose();
    super.dispose();
  }

  void _onBackgroundSyncCompleted(LanSyncResult result) {
    if (!mounted) return;
    setState(() {
      _savedPeerIp = LanSyncService.savedPeerIp;
      _savedPeerName = LanSyncService.savedPeerName;
      if (_savedPeerIp != null && _peerIpController.text.trim().isEmpty) {
        _peerIpController.text = _savedPeerIp!;
      }
      _syncStatusMessage = result.message;
      _isSyncSuccess = true;
    });
  }

  Future<void> _initSettings() async {
    await AudioSpeechService.loadVoiceSettings();
    await DailyReminderWidgetService.loadSettings();
    await LanSyncService.loadSavedSyncConfig();
    final ip = await LanSyncService.getLocalLanIp();
    if (!mounted) return;
    setState(() {
      _selectedVoiceId = AudioSpeechService.currentVoiceId;
      _speechRate = AudioSpeechService.currentSpeechRate;
      _dailyReminderEnabled = DailyReminderWidgetService.dailyReminderEnabled;
      _reminderHour = DailyReminderWidgetService.reminderHour;
      _reminderMinute = DailyReminderWidgetService.reminderMinute;
      _lockScreenWidgetEnabled =
          DailyReminderWidgetService.lockScreenWidgetEnabled;
      _myLanIp = ip;
      _isLanServerRunning = LanSyncService.isServerRunning;
      _autoSyncEnabled = LanSyncService.autoSyncEnabled;
      _savedPeerIp = LanSyncService.savedPeerIp;
      _savedPeerName = LanSyncService.savedPeerName;
      _discoveredPeers.addAll(LanSyncService.discoveredPeers);
      if (_savedPeerIp != null && _savedPeerIp!.isNotEmpty) {
        _peerIpController.text = _savedPeerIp!;
      }
      _isLoading = false;
    });
  }

  Future<void> _pickReminderTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: _reminderHour, minute: _reminderMinute),
    );
    if (picked != null) {
      await DailyReminderWidgetService.setDailyReminderTime(
        picked.hour,
        picked.minute,
      );
      if (!mounted) return;
      setState(() {
        _reminderHour = picked.hour;
        _reminderMinute = picked.minute;
      });
    }
  }

  Future<void> _toggleAutoSync(bool value) async {
    await LanSyncService.setAutoSyncEnabled(value);
    if (!mounted) return;
    setState(() {
      _autoSyncEnabled = value;
      _isLanServerRunning = LanSyncService.isServerRunning;
    });
  }

  Future<void> _toggleLanServer() async {
    if (_isLanServerRunning) {
      await LanSyncService.stopLanSyncServer();
      if (!mounted) return;
      setState(() {
        _isLanServerRunning = false;
        _discoveredPeers.clear();
        _syncStatusMessage = 'Đã tắt chế độ chờ đồng bộ mạng LAN.';
        _isSyncSuccess = true;
      });
      return;
    }

    try {
      final ip = await LanSyncService.startLanSyncServer(
        onDataSynced: widget.onDataSynced,
        onPeerDiscovered: (peer) {
          if (!mounted) return;
          setState(() {
            _discoveredPeers[peer.ip] = peer;
            if (_peerIpController.text.trim().isEmpty) {
              _peerIpController.text = peer.ip;
            }
          });
        },
      );

      if (!mounted) return;
      setState(() {
        _myLanIp = ip;
        _isLanServerRunning = true;
        _syncStatusMessage =
            'Đang mở kết nối LAN tại IP: $ip. Điện thoại kia có thể bấm kết nối ngay!';
        _isSyncSuccess = true;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLanServerRunning = false;
        _syncStatusMessage = e.toString().replaceFirst('Exception: ', '');
        _isSyncSuccess = false;
      });
    }
  }

  Future<void> _syncWithTargetIp(String targetIp) async {
    final cleanIp = targetIp.trim();
    if (cleanIp.isEmpty) {
      setState(() {
        _syncStatusMessage =
            'Bạn hãy nhập địa chỉ IP hiện trên màn hình điện thoại kia nhé!';
        _isSyncSuccess = false;
      });
      return;
    }

    setState(() {
      _isSyncing = true;
      _syncStatusMessage = 'Đang đồng bộ dữ liệu với $cleanIp...';
      _isSyncSuccess = true;
    });

    try {
      final result = await LanSyncService.syncWithPeerIp(
        cleanIp,
        onDataSynced: widget.onDataSynced,
      );
      if (!mounted) return;
      setState(() {
        _isSyncing = false;
        _savedPeerIp = LanSyncService.savedPeerIp;
        _savedPeerName = LanSyncService.savedPeerName;
        _syncStatusMessage = result.message;
        _isSyncSuccess = true;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: const Color(0xFF15803D),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          content: Text(
            result.message,
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isSyncing = false;
        _syncStatusMessage = e.toString().replaceFirst('Exception: ', '');
        _isSyncSuccess = false;
      });
    }
  }

  Future<void> _clearSavedDevice() async {
    await LanSyncService.clearSavedPeer();
    if (!mounted) return;
    setState(() {
      _savedPeerIp = null;
      _savedPeerName = null;
      _peerIpController.clear();
      _syncStatusMessage = 'Đã xóa thiết bị đã lưu.';
      _isSyncSuccess = true;
    });
  }

  Future<void> _selectVoice(EnglishVoiceOption option) async {
    await AudioSpeechService.setVoiceOption(option.id);
    if (!mounted) return;
    setState(() {
      _selectedVoiceId = option.id;
    });
    await AudioSpeechService.speakEnglishWord('Vocabulary');
  }

  Future<void> _changeRate(double newRate) async {
    await AudioSpeechService.setSpeechRate(newRate);
    if (!mounted) return;
    setState(() {
      _speechRate = newRate;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: ChibiTheme.pastelPink),
      );
    }

    final usVoices = AudioSpeechService.voiceOptions
        .where((v) => v.localeCode == 'en-US')
        .toList();
    final ukVoices = AudioSpeechService.voiceOptions
        .where((v) => v.localeCode == 'en-GB')
        .toList();

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(18, 8, 18, 36),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 1. Khung Nhắc ôn tập từ mới qua ngày & Tiện ích màn hình khóa
          _buildDailyReminderAndWidgetSection(),
          const SizedBox(height: 18),

          // 2. Khung Đồng Bộ Dữ Liệu Qua Mạng LAN Giữa 2 Điện Thoại (Có lưu thiết bị & tự động đồng bộ khi mở app)
          _buildLanSyncSection(),
          const SizedBox(height: 18),

          // 2. Header Cài đặt giọng đọc
          Container(
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
                    'assets/images/chibi_listen.jpg',
                    width: 68,
                    height: 68,
                    fit: BoxFit.cover,
                  ),
                ),
                const SizedBox(width: 14),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Cài Đặt Giọng Đọc 🎧',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w900,
                          color: ChibiTheme.textDark,
                        ),
                      ),
                      SizedBox(height: 3),
                      Text(
                        'Chọn Giọng Nữ hoặc Giọng Nam theo phát âm Tiếng Mỹ (US) và Tiếng Anh (UK).',
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
          const SizedBox(height: 14),

          _buildAccentSection(
            title: '🇺🇸 Giọng Tiếng Mỹ (American English)',
            voices: usVoices,
          ),
          const SizedBox(height: 14),

          _buildAccentSection(
            title: '🇬🇧 Giọng Tiếng Anh (British English)',
            voices: ukVoices,
          ),
          const SizedBox(height: 14),

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
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Tốc độ phát âm từ mới:',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w900,
                        color: ChibiTheme.textDark,
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: ChibiTheme.softPink,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        _speechRate < 0.85
                            ? 'Chậm rõ chữ (${_speechRate.toStringAsFixed(1)}x)'
                            : (_speechRate > 1.1
                                ? 'Nhanh (${_speechRate.toStringAsFixed(1)}x)'
                                : 'Chuẩn (1.0x)'),
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          color: ChibiTheme.deepPink,
                        ),
                      ),
                    ),
                  ],
                ),
                Slider(
                  value: _speechRate,
                  min: 0.6,
                  max: 1.3,
                  divisions: 7,
                  activeColor: ChibiTheme.deepPink,
                  inactiveColor: ChibiTheme.softPink,
                  onChanged: _changeRate,
                ),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () =>
                        AudioSpeechService.speakEnglishWord('Vocabulary'),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(
                          color: ChibiTheme.pastelPink, width: 1.8),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    icon: const Icon(Icons.volume_up_rounded,
                        color: ChibiTheme.deepPink),
                    label: const Text(
                      'Nghe thử giọng đang chọn ("Vocabulary")',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        color: ChibiTheme.deepPink,
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

  Widget _buildDailyReminderAndWidgetSection() {
    final timeStr =
        '${_reminderHour.toString().padLeft(2, '0')}:${_reminderMinute.toString().padLeft(2, '0')}';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: ChibiTheme.kawaiiCardDecoration(
        color: Colors.white,
        borderColor: ChibiTheme.softPink,
        radius: 26,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
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
                  Icons.notifications_active_rounded,
                  color: ChibiTheme.deepPink,
                  size: 25,
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Nhắc Ôn Tập & Tiện Ích Màn Hình Khóa ⏰',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                        color: ChibiTheme.textDark,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'Nhắc ôn tập từ mới khi qua ngày và ghim từ mới trong ngày lên màn hình khóa',
                      style: TextStyle(
                        fontSize: 12,
                        color: ChibiTheme.textMuted,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // 1. Nhắc ôn tập từ mới khi qua ngày
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: ChibiTheme.bgCream,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: ChibiTheme.softPink),
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    const Icon(Icons.alarm_rounded,
                        color: ChibiTheme.deepPink, size: 22),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Nhắc ôn tập từ mới qua ngày',
                            style: TextStyle(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w900,
                              color: ChibiTheme.textDark,
                            ),
                          ),
                          Text(
                            'Thông báo nhắc học từ mới mỗi ngày',
                            style: TextStyle(
                              fontSize: 11.5,
                              color: ChibiTheme.textMuted,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Switch(
                      value: _dailyReminderEnabled,
                      activeTrackColor: ChibiTheme.deepPink,
                      onChanged: (val) async {
                        await DailyReminderWidgetService
                            .setDailyReminderEnabled(val);
                        if (!mounted) return;
                        setState(() {
                          _dailyReminderEnabled = val;
                        });
                      },
                    ),
                  ],
                ),
                if (_dailyReminderEnabled) ...[
                  const Divider(height: 12, color: ChibiTheme.softPink),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Giờ nhắc hàng ngày:',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          color: ChibiTheme.textDark,
                        ),
                      ),
                      TextButton.icon(
                        onPressed: _pickReminderTime,
                        style: TextButton.styleFrom(
                          backgroundColor: Colors.white,
                          foregroundColor: ChibiTheme.deepPink,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 6),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        icon: const Icon(Icons.access_time_filled_rounded,
                            size: 16),
                        label: Text(
                          timeStr,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 10),

          // 2. Tiện ích hiển thị từ mới trên màn hình khóa
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFFEAF3FF),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: ChibiTheme.softPink),
            ),
            child: Row(
              children: [
                const Icon(Icons.lock_clock_rounded,
                    color: ChibiTheme.deepPink, size: 22),
                const SizedBox(width: 10),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Tiện ích từ mới trên Màn hình khóa',
                        style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w900,
                          color: ChibiTheme.textDark,
                        ),
                      ),
                      Text(
                        'Hiển thị từ mới của Flashcard trong ngày ở màn hình khóa & Widget',
                        style: TextStyle(
                          fontSize: 11.5,
                          color: ChibiTheme.textMuted,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                Switch(
                  value: _lockScreenWidgetEnabled,
                  activeTrackColor: ChibiTheme.deepPink,
                  onChanged: (val) async {
                    await DailyReminderWidgetService.setLockScreenWidgetEnabled(
                        val);
                    if (!mounted) return;
                    setState(() {
                      _lockScreenWidgetEnabled = val;
                    });
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLanSyncSection() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: ChibiTheme.kawaiiCardDecoration(
        color: Colors.white,
        borderColor: ChibiTheme.pastelPink,
        radius: 26,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
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
                  Icons.wifi_protected_setup_rounded,
                  color: ChibiTheme.deepPink,
                  size: 26,
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Đồng Bộ Dữ Liệu Qua Mạng LAN 📲',
                      style: TextStyle(
                        fontSize: 16.5,
                        fontWeight: FontWeight.w900,
                        color: ChibiTheme.textDark,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'Tự động lưu thiết bị và tự động đồng bộ khi mở app nếu mạng LAN sẵn sàng',
                      style: TextStyle(
                        fontSize: 12,
                        color: ChibiTheme.textMuted,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Công tắc: Tự động đồng bộ khi mở ứng dụng
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: const Color(0xFFEAF3FF),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: ChibiTheme.softPink),
            ),
            child: Row(
              children: [
                const Icon(Icons.autorenew_rounded,
                    color: ChibiTheme.deepPink, size: 22),
                const SizedBox(width: 10),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Tự động đồng bộ khi mở App',
                        style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w900,
                          color: ChibiTheme.textDark,
                        ),
                      ),
                      Text(
                        'Tự bật LAN & đồng bộ với thiết bị đã lưu',
                        style: TextStyle(
                          fontSize: 11.5,
                          color: ChibiTheme.textMuted,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                Switch(
                  value: _autoSyncEnabled,
                  activeTrackColor: ChibiTheme.deepPink,
                  onChanged: _toggleAutoSync,
                ),
              ],
            ),
          ),

          // Hiển thị thông tin thiết bị đã lưu (nếu đã từng đồng bộ)
          if (_savedPeerIp != null && _savedPeerIp!.isNotEmpty) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFFE6F7EE),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFF86EFAC)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.link_rounded,
                      color: Color(0xFF15803D), size: 22),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Đã lưu: ${_savedPeerName ?? "Điện thoại Chibi"} ($_savedPeerIp)',
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w900,
                            color: Color(0xFF15803D),
                          ),
                        ),
                        const Text(
                          'Mở app ở cả 2 máy sẽ tự động đồng bộ ngay',
                          style: TextStyle(
                            fontSize: 11.5,
                            color: Color(0xFF166534),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: _clearSavedDevice,
                    icon: const Icon(Icons.close_rounded,
                        size: 18, color: Color(0xFF15803D)),
                    visualDensity: VisualDensity.compact,
                    tooltip: 'Quên thiết bị này',
                  ),
                ],
              ),
            ),
          ],

          const SizedBox(height: 10),

          // Trạng thái IP của máy hiện tại
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: ChibiTheme.bgCream,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: ChibiTheme.softPink),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'IP máy này: ${_myLanIp ?? "Chưa kết nối Wi-Fi"}',
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w900,
                          color: ChibiTheme.deepPink,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _isLanServerRunning
                            ? 'Mạng LAN đã sẵn sàng đồng bộ (Cổng ${LanSyncService.defaultHttpPort})'
                            : 'Đang tắt kết nối LAN',
                        style: const TextStyle(
                          fontSize: 11.5,
                          color: ChibiTheme.textMuted,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
                ElevatedButton.icon(
                  onPressed: _toggleLanServer,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _isLanServerRunning
                        ? Colors.redAccent
                        : ChibiTheme.deepPink,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  icon: Icon(
                    _isLanServerRunning
                        ? Icons.stop_circle_outlined
                        : Icons.sensors_rounded,
                    size: 18,
                  ),
                  label: Text(
                    _isLanServerRunning ? 'Tắt' : 'Bật kết nối',
                    style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ],
            ),
          ),

          if (_discoveredPeers.isNotEmpty) ...[
            const SizedBox(height: 12),
            const Text(
              'Thiết bị tìm thấy trong mạng LAN (Chạm để đồng bộ & lưu):',
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w800,
                color: ChibiTheme.textDark,
              ),
            ),
            const SizedBox(height: 6),
            ..._discoveredPeers.values.map((peer) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onTap: _isSyncing ? null : () => _syncWithTargetIp(peer.ip),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEAF3FF),
                      borderRadius: BorderRadius.circular(16),
                      border:
                          Border.all(color: ChibiTheme.deepPink, width: 1.5),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.phone_iphone_rounded,
                            color: ChibiTheme.deepPink),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${peer.deviceName} (${peer.ip})',
                                style: const TextStyle(
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.w900,
                                  color: ChibiTheme.textDark,
                                ),
                              ),
                              Text(
                                '${peer.flashcardCount} Flashcard • ${peer.noteCount} Ghi chú',
                                style: const TextStyle(
                                  fontSize: 11.5,
                                  color: ChibiTheme.textMuted,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: ChibiTheme.deepPink,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Text(
                            'Đồng bộ ngay',
                            style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w900,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }),
          ],

          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _peerIpController,
                  keyboardType: TextInputType.url,
                  style: const TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w800,
                  ),
                  decoration: InputDecoration(
                    hintText: 'Nhập IP máy kia (VD: 192.168.1.15)',
                    hintStyle: const TextStyle(
                      fontSize: 13,
                      color: ChibiTheme.textMuted,
                    ),
                    filled: true,
                    fillColor: ChibiTheme.bgCream,
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 12),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton.icon(
                onPressed: _isSyncing
                    ? null
                    : () => _syncWithTargetIp(_peerIpController.text),
                style: ElevatedButton.styleFrom(
                  backgroundColor: ChibiTheme.deepPink,
                  foregroundColor: Colors.white,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                icon: _isSyncing
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.sync_rounded, size: 18),
                label: Text(
                  _isSyncing ? 'Đang đồng bộ' : 'Đồng bộ',
                  style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),

          if (_syncStatusMessage != null) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: _isSyncSuccess
                    ? const Color(0xFFE6F7EE)
                    : const Color(0xFFFFEDF2),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Text(
                _syncStatusMessage!,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w800,
                  color: _isSyncSuccess
                      ? const Color(0xFF15803D)
                      : Colors.redAccent,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildAccentSection({
    required String title,
    required List<EnglishVoiceOption> voices,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: ChibiTheme.kawaiiCardDecoration(
        color: Colors.white,
        borderColor: ChibiTheme.softPink,
        radius: 24,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 15.5,
              fontWeight: FontWeight.w900,
              color: ChibiTheme.textDark,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: voices.map((option) {
              final isSelected = option.id == _selectedVoiceId;
              final isFemale = option.gender == VoiceGender.female;
              return Expanded(
                child: Padding(
                  padding: EdgeInsets.only(
                    right: option == voices.first ? 6 : 0,
                    left: option == voices.last ? 6 : 0,
                  ),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(18),
                    onTap: () => _selectVoice(option),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 14),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? const Color(0xFFEAF3FF)
                            : ChibiTheme.bgCream,
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(
                          color: isSelected
                              ? ChibiTheme.deepPink
                              : ChibiTheme.softPink,
                          width: isSelected ? 2.2 : 1.5,
                        ),
                      ),
                      child: Column(
                        children: [
                          CircleAvatar(
                            radius: 22,
                            backgroundColor: isSelected
                                ? ChibiTheme.deepPink
                                : ChibiTheme.softPink,
                            child: Icon(
                              isFemale
                                  ? Icons.female_rounded
                                  : Icons.male_rounded,
                              color: isSelected
                                  ? Colors.white
                                  : ChibiTheme.deepPink,
                              size: 26,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            isFemale ? 'Giọng Nữ' : 'Giọng Nam',
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w900,
                              color: ChibiTheme.textDark,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            option.localeCode == 'en-US'
                                ? 'Tiếng Mỹ (US)'
                                : 'Tiếng Anh (UK)',
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: ChibiTheme.textMuted,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                isSelected
                                    ? Icons.check_circle_rounded
                                    : Icons.volume_up_rounded,
                                size: 16,
                                color: ChibiTheme.deepPink,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                isSelected ? 'Đang chọn' : 'Nghe thử',
                                style: const TextStyle(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w800,
                                  color: ChibiTheme.deepPink,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}
