import 'dart:convert';
import 'dart:io';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum VoiceGender {
  female, // Giọng Nữ
  male, // Giọng Nam
}

class EnglishVoiceOption {
  final String id;
  final String name;
  final String subtitle;
  final String localeCode; // 'en-US' (Tiếng Mỹ) hoặc 'en-GB' (Tiếng Anh)
  final VoiceGender gender;

  const EnglishVoiceOption({
    required this.id,
    required this.name,
    required this.subtitle,
    required this.localeCode,
    required this.gender,
  });
}

class AudioSpeechService {
  static final AudioPlayer _audioPlayer = AudioPlayer();
  static final FlutterTts _flutterTts = FlutterTts();

  static const String _prefVoiceIdKey = 'chibi_english_voice_id_v2';
  static const String _prefSpeechRateKey = 'chibi_english_speech_rate';

  /// 4 lựa chọn giọng đọc tự nhiên: Giọng Nữ & Giọng Nam cho Tiếng Mỹ (en-US) và Tiếng Anh (en-GB)
  static const List<EnglishVoiceOption> voiceOptions = [
    EnglishVoiceOption(
      id: 'us_female',
      name: 'Giọng Nữ • Tiếng Mỹ (US)',
      subtitle: 'Giọng đọc Từ điển Quốc tế & Google Neural tự nhiên (Mặc định)',
      localeCode: 'en-US',
      gender: VoiceGender.female,
    ),
    EnglishVoiceOption(
      id: 'us_male',
      name: 'Giọng Nam • Tiếng Mỹ (US)',
      subtitle: 'Giọng Nam chuẩn Anh - Mỹ tự nhiên, rõ chữ',
      localeCode: 'en-US',
      gender: VoiceGender.male,
    ),
    EnglishVoiceOption(
      id: 'uk_female',
      name: 'Giọng Nữ • Tiếng Anh (UK)',
      subtitle: 'Giọng đọc Từ điển Anh - Anh (British) tự nhiên',
      localeCode: 'en-GB',
      gender: VoiceGender.female,
    ),
    EnglishVoiceOption(
      id: 'uk_male',
      name: 'Giọng Nam • Tiếng Anh (UK)',
      subtitle: 'Giọng Nam chuẩn Hoàng gia Anh (British) tự nhiên',
      localeCode: 'en-GB',
      gender: VoiceGender.male,
    ),
  ];

  static String _currentVoiceId = 'us_female';
  static double _speechRate = 1.0; // 1.0 = Bình thường, 0.7 = Chậm
  static bool _prefsLoaded = false;
  static bool _isSpeaking = false;
  static List<Map<String, String>>? _availableDeviceVoices;

  static Future<void> loadVoiceSettings() async {
    if (_prefsLoaded) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      _currentVoiceId = prefs.getString(_prefVoiceIdKey) ?? 'us_female';
      _speechRate = prefs.getDouble(_prefSpeechRateKey) ?? 1.0;
      _prefsLoaded = true;
    } catch (_) {}
  }

  static String get currentVoiceId => _currentVoiceId;
  static double get currentSpeechRate => _speechRate;

  static EnglishVoiceOption get currentVoiceOption {
    return voiceOptions.firstWhere(
      (v) => v.id == _currentVoiceId,
      orElse: () => voiceOptions.first,
    );
  }

  static Future<void> setVoiceOption(String voiceId) async {
    _currentVoiceId = voiceId;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefVoiceIdKey, voiceId);
  }

  static Future<void> setSpeechRate(double rate) async {
    _speechRate = rate;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_prefSpeechRateKey, rate);
  }

  /// Tìm giọng đọc Neural/Enhanced tự nhiên nhất trên thiết bị (tránh các giọng compact robot cũ)
  /// và KHÔNG biến dạng pitch quá mức khiến giọng bị méo như robot.
  static Future<Map<String, String>?> _findBestNaturalDeviceVoice({
    required String localeCode,
    required VoiceGender gender,
  }) async {
    try {
      if (_availableDeviceVoices == null) {
        final rawVoices = await _flutterTts.getVoices;
        if (rawVoices is List) {
          _availableDeviceVoices = rawVoices
              .whereType<Map>()
              .map((m) => m.map(
                  (k, v) => MapEntry(k.toString(), v?.toString() ?? '')))
              .toList();
        } else {
          _availableDeviceVoices = [];
        }
      }

      if (_availableDeviceVoices == null || _availableDeviceVoices!.isEmpty) {
        return null;
      }

      final targetPrefix = localeCode.toLowerCase().replaceAll('_', '-');
      final candidates = _availableDeviceVoices!.where((v) {
        final loc = (v['locale'] ?? '').toLowerCase().replaceAll('_', '-');
        return loc == targetPrefix ||
            loc.startsWith(targetPrefix.split('-').first);
      }).toList();

      const maleIndicators = [
        'male',
        '#male',
        'daniel',
        'arthur',
        'aaron',
        'Alex',
        'alex',
        'oliver',
        'tom',
        'evan',
        'nathan',
        'iom',
        'tpd',
        'rjs',
        'gbd',
        'gba',
      ];
      const femaleIndicators = [
        'female',
        '#female',
        'samantha',
        'ava',
        'allison',
        'susan',
        'victoria',
        'karen',
        'martha',
        'serena',
        'moira',
        'tessa',
        'sfg',
        'iog',
        'gbg',
        'gbc',
      ];

      final exactLocaleCandidates = candidates.where((v) {
        final loc = (v['locale'] ?? '').toLowerCase().replaceAll('_', '-');
        return loc == targetPrefix;
      }).toList();

      final pool =
          exactLocaleCandidates.isNotEmpty ? exactLocaleCandidates : candidates;

      // Sắp xếp ưu tiên các giọng Enhanced / Premium / Network (tự nhiên hơn giọng compact)
      pool.sort((a, b) {
        final aStr = a.values.join(' ').toLowerCase();
        final bStr = b.values.join(' ').toLowerCase();
        final aScore = (aStr.contains('enhanced') ||
                aStr.contains('premium') ||
                aStr.contains('network') ||
                aStr.contains('siri'))
            ? 1
            : 0;
        final bScore = (bStr.contains('enhanced') ||
                bStr.contains('premium') ||
                bStr.contains('network') ||
                bStr.contains('siri'))
            ? 1
            : 0;
        return bScore.compareTo(aScore);
      });

      for (final v in pool) {
        final combined =
            '${v['name'] ?? ''} ${v['gender'] ?? ''} ${v['identifier'] ?? ''}'
                .toLowerCase();
        if (gender == VoiceGender.male) {
          if (maleIndicators.any((k) => combined.contains(k.toLowerCase())) &&
              !combined.contains('female')) {
            return {
              'name': v['name'] ?? '',
              'locale': v['locale'] ?? localeCode,
            };
          }
        } else {
          if (femaleIndicators.any((k) => combined.contains(k.toLowerCase()))) {
            return {
              'name': v['name'] ?? '',
              'locale': v['locale'] ?? localeCode,
            };
          }
        }
      }
    } catch (_) {}
    return null;
  }

  /// Tải file MP3 giọng đọc người thật (Human Dictionary Audio) hoặc Google Neural TTS
  /// và lưu vào file tạm `.mp3` trong thư mục cache trước khi phát bằng `DeviceFileSource`.
  /// -> Khắc phục hoàn toàn lỗi crash `AVPlayer` trên iOS khi dùng `BytesSource`!
  static Future<bool> _tryPlayOnlineNaturalAudio(
    String cleanWord,
    EnglishVoiceOption option,
  ) async {
    final encoded = Uri.encodeComponent(cleanWord);
    final isUk = option.localeCode == 'en-GB';
    final isFemale = option.gender == VoiceGender.female;

    final List<String> candidateUrls = [];

    if (isFemale) {
      // Giọng Nữ:
      // 1. Giọng người thật từ Từ điển Quốc tế (Youdao/Collins Dictionary Voice: type=2 là Mỹ, type=1 là Anh)
      final dictType = isUk ? 1 : 2;
      candidateUrls.add(
        'https://dict.youdao.com/dictvoice?audio=$encoded&type=$dictType',
      );
      // 2. Google Translate Neural Voice (client=tw-ob & client=at)
      final ttsspeed = _speechRate < 0.85 ? '0.4' : '1';
      candidateUrls.add(
        'https://translate.google.com/translate_tts?ie=UTF-8&client=at&tl=${option.localeCode}&ttsspeed=$ttsspeed&q=$encoded',
      );
    } else {
      // Giọng Nam:
      // 1. Tìm file MP3 giọng người thật chuẩn từ Free Dictionary API (Wikimedia / Oxford human audio)
      try {
        final dictApiUrl = Uri.parse(
            'https://api.dictionaryapi.dev/api/v2/entries/en/$encoded');
        final dictResp = await http
            .get(dictApiUrl)
            .timeout(const Duration(milliseconds: 2500));
        if (dictResp.statusCode == 200) {
          final decoded = jsonDecode(dictResp.body);
          if (decoded is List && decoded.isNotEmpty) {
            final phonetics = decoded.first['phonetics'];
            if (phonetics is List) {
              String? fallbackAudio;
              final targetSuffix = isUk ? '-uk.mp3' : '-us.mp3';
              for (final ph in phonetics) {
                final audioUrl = ph['audio']?.toString() ?? '';
                if (audioUrl.isNotEmpty) {
                  fallbackAudio ??= audioUrl;
                  if (audioUrl.toLowerCase().endsWith(targetSuffix)) {
                    candidateUrls.add(audioUrl);
                    break;
                  }
                }
              }
              if (candidateUrls.isEmpty && fallbackAudio != null) {
                candidateUrls.add(fallbackAudio);
              }
            }
          }
        }
      } catch (_) {}

      // 2. Từ điển Youdao/Collins Human Audio (type=1 Anh-Anh, type=2 Anh-Mỹ)
      // Nếu thiết bị không có giọng Nam Neural cao cấp, ưu tiên phát giọng người thật từ từ điển thay vì giọng TTS robot
      final dictType = isUk ? 1 : 2;
      candidateUrls.add(
        'https://dict.youdao.com/dictvoice?audio=$encoded&type=$dictType',
      );
    }

    for (final url in candidateUrls) {
      try {
        final resp = await http.get(
          Uri.parse(url),
          headers: const {
            'User-Agent':
                'Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148',
          },
        ).timeout(const Duration(seconds: 5));

        if (resp.statusCode == 200 && resp.bodyBytes.length > 500) {
          final tempDir = await getTemporaryDirectory();
          final safeWord =
              cleanWord.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '_');
          final tempFile = File(
            p.join(
                tempDir.path, 'tts_${option.id}_$safeWord.mp3'),
          );
          await tempFile.writeAsBytes(resp.bodyBytes, flush: true);

          await _audioPlayer.stop();
          await _audioPlayer.setPlaybackRate(_speechRate);
          await _audioPlayer.play(DeviceFileSource(tempFile.path));
          return true;
        }
      } catch (_) {}
    }

    return false;
  }

  /// Phát âm từ tiếng Anh:
  /// - An toàn tuyệt đối trên iOS (không gọi đồng thời AVPlayer + AVSpeechSynthesizer gây crash)
  /// - Ưu tiên giọng đọc người thật từ Từ điển & Google Neural chuẩn, tự nhiên, không bị méo giọng robot.
  static Future<void> speakEnglishWord(String word) async {
    final clean = word.trim();
    if (clean.isEmpty) return;

    // Ngăn gọi chồng chéo liên tiếp làm crash AudioSession trên iOS
    if (_isSpeaking) {
      try {
        await _audioPlayer.stop();
        await _flutterTts.stop();
      } catch (_) {}
    }
    _isSpeaking = true;

    try {
      await loadVoiceSettings();
      final option = currentVoiceOption;

      // Nếu người dùng chọn Giọng Nam và thiết bị (đặc biệt là iOS với giọng Daniel/Arthur/Aaron)
      // có sẵn giọng Nam bản xứ chất lượng cao -> Dùng giọng Nam tự nhiên với pitch chuẩn (1.0)
      if (option.gender == VoiceGender.male) {
        final matchedMaleVoice = await _findBestNaturalDeviceVoice(
          localeCode: option.localeCode,
          gender: VoiceGender.male,
        );
        if (matchedMaleVoice != null &&
            (matchedMaleVoice['name']?.isNotEmpty ?? false)) {
          await _audioPlayer.stop();
          await _flutterTts.stop();
          await _flutterTts.setLanguage(option.localeCode);
          await _flutterTts.setVoice(matchedMaleVoice);
          // Giữ pitch = 1.0 tự nhiên để không bị tiếng trầm robot
          await _flutterTts.setPitch(1.0);
          final ttsRate = Platform.isIOS
              ? (_speechRate * 0.5).clamp(0.3, 0.65)
              : (_speechRate * 0.48).clamp(0.28, 0.75);
          await _flutterTts.setSpeechRate(ttsRate);
          await _flutterTts.speak(clean);
          return;
        }
      }

      // Ưu tiên phát file MP3 giọng đọc người thật (Từ điển Quốc tế / Google Neural) qua file tạm an toàn trên cả iOS & Android
      final playedOnline = await _tryPlayOnlineNaturalAudio(clean, option);
      if (playedOnline) {
        return;
      }

      // Dự phòng Offline TTS trên máy với pitch tự nhiên (1.0) để không bị giọng robot
      await _audioPlayer.stop();
      await _flutterTts.stop();
      await _flutterTts.setLanguage(option.localeCode);

      final matchedVoice = await _findBestNaturalDeviceVoice(
        localeCode: option.localeCode,
        gender: option.gender,
      );
      if (matchedVoice != null &&
          (matchedVoice['name']?.isNotEmpty ?? false)) {
        await _flutterTts.setVoice(matchedVoice);
      }

      // Giữ pitch chuẩn tự nhiên (0.95 cho Nam, 1.03 cho Nữ) thay vì ép pitch quá sâu gây tiếng robot
      await _flutterTts
          .setPitch(option.gender == VoiceGender.male ? 0.95 : 1.03);
      final ttsRate = Platform.isIOS
          ? (_speechRate * 0.5).clamp(0.3, 0.65)
          : (_speechRate * 0.48).clamp(0.28, 0.75);
      await _flutterTts.setSpeechRate(ttsRate);
      await _flutterTts.speak(clean);
    } catch (_) {
      // Bắt mọi ngoại lệ âm thanh để không bao giờ gây crash app trên iOS
    } finally {
      _isSpeaking = false;
    }
  }

  static Future<void> stop() async {
    try {
      await _audioPlayer.stop();
      await _flutterTts.stop();
    } catch (_) {}
  }
}
