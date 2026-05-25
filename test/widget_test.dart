import 'package:flutter_test/flutter_test.dart';
import 'package:sleep_eeg_desktop/src/app.dart';

void main() {
  testWidgets('renders the sleep EEG viewer shell', (tester) async {
    await tester.pumpWidget(const SleepEegApp());

    expect(find.text('Sleep EEG Scorer'), findsOneWidget);
    expect(find.text('Demo recording'), findsOneWidget);
    expect(find.text('N2'), findsOneWidget);
  });
}
