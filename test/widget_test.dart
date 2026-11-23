import 'package:flutter_test/flutter_test.dart';
import 'package:chibi_flashcard/main.dart';

void main() {
  testWidgets('Chibi Flashcard app renders Vietnamese UI', (WidgetTester tester) async {
    await tester.pumpWidget(const ChibiFlashcardApp());
    expect(find.text('Chibi Flashcard Tiếng Anh'), findsOneWidget);
  });
}
