import 'package:flutter/material.dart';
import 'screens/home_screen.dart';
import 'theme/chibi_theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ChibiFlashcardApp());
}

class ChibiFlashcardApp extends StatelessWidget {
  const ChibiFlashcardApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Chibi Flashcard Tiếng Anh',
      debugShowCheckedModeBanner: false,
      theme: ChibiTheme.buildTheme(),
      home: const HomeScreen(),
    );
  }
}
