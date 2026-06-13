import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:scoring_nidra/src/app.dart';

void main() {
  testWidgets('renders the sleep EEG viewer shell', (tester) async {
    PackageInfo.setMockInitialValues(
      appName: 'ScoringNidra',
      packageName: 'scoring_nidra',
      version: '1.1.3',
      buildNumber: '9',
      buildSignature: '',
    );
    await tester.pumpWidget(const ScoringNidraApp());
    await tester.pump();

    expect(find.text('Jump to epoch:'), findsOneWidget);
    expect(find.textContaining('Ready'), findsOneWidget);
    expect(find.text('ScoringNidra v1.1.3 (build 9)'), findsOneWidget);
  });
}
