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
  final int flashcardCount;
  final int noteCount;
  final DateTime lastSeen;

  DiscoveredLanPeer({
    required this.ip,
    required this.port,
    required this.deviceName,
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
  final String message;

  LanSyncResult({
    required this.totalFlashcards,
    required this.totalNotes,
    required this.addedFlashcards,
    required this.addedNotes,
    required this.message,
  });
}

/// Dịch vụ Đồng Bộ Dữ Liệu Qua Mạng LAN (Wi-Fi nội bộ) giữa 2 điện thoại (Android <-> iOS):
/// - Tự động mở cổng HTTP nội bộ (`24680`) và phát tín hiệu UDP Broadcast (`24681`) để 2 máy cùng Wi-Fi tự nhìn thấy nhau.
/// - Hỗ trợ kết nối bằng 1 chạm khi thấy thiết bị trên mạng LAN hoặc nhập trực tiếp địa chỉ IP.
/// - Đồng bộ đầy đủ 2 chiều:
///   1. Toàn bộ Flashcard
///   2. Trạng thái Ôn tập (`isReviewed`, danh sách Không nhớ `isNotRemembered`)
///   3. Toàn bộ Ghi chú & Khái niệm (`StudyNoteItem`)
///   4. Danh sách từ đã bấm "Bỏ qua" trong Topic
class LanSyncService {
  static const int defaultHttpPort = 24680;
  static const int udpDiscoveryPort = 24681;
  static const String _skippedWordsPrefKey = 'chibi_topic_skipped_words_v1';

  static HttpServer? _httpServer;
  static RawDatagramSocket? _udpSocket;
  static Timer? _broadcastTimer;
  static String? _localIp;
  static VoidCallback? _onDataSyncedCallback;

  static bool get isServerRunning => _httpServer != null;
  static String? get localIp => _localIp;

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

  /// Đóng gói toàn bộ dữ liệu hiện tại của máy (Flashcard + Ôn tập + Ghi chú + Từ bỏ qua Topic)
  static Future<Map<String, dynamic>> exportFullSyncPayload() async {
    final flashcards = await StorageService.loadFlashcards();
    final notes = await NoteStorageService.loadNotes();
    final prefs = await SharedPreferences.getInstance();
    final skippedWords = prefs.getStringList(_skippedWordsPrefKey) ?? [];

    return {
      'app': 'chibi_flashcard_sync_v1',
      'deviceName': Platform.isIOS ? 'iPhone / iPad' : 'Điện thoại Android',
      'timestamp': DateTime.now().toIso8601String(),
      'flashcards': flashcards.map((f) => f.toJson()).toList(),
      'notes': notes.map((n) => n.toJson()).toList(),
      'skippedTopicWords': skippedWords,
    };
  }

  /// Gộp dữ liệu nhận được từ máy kia vào dữ liệu máy hiện tại (không làm mất dữ liệu của cả 2 máy)
  static Future<LanSyncResult> mergeIncomingPayload(
      Map<String, dynamic> payload) async {
    if (payload['app'] != 'chibi_flashcard_sync_v1') {
      throw Exception('Dữ liệu không đúng định dạng Chibi Flashcard!');
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
        // Nếu từ đã tồn tại ở cả 2 máy -> Gộp trạng thái Ôn tập & Không nhớ
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
        // Lấy bản ghi chú nào được cập nhật mới hơn hoặc nhiều mục hơn
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

    _onDataSyncedCallback?.call();

    return LanSyncResult(
      totalFlashcards: savedCards.length,
      totalNotes: savedNotes.length,
      addedFlashcards: addedFlashcards,
      addedNotes: addedNotes,
      message:
          'Đồng bộ thành công! Hiện có ${savedCards.length} Flashcard (+$addedFlashcards mới) & ${savedNotes.length} Ghi chú (+$addedNotes mới).',
    );
  }

  /// Bật chế độ Máy chủ chờ đồng bộ trên mạng LAN (HTTP Server + UDP Broadcast)
  static Future<String> startLanSyncServer({
    required ValueChanged<DiscoveredLanPeer> onPeerDiscovered,
    required ValueChanged<LanSyncResult> onIncomingSyncCompleted,
    VoidCallback? onDataSynced,
  }) async {
    _onDataSyncedCallback = onDataSynced;
    await stopLanSyncServer();

    final ip = await getLocalLanIp();
    if (ip == null || ip.isEmpty) {
      throw Exception(
          'Không tìm thấy địa chỉ IP mạng LAN. Hãy kiểm tra điện thoại đã bật Wi-Fi hoặc Điểm truy cập cá nhân (Hotspot) chưa nhé!');
    }

    _httpServer = await HttpServer.bind(
      InternetAddress.anyIPv4,
      defaultHttpPort,
      shared: true,
    );

    _httpServer!.listen((HttpRequest request) async {
      try {
        request.response.headers.contentType = ContentType.json;
        if (request.method == 'GET' && request.uri.path == '/sync') {
          final payload = await exportFullSyncPayload();
          request.response.write(jsonEncode(payload));
          await request.response.close();
        } else if (request.method == 'POST' && request.uri.path == '/sync') {
          // Nhận dữ liệu từ máy kia đẩy sang, gộp dữ liệu và trả về bộ dữ liệu đã gộp đầy đủ cho cả 2 máy
          final bodyStr = await utf8.decoder.bind(request).join();
          final incomingMap =
              jsonDecode(bodyStr) as Map<String, dynamic>;
          final syncRes = await mergeIncomingPayload(incomingMap);

          final mergedPayload = await exportFullSyncPayload();
          request.response.write(jsonEncode(mergedPayload));
          await request.response.close();

          onIncomingSyncCompleted(syncRes);
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
              onPeerDiscovered(
                DiscoveredLanPeer(
                  ip: senderIp,
                  port: (decoded['port'] as num?)?.toInt() ?? defaultHttpPort,
                  deviceName:
                      decoded['deviceName']?.toString() ?? 'Thiết bị Chibi',
                  flashcardCount:
                      (decoded['flashcardCount'] as num?)?.toInt() ?? 0,
                  noteCount: (decoded['noteCount'] as num?)?.toInt() ?? 0,
                  lastSeen: DateTime.now(),
                ),
              );
            }
          } catch (_) {}
        }
      });

      _broadcastTimer =
          Timer.periodic(const Duration(seconds: 2), (_) async {
        await _sendUdpBeacon();
      });
      await _sendUdpBeacon();
    } catch (_) {
      // Nếu mạng Wi-Fi chặn UDP broadcast thì người dùng vẫn nhập IP đồng bộ trực tiếp qua HTTP bình thường
    }

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
        'deviceName': Platform.isIOS ? 'iPhone / iPad' : 'Điện thoại Android',
        'flashcardCount': cards.length,
        'noteCount': notes.length,
      });
      final data = utf8.encode(beacon);

      // Gửi tới cả địa chỉ broadcast toàn cục 255.255.255.255 và broadcast của lớp mạng hiện tại (VD 192.168.1.255)
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

  /// Kết nối tới địa chỉ IP của điện thoại thứ 2 trên mạng LAN và đồng bộ 2 chiều:
  /// - Gửi toàn bộ dữ liệu máy này sang máy kia (để máy kia gộp)
  /// - Nhận lại toàn bộ dữ liệu đã gộp từ máy kia và lưu vào máy này
  /// -> Cả 2 điện thoại sẽ có bộ dữ liệu Flashcard, Ghi chú và tiến độ Ôn tập giống hệt nhau!
  static Future<LanSyncResult> syncWithPeerIp(
    String targetIpInput, {
    VoidCallback? onDataSynced,
  }) async {
    _onDataSyncedCallback = onDataSynced;
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
        .timeout(const Duration(seconds: 10));

    if (response.statusCode != 200) {
      throw Exception(
          'Không thể đồng bộ với $cleanIp (Mã lỗi: ${response.statusCode})');
    }

    final remoteMergedJson =
        jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
    return mergeIncomingPayload(remoteMergedJson);
  }
}
