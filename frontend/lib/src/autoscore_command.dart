import 'dart:io';

class AutoscoreInvocation {
  const AutoscoreInvocation({
    required this.executable,
    this.argumentPrefix = const [],
  });

  final String executable;
  final List<String> argumentPrefix;

  List<String> argumentsFor(List<String> arguments) => [
    ...argumentPrefix,
    ...arguments,
  ];
}

AutoscoreInvocation resolveAutoscoreInvocation({
  String? resolvedExecutable,
  String? currentDirectory,
  bool? isWindows,
  bool? isMacOS,
  bool Function(String path)? fileExists,
}) {
  final executablePath = resolvedExecutable ?? Platform.resolvedExecutable;
  final currentDir = currentDirectory ?? Directory.current.path;
  final windows = isWindows ?? Platform.isWindows;
  final macOS = isMacOS ?? Platform.isMacOS;
  final exists = fileExists ?? (String path) => File(path).existsSync();
  final separator = windows ? r'\' : '/';
  final executableDir = File(executablePath).parent.path;
  String join(List<String> parts) => parts.join(separator);

  final packagedCandidates = <String>[
    if (windows) join([executableDir, 'autoscore-backend.exe']),
    if (!windows) join([executableDir, 'autoscore-backend']),
    if (macOS) join([executableDir, '..', 'Resources', 'autoscore-backend']),
    if (!windows && !macOS)
      join([executableDir, '..', 'lib', 'scoringnidra', 'autoscore-backend']),
    if (!windows) join([currentDir, 'dist', 'autoscore-backend']),
    if (windows) join([currentDir, 'dist', 'autoscore-backend.exe']),
  ];
  for (final candidate in packagedCandidates) {
    if (exists(candidate)) {
      return AutoscoreInvocation(executable: candidate);
    }
  }

  final roots = <String>{
    currentDir,
    File(currentDir).parent.path,
    File(executableDir).parent.path,
  };
  final scriptCandidates = <String>[
    for (final root in roots) ...[
      join([root, 'backend_entry.py']),
      join([root, 'backend', 'backend_entry.py']),
      join([root, '..', 'backend_entry.py']),
    ],
  ];
  String? script;
  for (final candidate in scriptCandidates) {
    if (exists(candidate)) {
      script = candidate;
      break;
    }
  }

  if (script != null) {
    final pythonCandidates = windows
        ? <String>[
            join([currentDir, 'backend', 'sleep_env', 'Scripts', 'python.exe']),
            join([
              currentDir,
              '..',
              'backend',
              'sleep_env',
              'Scripts',
              'python.exe',
            ]),
            'python.exe',
          ]
        : <String>[
            join([currentDir, 'backend', 'sleep_env', 'bin', 'python']),
            join([currentDir, '..', 'backend', 'sleep_env', 'bin', 'python']),
            if (macOS) '/opt/homebrew/bin/python3',
            if (macOS) '/usr/local/bin/python3',
            'python3',
          ];
    for (final candidate in pythonCandidates) {
      if (!candidate.contains(separator) || exists(candidate)) {
        return AutoscoreInvocation(
          executable: candidate,
          argumentPrefix: [script],
        );
      }
    }
  }

  throw StateError(
    'AutoscoreNidra backend is not installed. Install the Full build or '
    'place autoscore-backend beside the application executable.',
  );
}
