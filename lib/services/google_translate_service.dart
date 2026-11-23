import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/flashcard_model.dart';

class GoogleTranslateService {
  static const Map<String, String> _androidHeaders = {
    'User-Agent':
        'AndroidTranslate/5.3.0.RC02.130475354-53000263 5.1 phone TRANSLATE_OPM5_TEST_1',
    'Accept': 'application/json',
    'Accept-Charset': 'UTF-8',
  };

  /// Gọi API Google Dịch dành cho Android (client=at) với cơ chế tự động dự phòng
  /// nhiều cổng Google Translate để tránh lỗi 429 Too Many Requests.
  static Future<FlashcardItem> translateAndBuildFlashcard({
    required String englishWord,
    required int indexNumber,
  }) async {
    final cleanWord = englishWord.trim();
    if (cleanWord.isEmpty) {
      throw Exception('Vui lòng nhập từ tiếng Anh!');
    }

    final encodedWord = Uri.encodeComponent(cleanWord);

    // Danh sách các cổng API Google Dịch theo thứ tự ưu tiên:
    // 1. Cổng Android Translate chính thức (client=at trên translate.google.com) -> Không bị chặn 429
    // 2. Cổng Android Translate quốc tế (translate.google.com.vn)
    // 3. Cổng Google Translate API (translate.googleapis.com với client=at)
    final endpoints = <Uri>[
      Uri.parse(
        'https://translate.google.com/translate_a/single'
        '?client=at'
        '&dt=t&dt=ld&dt=qca&dt=rm&dt=bd&dt=md&dt=ex&dt=ss&dt=at'
        '&dj=1&hl=vi&ie=UTF-8&oe=UTF-8&inputm=2&otf=2'
        '&iid=1dd3b944-fa62-4b55-b330-74909a99969e'
        '&sl=en&tl=vi&q=$encodedWord',
      ),
      Uri.parse(
        'https://translate.google.com.vn/translate_a/single'
        '?client=at'
        '&dt=t&dt=ld&dt=qca&dt=rm&dt=bd&dt=md&dt=ex&dt=ss&dt=at'
        '&dj=1&hl=vi&ie=UTF-8&oe=UTF-8'
        '&sl=en&tl=vi&q=$encodedWord',
      ),
      Uri.parse(
        'https://translate.googleapis.com/translate_a/single'
        '?client=at'
        '&dt=t&dt=bd&dt=rm&dt=md&dt=ex&dt=ss&dt=at'
        '&dj=1&hl=vi'
        '&sl=en&tl=vi&q=$encodedWord',
      ),
    ];

    http.Response? successResponse;
    int? lastStatusCode;
    Object? lastError;

    for (final uri in endpoints) {
      try {
        final resp = await http
            .get(uri, headers: _androidHeaders)
            .timeout(const Duration(seconds: 10));
        if (resp.statusCode == 200) {
          successResponse = resp;
          break;
        } else {
          lastStatusCode = resp.statusCode;
        }
      } catch (e) {
        lastError = e;
      }
    }

    if (successResponse == null) {
      if (lastStatusCode != null) {
        throw Exception(
            'Không thể kết nối Google Dịch (Mã lỗi: $lastStatusCode). Bạn hãy kiểm tra kết nối mạng nhé!');
      }
      throw Exception(
          'Không thể kết nối Google Dịch (${lastError ?? "Lỗi mạng"}). Bạn hãy kiểm tra Wi-Fi/4G nhé!');
    }

    final rawJsonString = utf8.decode(successResponse.bodyBytes);
    final Map<String, dynamic> data =
        jsonDecode(rawJsonString) as Map<String, dynamic>;

    // 1. Lấy nghĩa chính và phiên âm từ mảng sentences
    String primaryVi = '';
    String phonetic = '';
    if (data['sentences'] is List) {
      final sentences = data['sentences'] as List;
      final buffer = StringBuffer();
      for (final s in sentences) {
        if (s is Map) {
          if (s['trans'] != null) {
            buffer.write(s['trans'].toString());
          }
          if (s['src_translit'] != null &&
              s['src_translit'].toString().trim().isNotEmpty) {
            phonetic = s['src_translit'].toString().trim();
          }
        }
      }
      primaryVi = buffer.toString().trim();
    }

    // 2. Lấy chi tiết từ loại và các từ đồng nghĩa từ mảng dict
    final List<WordTypeEntry> wordTypes = [];
    if (data['dict'] is List) {
      for (final d in data['dict'] as List) {
        if (d is Map) {
          final pos = d['pos']?.toString() ?? '';
          final terms = (d['terms'] as List?)
                  ?.map((e) => e.toString())
                  .where((e) => e.trim().isNotEmpty)
                  .toList() ??
              [];
          final List<String> reverseList = [];
          if (d['entry'] is List) {
            for (final entry in d['entry'] as List) {
              if (entry is Map && entry['word'] != null) {
                final w = entry['word'].toString();
                final rev = (entry['reverse_translation'] as List?)
                        ?.map((e) => e.toString())
                        .join(', ') ??
                    '';
                reverseList.add(rev.isNotEmpty ? '$w ($rev)' : w);
              }
            }
          }
          wordTypes.add(
            WordTypeEntry(
              pos: pos,
              terms: terms,
              reverseTranslations: reverseList,
            ),
          );
        }
      }
    }

    // 3. Lấy các bản dịch thay thế từ alternative_translations
    final List<String> altTranslations = [];
    if (data['alternative_translations'] is List) {
      for (final alt in data['alternative_translations'] as List) {
        if (alt is Map && alt['alternative'] is List) {
          for (final item in alt['alternative'] as List) {
            if (item is Map && item['word_postproc'] != null) {
              final wordPost = item['word_postproc'].toString().trim();
              if (wordPost.isNotEmpty &&
                  wordPost.toLowerCase() != primaryVi.toLowerCase() &&
                  !altTranslations.contains(wordPost)) {
                altTranslations.add(wordPost);
              }
            }
          }
        }
      }
    }

    // 4. Lấy định nghĩa mở rộng từ definitions
    final List<DefinitionEntry> definitions = [];
    if (data['definitions'] is List) {
      for (final defGroup in data['definitions'] as List) {
        if (defGroup is Map) {
          final pos = defGroup['pos']?.toString() ?? '';
          if (defGroup['entry'] is List) {
            for (final entry in defGroup['entry'] as List) {
              if (entry is Map && entry['gloss'] != null) {
                definitions.add(
                  DefinitionEntry(
                    pos: pos,
                    gloss: entry['gloss'].toString(),
                    example: entry['example']?.toString(),
                  ),
                );
              }
            }
          }
        }
      }
    }

    // 5. Lấy câu ví dụ từ examples
    final List<String> examples = [];
    if (data['examples'] is Map && data['examples']['example'] is List) {
      for (final ex in data['examples']['example'] as List) {
        if (ex is Map && ex['text'] != null) {
          final cleanedEx = ex['text']
              .toString()
              .replaceAll('<b>', '')
              .replaceAll('</b>', '')
              .trim();
          if (cleanedEx.isNotEmpty) {
            examples.add(cleanedEx);
          }
        }
      }
    }

    if (primaryVi.isEmpty &&
        wordTypes.isNotEmpty &&
        wordTypes.first.terms.isNotEmpty) {
      primaryVi = wordTypes.first.terms.first;
    }

    final prettyRawJson = const JsonEncoder.withIndent('  ').convert(data);

    return FlashcardItem(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      indexNumber: indexNumber,
      englishWord: cleanWord,
      primaryVietnamese: primaryVi.isNotEmpty ? primaryVi : cleanWord,
      phonetic: phonetic,
      wordTypes: wordTypes,
      definitions: definitions,
      examples: examples,
      alternativeTranslations: altTranslations,
      rawGoogleResponseJson: prettyRawJson,
      createdAt: DateTime.now(),
    );
  }

  /// Đường dẫn phát âm thanh chuẩn từ Google Dịch TTS
  static String getGoogleTtsAudioUrl(String englishWord) {
    final encoded = Uri.encodeComponent(englishWord.trim());
    return 'https://translate.google.com/translate_tts?ie=UTF-8&client=at&tl=en&q=$encoded';
  }
}
