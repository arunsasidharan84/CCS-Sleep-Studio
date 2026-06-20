import 'package:flutter_test/flutter_test.dart';
import 'package:scoring_nidra/src/eeg_backend.dart';

void main() {
  test('report metadata survives native configuration serialization', () {
    final config = AppConfig(
      reportTitle: 'Custom Sleep Study',
      studySite: 'Study Centre',
      investigatorName: 'Dr Example',
      subjectId: 'SUB-42',
      subjectDetails: 'Control participant',
    );

    final restored = AppConfig.fromJson(config.toJson());

    expect(restored.reportTitle, 'Custom Sleep Study');
    expect(restored.studySite, 'Study Centre');
    expect(restored.investigatorName, 'Dr Example');
    expect(restored.subjectId, 'SUB-42');
    expect(restored.subjectDetails, 'Control participant');
  });

  test(
    'report metadata survives legacy Python configuration serialization',
    () {
      final config = AppConfig(
        reportTitle: 'Custom Sleep Study',
        studySite: 'Study Centre',
        investigatorName: 'Dr Example',
        subjectId: 'SUB-42',
        subjectDetails: 'Control participant',
      );

      final restored = AppConfig.fromPythonJson(
        config.toPythonJson(),
        const [],
      );

      expect(restored.reportTitle, 'Custom Sleep Study');
      expect(restored.studySite, 'Study Centre');
      expect(restored.investigatorName, 'Dr Example');
      expect(restored.subjectId, 'SUB-42');
      expect(restored.subjectDetails, 'Control participant');
    },
  );
}
