import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/flashcard_model.dart';
import '../models/note_model.dart';
import 'note_storage_service.dart';
import 'storage_service.dart';

class DiscoveredLanPeer {
  final String ip;
  final int port;
  final String deviceName;
  final String deviceId;
  final int flashcardCount;
  final int noteCount;
  final DateTime lastSeen;

  DiscoveredLanPeer({
    required this.ip,
    required this.port,
    required this.deviceName,
    required this.deviceId,
    required this.flashcardCount,
    required this.noteCount,
    required this.lastSeen,
  });
}

class LanSyncResult {
  final int totalFlashcards;
  final int totalNotes;
  final int addedFlashcards;
  final int addedNotes;
  final String peerIp;
  final String peerName;
  final String message;

  LanSyncResult({
    required this.totalFlashcards,
    required this.totalNotes,
    required this.addedFlashcards,
    required this.addedNotes,
    required this.peerIp,
    required this.peerName,
    required this.message,
  });
}

/// Dịch vụ Đồng Bộ Dữ Liệu Qua Mạng LAN (Wi-Fi nội bộ) giữa 2 điện thoại:
/// - Tự động lưu thông tin thiết bị đã đồng bộ (IP, Device ID, Tên thiết bị, Thời gian đồng bộ gần nhất, Cờ Tự động đồng bộ).
/// - Lần sau khi mở App:
///   1. Tự động bật dịch vụ mạng LAN ngầm nếu người dùng đã từng bật/đồng bộ.
///   2. Tự động kiểm tra địa chỉ IP đã lưu của máy kia -> Nếu máy kia đang mở và sẵn sàng trên mạng LAN thì tự động đồng bộ 2 chiều ngay lập tức!
///   3. Nếu máy kia đổi IP Wi-Fi mới, ngay khi nhận được tín hiệu UDP Beacon từ máy kia trên mạng LAN, ứng dụng cũng tự động cập nhật IP mới và tự động đồng bộ luôn!
class LanSyncService {
  static const int defaultHttpPort = 24680;
  static const int udpDiscoveryPort = 24681;
  static const String _skippedWordsPrefKey = 'chibi_topic_skipped_words_v1';

  // Các khóa lưu thông tin đồng bộ vào SharedPreferences để tự động đồng bộ ở những lần mở app sau
  static const String _prefAutoSyncEnabledKey = 'chibi_lan_auto_sync_enabled_v1';
  static const String _prefSavedPeerIpKey = 'chibi_lan_saved_peer_ip_v1';
  static const String _prefSavedPeerNameKey = 'chibi_lan_saved_peer_name_v1';
  static const String _prefSavedPeerDeviceIdKey =
      'chibi_lan_saved_peer_device_id_v1';
  static const String _prefMyDeviceIdKey = 'chibi_lan_my_device_id_v1';
  static const String _prefLastSyncTimeKey = 'chibi_lan_last_sync_time_v1';

  static HttpServer? _httpServer;
  static RawDatagramSocket? _udpSocket;
  static Timer? _broadcastTimer;
  static String? _localIp;
  static String? _myDeviceId;

  static bool _autoSyncEnabled = true;
  static String? _savedPeerIp;
  static String? _savedPeerName;
  static String? _savedPeerDeviceId;
  static String? _lastSyncTimeIso;

  static DateTime? _lastAutoSyncAttempt;
  static bool _isAutoSyncInProgress = false;

  static final List<VoidCallback> _dataSyncedListeners = [];
  static final List<ValueChanged<LanSyncResult>> _syncCompletedListeners = [];
  static final Map<String, DiscoveredLanPeer> _discoveredPeers = {};

  static bool get isServerRunning => _httpServer != null;
  static String? get localIp => _localIp;
  static bool get autoSyncEnabled => _autoSyncEnabled;
  static String? get savedPeerIp => _savedPeerIp;
  static String? get savedPeerName => _savedPeerName;
  static String? get lastSyncTimeIso => _lastSyncTimeIso;
  static Map<String, DiscoveredLanPeer> get discoveredPeers => _discoveredPeers;

  static void addDataSyncedListener(VoidCallback listener) {
    if (!_dataSyncedListeners.contains(listener)) {
      _dataSyncedListeners.add(listener);
    }
  }

  static void removeDataSyncedListener(VoidCallback listener) {
    _dataSyncedListeners.remove(listener);
  }

  static void addSyncCompletedListener(ValueChanged<LanSyncResult> listener) {
    if (!_syncCompletedListeners.contains(listener)) {
      _syncCompletedListeners.add(listener);
    }
  }

  static void removeSyncCompletedListener(
      ValueChanged<LanSyncResult> listener) {
    _syncCompletedListeners.remove(listener);
  }

  static void _notifyDataSynced() {
    for (final l in List<VoidCallback>.from(_dataSyncedListeners)) {
      try {
        l();
      } catch (_) {}
    }
  }

  static void _notifySyncCompleted(LanSyncResult result) {
    for (final l
        in List<ValueChanged<LanSyncResult>>.from(_syncCompletedListeners)) {
      try {
        l(result);
      } catch (_) {}
    }
  }

  /// Đọc thông tin thiết bị đã lưu từ những lần đồng bộ trước
  static Future<void> loadSavedSyncConfig() async {
    final prefs = await SharedPreferences.getInstance();
    _autoSyncEnabled = prefs.getBool(_prefAutoSyncEnabledKey) ?? true;
    _savedPeerIp = prefs.getString(_prefSavedPeerIpKey);
    _savedPeerName = prefs.getString(_prefSavedPeerNameKey);
    _savedPeerDeviceId = prefs.getString(_prefSavedPeerDeviceIdKey);
    _lastSyncTimeIso = prefs.getString(_prefLastSyncTimeKey);

    var myId = prefs.getString(_prefMyDeviceIdKey);
    if (myId == null || myId.isEmpty) {
      myId =
          '${Platform.isIOS ? "ios" : "android"}_${DateTime.now().millisecondsSinceEpoch}';
      await prefs.setString(_prefMyDeviceIdKey, myId);
    }
    _myDeviceId = myId;
  }

  static Future<void> setAutoSyncEnabled(bool enabled) async {
    _autoSyncEnabled = enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefAutoSyncEnabledKey, enabled);
    if (enabled && !isServerRunning) {
      await initAutoSyncOnAppStart();
    }
  }

  /// Lưu thông tin thiết bị vừa đồng bộ thành công để lần sau mở App tự động đồng bộ
  static Future<void> _savePairedPeerInfo({
    required String peerIp,
    String? peerName,
    String? peerDeviceId,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    _savedPeerIp = peerIp;
    await prefs.setString(_prefSavedPeerIpKey, peerIp);

    if (peerName != null && peerName.isNotEmpty) {
      _savedPeerName = peerName;
      await prefs.setString(_prefSavedPeerNameKey, peerName);
    }
    if (peerDeviceId != null && peerDeviceId.isNotEmpty) {
      _savedPeerDeviceId = peerDeviceId;
      await prefs.setString(_prefSavedPeerDeviceIdKey, peerDeviceId);
    }
    final nowIso = DateTime.now().toIso8601String();
    _lastSyncTimeIso = nowIso;
    await prefs.setString(_prefLastSyncTimeKey, nowIso);
  }

  static Future<void> clearSavedPeer() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefSavedPeerIpKey);
    await prefs.remove(_prefSavedPeerNameKey);
    await prefs.remove(_prefSavedPeerDeviceIdKey);
    _savedPeerIp = null;
    _savedPeerName = null;
    _savedPeerDeviceId = null;
  }

  /// Hàm được gọi tự động ngay khi người dùng mở ứng dụng (ở HomeScreen):
  /// 1. Nạp cấu hình đồng bộ đã lưu.
  /// 2. Tự động bật máy chủ LAN ngầm để sẵn sàng nhận hoặc phát hiện máy kia.
  /// 3. Nếu đã lưu IP của máy kia và chế độ Tự động đồng bộ đang bật -> Tự động kết nối và đồng bộ ngay lập tức nếu máy kia sẵn sàng trên mạng LAN!
  static Future<void> initAutoSyncOnAppStart({
    VoidCallback? onDataSynced,
    ValueChanged<LanSyncResult>? onAutoSyncSuccess,
  }) async {
    if (onDataSynced != null) {
      addDataSyncedListener(onDataSynced);
    }
    if (onAutoSyncSuccess != null) {
      addSyncCompletedListener(onAutoSyncSuccess);
    }

    await loadSavedSyncConfig();
    if (!_autoSyncEnabled) return;

    try {
      await startLanSyncServer();
    } catch (_) {
      // Nếu máy đang tắt Wi-Fi thì bỏ qua êm ái, không báo lỗi làm phiền người dùng
      return;
    }

    // Nếu đã có IP thiết bị đã lưu từ lần đồng bộ trước -> Thử tự động đồng bộ ngầm ngay
    if (_savedPeerIp != null && _savedPeerIp!.trim().isNotEmpty) {
      unawaited(_trySilentAutoSyncWithIp(_savedPeerIp!));
    }
  }

  static Future<void> _trySilentAutoSyncWithIp(String targetIp) async {
    if (_isAutoSyncInProgress) return;
    final now = DateTime.now();
    // Tránh gọi lặp lại quá dày trong vòng 15 giây
    if (_lastAutoSyncAttempt != null &&
        now.difference(_lastAutoSyncAttempt!).inSeconds < 15) {
      return;
    }
    _isAutoSyncInProgress = true;
    _lastAutoSyncAttempt = now;

    try {
      final result = await syncWithPeerIp(targetIp, isSilentAutoSync: true);
      _notifySyncCompleted(result);
    } catch (_) {
      // Máy kia chưa mở app hoặc chưa cùng mạng LAN -> Bỏ qua êm ái, khi nào máy kia bật lên sẽ bắt được qua UDP Beacon
    } finally {
      _isAutoSyncInProgress = false;
    }
  }

  /// Lấy địa chỉ IPv4 trong mạng LAN Wi-Fi của điện thoại (VD: 192.168.1.x)
  static Future<String?> getLocalLanIp() async {
    try {
      final interfaces = await NetworkInterface.list(
        includeLoopback: false,
        type: InternetAddressType.IPv4,
      );
      String? fallbackIp;
      for (final interface in interfaces) {
        final name = interface.name.toLowerCase();
        for (final addr in interface.addresses) {
          final ip = addr.address;
          if (ip.startsWith('192.168.') ||
              ip.startsWith('10.') ||
              ip.startsWith('172.')) {
            if (name.contains('wlan') ||
                name.contains('en0') ||
                name.contains('wifi') ||
                name.contains('ap')) {
              _localIp = ip;
              return ip;
            }
            fallbackIp ??= ip;
          }
        }
      }
      _localIp = fallbackIp;
      return fallbackIp;
    } catch (_) {
      return null;
    }
  }

  /// Đóng gói toàn bộ dữ liệu hiện tại của máy
  static Future<Map<String, dynamic>> exportFullSyncPayload() async {
    await loadSavedSyncConfig();
    final flashcards = await StorageService.loadFlashcards();
    final notes = await NoteStorageService.loadNotes();
    final prefs = await SharedPreferences.getInstance();
    final skippedWords = prefs.getStringList(_skippedWordsPrefKey) ?? [];

    return {
      'app': 'chibi_flashcard_sync_v1',
      'deviceId': _myDeviceId ?? '',
      'deviceName': Platform.isIOS ? 'iPhone / iPad' : 'Điện thoại Android',
      'timestamp': DateTime.now().toIso8601String(),
      'flashcards': flashcards.map((f) => f.toJson()).toList(),
      'notes': notes.map((n) => n.toJson()).toList(),
      'skippedTopicWords': skippedWords,
    };
  }

  /// Gộp dữ liệu nhận được từ máy kia vào dữ liệu máy hiện tại
  static Future<LanSyncResult> mergeIncomingPayload(
    Map<String, dynamic> payload, {
    String? senderIp,
  }) async {
    if (payload['app'] != 'chibi_flashcard_sync_v1') {
      throw Exception('Dữ liệu không đúng định dạng Chibi Flashcard!');
    }

    final remoteDeviceName =
        payload['deviceName']?.toString() ?? 'Điện thoại Chibi';
    final remoteDeviceId = payload['deviceId']?.toString();

    if (senderIp != null && senderIp.isNotEmpty) {
      await _savePairedPeerInfo(
        peerIp: senderIp,
        peerName: remoteDeviceName,
        peerDeviceId: remoteDeviceId,
      );
    }

    // 1. Gộp Flashcards & Trạng thái Ôn tập (isReviewed, isNotRemembered)
    final currentCards = await StorageService.loadFlashcards();
    final incomingCardsRaw = (payload['flashcards'] as List?) ?? [];
    final incomingCards = incomingCardsRaw
        .map((e) => FlashcardItem.fromJson(Map<String, dynamic>.from(e)))
        .toList();

    final Map<String, FlashcardItem> cardByWord = {};
    for (final c in currentCards) {
      cardByWord[c.englishWord.trim().toLowerCase()] = c;
    }

    int addedFlashcards = 0;
    for (final inc in incomingCards) {
      final key = inc.englishWord.trim().toLowerCase();
      if (key.isEmpty) continue;
      if (!cardByWord.containsKey(key)) {
        cardByWord[key] = inc;
        addedFlashcards++;
      } else {
        final existing = cardByWord[key]!;
        cardByWord[key] = existing.copyWith(
          isReviewed: existing.isReviewed || inc.isReviewed,
          isNotRemembered: existing.isNotRemembered || inc.isNotRemembered,
          phonetic:
              existing.phonetic.isNotEmpty ? existing.phonetic : inc.phonetic,
        );
      }
    }

    final mergedCardsList = cardByWord.values.toList()
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    final savedCards = await StorageService.saveFlashcards(mergedCardsList);

    // 2. Gộp Ghi chú & Khái niệm
    final currentNotes = await NoteStorageService.loadNotes();
    final incomingNotesRaw = (payload['notes'] as List?) ?? [];
    final incomingNotes = incomingNotesRaw
        .map((e) => StudyNoteItem.fromJson(Map<String, dynamic>.from(e)))
        .toList();

    final Map<String, StudyNoteItem> noteByKey = {};
    for (final n in currentNotes) {
      noteByKey[n.title.trim().toLowerCase()] = n;
    }

    int addedNotes = 0;
    for (final incNote in incomingNotes) {
      final key = incNote.title.trim().toLowerCase();
      if (key.isEmpty) continue;
      if (!noteByKey.containsKey(key)) {
        noteByKey[key] = incNote;
        addedNotes++;
      } else {
        final existing = noteByKey[key]!;
        if (incNote.updatedAt.isAfter(existing.updatedAt) ||
            incNote.blocks.length > existing.blocks.length) {
          noteByKey[key] = incNote;
        }
      }
    }

    final mergedNotesList = noteByKey.values.toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    final savedNotes = await NoteStorageService.saveNotes(mergedNotesList);

    // 3. Gộp danh sách từ đã Bỏ qua trong Topic
    final prefs = await SharedPreferences.getInstance();
    final currentSkipped =
        (prefs.getStringList(_skippedWordsPrefKey) ?? []).toSet();
    final incomingSkipped = ((payload['skippedTopicWords'] as List?) ?? [])
        .map((e) => e.toString().toLowerCase())
        .toSet();
    final mergedSkipped = {...currentSkipped, ...incomingSkipped}.toList();
    await prefs.setStringList(_skippedWordsPrefKey, mergedSkipped);

    _notifyDataSynced();

    return LanSyncResult(
      totalFlashcards: savedCards.length,
      totalNotes: savedNotes.length,
      addedFlashcards: addedFlashcards,
      addedNotes: addedNotes,
      peerIp: senderIp ?? (_savedPeerIp ?? ''),
      peerName: remoteDeviceName,
      message:
          'Đã đồng bộ với $remoteDeviceName! (${savedCards.length} Flashcard, ${savedNotes.length} Ghi chú)',
    );
  }

  /// Bật chế độ Máy chủ chờ đồng bộ trên mạng LAN (HTTP Server + UDP Broadcast)
  static Future<String> startLanSyncServer({
    ValueChanged<DiscoveredLanPeer>? onPeerDiscovered,
    ValueChanged<LanSyncResult>? onIncomingSyncCompleted,
    VoidCallback? onDataSynced,
  }) async {
    await loadSavedSyncConfig();
    if (onDataSynced != null) {
      addDataSyncedListener(onDataSynced);
    }
    if (onIncomingSyncCompleted != null) {
      addSyncCompletedListener(onIncomingSyncCompleted);
    }

    final ip = await getLocalLanIp();
    if (ip == null || ip.isEmpty) {
      throw Exception(
          'Không tìm thấy địa chỉ IP mạng LAN. Hãy kiểm tra điện thoại đã bật Wi-Fi chưa nhé!');
    }

    if (_httpServer != null) {
      return ip;
    }

    _httpServer = await HttpServer.bind(
      InternetAddress.anyIPv4,
      defaultHttpPort,
      shared: true,
    );

    _httpServer!.listen((HttpRequest request) async {
      try {
        request.response.headers.contentType = ContentType.json;
        final remoteIp = request.connectionInfo?.remoteAddress.address;

        if (request.method == 'GET' && request.uri.path == '/sync') {
          final payload = await exportFullSyncPayload();
          request.response.write(jsonEncode(payload));
          await request.response.close();
        } else if (request.method == 'POST' && request.uri.path == '/sync') {
          final bodyStr = await utf8.decoder.bind(request).join();
          final incomingMap =
              jsonDecode(bodyStr) as Map<String, dynamic>;
          final syncRes = await mergeIncomingPayload(
            incomingMap,
            senderIp: remoteIp,
          );

          final mergedPayload = await exportFullSyncPayload();
          request.response.write(jsonEncode(mergedPayload));
          await request.response.close();

          _notifySyncCompleted(syncRes);
        } else {
          request.response.statusCode = HttpStatus.notFound;
          await request.response.close();
        }
      } catch (e) {
        try {
          request.response.statusCode = HttpStatus.internalServerError;
          request.response.write(jsonEncode({'error': e.toString()}));
          await request.response.close();
        } catch (_) {}
      }
    });

    // Mở cổng UDP để tự động phát tín hiệu và tìm điện thoại khác cùng mạng Wi-Fi
    try {
      _udpSocket = await RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        udpDiscoveryPort,
        reuseAddress: true,
      );
      _udpSocket!.broadcastEnabled = true;

      _udpSocket!.listen((RawSocketEvent event) {
        if (event == RawSocketEvent.read) {
          final datagram = _udpSocket?.receive();
          if (datagram == null) return;
          final senderIp = datagram.address.address;
          if (senderIp == _localIp) return;

          try {
            final msg = utf8.decode(datagram.data);
            final decoded = jsonDecode(msg) as Map<String, dynamic>;
            if (decoded['app'] == 'chibi_flashcard_lan_beacon') {
              final peerDeviceId = decoded['deviceId']?.toString() ?? '';
              if (peerDeviceId.isNotEmpty && peerDeviceId == _myDeviceId) {
                return;
              }
              final peer = DiscoveredLanPeer(
                ip: senderIp,
                port: (decoded['port'] as num?)?.toInt() ?? defaultHttpPort,
                deviceName:
                    decoded['deviceName']?.toString() ?? 'Thiết bị Chibi',
                deviceId: peerDeviceId,
                flashcardCount:
                    (decoded['flashcardCount'] as num?)?.toInt() ?? 0,
                noteCount: (decoded['noteCount'] as num?)?.toInt() ?? 0,
                lastSeen: DateTime.now(),
              );
              _discoveredPeers[senderIp] = peer;
              onPeerDiscovered?.call(peer);

              // Tự động đồng bộ ngay khi phát hiện thiết bị đã từng ghép đôi (theo IP hoặc theo DeviceId) sẵn sàng trên mạng LAN!
              if (_autoSyncEnabled) {
                final isMatchedSavedPeer =
                    (_savedPeerIp != null && _savedPeerIp == senderIp) ||
                        (_savedPeerDeviceId != null &&
                            _savedPeerDeviceId!.isNotEmpty &&
                            _savedPeerDeviceId == peerDeviceId);
                if (isMatchedSavedPeer) {
                  unawaited(_trySilentAutoSyncWithIp(senderIp));
                }
              }
            }
          } catch (_) {}
        }
      });

      _broadcastTimer =
          Timer.periodic(const Duration(seconds: 3), (_) async {
        await _sendUdpBeacon();
      });
      await _sendUdpBeacon();
    } catch (_) {}

    return ip;
  }

  static Future<void> _sendUdpBeacon() async {
    if (_udpSocket == null || _localIp == null) return;
    try {
      final cards = await StorageService.loadFlashcards();
      final notes = await NoteStorageService.loadNotes();
      final beacon = jsonEncode({
        'app': 'chibi_flashcard_lan_beacon',
        'port': defaultHttpPort,
        'deviceId': _myDeviceId ?? '',
        'deviceName': Platform.isIOS ? 'iPhone / iPad' : 'Điện thoại Android',
        'flashcardCount': cards.length,
        'noteCount': notes.length,
      });
      final data = utf8.encode(beacon);

      _udpSocket!.send(
        data,
        InternetAddress('255.255.255.255'),
        udpDiscoveryPort,
      );
      final parts = _localIp!.split('.');
      if (parts.length == 4) {
        final subnetBroadcast = '${parts[0]}.${parts[1]}.${parts[2]}.255';
        _udpSocket!.send(
          data,
          InternetAddress(subnetBroadcast),
          udpDiscoveryPort,
        );
      }
    } catch (_) {}
  }

  static Future<void> stopLanSyncServer() async {
    _broadcastTimer?.cancel();
    _broadcastTimer = null;
    try {
      _udpSocket?.close();
    } catch (_) {}
    _udpSocket = null;
    try {
      await _httpServer?.close(force: true);
    } catch (_) {}
    _httpServer = null;
  }

  /// Kết nối tới địa chỉ IP của điện thoại thứ 2 trên mạng LAN, đồng bộ 2 chiều và LƯU lại thông tin thiết bị
  static Future<LanSyncResult> syncWithPeerIp(
    String targetIpInput, {
    VoidCallback? onDataSynced,
    bool isSilentAutoSync = false,
  }) async {
    if (onDataSynced != null) {
      addDataSyncedListener(onDataSynced);
    }

    var cleanIp = targetIpInput.trim();
    if (cleanIp.isEmpty) {
      throw Exception('Vui lòng nhập địa chỉ IP của điện thoại kia!');
    }

    int port = defaultHttpPort;
    if (cleanIp.contains(':')) {
      final parts = cleanIp.split(':');
      cleanIp = parts.first.trim();
      port = int.tryParse(parts.last.trim()) ?? defaultHttpPort;
    }

    final uri = Uri.parse('http://$cleanIp:$port/sync');
    final myPayload = await exportFullSyncPayload();

    final response = await http
        .post(
          uri,
          headers: {'Content-Type': 'application/json; charset=utf-8'},
          body: jsonEncode(myPayload),
        )
        .timeout(Duration(seconds: isSilentAutoSync ? 4 : 10));

    if (response.statusCode != 200) {
      throw Exception(
          'Không thể đồng bộ với $cleanIp (Mã lỗi: ${response.statusCode})');
    }

    final remoteMergedJson =
        jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
    return mergeIncomingPayload(
      remoteMergedJson,
      senderIp: cleanIp,
    );
  }
}
