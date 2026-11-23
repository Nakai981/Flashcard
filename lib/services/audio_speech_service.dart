import 'dart:io';
import 'dart:typed_data';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:http/http.dart' as http;
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
  final bool preferGoogleOnlineForFemale;
  final double pitch;

  const EnglishVoiceOption({
    required this.id,
    required this.name,
    required this.subtitle,
    required this.localeCode,
    required this.gender,
    this.preferGoogleOnlineForFemale = false,
    this.pitch = 1.0,
  });
}

class AudioSpeechService {
  static final AudioPlayer _audioPlayer = AudioPlayer();
  static final FlutterTts _flutterTts = FlutterTts();

  static const String _prefVoiceIdKey = 'chibi_english_voice_id_v2';
  static const String _prefSpeechRateKey = 'chibi_english_speech_rate';

  /// 4 lựa chọn giọng đọc chuẩn: Giọng Nữ & Giọng Nam cho Tiếng Mỹ (en-US) và Tiếng Anh (en-GB)
  static const List<EnglishVoiceOption> voiceOptions = [
    EnglishVoiceOption(
      id: 'us_female',
      name: 'Giọng Nữ • Tiếng Mỹ (US)',
      subtitle: 'Phát âm chuẩn giọng Nữ Anh - Mỹ (Mặc định)',
      localeCode: 'en-US',
      gender: VoiceGender.female,
      preferGoogleOnlineForFemale: true,
      pitch: 1.15,
    ),
    EnglishVoiceOption(
      id: 'us_male',
      name: 'Giọng Nam • Tiếng Mỹ (US)',
      subtitle: 'Phát âm chuẩn giọng Nam trầm Anh - Mỹ',
      localeCode: 'en-US',
      gender: VoiceGender.male,
      preferGoogleOnlineForFemale: false,
      pitch: 0.78,
    ),
    EnglishVoiceOption(
      id: 'uk_female',
      name: 'Giọng Nữ • Tiếng Anh (UK)',
      subtitle: 'Phát âm chuẩn giọng Nữ Hoàng gia Anh - Anh',
      localeCode: 'en-GB',
      gender: VoiceGender.female,
      preferGoogleOnlineForFemale: true,
      pitch: 1.15,
    ),
    EnglishVoiceOption(
      id: 'uk_male',
      name: 'Giọng Nam • Tiếng Anh (UK)',
      subtitle: 'Phát âm chuẩn giọng Nam trầm Hoàng gia Anh - Anh',
      localeCode: 'en-GB',
      gender: VoiceGender.male,
      preferGoogleOnlineForFemale: false,
      pitch: 0.78,
    ),
  ];

  static String _currentVoiceId = 'us_female';
  static double _speechRate = 1.0; // 1.0 = Bình thường, 0.7 = Chậm
  static bool _prefsLoaded = false;
  static bool _iosAudioConfigured = false;
  static List<Map<String, String>>? _availableDeviceVoices;

  static Future<void> loadVoiceSettings() async {
    if (_prefsLoaded) return;
    final prefs = await SharedPreferences.getInstance();
    _currentVoiceId = prefs.getString(_prefVoiceIdKey) ?? 'us_female';
    _speechRate = prefs.getDouble(_prefSpeechRateKey) ?? 1.0;
    _prefsLoaded = true;
  }

  /// Cấu hình AVAudioSession trên iOS để vừa phát âm thanh qua loa ngoài
  /// vừa không xung đột với Micro thu âm.
  static Future<void> _configureIosAudioIfNeeded() async {
    if (_iosAudioConfigured) return;
    _iosAudioConfigured = true;
    try {
      if (Platform.isIOS) {
        await _flutterTts.setSharedInstance(true);
        await _flutterTts.setIosAudioCategory(
          IosTextToSpeechAudioCategory.playAndRecord,
          [
            IosTextToSpeechAudioCategoryOptions.allowBluetooth,
            IosTextToSpeechAudioCategoryOptions.allowBluetoothA2DP,
            IosTextToSpeechAudioCategoryOptions.mixWithOthers,
            IosTextToSpeechAudioCategoryOptions.defaultToSpeaker,
          ],
          IosTextToSpeechAudioMode.defaultMode,
        );
      }
    } catch (_) {}
  }

  /// Tìm giọng Nam / Nữ thực tế có sẵn trên thiết bị Android hoặc iOS
  static Future<Map<String, String>?> _findMatchingDeviceVoice({
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

      final targetPrefix = localeCode.toLowerCase().replaceAll('_', '-');
      final candidates = _availableDeviceVoices!.where((v) {
        final loc = (v['locale'] ?? '').toLowerCase().replaceAll('_', '-');
        return loc == targetPrefix || loc.startsWith(targetPrefix.split('-').first);
      }).toList();

      // Các từ khóa nhận diện giọng Nam / Nữ trên iOS (Daniel, Arthur, Aaron, Samantha, Karen, Martha...)
      // và trên Android Google TTS (en-us-x-iom, iog, sfg, tpd, en-gb-x-rjs, gbd, gba...)
      const maleIndicators = [
        'male',
        '#male',
        'daniel',
        'arthur',
        'aaron',
        'fred',
        'gordon',
        'oliver',
        'rishi',
        'iom',
        'tpd',
        'rjs',
        'gbd',
        'gba',
        'men',
      ];
      const femaleIndicators = [
        'female',
        '#female',
        'samantha',
        'victoria',
        'karen',
        'martha',
        'SERENA',
        'serena',
        'moira',
        'tessa',
        'sfg',
        'iog',
        'gbg',
        'gbc',
        'women',
      ];

      final exactLocaleCandidates = candidates.where((v) {
        final loc = (v['locale'] ?? '').toLowerCase().replaceAll('_', '-');
        return loc == targetPrefix;
      }).toList();

      final pool =
          exactLocaleCandidates.isNotEmpty ? exactLocaleCandidates : candidates;

      for (final v in pool) {
        final combined =
            '${v['name'] ?? ''} ${v['gender'] ?? ''} ${v['identifier'] ?? ''}'
                .toLowerCase();
        if (gender == VoiceGender.male) {
          if (maleIndicators.any((k) => combined.contains(k)) &&
              !combined.contains('female')) {
            return {
              'name': v['name'] ?? '',
              'locale': v['locale'] ?? localeCode,
            };
          }
        } else {
          if (femaleIndicators.any((k) => combined.contains(k))) {
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

  /// Phát âm từ tiếng Anh theo giọng Nữ / Nam của Tiếng Anh (UK) hoặc Tiếng Mỹ (US)
  static Future<void> speakEnglishWord(String word) async {
    final clean = word.trim();
    if (clean.isEmpty) return;

    await loadVoiceSettings();
    await _configureIosAudioIfNeeded();
    final option = currentVoiceOption;

    // 1. Nếu là giọng Nữ (US hoặc UK), ưu tiên giọng Nữ chuẩn của Google Dịch Online trước
    if (option.preferGoogleOnlineForFemale) {
      try {
        await _audioPlayer.stop();
        await _flutterTts.stop();
        final encoded = Uri.encodeComponent(clean);
        final ttsspeed = _speechRate < 0.85 ? '0.3' : '1';
        final url =
            'https://translate.google.com/translate_tts?ie=UTF-8&client=at&tl=${option.localeCode}&ttsspeed=$ttsspeed&q=$encoded';

        final resp = await http.get(
          Uri.parse(url),
          headers: const {
            'User-Agent':
                'AndroidTranslate/5.3.0.RC02.130475354-53000263 5.1 phone TRANSLATE_OPM5_TEST_1',
          },
        ).timeout(const Duration(seconds: 6));

        if (resp.statusCode == 200 && resp.bodyBytes.isNotEmpty) {
          await _audioPlayer.setPlaybackRate(_speechRate);
          await _audioPlayer
              .play(BytesSource(Uint8List.fromList(resp.bodyBytes)));
          return;
        }
      } catch (_) {
        // Nếu mất mạng thì tự động chuyển xuống giọng Nữ TTS trên thiết bị
      }
    }

    // 2. Phát bằng giọng Nam hoặc Nữ TTS trên thiết bị (chọn đúng Voice Nam/Nữ của en-US hoặc en-GB + chỉnh Pitch)
    await _audioPlayer.stop();
    await _flutterTts.stop();
    await _flutterTts.setLanguage(option.localeCode);

    final matchedVoice = await _findMatchingDeviceVoice(
      localeCode: option.localeCode,
      gender: option.gender,
    );
    if (matchedVoice != null && (matchedVoice['name']?.isNotEmpty ?? false)) {
      await _flutterTts.setVoice(matchedVoice);
      // Nếu đã tìm thấy đúng voice Nam/Nữ gốc của hệ điều hành thì giữ pitch tự nhiên gần 1.0
      await _flutterTts
          .setPitch(option.gender == VoiceGender.male ? 0.92 : 1.05);
    } else {
      // Nếu máy chỉ có 1 voice mặc định cho ngôn ngữ đó, điều chỉnh pitch để tạo giọng Nam trầm (0.78) hoặc Nữ cao (1.15)
      await _flutterTts.setPitch(option.pitch);
    }

    final ttsRate = (_speechRate * 0.48).clamp(0.25, 0.85);
    await _flutterTts.setSpeechRate(ttsRate);
    await _flutterTts.speak(clean);
  }

  static Future<void> stop() async {
    try {
      await _audioPlayer.stop();
      await _flutterTts.stop();
    } catch (_) {}
  }
}
