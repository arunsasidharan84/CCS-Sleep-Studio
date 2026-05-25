import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import 'eeg_backend.dart';
import 'models.dart';
import 'timeline_painter.dart';

class SleepEegApp extends StatelessWidget {
  const SleepEegApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Sleep EEG Scorer',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF24786D),
          brightness: Brightness.light,
        ),
        useMaterial3: true,
      ),
      home: const SleepEegHome(),
    );
  }
}

class SleepEegHome extends StatefulWidget {
  const SleepEegHome({super.key});

  @override
  State<SleepEegHome> createState() => _SleepEegHomeState();
}

class _SleepEegHomeState extends State<SleepEegHome> {
  final EegBackend _backend = EegBackend();
  EegViewport? _viewport;
  String? _activePath;
  String? _status;
  SleepStage _selectedStage = SleepStage.n2;

  @override
  void initState() {
    super.initState();
    _loadDemo();
  }

  void _loadDemo() {
    setState(() {
      _activePath = null;
      _viewport = _backend.loadDemoViewport();
      _status = _backend.isNativeAvailable
          ? 'Rust backend loaded'
          : 'Rust backend not built; using Dart demo data';
    });
  }

  Future<void> _openRecording() async {
    final result = await FilePicker.pickFiles(
      dialogTitle: 'Open EEG recording',
      type: FileType.custom,
      allowedExtensions: const ['edf', 'mat'],
    );

    final path = result?.files.single.path;
    if (path == null) {
      return;
    }

    setState(() {
      _activePath = path;
      _viewport = _backend.loadFileViewport(path);
      _status = _backend.isNativeAvailable
          ? 'Loaded through Rust FFI'
          : 'Rust backend not built; showing demo trace for selected file';
    });
  }

  void _scoreCurrentEpoch(SleepStage stage) {
    final viewport = _viewport;
    if (viewport == null) {
      return;
    }

    setState(() {
      _selectedStage = stage;
      _viewport = viewport.copyWith(
        stages: [
          for (var index = 0; index < viewport.epochCount; index++)
            index == viewport.currentEpoch ? stage : viewport.stages[index],
        ],
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final viewport = _viewport;

    return Scaffold(
      body: Column(
        children: [
          _Toolbar(
            activePath: _activePath,
            status: _status,
            selectedStage: _selectedStage,
            onOpen: _openRecording,
            onDemo: _loadDemo,
            onScore: _scoreCurrentEpoch,
          ),
          Expanded(
            child: ColoredBox(
              color: const Color(0xFFF4F6F5),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: viewport == null
                    ? const Center(child: CircularProgressIndicator())
                    : _ViewerSurface(viewport: viewport),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Toolbar extends StatelessWidget {
  const _Toolbar({
    required this.activePath,
    required this.status,
    required this.selectedStage,
    required this.onOpen,
    required this.onDemo,
    required this.onScore,
  });

  final String? activePath;
  final String? status;
  final SleepStage selectedStage;
  final VoidCallback onOpen;
  final VoidCallback onDemo;
  final ValueChanged<SleepStage> onScore;

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 1,
      color: Colors.white,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final title = _TitleBlock(activePath: activePath);
              final scorer = _StageSelector(
                selectedStage: selectedStage,
                onScore: onScore,
              );
              final actions = Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton.filledTonal(
                    tooltip: 'Open EDF or MAT file',
                    onPressed: onOpen,
                    icon: const Icon(Icons.folder_open),
                  ),
                  IconButton(
                    tooltip: 'Load demo trace',
                    onPressed: onDemo,
                    icon: const Icon(Icons.restart_alt),
                  ),
                ],
              );

              if (constraints.maxWidth >= 1040) {
                return Row(
                  children: [
                    const Icon(Icons.monitor_heart_outlined, size: 28),
                    const SizedBox(width: 12),
                    Expanded(child: title),
                    Flexible(
                      child: Text(
                        status ?? '',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 16),
                    scorer,
                    const SizedBox(width: 8),
                    actions,
                  ],
                );
              }

              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.monitor_heart_outlined, size: 28),
                      const SizedBox(width: 12),
                      Expanded(child: title),
                      actions,
                    ],
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 12,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 320),
                        child: Text(
                          status ?? '',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      scorer,
                    ],
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _TitleBlock extends StatelessWidget {
  const _TitleBlock({required this.activePath});

  final String? activePath;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text(
          'Sleep EEG Scorer',
          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18),
        ),
        Text(
          activePath ?? 'Demo recording',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }
}

class _StageSelector extends StatelessWidget {
  const _StageSelector({required this.selectedStage, required this.onScore});

  final SleepStage selectedStage;
  final ValueChanged<SleepStage> onScore;

  @override
  Widget build(BuildContext context) {
    return SegmentedButton<SleepStage>(
      segments: const [
        ButtonSegment(value: SleepStage.wake, label: Text('W')),
        ButtonSegment(value: SleepStage.n1, label: Text('N1')),
        ButtonSegment(value: SleepStage.n2, label: Text('N2')),
        ButtonSegment(value: SleepStage.n3, label: Text('N3')),
        ButtonSegment(value: SleepStage.rem, label: Text('REM')),
      ],
      selected: {selectedStage},
      onSelectionChanged: (value) => onScore(value.first),
    );
  }
}

class _ViewerSurface extends StatelessWidget {
  const _ViewerSurface({required this.viewport});

  final EegViewport viewport;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: 82,
          child: CustomPaint(painter: HypnogramPainter(viewport)),
        ),
        const SizedBox(height: 12),
        Expanded(
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border.all(color: const Color(0xFFD8DEDC)),
              borderRadius: BorderRadius.circular(8),
            ),
            child: CustomPaint(
              painter: TimelinePainter(viewport),
              child: const SizedBox.expand(),
            ),
          ),
        ),
      ],
    );
  }
}
