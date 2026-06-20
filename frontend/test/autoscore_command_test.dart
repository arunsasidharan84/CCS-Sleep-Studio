import 'package:flutter_test/flutter_test.dart';
import 'package:scoring_nidra/src/autoscore_command.dart';

void main() {
  test('uses packaged macOS AutoscoreNidra backend', () {
    final invocation = resolveAutoscoreInvocation(
      resolvedExecutable:
          '/Applications/ScoringNidra.app/Contents/MacOS/ScoringNidra',
      currentDirectory: '/tmp',
      isWindows: false,
      isMacOS: true,
      fileExists: (path) =>
          path ==
          '/Applications/ScoringNidra.app/Contents/MacOS/../Resources/autoscore-backend',
    );

    expect(invocation.executable, contains('Resources/autoscore-backend'));
    expect(invocation.argumentPrefix, isEmpty);
  });

  test('pairs development Python with backend_entry.py', () {
    final invocation = resolveAutoscoreInvocation(
      resolvedExecutable: '/tmp/ScoringNidra',
      currentDirectory: '/workspace/ScoringNidra',
      isWindows: false,
      isMacOS: true,
      fileExists: (path) =>
          path == '/workspace/ScoringNidra/backend_entry.py' ||
          path == '/opt/homebrew/bin/python3',
    );

    expect(invocation.executable, '/opt/homebrew/bin/python3');
    expect(invocation.argumentPrefix, [
      '/workspace/ScoringNidra/backend_entry.py',
    ]);
  });

  test('finds the backend from an installed Linux launcher path', () {
    final invocation = resolveAutoscoreInvocation(
      resolvedExecutable: '/usr/bin/scoringnidra',
      currentDirectory: '/home/researcher',
      isWindows: false,
      isMacOS: false,
      fileExists: (path) =>
          path == '/usr/bin/../lib/scoringnidra/autoscore-backend',
    );

    expect(
      invocation.executable,
      '/usr/bin/../lib/scoringnidra/autoscore-backend',
    );
  });

  test('prefers a validated development standalone backend', () {
    final invocation = resolveAutoscoreInvocation(
      resolvedExecutable: '/tmp/ScoringNidra',
      currentDirectory: '/workspace/ScoringNidra',
      isWindows: false,
      isMacOS: true,
      fileExists: (path) =>
          path == '/workspace/ScoringNidra/dist/autoscore-backend' ||
          path == '/workspace/ScoringNidra/backend_entry.py' ||
          path == '/opt/homebrew/bin/python3',
    );

    expect(
      invocation.executable,
      '/workspace/ScoringNidra/dist/autoscore-backend',
    );
    expect(invocation.argumentPrefix, isEmpty);
  });

  test('never falls back to Python without a backend script', () {
    expect(
      () => resolveAutoscoreInvocation(
        resolvedExecutable: '/tmp/ScoringNidra',
        currentDirectory: '/tmp',
        isWindows: false,
        isMacOS: true,
        fileExists: (_) => false,
      ),
      throwsStateError,
    );
  });
}
