import 'package:flutter/material.dart';
import '../services/audio_speech_service.dart';
import '../theme/chibi_theme.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  String _selectedVoiceId = AudioSpeechService.currentVoiceId;
  double _speechRate = AudioSpeechService.currentSpeechRate;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _initSettings();
  }

  Future<void> _initSettings() async {
    await AudioSpeechService.loadVoiceSettings();
    if (!mounted) return;
    setState(() {
      _selectedVoiceId = AudioSpeechService.currentVoiceId;
      _speechRate = AudioSpeechService.currentSpeechRate;
      _isLoading = false;
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
      padding: const EdgeInsets.fromLTRB(18, 8, 18, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header nhân vật Chibi
          Container(
            padding: const EdgeInsets.all(18),
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
                    width: 74,
                    height: 74,
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
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                          color: ChibiTheme.textDark,
                        ),
                      ),
                      SizedBox(height: 4),
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
          const SizedBox(height: 16),

          // Nhóm 1: Giọng Tiếng Mỹ (US) - Nữ & Nam
          _buildAccentSection(
            title: '🇺🇸 Giọng Tiếng Mỹ (American English)',
            voices: usVoices,
          ),
          const SizedBox(height: 16),

          // Nhóm 2: Giọng Tiếng Anh (UK) - Nữ & Nam
          _buildAccentSection(
            title: '🇬🇧 Giọng Tiếng Anh (British English)',
            voices: ukVoices,
          ),
          const SizedBox(height: 16),

          // Tốc độ đọc
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
