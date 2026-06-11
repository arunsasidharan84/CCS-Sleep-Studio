// lib/src/app.dart

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'config_dialog.dart';
import 'detection_dialogs.dart';
import 'eeg_backend.dart';
import 'models.dart';
import 'scoring_io.dart';
import 'signal_processing.dart' as sp;
import 'timeline_painter.dart';

const double _plotLeftPadding = 90.0;
const bool buildLite = bool.fromEnvironment('LITE_BUILD', defaultValue: false);

class ScoringNidraApp extends StatelessWidget {
  const ScoringNidraApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'ScoringNidra',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF3B6EA5),
          brightness: Brightness.light,
        ),
        useMaterial3: false,
        fontFamily: Platform.isMacOS ? '.AppleSystemUIFont' : null,
      ),
      home: const ScoringNidraHome(),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────

class ScoringNidraHome extends StatefulWidget {
  const ScoringNidraHome({super.key});

  @override
  State<ScoringNidraHome> createState() => _ScoringNidraHomeState();
}

class _ScoringNidraHomeState extends State<ScoringNidraHome> {
  final EegBackend _backend = EegBackend();
  final FocusNode _viewerFocusNode = FocusNode();
  AppConfig _config = AppConfig();

  EegViewport? _viewport;
  LoadedEeg? _loadedEeg;
  List<SleepStage>? _comparisonStages;
  String? _activePath;
  String _status = 'Ready — load an EDF file to begin scoring';
  int _navigationSerial = 0;
  Timer? _tfRefreshTimer;

  // SWA slider value (0–100). 100 = no smoothing, 0 = maximum smoothing.
  int _swaSlider = 100;

  // Batch Staging State
  final List<String> _batchStagingFiles = [];
  String _batchStagingAlgorithm = 'yasa';
  String _batchStagingCorrection = 'none';
  final List<String> _batchStagingEeg = [];
  final List<String> _batchStagingRef = [];
  final List<String> _batchStagingEog = [];
  final List<String> _batchStagingEmg = [];

  // Batch AnalyseNidra State
  final List<Map<String, String>> _batchAnalysePairs = [];
  final TextEditingController _batchAnalyseEegController = TextEditingController(text: 'AF7,AF8');
  final TextEditingController _batchAnalyseRefController = TextEditingController(text: 'PPG');

  // ─── Lifecycle ─────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _viewport = _backend.loadDemoViewport();
  }

  @override
  void dispose() {
    _tfRefreshTimer?.cancel();
    _viewerFocusNode.dispose();
    super.dispose();
  }

  // ─── Status bar helpers ───────────────────────────────────────────────────

  void _setStatus(String s) => setState(() => _status = s);

  void _showPending(String feature) =>
      _setStatus('$feature — not yet implemented in this version.');

  // ─── File loading ─────────────────────────────────────────────────────────

  Future<void> _openRecording({required String kind}) async {
    _setStatus(
      kind == 'mat'
          ? 'Opening MAT file picker…'
          : (kind == 'orbit'
              ? 'Opening Orbit file picker…'
              : 'Opening EDF file picker…'),
    );
    final result = await FilePicker.pickFiles(
      dialogTitle: kind == 'mat'
          ? 'Load EEGLAB structure (.mat)'
          : (kind == 'r09'
              ? 'Load Zurich file (.r09)'
              : (kind == 'orbit'
                  ? 'Load Orbit file (.orb, .signal)'
                  : 'Load EDF/Orbit file (.edf, .orb, .signal)')),
      type: FileType.custom,
      allowedExtensions: kind == 'mat'
          ? ['mat']
          : (kind == 'r09'
              ? ['r09']
              : (kind == 'orbit'
                  ? ['orb', 'signal']
                  : ['edf', 'orb', 'signal'])),
    );
    final path = result?.files.single.path;
    if (path == null) {
      _setStatus('Open cancelled');
      return;
    }
    await _openRecordingPath(path, kind: kind);
  }

  Future<void> _openRecordingPath(String path, {required String kind}) async {
    _setStatus('Loading ${_basename(path)} — computing spectrogram…');
    await Future.microtask(() {}); // let the UI update

    try {
      // Try to auto-load config JSON next to the EDF
      final autoCfg = await tryLoadAutoConfig(path);

      final LoadedEeg rawEeg;
      if (kind == 'edf' || kind == 'orbit') {
        rawEeg = _backend.loadEdf(path);
      } else if (kind == 'edfvolt') {
        rawEeg = _backend.loadEdf(path, scaleVoltsToMicrovolts: true);
      } else if (kind == 'r09') {
        rawEeg = _backend.loadR09(path);
      } else {
        rawEeg = _backend.loadMat(path);
      }

      final activeConfig =
          autoCfg ??
          AppConfig.defaultsForChannels(
            rawEeg.channelLabels,
            sampleRateHz: rawEeg.sampleRateHz,
          );
      // ignore: avoid_print
      print(
        '[ScoringNidra] Config ${autoCfg != null ? "LOADED" : "GENERATED"} '
        'for ${_basename(path)}: ${activeConfig.channels.length} channels',
      );
      if (autoCfg == null) {
        // Copy user preferences
        activeConfig.amplitudeRangeUv = _config.amplitudeRangeUv;
        activeConfig.tfFreqMin = _config.tfFreqMin;
        activeConfig.tfFreqMax = _config.tfFreqMax;
        activeConfig.spectrogramFreqMin = _config.spectrogramFreqMin;
        activeConfig.spectrogramFreqMax = _config.spectrogramFreqMax;
        activeConfig.swaChannelIndex = _config.swaChannelIndex;
        activeConfig.periodogramFreqMin = _config.periodogramFreqMin;
        activeConfig.periodogramFreqMax = _config.periodogramFreqMax;
        activeConfig.spectrogramPowerMin = _config.spectrogramPowerMin;
        activeConfig.spectrogramPowerMax = _config.spectrogramPowerMax;
        activeConfig.tfEnabled = _config.tfEnabled;
        activeConfig.tfDisplayMode = _config.tfDisplayMode;
        activeConfig.tfFrequencyScale = _config.tfFrequencyScale;
        activeConfig.tfShowRidge = _config.tfShowRidge;
        activeConfig.tfAutoScale = _config.tfAutoScale;
        activeConfig.tfPowerMin = _config.tfPowerMin;
        activeConfig.tfPowerMax = _config.tfPowerMax;
        activeConfig.stackChannels = _config.stackChannels;
        activeConfig.robustZStandardize = _config.robustZStandardize;
        activeConfig.periodogramDisplayMode = _config.periodogramDisplayMode;
        activeConfig.eegPanelTimeUnit = _config.eegPanelTimeUnit;
        activeConfig.distanceBetweenChannelsUv =
            _config.distanceBetweenChannelsUv;
        activeConfig.referenceAmplitudeLineUv =
            _config.referenceAmplitudeLineUv;
      }
      activeConfig.bindLoadedChannels(
        rawEeg.channelLabels,
        sampleRateHz: rawEeg.sampleRateHz,
      );
      // Always save after binding — persists channel index corrections
      await saveAutoConfig(path, activeConfig);

      // Pre-compute night products. Per-epoch wavelets are computed lazily.
      _setStatus('Computing spectrogram and power summaries…');
      final eeg = await _backend.computeNightProducts(rawEeg, activeConfig);

      // Try to auto-load an existing scoring JSON next to the EDF
      final epochCount = (eeg.durationSeconds / 30).ceil();
      final loadResult = await tryLoadAutoScoring(path, epochCount);
      final existingStages = loadResult?.stages;
      final existingStagesUncertain = loadResult?.stagesUncertain;
      final existingEvents = await tryLoadAutoEvents(path);

      final viewport = await _backend.viewportFromEeg(
        eeg,
        currentEpoch: 0,
        config: activeConfig,
        existingStages: existingStages,
        existingStagesUncertain: existingStagesUncertain,
        existingConfidence: loadResult?.stagesConfidence,
        includeTimeFrequency: false,
      );

      setState(() {
        _activePath = path;
        _loadedEeg = eeg;
        _config = activeConfig;
        _viewport = viewport.copyWith(scoredEvents: existingEvents);
        _status =
            'Loaded ${_basename(path)} — '
            '${existingStages != null ? '${existingStages.where((s) => s.isScored).length}/${existingStages.length} epochs already scored' : 'scoring started'}';
      });
      _viewerFocusNode.requestFocus();
      if (_config.tfEnabled) {
        _scheduleTimeFrequencyRefresh(++_navigationSerial);
      }
    } on UnsupportedError catch (e) {
      _setStatus(e.message ?? e.toString());
    } on Object catch (e) {
      _setStatus('Could not load ${_basename(path)}: $e');
    }
  }

  // ─── Close file ────────────────────────────────────────────────────────────

  void _closeCurrentFile() {
    _tfRefreshTimer?.cancel();
    _tfRefreshTimer = null;
    setState(() {
      _activePath = null;
      _loadedEeg = null;
      _comparisonStages = null;
      _viewport = _backend.loadDemoViewport();
      _config = AppConfig();
      _status = 'File closed — load an EDF file to begin scoring';
    });
  }

  // ─── Scoring ──────────────────────────────────────────────────────────────

  void _scoreCurrentEpoch(SleepStage stage) {
    final viewport = _viewport;
    if (viewport == null) return;

    final newStages = [
      for (var i = 0; i < viewport.epochCount; i++)
        i == viewport.currentEpoch ? stage : viewport.stages[i],
    ];
    setState(() {
      _viewport = viewport.copyWith(stages: newStages);
      _status = 'Epoch ${viewport.currentEpoch + 1} scored';
    });

    // Auto-save on every score change
    autoSaveScoring(
      _activePath,
      newStages,
      viewport.epochSeconds,
      events: viewport.scoredEvents,
      stagesUncertain: viewport.stagesUncertain,
      stagesConfidence: viewport.stagesConfidence,
    );

    // Auto-advance to next epoch (matching Python score_stage.py)
    _nextEpoch();
  }

  void _toggleUncertainty() {
    final v = _viewport;
    if (v == null) return;
    final epoch = v.currentEpoch;
    final newUncertain = List<bool>.from(v.stagesUncertain);
    newUncertain[epoch] = !newUncertain[epoch];
    final updated = v.copyWith(stagesUncertain: newUncertain);
    setState(() {
      _viewport = updated;
      _status =
          'Epoch ${epoch + 1} uncertainty toggled to ${newUncertain[epoch]}';
    });
    autoSaveScoring(
      _activePath,
      updated.stages,
      updated.epochSeconds,
      events: updated.scoredEvents,
      stagesUncertain: updated.stagesUncertain,
      stagesConfidence: updated.stagesConfidence,
    );
  }

  void _toggleWavelet() async {
    final eeg = _loadedEeg;
    final v = _viewport;
    if (eeg == null || v == null) return;

    final newTfEnabled = !_config.tfEnabled;
    setState(() {
      _config.tfEnabled = newTfEnabled;
    });

    if (_activePath != null) {
      await saveAutoConfig(_activePath!, _config);
    }

    _setStatus(newTfEnabled ? 'Computing wavelet TF…' : 'Wavelet panel hidden');

    if (newTfEnabled) {
      _scheduleTimeFrequencyRefresh(++_navigationSerial);
    } else {
      final newViewport = await _backend.viewportFromEeg(
        eeg,
        currentEpoch: v.currentEpoch,
        config: _config,
        existingStages: v.stages,
        existingStagesUncertain: v.stagesUncertain,
        existingConfidence: v.stagesConfidence,
        includeTimeFrequency: false,
      );
      setState(() {
        _viewport = newViewport;
      });
    }
  }

  // ─── Navigation ───────────────────────────────────────────────────────────

  void _nextEpoch() => _jumpRelative(1);
  void _previousEpoch() => _jumpRelative(-1);

  void _jumpRelative(int delta) {
    final v = _viewport;
    if (v == null) return;
    _jumpToEpoch(v.currentEpoch + 1 + delta);
  }

  void _jumpToEpoch(int epochOneBased, [bool claimFocus = true]) {
    final v = _viewport;
    if (v == null) return;
    final epoch = (epochOneBased - 1).clamp(0, v.epochCount - 1);
    final eeg = _loadedEeg;
    final serial = ++_navigationSerial;
    _tfRefreshTimer?.cancel();

    EegViewport newViewport;
    if (eeg == null) {
      newViewport = v.copyWith(currentEpoch: epoch);
    } else {
      newViewport = _backend
          .rebuildViewportForEpochSync(v, eeg, epoch, config: _config)
          .copyWith(stages: v.stages, stagesUncertain: v.stagesUncertain);
    }

    if (mounted) {
      setState(() {
        _viewport = newViewport;
        _status =
            'Epoch ${epoch + 1} / ${v.epochCount}  |  ${v.stages[epoch].label}';
      });
      if (claimFocus) {
        _viewerFocusNode.requestFocus();
      }
    }
    if (eeg != null && _config.tfEnabled) {
      _scheduleTimeFrequencyRefresh(serial);
    }
  }

  void _scheduleTimeFrequencyRefresh(int serial) {
    _tfRefreshTimer?.cancel();
    _tfRefreshTimer = Timer(const Duration(milliseconds: 550), () {
      unawaited(_refreshTimeFrequency(serial));
    });
  }

  Future<void> _refreshTimeFrequency(int serial) async {
    final v = _viewport;
    final eeg = _loadedEeg;
    if (v == null || eeg == null || serial != _navigationSerial) return;

    try {
      final refreshed = await _backend.refreshTimeFrequencyForEpoch(
        v,
        eeg,
        config: _config,
      );
      if (!mounted || serial != _navigationSerial) return;
      setState(() {
        _viewport = refreshed.copyWith(
          stages: v.stages,
          stagesUncertain: v.stagesUncertain,
        );
      });
    } catch (e) {
      if (!mounted || serial != _navigationSerial) return;
      _setStatus('Wavelet rendering failed: $e');
    }
  }

  // ─── Toolbar navigation jumps ─────────────────────────────────────────────

  /// Jump to the next epoch satisfying [test], starting from currentEpoch+1.
  void _jumpToNext(bool Function(SleepStage s) test, String label) {
    final v = _viewport;
    if (v == null) return;
    for (var i = v.currentEpoch + 1; i < v.epochCount; i++) {
      if (test(v.stages[i])) {
        _jumpToEpoch(i + 1);
        return;
      }
    }
    _setStatus('No more $label epochs found');
  }

  void _jumpNextUnscored() => _jumpToNext((s) => !s.isScored, 'unscored');

  void _jumpNextUncertain() {
    final v = _viewport;
    if (v == null) return;
    for (var i = v.currentEpoch + 1; i < v.epochCount; i++) {
      if (v.stagesUncertain[i]) {
        _jumpToEpoch(i + 1);
        return;
      }
    }
    _setStatus('No more uncertain epochs found');
  }

  void _jumpNextTransition() {
    final v = _viewport;
    if (v == null) return;
    for (var i = v.currentEpoch + 1; i < v.epochCount; i++) {
      if (i > 0 && v.stages[i] != v.stages[i - 1]) {
        _jumpToEpoch(i + 1);
        return;
      }
    }
    _setStatus('No more stage transitions found');
  }

  void _jumpNextHuman() => _jumpToNext(
    (s) => s.isScored && s != SleepStage.inconclusive,
    'human-scored',
  );

  void _jumpNextEvent() {
    final v = _viewport;
    if (v == null) return;
    final currentEpoch = v.currentEpoch;
    final eventEpochs = <int>{};
    for (final event in v.scoredEvents) {
      eventEpochs.addAll(event.epochs(v.epochSeconds, v.epochCount));
    }
    final sorted = eventEpochs.toList()..sort();
    for (final epoch in sorted) {
      if (epoch > currentEpoch) {
        _jumpToEpoch(epoch + 1);
        return;
      }
    }
    _setStatus('No more event epochs found');
  }

  void _jumpNextDisagreement() {
    final v = _viewport;
    final comparison = _comparisonStages;
    if (v == null || comparison == null) {
      _setStatus('No comparison scoring loaded');
      return;
    }
    for (
      var i = v.currentEpoch + 1;
      i < v.epochCount && i < comparison.length;
      i++
    ) {
      if (v.stages[i] != comparison[i]) {
        _jumpToEpoch(i + 1);
        return;
      }
    }
    _setStatus('No more disagreement epochs found');
  }

  void _updateFlexValues(int spectrogramFlex, int hypnogramFlex, int periodogramFlex) async {
    setState(() {
      _config.spectrogramFlex = spectrogramFlex;
      _config.hypnogramFlex = hypnogramFlex;
      _config.periodogramFlex = periodogramFlex;
    });

    final v = _viewport;
    if (v != null) {
      setState(() {
        _viewport = v.copyWith(
          spectrogramFlex: spectrogramFlex,
          hypnogramFlex: hypnogramFlex,
          periodogramFlex: periodogramFlex,
        );
      });
    }

    if (_activePath != null) {
      await saveAutoConfig(_activePath!, _config);
    }
  }

  // ─── Selection ────────────────────────────────────────────────────────────

  Future<void> _updateSelection(
    double? startSec,
    double? endSec,
    int? channel,
    double? startUv,
    double? endUv,
  ) async {
    final v = _viewport;
    final eeg = _loadedEeg;
    if (v == null || eeg == null) return;

    final newViewport = await _backend.updateSelection(
      v,
      eeg,
      startSec,
      endSec,
      channel: channel,
      startUv: startUv,
      endUv: endUv,
      config: _config,
    );
    if (mounted) {
      setState(() {
        _viewport = newViewport;
      });
      if (newViewport.scoredEvents.length != v.scoredEvents.length) {
        autoSaveScoring(
          _activePath,
          newViewport.stages,
          newViewport.epochSeconds,
          events: newViewport.scoredEvents,
          stagesUncertain: newViewport.stagesUncertain,
        );
      }
    }
  }

  void _markEvent(int digit) {
    final v = _viewport;
    if (v == null) return;
    final label = _eventLabel(digit);
    final key = digit == 0 ? 'A' : 'F$digit';
    final newEvents = <ScoredEvent>[...v.scoredEvents];
    if (v.eventSelections.isEmpty) {
      final start = v.currentEpoch * v.epochSeconds.toDouble();
      newEvents.add(
        ScoredEvent(
          digit: digit,
          key: key,
          label: label,
          startSec: start,
          endSec: start + v.epochSeconds,
        ),
      );
    } else {
      for (final selection in v.eventSelections) {
        final start = selection.startSec < selection.endSec
            ? selection.startSec
            : selection.endSec;
        final end = selection.startSec < selection.endSec
            ? selection.endSec
            : selection.startSec;
        if (end > start) {
          newEvents.add(
            ScoredEvent(
              digit: digit,
              key: key,
              label: label,
              startSec: start,
              endSec: end,
            ),
          );
        }
      }
    }
    setState(() {
      _viewport = v.copyWith(
        scoredEvents: _mergeScoredEvents(newEvents),
        clearSelection: true,
        clearEventSelections: true,
      );
      _status = 'Marked ${_eventLabel(digit)}';
    });
    final updated = _viewport;
    if (updated != null) {
      autoSaveScoring(
        _activePath,
        updated.stages,
        updated.epochSeconds,
        events: updated.scoredEvents,
        stagesUncertain: updated.stagesUncertain,
      );
    }
  }

  void _eraseEventsInSelections() {
    final v = _viewport;
    if (v == null || v.eventSelections.isEmpty) return;
    final eraseRanges = [
      for (final selection in v.eventSelections)
        (
          selection.startSec < selection.endSec
              ? selection.startSec
              : selection.endSec,
          selection.startSec < selection.endSec
              ? selection.endSec
              : selection.startSec,
        ),
    ];
    final kept = <ScoredEvent>[];
    for (final event in v.scoredEvents) {
      var fragments = <(double, double)>[(event.startSec, event.endSec)];
      for (final erase in eraseRanges) {
        final next = <(double, double)>[];
        for (final fragment in fragments) {
          final start = fragment.$1;
          final end = fragment.$2;
          final eraseStart = erase.$1;
          final eraseEnd = erase.$2;
          if (eraseEnd <= start || eraseStart >= end) {
            next.add(fragment);
          } else {
            if (eraseStart > start) next.add((start, eraseStart));
            if (eraseEnd < end) next.add((eraseEnd, end));
          }
        }
        fragments = next;
      }
      for (final fragment in fragments) {
        if (fragment.$2 > fragment.$1) {
          kept.add(
            ScoredEvent(
              digit: event.digit,
              key: event.key,
              label: event.label,
              startSec: fragment.$1,
              endSec: fragment.$2,
            ),
          );
        }
      }
    }
    setState(() {
      _viewport = v.copyWith(
        scoredEvents: kept,
        clearSelection: true,
        clearEventSelections: true,
      );
      _status = 'Erased events in drawn selection';
    });
    final updated = _viewport;
    if (updated != null) {
      autoSaveScoring(
        _activePath,
        updated.stages,
        updated.epochSeconds,
        events: updated.scoredEvents,
        stagesUncertain: updated.stagesUncertain,
      );
    }
  }

  void _deleteAllEvents() {
    final v = _viewport;
    if (v == null) return;
    setState(() {
      _viewport = v.copyWith(
        scoredEvents: const [],
        clearEventSelections: true,
      );
      _status = 'Deleted all events';
    });
    autoSaveScoring(
      _activePath,
      v.stages,
      v.epochSeconds,
      stagesUncertain: v.stagesUncertain,
    );
  }

  List<ScoredEvent> _mergeScoredEvents(List<ScoredEvent> events) {
    events.sort((a, b) {
      final labelCompare = a.digit.compareTo(b.digit);
      if (labelCompare != 0) return labelCompare;
      return a.startSec.compareTo(b.startSec);
    });
    final merged = <ScoredEvent>[];
    for (final event in events) {
      if (merged.isEmpty ||
          merged.last.digit != event.digit ||
          event.startSec > merged.last.endSec) {
        merged.add(event);
      } else {
        final last = merged.removeLast();
        merged.add(
          ScoredEvent(
            digit: last.digit,
            key: last.key,
            label: last.label,
            startSec: last.startSec,
            endSec: event.endSec > last.endSec ? event.endSec : last.endSec,
          ),
        );
      }
    }
    return merged;
  }

  String _eventLabel(int digit) => digit == 0 ? 'Artifact' : 'Event $digit';

  // ─── Scoring I/O ──────────────────────────────────────────────────────────

  Future<void> _loadScoring() async {
    final v = _viewport;
    if (v == null) {
      _setStatus('Load an EDF first');
      return;
    }
    final result = await importScoringDialog(
      v.epochCount,
      'any',
      onStatus: _setStatus,
    );
    if (result != null) {
      setState(() {
        _viewport = v.copyWith(
          stages: result.stages,
          stagesUncertain: result.stagesUncertain,
        );
      });
    }
  }

  Future<void> _runAutoScoring() async {
    final v = _viewport;
    final eeg = _loadedEeg;
    final path = _activePath;
    if (v == null || eeg == null || path == null) {
      _setStatus('Load an EDF first');
      return;
    }

    showDialog(
      context: context,
      builder: (_) => AutoScoringDialog(
        channelLabels: eeg.channelLabels,
        onRun: (settings) async {
          _executeAutoScoring(settings);
        },
      ),
    );
  }

  Future<void> _executeAutoScoring(Map<String, dynamic> settings) async {
    final v = _viewport;
    final eeg = _loadedEeg;
    final path = _activePath;
    if (v == null || eeg == null || path == null) return;

    final navigator = Navigator.of(context);
    final executable = detectBackendExecutable();
    final script = detectBackendScript();

    final args = <String>[];
    if (executable.endsWith('.py') ||
        script.isNotEmpty &&
            (executable.contains('python') || executable.contains('python3'))) {
      if (script.isNotEmpty) {
        args.add(script);
      }
    }

    args.add(path);

    final algorithm = settings['algorithm'] as String;
    args.addAll(['--algorithm', algorithm]);

    final correction = settings['sequence_correction'] as String;
    args.addAll(['--sequence-correction', correction]);

    final eegChans = settings['eeg'] as List<String>;
    if (eegChans.isNotEmpty) {
      args.addAll(['--eeg', eegChans.join(',')]);
    }

    final refChans = settings['ref'] as List<String>;
    if (refChans.isNotEmpty) {
      args.addAll(['--ref', refChans.join(',')]);
    }

    final eogChans = settings['eog'] as List<String>;
    if (eogChans.isNotEmpty) {
      args.addAll(['--eog', eogChans.join(',')]);
    }

    final emgChans = settings['emg'] as List<String>;
    if (emgChans.isNotEmpty) {
      args.addAll(['--emg', emgChans.join(',')]);
    }

    if (correction == 'sleepgpt') {
      final alpha = settings['sleepgpt_alpha'] as double;
      args.addAll(['--sleepgpt-alpha', alpha.toString()]);
      final ngram = settings['sleepgpt_ngram'] as int;
      args.addAll(['--sleepgpt-ngram', ngram.toString()]);
    }

    final logsController = StreamController<String>();
    final logLines = <String>[];
    var isDone = false;
    String? outputJsonPath;
    StateSetter? setStateDialogRef;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            setStateDialogRef = setStateDialog;
            return AlertDialog(
              title: const Text('Auto-Scoring Progress'),
              content: SizedBox(
                width: 600,
                height: 400,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Executing python backend scoring process…',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 10),
                    const LinearProgressIndicator(),
                    const SizedBox(height: 10),
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        color: Colors.black87,
                        width: double.infinity,
                        child: StreamBuilder<String>(
                          stream: logsController.stream,
                          builder: (context, snapshot) {
                            return Scrollbar(
                              child: ListView.builder(
                                shrinkWrap: true,
                                itemCount: logLines.length,
                                itemBuilder: (context, index) {
                                  return Text(
                                    logLines[index],
                                    style: const TextStyle(
                                      color: Colors.lightGreenAccent,
                                      fontFamily: 'Courier',
                                      fontSize: 12,
                                    ),
                                  );
                                },
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: isDone ? () => navigator.pop() : null,
                  child: Text(isDone ? 'Close' : 'Scoring…'),
                ),
              ],
            );
          },
        );
      },
    );

    Future.microtask(() async {
      _setStatus('Spawning automated sleep scoring backend…');
      try {
        void onLine(String line) {
          logsController.add(line);
          logLines.add(line);
          setStateDialogRef?.call(() {});
        }

        final exitCode = await _backend.runCommandStreamAsync(
          executable: executable,
          arguments: args,
          onLine: onLine,
        );
        isDone = true;
        setStateDialogRef?.call(() {});
        outputJsonPath = _outputPathFromLogs(logLines);

        if (exitCode == 0 &&
            outputJsonPath != null &&
            outputJsonPath!.isNotEmpty) {
          logsController.add(
            '\nScoring finished successfully! Loading predictions...',
          );
          logLines.add(
            '\nScoring finished successfully! Loading predictions...',
          );

          final scoringData = await loadScoringFileDirectly(
            outputJsonPath!,
            'scoringhero',
            v.epochCount,
          );
          setState(() {
            _viewport = v.copyWith(
              stages: scoringData.stages,
              stagesUncertain: scoringData.stagesUncertain,
            );
            _status = 'Automated scoring completed with $algorithm';
          });
          navigator.pop();
        } else {
          logsController.add('\nScoring failed with exit code $exitCode');
          logLines.add('\nScoring failed with exit code $exitCode');
          _setStatus('Automated sleep scoring failed. Exit code: $exitCode');

          navigator.pop();
          if (mounted) {
            showDialog(
              context: context,
              builder: (context) => AlertDialog(
                title: const Text('Scoring Failed'),
                content: SizedBox(
                  width: 600,
                  height: 400,
                  child: SingleChildScrollView(
                    child: Text(
                      'Auto-scoring process returned exit code $exitCode.\n\nLogs:\n${logLines.join('\n')}',
                      style: const TextStyle(
                        fontSize: 12,
                        fontFamily: 'Courier',
                      ),
                    ),
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Close'),
                  ),
                ],
              ),
            );
          }
        }
      } catch (e) {
        logsController.add('\nException occurred: $e');
        logLines.add('\nException occurred: $e');
        _setStatus('Automated sleep scoring failed: $e');
        isDone = true;
        navigator.pop();
        if (mounted) {
          showDialog(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('Scoring Exception'),
              content: SizedBox(
                width: 600,
                height: 400,
                child: SingleChildScrollView(
                  child: Text(
                    'Auto-scoring process encountered exception: $e\n\nLogs:\n${logLines.join('\n')}',
                    style: const TextStyle(fontSize: 12, fontFamily: 'Courier'),
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Close'),
                ),
              ],
            ),
          );
        }
      } finally {
        logsController.close();
      }
    });
  }

  Future<void> _runBatchAutoScoring() async {
    _setStatus('Opening multi-EDF file picker…');
    final result = await FilePicker.pickFiles(
      dialogTitle: 'Select EDF files for Batch Auto-Scoring',
      type: FileType.custom,
      allowedExtensions: ['edf'],
      allowMultiple: true,
    );
    if (result == null || result.files.isEmpty) {
      _setStatus('Batch scoring cancelled');
      return;
    }

    final files = result.files.map((f) => f.path).whereType<String>().toList();
    if (files.isEmpty) {
      _setStatus('No valid files selected');
      return;
    }

    if (!mounted) return;

    List<String> channelLabels = const [];
    try {
      channelLabels = _backend.loadEdf(files.first).channelLabels;
    } on Object catch (error) {
      _setStatus('Could not inspect batch channels: $error');
    }

    showDialog(
      context: context,
      builder: (_) => BatchAutoScoringDialog(
        files: files,
        channelLabels: channelLabels,
        onRun: (settings) async {
          _executeBatchAutoScoring(files, settings);
        },
      ),
    );
  }

  Future<void> _runAnalyseNidraCurrent() async {
    final path = _activePath;
    final eeg = _loadedEeg;
    final viewport = _viewport;
    if (path == null || eeg == null || viewport == null) {
      _setStatus('Load an EDF first');
      return;
    }
    if (!path.toLowerCase().endsWith('.edf')) {
      _setStatus('analyseNidra currently requires an EDF recording');
      return;
    }
    await autoSaveScoring(
      path,
      viewport.stages,
      viewport.epochSeconds,
      stagesUncertain: viewport.stagesUncertain,
      stagesConfidence: viewport.stagesConfidence,
    );
    final scoringPath = _sidecarPath(path, '.json');
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (_) => AnalyseNidraDialog(
        channelLabels: eeg.channelLabels,
        batchCount: 1,
        onRun: (channels, references) {
          _runAnalyseNidraJobs(
            [
              _AnalyseNidraJob(
                edfPath: path,
                scoringPath: scoringPath,
                mappedScoringPath: scoringPath,
              ),
            ],
            channels,
            references,
          );
        },
      ),
    );
  }

  Future<void> _runAnalyseNidraBatch() async {
    final result = await FilePicker.pickFiles(
      dialogTitle: 'Select sleep scoring files for batch analyseNidra',
      type: FileType.custom,
      allowedExtensions: ['json', 'txt', 'csv', 'vis', 'annot', 'edf'],
      allowMultiple: true,
    );
    final scoringPaths = result?.files
        .map((file) => file.path)
        .whereType<String>()
        .toList();
    if (scoringPaths == null || scoringPaths.isEmpty) {
      _setStatus('Batch analysis cancelled');
      return;
    }

    final jobs = <_AnalyseNidraJob>[];
    final failures = <String>[];
    for (final scoringPath in scoringPaths) {
      final edfPath = _detectMatchingEdf(scoringPath);
      if (edfPath == null) {
        failures.add('${_basename(scoringPath)}: matching EDF not found');
        continue;
      }
      try {
        final loaded = _backend.loadEdf(edfPath);
        final epochCount = math.max(1, (loaded.durationSeconds / 30).ceil());
        final detection = await detectScoringFormat(scoringPath);
        final scoring = await loadScoringFileDirectly(
          scoringPath,
          detection.parserType,
          epochCount,
        );
        final mappedPath = _sidecarPath(scoringPath, '.analyse-mapped.json');
        await writeMappedScoringJson(
          mappedPath,
          scoring.stages,
          sourcePath: edfPath,
          stagesUncertain: scoring.stagesUncertain,
          stagesConfidence: scoring.stagesConfidence,
        );
        jobs.add(
          _AnalyseNidraJob(
            edfPath: edfPath,
            scoringPath: scoringPath,
            mappedScoringPath: mappedPath,
          ),
        );
      } on Object catch (error) {
        failures.add('${_basename(scoringPath)}: $error');
      }
    }
    if (jobs.isEmpty) {
      _setStatus('No scoring files could be paired with EDF data');
      if (mounted) {
        _showTextDialog('Batch analysis setup failed', failures.join('\n'));
      }
      return;
    }
    final labels = _backend.loadEdf(jobs.first.edfPath).channelLabels;
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (_) => AnalyseNidraDialog(
        channelLabels: labels,
        batchCount: jobs.length,
        onRun: (channels, references) {
          if (failures.isNotEmpty) {
            _setStatus(
              '${jobs.length} analysis jobs ready; ${failures.length} skipped',
            );
          }
          _runAnalyseNidraJobs(jobs, channels, references);
        },
      ),
    );
  }

  void _runAnalyseNidraJobs(
    List<_AnalyseNidraJob> jobs,
    List<String> channels,
    List<String> references,
  ) {
    final executable = detectAnalyseNidraExecutable();
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => _CommandBatchProgressDialog(
        title: 'analyseNidra',
        jobs: [
          for (final job in jobs)
            _CommandJob(
              label: _basename(job.edfPath),
              executable: executable,
              arguments: _analyseNidraArguments(job, channels, references),
            ),
        ],
        onFinished: (failed) => _setStatus(
          failed == 0
              ? 'analyseNidra completed for ${jobs.length} recording(s)'
              : 'analyseNidra finished: ${jobs.length - failed} completed, $failed failed',
        ),
      ),
    );
  }

  void _showTextDialog(String title, String text) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(title),
        content: SelectableText(text),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  void _executeBatchAutoScoring(
    List<String> files,
    Map<String, dynamic> settings,
  ) {
    final algorithm = settings['algorithm'] as String;
    final correction = settings['sequence_correction'] as String;
    final alpha = (settings['sleepgpt_alpha'] as num?)?.toDouble() ?? 0.1;
    final ngram = (settings['sleepgpt_ngram'] as num?)?.toInt() ?? 30;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return BatchProgressDialog(
          files: files,
          algorithm: algorithm,
          correction: correction,
          sleepgptAlpha: alpha,
          sleepgptNgram: ngram,
          eegChannels: List<String>.from(settings['eeg'] as List? ?? const []),
          refChannels: List<String>.from(settings['ref'] as List? ?? const []),
          eogChannels: List<String>.from(settings['eog'] as List? ?? const []),
          emgChannels: List<String>.from(settings['emg'] as List? ?? const []),
          onFinished: () {
            _setStatus('Batch auto-scoring finished');
            // If the active file was one of the scored files, reload it
            final active = _activePath;
            if (active != null && files.contains(active)) {
              _openRecordingPath(
                active,
                kind: active.split('.').last.toLowerCase(),
              );
            }
          },
        );
      },
    );
  }

  Future<void> _saveScoring() async {
    final v = _viewport;
    if (v == null) {
      _setStatus('Nothing to save');
      return;
    }
    await exportScoringDialog(
      v.stages,
      v.epochSeconds,
      _activePath,
      events: v.scoredEvents,
      stagesUncertain: v.stagesUncertain,
      onStatus: _setStatus,
    );
  }

  Future<void> _loadComparisonScoring() async {
    final v = _viewport;
    if (v == null) {
      _setStatus('Load an EDF first');
      return;
    }
    final result = await importScoringDialog(
      v.epochCount,
      'any',
      onStatus: _setStatus,
    );
    if (result == null) return;
    setState(() {
      _comparisonStages = result.stages;
      _status =
          'Loaded ${result.sourceFormat} comparison — '
          '${_disagreementCount(v.stages, result.stages)} disagreements';
    });
  }

  void _removeComparisonScoring() {
    setState(() {
      _comparisonStages = null;
      _status = 'Comparison scoring removed';
    });
  }

  void _showComparisonStats() {
    final v = _viewport;
    final comparison = _comparisonStages;
    if (v == null || comparison == null) {
      _setStatus('No comparison scoring loaded');
      return;
    }
    final metrics = _StageComparisonMetrics.compute(v.stages, comparison);
    showDialog(
      context: context,
      builder: (context) => _ComparisonReportCardDialog(metrics: metrics),
    );
  }

  void _showSelectionHelp() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Signal selection box'),
        content: const Text(
          'Drag on the signal panel to draw one or more selection boxes. '
          'The total duration is shown in the upper right of the signal view. '
          'Press A for Artifact or F1-F12 for Event 1-12 to convert the drawn boxes into events. '
          'Press Backspace to erase existing events inside drawn boxes. '
          'Press Q to toggle uncertainty for the current epoch.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  Future<void> _loadSleeptripEvents() async {
    final v = _viewport;
    if (v == null) {
      _setStatus('Load an EDF first');
      return;
    }
    final result = await FilePicker.pickFiles(
      dialogTitle: 'Load Sleeptrip Events (_events.csv)',
      type: FileType.custom,
      allowedExtensions: ['csv', 'tsv', 'txt'],
    );
    final path = result?.files.single.path;
    if (path == null) {
      _setStatus('Event import cancelled');
      return;
    }
    try {
      final lines = await File(path).readAsLines();
      if (lines.isEmpty) throw const FormatException('Empty events file');
      final delimiter = lines.first.contains('\t') ? '\t' : ',';
      final header = lines.first
          .split(delimiter)
          .map((h) => h.trim().toLowerCase())
          .toList();
      final eventCol = header.indexOf('event');
      final startCol = header.indexOf('start');
      final stopCol = header.contains('stop')
          ? header.indexOf('stop')
          : header.indexOf('end');
      if (eventCol < 0 || startCol < 0 || stopCol < 0) {
        throw const FormatException(
          'Expected event, start, and stop/end columns',
        );
      }
      final labelToDigit = <String, int>{};
      final imported = <ScoredEvent>[];
      for (final line in lines.skip(1)) {
        if (line.trim().isEmpty) continue;
        final cols = line.split(delimiter);
        if (cols.length <= stopCol ||
            cols.length <= eventCol ||
            cols.length <= startCol) {
          continue;
        }
        final label = cols[eventCol].trim();
        final start = double.tryParse(cols[startCol].trim());
        final stop = double.tryParse(cols[stopCol].trim());
        if (label.isEmpty || start == null || stop == null || stop <= start) {
          continue;
        }
        final digit = labelToDigit.putIfAbsent(
          label,
          () => (labelToDigit.length + 1).clamp(1, 12).toInt(),
        );
        imported.add(
          ScoredEvent(
            digit: digit,
            key: 'F$digit',
            label: label,
            startSec: start,
            endSec: stop,
          ),
        );
      }
      setState(() {
        _viewport = v.copyWith(
          scoredEvents: _mergeScoredEvents([...v.scoredEvents, ...imported]),
        );
        _status = 'Imported ${imported.length} Sleeptrip events';
      });
    } catch (e) {
      _setStatus('Failed to import Sleeptrip events: $e');
    }
  }

  Future<void> _runKComplexDetection() async {
    final eeg = _loadedEeg;
    final v = _viewport;
    if (eeg == null || v == null) {
      _setStatus('Load an EDF first');
      return;
    }

    final hasStages = v.stages.any((s) => s.isScored);

    showDialog(
      context: context,
      builder: (_) => MtKcdDialog(
        channelLabels: eeg.channelLabels,
        hasStages: hasStages,
        onRun: (settings) async {
          showDialog(
            context: context,
            barrierDismissible: false,
            builder: (context) => const AlertDialog(
              content: Row(
                children: [
                  CircularProgressIndicator(),
                  SizedBox(width: 20),
                  Text('Running MT-KCD K-Complex detection…'),
                ],
              ),
            ),
          );

          try {
            final chIdx = eeg.channelLabels.indexOf(settings['channel']);
            if (chIdx < 0) throw Exception('Channel not found');
            final signal = eeg.channelSamples[chIdx];
            final sfreq = eeg.sampleRateHz;

            final amin = settings['amin'] as double;
            final dmax_s = settings['dmax_s'] as double;
            final q = settings['q'] as double;
            final fmax = settings['fmax'] as double;

            final events = await _runKComplexIsolate(
              signal,
              sfreq,
              amin,
              dmax_s,
              q,
              fmax,
            );

            if (mounted) Navigator.of(context).pop();

            final filterStages = settings['filter_stages'] as List<String>?;
            var finalEvents = events;
            if (filterStages != null && filterStages.isNotEmpty) {
              final stageSet = filterStages.toSet();
              finalEvents = events.where((event) {
                final mid = (event.$1 + event.$2) / 2.0;
                final epochIdx = (mid / v.epochSeconds).floor();
                if (epochIdx >= 0 && epochIdx < v.stages.length) {
                  return stageSet.contains(v.stages[epochIdx].label);
                }
                return false;
              }).toList();
            }

            final markerLabel = settings['marker'] as String;
            final digit = markerLabel == 'Artifact'
                ? 0
                : int.parse(markerLabel.substring(1));
            final key = digit == 0 ? 'A' : 'F$digit';
            final label = digit == 0 ? 'Artifact' : 'Event $digit';

            final scoredEvents = <ScoredEvent>[...v.scoredEvents];
            for (final ev in finalEvents) {
              scoredEvents.add(
                ScoredEvent(
                  digit: digit,
                  key: key,
                  label: label,
                  startSec: ev.$1,
                  endSec: ev.$2,
                ),
              );
            }

            final merged = _mergeScoredEvents(scoredEvents);

            if (mounted) {
              setState(() {
                _viewport = v.copyWith(
                  scoredEvents: merged,
                  clearEventSelections: true,
                );
                _status =
                    'MT-KCD completed: detected ${finalEvents.length} K-complex(s)';
              });

              autoSaveScoring(
                _activePath,
                _viewport!.stages,
                _viewport!.epochSeconds,
                events: _viewport!.scoredEvents,
                stagesUncertain: _viewport!.stagesUncertain,
              );
            }
          } catch (e) {
            if (mounted) {
              Navigator.of(context).pop();
              showDialog(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Text('MT-KCD Error'),
                  content: Text(
                    'An error occurred during K-complex detection:\n\n$e',
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('OK'),
                    ),
                  ],
                ),
              );
            }
          }
        },
      ),
    );
  }

  Future<void> _runSpindleDetection() async {
    final eeg = _loadedEeg;
    final v = _viewport;
    if (eeg == null || v == null) {
      _setStatus('Load an EDF first');
      return;
    }

    final hasStages = v.stages.any((s) => s.isScored);

    showDialog(
      context: context,
      builder: (_) => MtSpindleDialog(
        channelLabels: eeg.channelLabels,
        hasStages: hasStages,
        onRun: (settings) async {
          showDialog(
            context: context,
            barrierDismissible: false,
            builder: (context) => const AlertDialog(
              content: Row(
                children: [
                  CircularProgressIndicator(),
                  SizedBox(width: 20),
                  Text('Running MT-Spindle spindle detection…'),
                ],
              ),
            ),
          );

          try {
            final chIdx = eeg.channelLabels.indexOf(settings['channel']);
            if (chIdx < 0) throw Exception('Channel not found');
            final signal = eeg.channelSamples[chIdx];
            final sfreq = eeg.sampleRateHz;

            final fmin = settings['fmin'] as double;
            final fmax = settings['fmax'] as double;
            final amin = settings['amin'] as double;
            final dmin_s = settings['dmin_s'] as double;
            final dmax_s = settings['dmax_s'] as double;
            final q = settings['q'] as double;

            final events = await _runSpindleIsolate(
              signal,
              sfreq,
              fmin,
              fmax,
              amin,
              dmin_s,
              dmax_s,
              q,
            );

            if (mounted) Navigator.of(context).pop();

            final filterStages = settings['filter_stages'] as List<String>?;
            var finalEvents = events;
            if (filterStages != null && filterStages.isNotEmpty) {
              final stageSet = filterStages.toSet();
              finalEvents = events.where((event) {
                final mid = (event.$1 + event.$2) / 2.0;
                final epochIdx = (mid / v.epochSeconds).floor();
                if (epochIdx >= 0 && epochIdx < v.stages.length) {
                  return stageSet.contains(v.stages[epochIdx].label);
                }
                return false;
              }).toList();
            }

            final markerLabel = settings['marker'] as String;
            final digit = markerLabel == 'Artifact'
                ? 0
                : int.parse(markerLabel.substring(1));
            final key = digit == 0 ? 'A' : 'F$digit';
            final label = digit == 0 ? 'Artifact' : 'Event $digit';

            final scoredEvents = <ScoredEvent>[...v.scoredEvents];
            for (final ev in finalEvents) {
              scoredEvents.add(
                ScoredEvent(
                  digit: digit,
                  key: key,
                  label: label,
                  startSec: ev.$1,
                  endSec: ev.$2,
                ),
              );
            }

            final merged = _mergeScoredEvents(scoredEvents);

            if (mounted) {
              setState(() {
                _viewport = v.copyWith(
                  scoredEvents: merged,
                  clearEventSelections: true,
                );
                _status =
                    'MT-Spindle completed: detected ${finalEvents.length} spindle(s)';
              });

              autoSaveScoring(
                _activePath,
                _viewport!.stages,
                _viewport!.epochSeconds,
                events: _viewport!.scoredEvents,
                stagesUncertain: _viewport!.stagesUncertain,
              );
            }
          } catch (e) {
            if (mounted) {
              Navigator.of(context).pop();
              showDialog(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Text('MT-Spindle Error'),
                  content: Text(
                    'An error occurred during spindle detection:\n\n$e',
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('OK'),
                    ),
                  ],
                ),
              );
            }
          }
        },
      ),
    );
  }

  Future<void> _exportSleepReport() async {
    final v = _viewport;
    if (v == null) {
      _setStatus('Load an EDF first');
      return;
    }
    final output = await FilePicker.saveFile(
      dialogTitle: 'Export Sleep Report (PDF)',
      fileName: '${_basename(_activePath ?? 'sleep_report')}.report.pdf',
      type: FileType.custom,
      allowedExtensions: ['pdf'],
    );
    if (output == null) {
      _setStatus('Report export cancelled');
      return;
    }
    final path = output.toLowerCase().endsWith('.pdf') ? output : '$output.pdf';
    final lines = _sleepReportLines(v);
    await File(path).writeAsBytes(_buildSimplePdf(lines));
    _setStatus('Exported sleep report to ${_basename(path)}');
  }

  List<String> _sleepReportLines(EegViewport v) {
    final scored = v.stages.where((s) => s.isScored).length;
    final sleepEpochs = v.stages
        .where(
          (s) =>
              s == SleepStage.n1 ||
              s == SleepStage.n2 ||
              s == SleepStage.n3 ||
              s == SleepStage.rem,
        )
        .length;
    final totalMinutes = v.epochCount * v.epochSeconds / 60.0;
    final sleepMinutes = sleepEpochs * v.epochSeconds / 60.0;
    final efficiency = totalMinutes <= 0
        ? 0.0
        : sleepMinutes / totalMinutes * 100.0;
    final lines = <String>[
      'Scoring Hero Sleep Report',
      'Recording: ${_basename(_activePath ?? v.sourceDescription)}',
      'Epochs: ${v.epochCount} (${v.epochSeconds} s)',
      'Scored epochs: $scored / ${v.epochCount}',
      'Recording time: ${totalMinutes.toStringAsFixed(1)} min',
      'Total sleep time: ${sleepMinutes.toStringAsFixed(1)} min',
      'Sleep efficiency: ${efficiency.toStringAsFixed(1)} %',
      '',
      'Stage distribution',
    ];
    for (final stage in [
      SleepStage.wake,
      SleepStage.n1,
      SleepStage.n2,
      SleepStage.n3,
      SleepStage.rem,
      SleepStage.inconclusive,
      SleepStage.unknown,
    ]) {
      final count = v.stages.where((s) => s == stage).length;
      final minutes = count * v.epochSeconds / 60.0;
      lines.add(
        '${stage.label}: $count epochs, ${minutes.toStringAsFixed(1)} min',
      );
    }
    lines.add('');
    lines.add('Events');
    final eventsByLabel = <String, (int, double)>{};
    for (final event in v.scoredEvents) {
      final old = eventsByLabel[event.label] ?? (0, 0.0);
      eventsByLabel[event.label] = (old.$1 + 1, old.$2 + event.durationSeconds);
    }
    if (eventsByLabel.isEmpty) {
      lines.add('No events marked.');
    } else {
      for (final entry in eventsByLabel.entries) {
        lines.add(
          '${entry.key}: ${entry.value.$1} events, ${entry.value.$2.toStringAsFixed(1)} s',
        );
      }
    }
    return lines;
  }

  List<int> _buildSimplePdf(List<String> lines) {
    final escaped = lines
        .take(42)
        .map(
          (line) => line
              .replaceAll('\\', '\\\\')
              .replaceAll('(', r'\(')
              .replaceAll(')', r'\)'),
        )
        .toList();
    final content = StringBuffer('BT\n/F1 12 Tf\n50 760 Td\n');
    for (var i = 0; i < escaped.length; i++) {
      if (i > 0) content.write('0 -16 Td\n');
      content.write('(${escaped[i]}) Tj\n');
    }
    content.write('ET\n');
    final stream = content.toString();
    final objects = <String>[
      '<< /Type /Catalog /Pages 2 0 R >>',
      '<< /Type /Pages /Kids [3 0 R] /Count 1 >>',
      '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Resources << /Font << /F1 5 0 R >> >> /Contents 4 0 R >>',
      '<< /Length ${stream.length} >>\nstream\n$stream\nendstream',
      '<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>',
    ];
    final buffer = StringBuffer('%PDF-1.4\n');
    final offsets = <int>[0];
    for (var i = 0; i < objects.length; i++) {
      offsets.add(buffer.length);
      buffer.write('${i + 1} 0 obj\n${objects[i]}\nendobj\n');
    }
    final xrefOffset = buffer.length;
    buffer.write('xref\n0 ${objects.length + 1}\n');
    buffer.write('0000000000 65535 f \n');
    for (final offset in offsets.skip(1)) {
      buffer.write('${offset.toString().padLeft(10, '0')} 00000 n \n');
    }
    buffer.write(
      'trailer\n<< /Size ${objects.length + 1} /Root 1 0 R >>\nstartxref\n$xrefOffset\n%%EOF\n',
    );
    return buffer.toString().codeUnits;
  }

  void _zoomOnSelectedEeg() {
    final v = _viewport;
    final eeg = _loadedEeg;
    if (v == null || eeg == null || v.eventSelections.isEmpty) {
      _setStatus('Draw a signal selection first');
      return;
    }
    final selection = v.eventSelections.last;
    final rawIdx =
        selection.channel >= 0 &&
            selection.channel < v.signalChannelSourceIndices.length
        ? v.signalChannelSourceIndices[selection.channel]
        : selection.channel;
    if (rawIdx < 0 || rawIdx >= eeg.channelSamples.length) return;
    final srate = eeg.sampleRateHz;
    final start = (math.min(selection.startSec, selection.endSec) * srate)
        .round()
        .clamp(0, eeg.channelSamples[rawIdx].length);
    final end = (math.max(selection.startSec, selection.endSec) * srate)
        .round()
        .clamp(0, eeg.channelSamples[rawIdx].length);
    if (end <= start) return;
    final samples = _backend.getDisplaySegmentForChannel(
      eeg: eeg,
      channelIndex: selection.channel,
      start: start,
      end: end,
      config: _config,
      applyFilters: true,
    );
    if (samples.isEmpty) return;
    final label = rawIdx < v.channelLabels.length
        ? v.channelLabels[rawIdx]
        : 'Channel';
    showDialog(
      context: context,
      builder: (context) => Dialog(
        child: SizedBox(
          width: 760,
          height: 420,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(8),
                child: Text(
                  'Selected EEG: $label',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
              Expanded(
                child: CustomPaint(
                  painter: _ZoomSignalPainter(samples, srate),
                  child: const SizedBox.expand(),
                ),
              ),
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Close'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  int _disagreementCount(List<SleepStage> a, List<SleepStage> b) {
    final total = a.length < b.length ? a.length : b.length;
    var count = 0;
    for (var i = 0; i < total; i++) {
      if (a[i] != b[i]) count++;
    }
    return count;
  }

  // ─── Configuration I/O ────────────────────────────────────────────────────

  Future<void> _loadConfig() async {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['json'],
    );
    if (result != null && result.files.single.path != null) {
      final file = File(result.files.single.path!);
      try {
        final content = await file.readAsString();
        final dynamic decoded = jsonDecode(content);
        final newCfg = decoded is Map<String, dynamic>
            ? AppConfig.fromJson(decoded)
            : AppConfig.fromPythonJson(
                decoded,
                _viewport?.channelLabels ?? const [],
              );
        final eegForBinding = _loadedEeg;
        if (eegForBinding != null) {
          newCfg.bindLoadedChannels(
            eegForBinding.channelLabels,
            sampleRateHz: eegForBinding.sampleRateHz,
          );
        }

        setState(() {
          _config = newCfg;
        });
        if (_activePath != null) {
          await saveAutoConfig(_activePath!, newCfg);
        }

        final eeg = _loadedEeg;
        final v = _viewport;
        if (eeg != null && v != null) {
          _backend.clearDisplayCache();
          _setStatus('Applying loaded configuration…');
          final newEeg = await _backend.computeNightProducts(eeg, newCfg);
          final newViewport = await _backend.viewportFromEeg(
            newEeg,
            currentEpoch: v.currentEpoch,
            config: newCfg,
            existingStages: v.stages,
            existingStagesUncertain: v.stagesUncertain,
            existingConfidence: v.stagesConfidence,
            includeTimeFrequency: false,
          );
          if (mounted) {
            setState(() {
              _loadedEeg = newEeg;
              _viewport = newViewport;
              _status = 'Configuration loaded successfully';
            });
            if (_config.tfEnabled) {
              _scheduleTimeFrequencyRefresh(++_navigationSerial);
            }
          }
        } else {
          _setStatus('Configuration loaded');
        }
      } catch (e) {
        _setStatus('Error loading configuration: $e');
      }
    }
  }

  Future<void> _saveConfig() async {
    final String? outputFile = await FilePicker.saveFile(
      dialogTitle: 'Save Configuration',
      fileName: 'config.json',
      type: FileType.custom,
      allowedExtensions: ['json'],
    );

    if (outputFile != null) {
      try {
        final json = jsonEncode(_config.toPythonJson());
        await File(outputFile).writeAsString(json);
        _setStatus('Configuration saved to $outputFile');
      } catch (e) {
        _setStatus('Error saving configuration: $e');
      }
    }
  }

  // ─── Configuration ────────────────────────────────────────────────────────

  void _openConfigDialog() {
    final v = _viewport;
    if (v == null) {
      _setStatus('Load an EDF first to configure channels');
      return;
    }
    showDialog(
      context: context,
      builder: (_) => ConfigDialog(
        config: _config,
        channelLabels: v.channelLabels,
        onPreview: _previewDisplayConfig,
        onApply: (newCfg) {
          setState(() {
            _config = newCfg;
          });
          if (_activePath != null) {
            saveAutoConfig(_activePath!, newCfg);
          }
          final eeg = _loadedEeg;
          if (eeg != null) {
            _backend.clearDisplayCache();
            // Recompute with new channel config
            _setStatus('Recomputing spectrogram for new channel…');
            Future.microtask(() async {
              final newEeg = await _backend.computeNightProducts(eeg, newCfg);
              final newViewport = await _backend.viewportFromEeg(
                newEeg,
                currentEpoch: v.currentEpoch,
                config: newCfg,
                existingStages: v.stages,
                existingStagesUncertain: v.stagesUncertain,
                existingConfidence: v.stagesConfidence,
                includeTimeFrequency: false,
              );
              setState(() {
                _loadedEeg = newEeg;
                _viewport = newViewport;
                _status = 'Config applied — spectrogram channel updated';
              });
              if (_config.tfEnabled) {
                _scheduleTimeFrequencyRefresh(++_navigationSerial);
              }
            });
          }
        },
      ),
    );
  }

  void _openFilterDialog() {
    final v = _viewport;
    if (v == null) {
      _setStatus('Load an EDF first to configure filters');
      return;
    }
    showDialog(
      context: context,
      builder: (_) => FilterDialog(
        config: _config,
        channelLabels: v.channelLabels,
        onApply: (newCfg) {
          setState(() {
            _config = newCfg;
          });
          if (_activePath != null) {
            saveAutoConfig(_activePath!, newCfg);
          }
          final eeg = _loadedEeg;
          if (eeg != null) {
            _backend.clearDisplayCache();
            _setStatus('Applying filters and updating spectrogram…');
            Future.microtask(() async {
              final newEeg = await _backend.computeNightProducts(eeg, newCfg);
              final newViewport = await _backend.viewportFromEeg(
                newEeg,
                currentEpoch: v.currentEpoch,
                config: newCfg,
                existingStages: v.stages,
                existingStagesUncertain: v.stagesUncertain,
                existingConfidence: v.stagesConfidence,
                includeTimeFrequency: false,
              );
              setState(() {
                _loadedEeg = newEeg;
                _viewport = newViewport;
                _status = 'Filters applied and spectrogram updated';
              });
              if (_config.tfEnabled) {
                _scheduleTimeFrequencyRefresh(++_navigationSerial);
              }
            });
          } else {
            _previewDisplayConfig(newCfg);
            _setStatus('Filters applied');
          }
        },
      ),
    );
  }

  void _previewDisplayConfig(AppConfig newCfg) {
    final eeg = _loadedEeg;
    final v = _viewport;
    if (eeg == null || v == null) {
      setState(() => _config = newCfg);
      return;
    }
    // Clear waveform cache so filter/display changes take immediate effect.
    _backend.clearDisplayCache();
    final rebuilt = _backend
        .rebuildViewportForEpochSync(v, eeg, v.currentEpoch, config: newCfg)
        .copyWith(stages: v.stages, stagesUncertain: v.stagesUncertain);
    setState(() {
      _config = newCfg;
      _viewport = rebuilt;
      _status = 'Configuration preview applied';
    });
    if (_activePath != null) {
      saveAutoConfig(_activePath!, newCfg);
    }
    if (_config.tfEnabled) {
      _scheduleTimeFrequencyRefresh(++_navigationSerial);
    }
  }

  // ─── Platform menus ───────────────────────────────────────────────────────

  List<PlatformMenuItem> _platformMenus() {
    final appMenuItems = <PlatformMenuItem>[
      if (PlatformProvidedMenuItem.hasMenu(PlatformProvidedMenuItemType.about))
        const PlatformProvidedMenuItem(type: PlatformProvidedMenuItemType.about)
      else
        const PlatformMenuItem(label: 'About ScoringNidra'),
      if (PlatformProvidedMenuItem.hasMenu(PlatformProvidedMenuItemType.quit))
        const PlatformProvidedMenuItem(type: PlatformProvidedMenuItemType.quit),
    ];

    return [
      PlatformMenu(label: 'ScoringNidra', menus: appMenuItems),
      // ─── Data ─────────────────────────────────────────────────────────
      PlatformMenu(
        label: 'Data',
        menus: [
          PlatformMenuItem(
            label: 'Load EDF file (.edf)',
            onSelected: () => _openRecording(kind: 'edf'),
          ),
          PlatformMenuItem(
            label: 'Load EDF file (.edf) – scaled from V to µV',
            onSelected: () => _openRecording(kind: 'edfvolt'),
          ),
          PlatformMenuItem(
            label: 'Load Orbit file (.orb / .signal)',
            onSelected: () => _openRecording(kind: 'orbit'),
          ),
          PlatformMenuItem(
            label: 'Load EEGLAB structure (.mat)',
            onSelected: () => _openRecording(kind: 'mat'),
          ),
          PlatformMenuItem(
            label: 'Load Zurich data file (.r09)',
            onSelected: () => _openRecording(kind: 'r09'),
          ),
          PlatformMenuItem(
            label: 'Close Current File',
            onSelected: _closeCurrentFile,
          ),
        ],
      ),
      // ─── Scoring ──────────────────────────────────────────────────────
      PlatformMenu(
        label: 'Scoring',
        menus: [
          PlatformMenuItem(
            label: 'Import scoring… (auto-detect format)',
            onSelected: _loadScoring,
          ),
          PlatformMenuItem(
            label: 'Load Sleeptrip Events (_events.csv)',
            onSelected: _loadSleeptripEvents,
          ),
          if (!buildLite) ...[
            PlatformMenuItem(
              label: 'Run Auto-Scoring…',
              onSelected: _runAutoScoring,
            ),
            PlatformMenuItem(
              label: 'Run Batch Auto-Scoring…',
              onSelected: _runBatchAutoScoring,
            ),
          ],
          PlatformMenuItem(label: 'Save to…', onSelected: _saveScoring),
          PlatformMenuItem(
            label: 'Export Sleep Report (PDF)',
            onSelected: _exportSleepReport,
          ),
        ],
      ),
      // ─── Stages ───────────────────────────────────────────────────────
      PlatformMenu(
        label: 'Stages',
        menus: [
          PlatformMenuItem(
            label: 'None  [Delete]',
            onSelected: () => _scoreCurrentEpoch(SleepStage.unknown),
          ),
          PlatformMenuItem(
            label: 'Wake  [W]',
            onSelected: () => _scoreCurrentEpoch(SleepStage.wake),
          ),
          PlatformMenuItem(
            label: 'N1  [1]',
            onSelected: () => _scoreCurrentEpoch(SleepStage.n1),
          ),
          PlatformMenuItem(
            label: 'N2  [2]',
            onSelected: () => _scoreCurrentEpoch(SleepStage.n2),
          ),
          PlatformMenuItem(
            label: 'N3  [3]',
            onSelected: () => _scoreCurrentEpoch(SleepStage.n3),
          ),
          PlatformMenuItem(
            label: 'REM  [R]',
            onSelected: () => _scoreCurrentEpoch(SleepStage.rem),
          ),
          PlatformMenuItem(
            label: 'Inconclusive  [I]',
            onSelected: () => _scoreCurrentEpoch(SleepStage.inconclusive),
          ),
          PlatformMenuItem(
            label: 'Toggle Uncertainty [Q]',
            onSelected: _toggleUncertainty,
          ),
        ],
      ),
      // ─── Events ───────────────────────────────────────────────────────
      PlatformMenu(
        label: 'Events',
        menus: [
          PlatformMenuItem(label: 'Artefact', onSelected: () => _markEvent(0)),
          for (var i = 1; i <= 12; i++)
            PlatformMenuItem(
              label: 'Event $i',
              onSelected: () => _markEvent(i),
            ),
          PlatformMenuItem(
            label: 'Erase events in drawn selection [Backspace]',
            onSelected: _eraseEventsInSelections,
          ),
          PlatformMenuItem(
            label: 'Delete all events',
            onSelected: _deleteAllEvents,
          ),
        ],
      ),
      // ─── Utilities ────────────────────────────────────────────────────
      PlatformMenu(
        label: 'Utilities',
        menus: [
          if (!buildLite) ...[
            PlatformMenuItem(
              label: 'analyseNidra — current recording…',
              onSelected: _runAnalyseNidraCurrent,
            ),
            PlatformMenuItem(
              label: 'analyseNidra — batch from scoring files…',
              onSelected: _runAnalyseNidraBatch,
            ),
          ],
          PlatformMenuItem(
            label: 'K-Complex Detection (MT-KCD)  [Ctrl+K]',
            onSelected: _runKComplexDetection,
          ),
          PlatformMenuItem(
            label: 'Spindle Detection (MT-Spindle)  [Ctrl+Shift+S]',
            onSelected: _runSpindleDetection,
          ),
          PlatformMenuItem(
            label: 'Zoom on selected EEG  [Z]',
            onSelected: _zoomOnSelectedEeg,
          ),
        ],
      ),
      // ─── Compare ──────────────────────────────────────────────────────
      PlatformMenu(
        label: 'Compare',
        menus: [
          PlatformMenuItem(
            label: 'Import comparison scoring… (auto-detect format)',
            onSelected: _loadComparisonScoring,
          ),
          PlatformMenuItem(
            label: 'Remove comparison scoring',
            onSelected: _removeComparisonScoring,
          ),
          PlatformMenuItem(
            label: 'Show summary statistics',
            onSelected: _showComparisonStats,
          ),
        ],
      ),
      // ─── Configuration ────────────────────────────────────────────────
      PlatformMenu(
        label: 'Configuration',
        menus: [
          PlatformMenuItem(
            label: 'Open configuration window  [Ctrl+C]',
            onSelected: _openConfigDialog,
          ),
          PlatformMenuItem(
            label: 'Save configuration as .json',
            onSelected: _saveConfig,
          ),
          PlatformMenuItem(
            label: 'Load configuration from .json',
            onSelected: _loadConfig,
          ),
          PlatformMenuItem(
            label: 'Restore default configuration',
            onSelected: () {
              final eeg = _loadedEeg;
              final v = _viewport;
              if (eeg != null && v != null) {
                _backend.clearDisplayCache();
                final defaultConfig = AppConfig.defaultsForChannels(
                  eeg.channelLabels,
                  sampleRateHz: eeg.sampleRateHz,
                );
                setState(() {
                  _config = defaultConfig;
                });
                _setStatus('Restoring default configuration…');
                Future.microtask(() async {
                  final newEeg = await _backend.computeNightProducts(
                    eeg,
                    defaultConfig,
                  );
                  final newViewport = await _backend.viewportFromEeg(
                    newEeg,
                    currentEpoch: v.currentEpoch,
                    config: defaultConfig,
                    existingStages: v.stages,
                    existingStagesUncertain: v.stagesUncertain,
                    existingConfidence: v.stagesConfidence,
                    includeTimeFrequency: false,
                  );
                  if (mounted) {
                    setState(() {
                      _loadedEeg = newEeg;
                      _viewport = newViewport;
                      _status = 'Default configuration restored';
                    });
                    if (_config.tfEnabled) {
                      _scheduleTimeFrequencyRefresh(++_navigationSerial);
                    }
                  }
                });
              }
            },
          ),
        ],
      ),
      // ─── Help ─────────────────────────────────────────────────────────
      PlatformMenu(
        label: 'Help',
        menus: [
          PlatformMenuItem(
            label: 'Signal selection box  [Ctrl+H]',
            onSelected: _showSelectionHelp,
          ),
        ],
      ),
    ];
  }

  Widget _buildInAppMenuBar() {
    return Container(
      color: Colors.white,
      width: double.infinity,
      child: MenuBar(
        style: MenuStyle(
          elevation: MaterialStateProperty.all(0),
          backgroundColor: MaterialStateProperty.all(Colors.white),
        ),
        children: [
          SubmenuButton(
            menuChildren: [
              MenuItemButton(
                onPressed: () => _openRecording(kind: 'edf'),
                child: const Text('Load EDF file (.edf)'),
              ),
              MenuItemButton(
                onPressed: () => _openRecording(kind: 'edfvolt'),
                child: const Text('Load EDF file (.edf) – scaled V to µV'),
              ),
              MenuItemButton(
                onPressed: () => _openRecording(kind: 'orbit'),
                child: const Text('Load Orbit file (.orb / .signal)'),
              ),
              MenuItemButton(
                onPressed: () => _openRecording(kind: 'mat'),
                child: const Text('Load EEGLAB structure (.mat)'),
              ),
              MenuItemButton(
                onPressed: () => _openRecording(kind: 'r09'),
                child: const Text('Load Zurich data file (.r09)'),
              ),
              const Divider(height: 1),
              MenuItemButton(
                onPressed: _closeCurrentFile,
                child: const Text('Close Current File'),
              ),
            ],
            child: const Text('Data'),
          ),
          SubmenuButton(
            menuChildren: [
              MenuItemButton(
                onPressed: _loadScoring,
                child: const Text('Import scoring… (auto-detect format)'),
              ),
              MenuItemButton(
                onPressed: _loadSleeptripEvents,
                child: const Text('Load Sleeptrip Events (_events.csv)'),
              ),
              if (!buildLite) ...[
                MenuItemButton(
                  onPressed: _runAutoScoring,
                  child: const Text('Run Auto-Scoring…'),
                ),
                MenuItemButton(
                  onPressed: _runBatchAutoScoring,
                  child: const Text('Run Batch Auto-Scoring…'),
                ),
              ],
              const Divider(height: 1),
              MenuItemButton(
                onPressed: _saveScoring,
                child: const Text('Save to…'),
              ),
              MenuItemButton(
                onPressed: _exportSleepReport,
                child: const Text('Export Sleep Report (PDF)'),
              ),
            ],
            child: const Text('Scoring'),
          ),
          SubmenuButton(
            menuChildren: [
              MenuItemButton(
                onPressed: () => _scoreCurrentEpoch(SleepStage.unknown),
                child: const Text('None  [Delete]'),
              ),
              MenuItemButton(
                onPressed: () => _scoreCurrentEpoch(SleepStage.wake),
                child: const Text('Wake  [W]'),
              ),
              MenuItemButton(
                onPressed: () => _scoreCurrentEpoch(SleepStage.n1),
                child: const Text('N1  [1]'),
              ),
              MenuItemButton(
                onPressed: () => _scoreCurrentEpoch(SleepStage.n2),
                child: const Text('N2  [2]'),
              ),
              MenuItemButton(
                onPressed: () => _scoreCurrentEpoch(SleepStage.n3),
                child: const Text('N3  [3]'),
              ),
              MenuItemButton(
                onPressed: () => _scoreCurrentEpoch(SleepStage.rem),
                child: const Text('REM  [R]'),
              ),
              MenuItemButton(
                onPressed: () => _scoreCurrentEpoch(SleepStage.inconclusive),
                child: const Text('Inconclusive  [I]'),
              ),
              const Divider(height: 1),
              MenuItemButton(
                onPressed: _toggleUncertainty,
                child: const Text('Toggle Uncertainty [Q]'),
              ),
            ],
            child: const Text('Stages'),
          ),
          SubmenuButton(
            menuChildren: [
              MenuItemButton(
                onPressed: () => _markEvent(0),
                child: const Text('Artefact [A]'),
              ),
              for (var i = 1; i <= 12; i++)
                MenuItemButton(
                  onPressed: () => _markEvent(i),
                  child: Text('Event $i [F$i]'),
                ),
              const Divider(height: 1),
              MenuItemButton(
                onPressed: _eraseEventsInSelections,
                child: const Text(
                  'Erase events in drawn selection [Backspace]',
                ),
              ),
              MenuItemButton(
                onPressed: _deleteAllEvents,
                child: const Text('Delete all events'),
              ),
            ],
            child: const Text('Events'),
          ),
          SubmenuButton(
            menuChildren: [
              if (!buildLite) ...[
                MenuItemButton(
                  onPressed: _runAnalyseNidraCurrent,
                  child: const Text('analyseNidra — current recording…'),
                ),
                MenuItemButton(
                  onPressed: _runAnalyseNidraBatch,
                  child: const Text('analyseNidra — batch from scoring files…'),
                ),
                const Divider(height: 1),
              ],
              MenuItemButton(
                onPressed: _runKComplexDetection,
                child: const Text('K-Complex Detection (MT-KCD) [Ctrl+K]'),
              ),
              MenuItemButton(
                onPressed: _runSpindleDetection,
                child: const Text(
                  'Spindle Detection (MT-Spindle) [Ctrl+Shift+S]',
                ),
              ),
              MenuItemButton(
                onPressed: _zoomOnSelectedEeg,
                child: const Text('Zoom on selected EEG [Z]'),
              ),
            ],
            child: const Text('Utilities'),
          ),
          SubmenuButton(
            menuChildren: [
              MenuItemButton(
                onPressed: _loadComparisonScoring,
                child: const Text(
                  'Import comparison scoring… (auto-detect format)',
                ),
              ),
              MenuItemButton(
                onPressed: _removeComparisonScoring,
                child: const Text('Remove comparison scoring'),
              ),
              MenuItemButton(
                onPressed: _showComparisonStats,
                child: const Text('Show summary statistics'),
              ),
            ],
            child: const Text('Compare'),
          ),
          SubmenuButton(
            menuChildren: [
              MenuItemButton(
                onPressed: _openConfigDialog,
                child: const Text('Open Settings Dialog'),
              ),
              MenuItemButton(
                onPressed: _saveConfig,
                child: const Text('Save configuration as .json'),
              ),
              MenuItemButton(
                onPressed: _loadConfig,
                child: const Text('Load configuration from .json'),
              ),
              MenuItemButton(
                onPressed: () {
                  final eeg = _loadedEeg;
                  final v = _viewport;
                  if (eeg != null && v != null) {
                    _backend.clearDisplayCache();
                    final defaultConfig = AppConfig.defaultsForChannels(
                      eeg.channelLabels,
                      sampleRateHz: eeg.sampleRateHz,
                    );
                    setState(() {
                      _config = defaultConfig;
                    });
                    _setStatus('Restoring default configuration…');
                    Future.microtask(() async {
                      final newEeg = await _backend.computeNightProducts(
                        eeg,
                        defaultConfig,
                      );
                      final newViewport = await _backend.viewportFromEeg(
                        newEeg,
                        currentEpoch: v.currentEpoch,
                        config: defaultConfig,
                        existingStages: v.stages,
                        existingStagesUncertain: v.stagesUncertain,
                        existingConfidence: v.stagesConfidence,
                        includeTimeFrequency: false,
                      );
                      if (mounted) {
                        setState(() {
                          _loadedEeg = newEeg;
                          _viewport = newViewport;
                          _status = 'Default configuration restored';
                        });
                        if (_config.tfEnabled) {
                          _scheduleTimeFrequencyRefresh(++_navigationSerial);
                        }
                      }
                    });
                  }
                },
                child: const Text('Restore default configuration'),
              ),
            ],
            child: const Text('Configuration'),
          ),
          SubmenuButton(
            menuChildren: [
              MenuItemButton(
                onPressed: _showSelectionHelp,
                child: const Text('Signal selection box  [Ctrl+H]'),
              ),
            ],
            child: const Text('Help'),
          ),
        ],
      ),
    );
  }

  Widget _buildBatchProcessingTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Left Column: Batch Auto-Scoring
          Expanded(
            child: Card(
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
                side: const BorderSide(color: Color(0xFFD0D0D0)),
              ),
              color: Colors.white,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.psychology, color: Colors.purple),
                        SizedBox(width: 8),
                        Text(
                          'Batch Automated Sleep Scoring',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                    const Divider(height: 24),
                    const Text(
                      'Selected Recording Files (EDF/ORB/SIGNAL):',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      height: 150,
                      decoration: BoxDecoration(
                        border: Border.all(color: const Color(0xFFD0D0D0)),
                        borderRadius: BorderRadius.circular(4),
                        color: const Color(0xFFF9F9F9),
                      ),
                      child: _batchStagingFiles.isEmpty
                          ? const Center(child: Text('No files selected'))
                          : ListView.builder(
                              itemCount: _batchStagingFiles.length,
                              itemBuilder: (context, index) {
                                final f = _batchStagingFiles[index];
                                return ListTile(
                                  dense: true,
                                  title: Text(_basename(f)),
                                  subtitle: Text(f),
                                  trailing: IconButton(
                                    icon: const Icon(Icons.delete, size: 16, color: Colors.red),
                                    onPressed: () {
                                      setState(() {
                                        _batchStagingFiles.removeAt(index);
                                      });
                                    },
                                  ),
                                );
                              },
                            ),
                    ),
                    const SizedBox(height: 8),
                    ElevatedButton.icon(
                      icon: const Icon(Icons.add, size: 16),
                      label: const Text('Add Recording Files…'),
                      onPressed: () async {
                        final result = await FilePicker.pickFiles(
                          dialogTitle: 'Select EEG files for batch auto-scoring',
                          type: FileType.custom,
                          allowedExtensions: ['edf', 'orb', 'signal'],
                          allowMultiple: true,
                        );
                        if (result != null) {
                          setState(() {
                            for (final file in result.files) {
                              if (file.path != null && !_batchStagingFiles.contains(file.path!)) {
                                _batchStagingFiles.add(file.path!);
                              }
                            }
                          });
                        }
                      },
                    ),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<String>(
                      value: _batchStagingAlgorithm,
                      decoration: const InputDecoration(
                        labelText: 'Base Scorer Algorithm',
                        isDense: true,
                        border: OutlineInputBorder(),
                      ),
                      items: const [
                        DropdownMenuItem(value: 'yasa', child: Text('YASA LightGBM Consensus')),
                        DropdownMenuItem(value: 'usleep', child: Text('Offline U-Sleep Consensus')),
                        DropdownMenuItem(value: 'luna', child: Text('Luna POPS Stager')),
                        DropdownMenuItem(value: 'gssc', child: Text('Greifswald Classifier (GSSC)')),
                      ],
                      onChanged: (v) {
                        if (v != null) {
                          setState(() => _batchStagingAlgorithm = v);
                        }
                      },
                    ),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<String>(
                      value: _batchStagingCorrection,
                      decoration: const InputDecoration(
                        labelText: 'Sequence Correction',
                        isDense: true,
                        border: OutlineInputBorder(),
                      ),
                      items: const [
                        DropdownMenuItem(value: 'none', child: Text('None (Raw consensus predictions)')),
                        DropdownMenuItem(value: 'sleepgpt', child: Text('SleepGPT Language Model')),
                      ],
                      onChanged: (v) {
                        if (v != null) {
                          setState(() => _batchStagingCorrection = v);
                        }
                      },
                    ),
                    const SizedBox(height: 16),
                    const Text('Channel Mapping Configuration:', style: TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    TextFormField(
                      decoration: const InputDecoration(
                        labelText: 'EEG Channels (comma-separated)',
                        hintText: 'e.g. AF7,AF8 or F3,F4',
                        isDense: true,
                        border: OutlineInputBorder(),
                      ),
                      initialValue: _batchStagingEeg.join(','),
                      onChanged: (v) {
                        setState(() {
                          _batchStagingEeg.clear();
                          _batchStagingEeg.addAll(v.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty));
                        });
                      },
                    ),
                    const SizedBox(height: 8),
                    TextFormField(
                      decoration: const InputDecoration(
                        labelText: 'Reference Channels (comma-separated)',
                        hintText: 'e.g. PPG or M1,M2',
                        isDense: true,
                        border: OutlineInputBorder(),
                      ),
                      initialValue: _batchStagingRef.join(','),
                      onChanged: (v) {
                        setState(() {
                          _batchStagingRef.clear();
                          _batchStagingRef.addAll(v.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty));
                        });
                      },
                    ),
                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      height: 40,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.purple,
                          foregroundColor: Colors.white,
                        ),
                        onPressed: _batchStagingFiles.isEmpty
                            ? null
                            : () {
                                final settings = {
                                  'algorithm': _batchStagingAlgorithm,
                                  'sequence_correction': _batchStagingCorrection,
                                  'sleepgpt_alpha': 0.1,
                                  'sleepgpt_ngram': 30,
                                  'eeg': _batchStagingEeg,
                                  'ref': _batchStagingRef,
                                  'eog': _batchStagingEog,
                                  'emg': _batchStagingEmg,
                                };
                                _executeBatchAutoScoring(_batchStagingFiles, settings);
                              },
                        child: const Text('Run Batch Auto-Scoring', style: TextStyle(fontWeight: FontWeight.bold)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 16),
          // Right Column: Batch AnalyseNidra
          Expanded(
            child: Card(
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
                side: const BorderSide(color: Color(0xFFD0D0D0)),
              ),
              color: Colors.white,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.analytics, color: Colors.blue),
                        SizedBox(width: 8),
                        Text(
                          'Batch AnalyseNidra (Region analysis)',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                    const Divider(height: 24),
                    const Text(
                      'File Mappings (EEG file <-> Scoring file):',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      height: 150,
                      decoration: BoxDecoration(
                        border: Border.all(color: const Color(0xFFD0D0D0)),
                        borderRadius: BorderRadius.circular(4),
                        color: const Color(0xFFF9F9F9),
                      ),
                      child: _batchAnalysePairs.isEmpty
                          ? const Center(child: Text('No file pairs mapped'))
                          : ListView.builder(
                              itemCount: _batchAnalysePairs.length,
                              itemBuilder: (context, index) {
                                final pair = _batchAnalysePairs[index];
                                final eeg = pair['eegPath'] ?? '';
                                final scoring = pair['scoringPath'] ?? '';
                                return ListTile(
                                  dense: true,
                                  title: Text('EEG: ${_basename(eeg)}'),
                                  subtitle: Text('Scoring: ${_basename(scoring)}'),
                                  trailing: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      IconButton(
                                        icon: const Icon(Icons.edit, size: 16, color: Colors.grey),
                                        tooltip: 'Select scoring file',
                                        onPressed: () async {
                                          final result = await FilePicker.pickFiles(
                                            dialogTitle: 'Select scoring JSON file',
                                            type: FileType.custom,
                                            allowedExtensions: ['json'],
                                          );
                                          if (result != null && result.files.single.path != null) {
                                            setState(() {
                                              pair['scoringPath'] = result.files.single.path!;
                                            });
                                          }
                                        },
                                      ),
                                      IconButton(
                                        icon: const Icon(Icons.delete, size: 16, color: Colors.red),
                                        onPressed: () {
                                          setState(() {
                                            _batchAnalysePairs.removeAt(index);
                                          });
                                        },
                                      ),
                                    ],
                                  ),
                                );
                              },
                            ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        ElevatedButton.icon(
                          icon: const Icon(Icons.add_circle_outline, size: 16),
                          label: const Text('Add EEG File…'),
                          onPressed: () async {
                            final result = await FilePicker.pickFiles(
                              dialogTitle: 'Select EEG file (EDF/ORB/SIGNAL)',
                              type: FileType.custom,
                              allowedExtensions: ['edf', 'orb', 'signal'],
                            );
                            if (result != null && result.files.single.path != null) {
                              setState(() {
                                _batchAnalysePairs.add({
                                  'eegPath': result.files.single.path!,
                                  'scoringPath': '',
                                });
                              });
                            }
                          },
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton.icon(
                          icon: const Icon(Icons.settings_suggest, size: 16),
                          label: const Text('Auto-pair Directory…'),
                          onPressed: () async {
                            final dir = await FilePicker.getDirectoryPath(
                              dialogTitle: 'Select directory to auto-pair files',
                            );
                            if (dir != null) {
                              final directory = Directory(dir);
                              if (directory.existsSync()) {
                                final files = directory.listSync();
                                final List<String> eegs = [];
                                final List<String> scorings = [];
                                for (final file in files) {
                                  if (file is File) {
                                    final ext = file.path.split('.').last.toLowerCase();
                                    if (ext == 'edf' || ext == 'orb' || ext == 'signal') {
                                      eegs.add(file.path);
                                    } else if (ext == 'json') {
                                      scorings.add(file.path);
                                    }
                                  }
                                }

                                setState(() {
                                  for (final eeg in eegs) {
                                    final eegName = _basename(eeg).split('.').first;
                                    String matchedScoring = '';
                                    for (final scoring in scorings) {
                                      final scName = _basename(scoring).split('.').first;
                                      if (scName.contains(eegName) || eegName.contains(scName)) {
                                        matchedScoring = scoring;
                                        break;
                                      }
                                    }
                                    _batchAnalysePairs.add({
                                      'eegPath': eeg,
                                      'scoringPath': matchedScoring,
                                    });
                                  }
                                });
                              }
                            }
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _batchAnalyseEegController,
                      decoration: const InputDecoration(
                        labelText: 'EEG Channels for analysis (comma-separated)',
                        hintText: 'e.g. AF7,AF8',
                        isDense: true,
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _batchAnalyseRefController,
                      decoration: const InputDecoration(
                        labelText: 'Reference Channels for analysis (comma-separated)',
                        hintText: 'e.g. PPG',
                        isDense: true,
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      height: 40,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blue,
                          foregroundColor: Colors.white,
                        ),
                        onPressed: _batchAnalysePairs.isEmpty
                            ? null
                            : () {
                                final validPairs = _batchAnalysePairs
                                    .where((p) => (p['eegPath'] ?? '').isNotEmpty && (p['scoringPath'] ?? '').isNotEmpty)
                                    .toList();
                                if (validPairs.isEmpty) {
                                  _setStatus('Error: Mapped pairs must have both EEG and Scoring files.');
                                  return;
                                }

                                final jobs = validPairs.map((pair) {
                                  return _AnalyseNidraJob(
                                    edfPath: pair['eegPath']!,
                                    scoringPath: pair['scoringPath']!,
                                    mappedScoringPath: pair['scoringPath']!,
                                  );
                                }).toList();

                                final chans = _batchAnalyseEegController.text
                                    .split(',')
                                    .map((e) => e.trim())
                                    .where((e) => e.isNotEmpty)
                                    .toList();
                                final refs = _batchAnalyseRefController.text
                                    .split(',')
                                    .map((e) => e.trim())
                                    .where((e) => e.isNotEmpty)
                                    .toList();

                                _runAnalyseNidraJobs(jobs, chans, refs);
                              },
                        child: const Text('Run Batch AnalyseNidra', style: TextStyle(fontWeight: FontWeight.bold)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ─── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final viewport = _viewport;

    return PlatformMenuBar(
      menus: _platformMenus(),
      child: Shortcuts(
        shortcuts: _shortcuts,
        child: Actions(
          actions: {
            _ScoreIntent: CallbackAction<_ScoreIntent>(
              onInvoke: (i) => _scoreCurrentEpoch(i.stage),
            ),
            _NextEpochIntent: CallbackAction<_NextEpochIntent>(
              onInvoke: (_) => _nextEpoch(),
            ),
            _PreviousEpochIntent: CallbackAction<_PreviousEpochIntent>(
              onInvoke: (_) => _previousEpoch(),
            ),
            _EventIntent: CallbackAction<_EventIntent>(
              onInvoke: (i) => _markEvent(i.digit),
            ),
            _EraseEventsIntent: CallbackAction<_EraseEventsIntent>(
              onInvoke: (_) => _eraseEventsInSelections(),
            ),
            _ZoomSelectionIntent: CallbackAction<_ZoomSelectionIntent>(
              onInvoke: (_) => _zoomOnSelectedEeg(),
            ),
            _ToggleUncertaintyIntent: CallbackAction<_ToggleUncertaintyIntent>(
              onInvoke: (_) => _toggleUncertainty(),
            ),
            _KComplexDetectionIntent: CallbackAction<_KComplexDetectionIntent>(
              onInvoke: (_) => _runKComplexDetection(),
            ),
            _SpindleDetectionIntent: CallbackAction<_SpindleDetectionIntent>(
              onInvoke: (_) => _runSpindleDetection(),
            ),
            _ConfigIntent: CallbackAction<_ConfigIntent>(
              onInvoke: (_) => _openConfigDialog(),
            ),
            _FilterIntent: CallbackAction<_FilterIntent>(
              onInvoke: (_) => _openFilterDialog(),
            ),
          },
          child: Focus(
            focusNode: _viewerFocusNode,
            autofocus: true,
            child: DefaultTabController(
              length: 2,
              child: Scaffold(
                backgroundColor: const Color(0xFFEDEDED),
                appBar: PreferredSize(
                  preferredSize: const Size.fromHeight(36),
                  child: Container(
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      border: Border(bottom: BorderSide(color: Color(0xFFD0D0D0))),
                    ),
                    child: const TabBar(
                      labelColor: Colors.black,
                      unselectedLabelColor: Colors.grey,
                      indicatorColor: Colors.blue,
                      labelStyle: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                      unselectedLabelStyle: TextStyle(fontSize: 13),
                      tabs: [
                        Tab(text: 'Interactive Scoring'),
                        Tab(text: 'Batch Processing'),
                      ],
                    ),
                  ),
                ),
                body: TabBarView(
                  physics: const NeverScrollableScrollPhysics(),
                  children: [
                    Column(
                      children: [
                        if (!Platform.isMacOS) _buildInAppMenuBar(),
                        _Toolbar(
                          viewport: viewport,
                          onJump: _jumpToEpoch,
                          onPrevious: _previousEpoch,
                          onNext: _nextEpoch,
                          onUnscored: _jumpNextUnscored,
                          onUncertain: _jumpNextUncertain,
                          onTransition: _jumpNextTransition,
                          onHuman: _jumpNextHuman,
                          onEvent: _jumpNextEvent,
                          onDisagreement: _jumpNextDisagreement,
                          hasComparison: _comparisonStages != null,
                          onConfig: _openConfigDialog,
                          swaSlider: _swaSlider,
                          onSwaSlider: (v) => setState(() => _swaSlider = v),
                          onToggleUncertainty: _toggleUncertainty,
                          tfEnabled: _config.tfEnabled,
                          onToggleWavelet: _toggleWavelet,
                        ),
                        Expanded(
                          child: viewport == null
                              ? const Center(child: CircularProgressIndicator())
                              : _ScoringHeroSurface(
                                  viewport: viewport,
                                  onJump: (epoch) => _jumpToEpoch(epoch),
                                  swaSlider: _swaSlider,
                                  onSwaSlider: (v) => setState(() => _swaSlider = v),
                                  onSelectionEnd: _updateSelection,
                                  comparisonStages: _comparisonStages,
                                  tfEnabled: _config.tfEnabled,
                                  onResizeFlex: _updateFlexValues,
                                ),
                        ),
                        _StatusBar(
                          status: _status,
                          activePath: _activePath,
                          viewport: viewport,
                          comparisonStages: _comparisonStages,
                        ),
                      ],
                    ),
                    _buildBatchProcessingTab(),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Toolbar
// ─────────────────────────────────────────────────────────────────────────────

class _Toolbar extends StatefulWidget {
  const _Toolbar({
    required this.viewport,
    required this.onJump,
    required this.onPrevious,
    required this.onNext,
    required this.onUnscored,
    required this.onUncertain,
    required this.onTransition,
    required this.onHuman,
    required this.onEvent,
    required this.onDisagreement,
    required this.hasComparison,
    required this.onConfig,
    required this.swaSlider,
    required this.onSwaSlider,
    required this.onToggleUncertainty,
    required this.tfEnabled,
    required this.onToggleWavelet,
  });

  final EegViewport? viewport;
  final void Function(int, [bool]) onJump;
  final VoidCallback onPrevious;
  final VoidCallback onNext;
  final VoidCallback onUnscored;
  final VoidCallback onUncertain;
  final VoidCallback onTransition;
  final VoidCallback onHuman;
  final VoidCallback onEvent;
  final VoidCallback onDisagreement;
  final bool hasComparison;
  final VoidCallback onConfig;
  final int swaSlider;
  final ValueChanged<int> onSwaSlider;
  final VoidCallback onToggleUncertainty;
  final bool tfEnabled;
  final VoidCallback onToggleWavelet;

  @override
  State<_Toolbar> createState() => _ToolbarState();
}

class _ToolbarState extends State<_Toolbar> {
  late final TextEditingController _ctrl;
  final FocusNode _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    final epoch = widget.viewport?.currentEpoch ?? 0;
    _ctrl = TextEditingController(text: '${epoch + 1}');
    _focusNode.addListener(_handleFocusChange);
  }

  void _handleFocusChange() {
    if (!_focusNode.hasFocus) {
      final val = int.tryParse(_ctrl.text);
      if (val != null && widget.viewport != null) {
        final clamped = val.clamp(1, widget.viewport!.epochCount);
        widget.onJump(clamped, true);
      } else {
        final epoch = widget.viewport?.currentEpoch ?? 0;
        _ctrl.text = '${epoch + 1}';
      }
    }
  }

  @override
  void didUpdateWidget(covariant _Toolbar old) {
    super.didUpdateWidget(old);
    final epoch = widget.viewport?.currentEpoch ?? 0;
    if (!_focusNode.hasFocus) {
      _ctrl.text = '${epoch + 1}';
    }
  }

  @override
  void dispose() {
    _focusNode.removeListener(_handleFocusChange);
    _ctrl.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.viewport != null;
    return Material(
      color: const Color(0xFFF4F4F4),
      elevation: 1,
      child: SizedBox(
        height: 36,
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              const SizedBox(width: 8),
              const Text('Jump to epoch:', style: TextStyle(fontSize: 14)),
              const SizedBox(width: 6),
              SizedBox(
                width: 56,
                height: 24,
                child: Shortcuts(
                  shortcuts: const <ShortcutActivator, Intent>{
                    SingleActivator(LogicalKeyboardKey.keyW): DoNothingIntent(),
                    SingleActivator(LogicalKeyboardKey.digit1):
                        DoNothingIntent(),
                    SingleActivator(LogicalKeyboardKey.digit2):
                        DoNothingIntent(),
                    SingleActivator(LogicalKeyboardKey.digit3):
                        DoNothingIntent(),
                    SingleActivator(LogicalKeyboardKey.keyR): DoNothingIntent(),
                    SingleActivator(LogicalKeyboardKey.keyI): DoNothingIntent(),
                    SingleActivator(LogicalKeyboardKey.delete):
                        DoNothingIntent(),
                    SingleActivator(LogicalKeyboardKey.keyA): DoNothingIntent(),
                    SingleActivator(LogicalKeyboardKey.f1): DoNothingIntent(),
                    SingleActivator(LogicalKeyboardKey.f2): DoNothingIntent(),
                    SingleActivator(LogicalKeyboardKey.f3): DoNothingIntent(),
                    SingleActivator(LogicalKeyboardKey.f4): DoNothingIntent(),
                    SingleActivator(LogicalKeyboardKey.f5): DoNothingIntent(),
                    SingleActivator(LogicalKeyboardKey.f6): DoNothingIntent(),
                    SingleActivator(LogicalKeyboardKey.f7): DoNothingIntent(),
                    SingleActivator(LogicalKeyboardKey.f8): DoNothingIntent(),
                    SingleActivator(LogicalKeyboardKey.f9): DoNothingIntent(),
                    SingleActivator(LogicalKeyboardKey.f10): DoNothingIntent(),
                    SingleActivator(LogicalKeyboardKey.f11): DoNothingIntent(),
                    SingleActivator(LogicalKeyboardKey.f12): DoNothingIntent(),
                    SingleActivator(LogicalKeyboardKey.backspace):
                        DoNothingIntent(),
                    SingleActivator(LogicalKeyboardKey.keyZ): DoNothingIntent(),
                    SingleActivator(LogicalKeyboardKey.keyK, control: true):
                        DoNothingIntent(),
                    SingleActivator(
                      LogicalKeyboardKey.keyS,
                      control: true,
                      shift: true,
                    ): DoNothingIntent(),
                    SingleActivator(LogicalKeyboardKey.keyC, control: true):
                        DoNothingIntent(),
                    SingleActivator(LogicalKeyboardKey.keyF, control: true):
                        DoNothingIntent(),
                    SingleActivator(LogicalKeyboardKey.arrowRight):
                        DoNothingIntent(),
                    SingleActivator(LogicalKeyboardKey.arrowLeft):
                        DoNothingIntent(),
                    SingleActivator(LogicalKeyboardKey.keyQ): DoNothingIntent(),
                  },
                  child: TextField(
                    controller: _ctrl,
                    focusNode: _focusNode,
                    enabled: enabled,
                    keyboardType: TextInputType.number,
                    textAlign: TextAlign.center,
                    decoration: const InputDecoration(
                      isDense: true,
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 4,
                      ),
                    ),
                    style: const TextStyle(fontSize: 12),
                    onTapOutside: (_) => _focusNode.unfocus(),
                    onSubmitted: (_) => _focusNode.unfocus(),
                    onChanged: (text) {
                      final val = int.tryParse(text);
                      if (val != null && widget.viewport != null) {
                        final clamped = val.clamp(
                          1,
                          widget.viewport!.epochCount,
                        );
                        widget.onJump(clamped, false);
                      }
                    },
                  ),
                ),
              ),
              if (widget.viewport != null)
                Padding(
                  padding: const EdgeInsets.only(left: 3),
                  child: Text(
                    '/ ${widget.viewport!.epochCount}',
                    style: const TextStyle(fontSize: 11, color: Colors.black54),
                  ),
                ),
              const SizedBox(width: 8),
              _ToolButton(
                label: '◀',
                enabled: enabled,
                onPressed: widget.onPrevious,
              ),
              _ToolButton(
                label: '▶',
                enabled: enabled,
                onPressed: widget.onNext,
              ),
              const SizedBox(width: 8),
              const _Divider(),
              _ToolButton(
                label: 'unscored',
                tooltip: 'Jump to next unscored epoch',
                enabled: enabled,
                onPressed: widget.onUnscored,
              ),
              _ToolButton(
                label: 'uncertain',
                tooltip: 'Jump to next inconclusive epoch',
                enabled: enabled,
                onPressed: widget.onUncertain,
              ),
              _ToolButton(
                label: 'transition',
                tooltip: 'Jump to next stage transition',
                enabled: enabled,
                onPressed: widget.onTransition,
              ),
              _ToolButton(
                label: 'event',
                tooltip: 'Jump to next epoch with events',
                enabled: enabled,
                onPressed: widget.onEvent,
              ),
              _ToolButton(
                label: 'human',
                tooltip: 'Jump to next human-scored epoch',
                enabled: enabled,
                onPressed: widget.onHuman,
              ),
              _ToolButton(
                label: 'disagreement',
                tooltip: widget.hasComparison
                    ? 'Jump to next scoring disagreement'
                    : 'Compare scoring not loaded',
                enabled: enabled && widget.hasComparison,
                onPressed: widget.onDisagreement,
              ),
              const SizedBox(width: 8),
              const _Divider(),
              _ToolButton(
                label: 'Toggle uncertain [Q]',
                tooltip: 'Toggle uncertainty for current epoch',
                enabled: enabled,
                onPressed: widget.onToggleUncertainty,
              ),
              _ToolButton(
                label: 'config',
                tooltip: 'Open channel and display configuration',
                enabled: enabled,
                onPressed: widget.onConfig,
              ),
              _ToolButton(
                label: widget.tfEnabled ? 'wavelet [ON]' : 'wavelet [OFF]',
                tooltip: 'Toggle wavelet time-frequency panel visibility',
                enabled: enabled,
                onPressed: widget.onToggleWavelet,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Main scoring surface
// ─────────────────────────────────────────────────────────────────────────────

class _ScoringHeroSurface extends StatefulWidget {
  const _ScoringHeroSurface({
    required this.viewport,
    required this.onJump,
    required this.swaSlider,
    required this.onSwaSlider,
    required this.onSelectionEnd,
    required this.tfEnabled,
    required this.onResizeFlex,
    this.comparisonStages,
  });

  final EegViewport viewport;
  final ValueChanged<int> onJump;
  final int swaSlider;
  final ValueChanged<int> onSwaSlider;
  final void Function(
    double? startSec,
    double? endSec,
    int? channel,
    double? startUv,
    double? endUv,
  )
  onSelectionEnd;
  final List<SleepStage>? comparisonStages;
  final bool tfEnabled;
  final void Function(int spectrogramFlex, int hypnogramFlex, int periodogramFlex) onResizeFlex;

  @override
  State<_ScoringHeroSurface> createState() => _ScoringHeroSurfaceState();
}

class _ScoringHeroSurfaceState extends State<_ScoringHeroSurface> {
  double? _dragStartSec;
  double? _dragEndSec;
  int? _dragChannel;
  double? _dragStartUv;
  double? _dragEndUv;

  void _handlePanStart(DragStartDetails details, BoxConstraints constraints) {
    final n = widget.viewport.channelCount;
    if (n == 0) return;
    final drawWidth = (constraints.maxWidth - _plotLeftPadding).clamp(
      1.0,
      double.infinity,
    );
    final fx = ((details.localPosition.dx - _plotLeftPadding) / drawWidth)
        .clamp(0.0, 1.0);
    final sec =
        widget.viewport.visibleStartSeconds +
        fx * widget.viewport.visibleDurationSeconds;

    final ch = (details.localPosition.dy / constraints.maxHeight * n)
        .floor()
        .clamp(0, n - 1);
    final baselineFraction = (ch + 0.5) / n;
    final yFrac = details.localPosition.dy / constraints.maxHeight;
    final normalizedVal = (baselineFraction - yFrac) * n / 0.42;
    final uv = normalizedVal * widget.viewport.amplitudeRangeUv;

    setState(() {
      _dragStartSec = sec;
      _dragEndSec = sec;
      _dragChannel = ch;
      _dragStartUv = uv;
      _dragEndUv = uv;
    });
  }

  void _handlePanUpdate(DragUpdateDetails details, BoxConstraints constraints) {
    if (_dragStartSec == null || _dragChannel == null) return;
    final drawWidth = (constraints.maxWidth - _plotLeftPadding).clamp(
      1.0,
      double.infinity,
    );
    final fx = ((details.localPosition.dx - _plotLeftPadding) / drawWidth)
        .clamp(0.0, 1.0);
    final sec =
        widget.viewport.visibleStartSeconds +
        fx * widget.viewport.visibleDurationSeconds;

    final n = widget.viewport.channelCount;
    final baselineFraction = (_dragChannel! + 0.5) / n;
    final yFrac = details.localPosition.dy / constraints.maxHeight;
    final normalizedVal = (baselineFraction - yFrac) * n / 0.42;
    final uv = normalizedVal * widget.viewport.amplitudeRangeUv;

    setState(() {
      _dragEndSec = sec;
      _dragEndUv = uv;
    });
  }

  void _handlePanEnd(DragEndDetails details) {
    widget.onSelectionEnd(
      _dragStartSec,
      _dragEndSec,
      _dragChannel,
      _dragStartUv,
      _dragEndUv,
    );
    setState(() {
      _dragStartSec = null;
      _dragEndSec = null;
      _dragChannel = null;
      _dragStartUv = null;
      _dragEndUv = null;
    });
  }

  void _handlePanCancel() {
    widget.onSelectionEnd(null, null, null, null, null);
    setState(() {
      _dragStartSec = null;
      _dragEndSec = null;
      _dragChannel = null;
      _dragStartUv = null;
      _dragEndUv = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final zoomOption = widget.viewport.hypnogramZoom;
    final epochCount = widget.viewport.epochCount;
    final currentEpoch = widget.viewport.currentEpoch;

    int startEpoch = 0;
    int endEpoch = epochCount;

    if (zoomOption != 'Full Night') {
      int visibleEpochs = 100;
      if (zoomOption.contains('200')) {
        visibleEpochs = 200;
      } else if (zoomOption.contains('400')) {
        visibleEpochs = 400;
      }

      if (epochCount > visibleEpochs) {
        startEpoch = currentEpoch - (visibleEpochs ~/ 2);
        if (startEpoch < 0) {
          startEpoch = 0;
        }
        endEpoch = startEpoch + visibleEpochs;
        if (endEpoch > epochCount) {
          endEpoch = epochCount;
          startEpoch = (endEpoch - visibleEpochs).clamp(0, epochCount);
        }
      }
    }

    return ColoredBox(
      color: Colors.white,
      child: Column(
        children: [
          // Top strip: spectrogram | hypnogram | SWA slider | power spectrum
          LayoutBuilder(
            builder: (context, constraints) {
              final totalWidth = constraints.maxWidth;
              final showSwaPlot = widget.viewport.showSwaPlot;
              final swaWidth = showSwaPlot ? 42.0 : 0.0;
              final dividerWidth = 8.0;
              final netWidth = totalWidth - swaWidth - (dividerWidth * 2);

              final specFlex = widget.viewport.spectrogramFlex;
              final hypFlex = widget.viewport.hypnogramFlex;
              final perFlex = widget.viewport.periodogramFlex;
              final totalFlex = specFlex + hypFlex + perFlex;

              final flexPerPixel = totalFlex / netWidth;

              return SizedBox(
                height: 158,
                child: Row(
                  children: [
                    Expanded(
                      flex: specFlex,
                      child: _ClickablePainterPanel(
                        painter: SpectrogramPainter(widget.viewport),
                        onTapFraction: (fx) {
                          final epoch = (fx * widget.viewport.epochCount).floor();
                          widget.onJump(epoch + 1);
                        },
                      ),
                    ),
                    GestureDetector(
                      behavior: HitTestBehavior.translucent,
                      onHorizontalDragUpdate: (dragDetails) {
                        final dx = dragDetails.delta.dx;
                        final deltaFlex = (dx * flexPerPixel).round();
                        if (deltaFlex != 0) {
                          final newSpec = (specFlex + deltaFlex).clamp(5, totalFlex - 10);
                          final newHyp = (hypFlex - deltaFlex).clamp(5, totalFlex - 10);
                          if (newSpec + newHyp + perFlex == totalFlex) {
                            widget.onResizeFlex(newSpec, newHyp, perFlex);
                          }
                        }
                      },
                      child: MouseRegion(
                        cursor: SystemMouseCursors.resizeLeftRight,
                        child: SizedBox(
                          width: dividerWidth,
                          child: const Center(
                            child: VerticalDivider(
                              width: 1,
                              thickness: 1,
                              color: Color(0xFFD0D0D0),
                            ),
                          ),
                        ),
                      ),
                    ),
                    Expanded(
                      flex: hypFlex,
                      child: _ClickablePainterPanel(
                        painter: HypnogramPainter(
                          widget.viewport,
                          swaKernelSize: 101 - widget.swaSlider,
                          comparisonStages: widget.comparisonStages,
                          startEpoch: startEpoch,
                          endEpoch: endEpoch,
                        ),
                        onTapFraction: (fx) {
                          final visibleCount = endEpoch - startEpoch;
                          final epoch = startEpoch + (fx * visibleCount).floor();
                          widget.onJump(epoch + 1);
                        },
                      ),
                    ),
                    if (showSwaPlot) ...[
                      SizedBox(
                        width: 42,
                        child: _HypnogramSlider(
                          value: widget.swaSlider,
                          onChanged: widget.onSwaSlider,
                        ),
                      ),
                    ],
                    GestureDetector(
                      behavior: HitTestBehavior.translucent,
                      onHorizontalDragUpdate: (dragDetails) {
                        final dx = dragDetails.delta.dx;
                        final deltaFlex = (dx * flexPerPixel).round();
                        if (deltaFlex != 0) {
                          final newHyp = (hypFlex + deltaFlex).clamp(5, totalFlex - 10);
                          final newPer = (perFlex - deltaFlex).clamp(5, totalFlex - 10);
                          if (specFlex + newHyp + newPer == totalFlex) {
                            widget.onResizeFlex(specFlex, newHyp, newPer);
                          }
                        }
                      },
                      child: MouseRegion(
                        cursor: SystemMouseCursors.resizeLeftRight,
                        child: SizedBox(
                          width: dividerWidth,
                          child: const Center(
                            child: VerticalDivider(
                              width: 1,
                              thickness: 1,
                              color: Color(0xFFD0D0D0),
                            ),
                          ),
                        ),
                      ),
                    ),
                    Expanded(
                      flex: perFlex,
                      child: _Panel(
                        painter: RectanglePowerPainter(widget.viewport),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
          // Middle: EEG signal (largest panel)
          Expanded(
            flex: 74,
            child: LayoutBuilder(
              builder: (context, constraints) {
                return GestureDetector(
                  onPanStart: (d) => _handlePanStart(d, constraints),
                  onPanUpdate: (d) => _handlePanUpdate(d, constraints),
                  onPanEnd: _handlePanEnd,
                  onPanCancel: _handlePanCancel,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      _Panel(
                        painter: TimelinePainter(widget.viewport),
                        padding: EdgeInsets.zero,
                      ),
                      IgnorePointer(
                        child: CustomPaint(
                          painter: SelectionOverlayPainter(
                            widget.viewport,
                            activeDragStartSec: _dragStartSec,
                            activeDragEndSec: _dragEndSec,
                            activeDragChannel: _dragChannel,
                            activeDragStartUv: _dragStartUv,
                            activeDragEndUv: _dragEndUv,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
          // Bottom: Time-Frequency panel
          if (widget.tfEnabled) ...[
            Expanded(
              flex: 16,
              child: _Panel(painter: TimeFrequencyPainter(widget.viewport)),
            ),
          ],
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Status bar
// ─────────────────────────────────────────────────────────────────────────────

class _StatusBar extends StatelessWidget {
  const _StatusBar({
    required this.status,
    required this.activePath,
    required this.viewport,
    this.comparisonStages,
  });

  final String status;
  final String? activePath;
  final EegViewport? viewport;
  final List<SleepStage>? comparisonStages;

  @override
  Widget build(BuildContext context) {
    final vp = viewport;
    Widget? rightWidget;
    if (vp != null && activePath != null) {
      final currentIdx = vp.currentEpoch;
      final currentStage = vp.currentStage;
      final isUncertain =
          currentIdx < vp.stagesUncertain.length &&
          vp.stagesUncertain[currentIdx];
      final uncertainStr = isUncertain ? ' (Uncertain)' : '';

      String comparisonStr = '';
      bool isInconsistent = false;
      final cmpStages = comparisonStages;
      if (cmpStages != null && currentIdx < cmpStages.length) {
        final cmpStage = cmpStages[currentIdx];
        comparisonStr = '  |  Comparison: ${cmpStage.label}';
        if (currentStage != SleepStage.unknown &&
            cmpStage != SleepStage.unknown &&
            currentStage != cmpStage) {
          isInconsistent = true;
        }
      }

      double totalSelectionLength = 0.0;
      for (final sel in vp.eventSelections) {
        totalSelectionLength += sel.durationSeconds;
      }
      if (vp.selectionStartSec != null && vp.selectionEndSec != null) {
        totalSelectionLength += (vp.selectionEndSec! - vp.selectionStartSec!)
            .abs();
      }
      final selectionStr = totalSelectionLength > 0
          ? '  |  Total Length: ${totalSelectionLength.toStringAsFixed(2)} s'
          : '';

      // Model confidence display
      String confidenceStr = '';
      if (currentIdx < vp.stagesConfidence.length) {
        final conf = vp.stagesConfidence[currentIdx];
        if (conf != null) {
          confidenceStr =
              '  |  Confidence: ${(conf * 100).toStringAsFixed(1)}%';
        }
      }

      rightWidget = Text.rich(
        TextSpan(
          style: const TextStyle(fontSize: 12, color: Colors.black87),
          children: [
            if (isInconsistent)
              const TextSpan(
                text: '[INCONSISTENT]  ',
                style: TextStyle(
                  color: Colors.red,
                  fontWeight: FontWeight.bold,
                ),
              ),
            TextSpan(
              text:
                  'Epoch ${currentIdx + 1}/${vp.epochCount}  |  Current: ${currentStage.label}$uncertainStr$comparisonStr$confidenceStr$selectionStr  |  ${vp.sampleRateHz.toStringAsFixed(0)} Hz',
            ),
          ],
        ),
      );
    }
    return Container(
      height: 24,
      decoration: const BoxDecoration(
        color: Color(0xFFF2F2F2),
        border: Border(top: BorderSide(color: Color(0xFFCFCFCF))),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              status,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12),
            ),
          ),
          if (activePath != null)
            Flexible(
              child: Text(
                _basename(activePath!),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12),
              ),
            ),
          const SizedBox(width: 12),
          ?rightWidget,
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Widget helpers
// ─────────────────────────────────────────────────────────────────────────────

class _Panel extends StatelessWidget {
  const _Panel({required this.painter, this.padding = const EdgeInsets.all(1)});

  final CustomPainter painter;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding,
      child: RepaintBoundary(
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border.all(color: const Color(0xFFD0D0D0)),
          ),
          child: ClipRect(
            child: CustomPaint(
              painter: painter,
              child: const SizedBox.expand(),
            ),
          ),
        ),
      ),
    );
  }
}

class _ClickablePainterPanel extends StatelessWidget {
  const _ClickablePainterPanel({
    required this.painter,
    required this.onTapFraction,
  });

  final CustomPainter painter;
  final void Function(double fx) onTapFraction;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(1),
      child: RepaintBoundary(
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border.all(color: const Color(0xFFD0D0D0)),
          ),
          child: GestureDetector(
            onTapDown: (details) {
              final rb = context.findRenderObject()! as RenderBox;
              final plotWidth = (rb.size.width - _plotLeftPadding).clamp(
                1.0,
                double.infinity,
              );
              final fx =
                  ((details.localPosition.dx - _plotLeftPadding) / plotWidth)
                      .clamp(0.0, 1.0);
              onTapFraction(fx);
            },
            onPanUpdate: (details) {
              final rb = context.findRenderObject()! as RenderBox;
              final plotWidth = (rb.size.width - _plotLeftPadding).clamp(
                1.0,
                double.infinity,
              );
              final fx =
                  ((details.localPosition.dx - _plotLeftPadding) / plotWidth)
                      .clamp(0.0, 1.0);
              onTapFraction(fx);
            },
            onPanDown: (details) {
              final rb = context.findRenderObject()! as RenderBox;
              final plotWidth = (rb.size.width - _plotLeftPadding).clamp(
                1.0,
                double.infinity,
              );
              final fx =
                  ((details.localPosition.dx - _plotLeftPadding) / plotWidth)
                      .clamp(0.0, 1.0);
              onTapFraction(fx);
            },
            child: ClipRect(
              child: CustomPaint(
                painter: painter,
                child: const SizedBox.expand(),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _HypnogramSlider extends StatelessWidget {
  const _HypnogramSlider({required this.value, required this.onChanged});

  final int value;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const Padding(
          padding: EdgeInsets.only(top: 4.0),
          child: Text(
            'SWA',
            style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold),
          ),
        ),
        Expanded(
          child: RotatedBox(
            quarterTurns: 3,
            child: Slider(
              value: value.toDouble(),
              min: 0,
              max: 100,
              onChanged: (v) => onChanged(v.round()),
            ),
          ),
        ),
      ],
    );
  }
}

class _ToolButton extends StatelessWidget {
  const _ToolButton({
    required this.label,
    required this.enabled,
    required this.onPressed,
    this.tooltip,
  });

  final String label;
  final bool enabled;
  final VoidCallback onPressed;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final btn = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: SizedBox(
        height: 24,
        child: OutlinedButton(
          onPressed: enabled ? onPressed : null,
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            minimumSize: Size.zero,
          ),
          child: Text(label, style: const TextStyle(fontSize: 12)),
        ),
      ),
    );
    if (tooltip != null) {
      return Tooltip(message: tooltip!, child: btn);
    }
    return btn;
  }
}

class _ZoomSignalPainter extends CustomPainter {
  const _ZoomSignalPainter(this.samples, this.sampleRate);

  final List<double> samples;
  final double sampleRate;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = Colors.white);
    if (samples.length < 2) return;
    final minV = samples.reduce(math.min);
    final maxV = samples.reduce(math.max);
    final range = math.max(maxV - minV, 1e-6);
    const pad = EdgeInsets.fromLTRB(44, 12, 12, 28);
    final plotW = size.width - pad.left - pad.right;
    final plotH = size.height - pad.top - pad.bottom;
    final axisPaint = Paint()
      ..color = Colors.black38
      ..strokeWidth = 0.8;
    canvas.drawRect(
      Rect.fromLTWH(pad.left, pad.top, plotW, plotH),
      Paint()
        ..color = Colors.black12
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.6,
    );
    final zeroY = pad.top + (1.0 - (0.0 - minV) / range) * plotH;
    if (zeroY >= pad.top && zeroY <= pad.top + plotH) {
      canvas.drawLine(
        Offset(pad.left, zeroY),
        Offset(pad.left + plotW, zeroY),
        axisPaint,
      );
    }
    final path = Path();
    for (var i = 0; i < samples.length; i++) {
      final x = pad.left + (i / (samples.length - 1)) * plotW;
      final y = pad.top + (1.0 - (samples[i] - minV) / range) * plotH;
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = Colors.black
        ..strokeWidth = 1.2
        ..style = PaintingStyle.stroke,
    );
    final duration = samples.length / sampleRate;
    _paintText(
      canvas,
      '0 s',
      Offset(pad.left, size.height - 12),
      TextAlign.left,
    );
    _paintText(
      canvas,
      '${duration.toStringAsFixed(2)} s',
      Offset(pad.left + plotW, size.height - 12),
      TextAlign.right,
    );
    _paintText(
      canvas,
      '${maxV.toStringAsFixed(1)} µV',
      Offset(4, pad.top + 6),
      TextAlign.left,
    );
    _paintText(
      canvas,
      '${minV.toStringAsFixed(1)} µV',
      Offset(4, pad.top + plotH - 6),
      TextAlign.left,
    );
  }

  void _paintText(Canvas canvas, String text, Offset offset, TextAlign align) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: const TextStyle(fontSize: 11, color: Colors.black87),
      ),
      textDirection: TextDirection.ltr,
      textAlign: align,
    )..layout(maxWidth: 140);
    var dx = offset.dx;
    if (align == TextAlign.right) dx -= painter.width;
    painter.paint(canvas, Offset(dx, offset.dy - painter.height / 2));
  }

  @override
  bool shouldRepaint(_ZoomSignalPainter oldDelegate) =>
      oldDelegate.samples != samples || oldDelegate.sampleRate != sampleRate;
}

class _Divider extends StatelessWidget {
  const _Divider();
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: 20,
      margin: const EdgeInsets.symmetric(horizontal: 4),
      color: const Color(0xFFCCCCCC),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Intents + Shortcuts
// ─────────────────────────────────────────────────────────────────────────────

class _ScoreIntent extends Intent {
  const _ScoreIntent(this.stage);
  final SleepStage stage;
}

class _NextEpochIntent extends Intent {
  const _NextEpochIntent();
}

class _PreviousEpochIntent extends Intent {
  const _PreviousEpochIntent();
}

class _ToggleUncertaintyIntent extends Intent {
  const _ToggleUncertaintyIntent();
}

class _EventIntent extends Intent {
  const _EventIntent(this.digit);
  final int digit;
}

class _EraseEventsIntent extends Intent {
  const _EraseEventsIntent();
}

class _ZoomSelectionIntent extends Intent {
  const _ZoomSelectionIntent();
}

class _KComplexDetectionIntent extends Intent {
  const _KComplexDetectionIntent();
}

class _SpindleDetectionIntent extends Intent {
  const _SpindleDetectionIntent();
}

class _ConfigIntent extends Intent {
  const _ConfigIntent();
}

class _FilterIntent extends Intent {
  const _FilterIntent();
}

final _shortcuts = <ShortcutActivator, Intent>{
  // Stage scoring
  const SingleActivator(LogicalKeyboardKey.keyW): const _ScoreIntent(
    SleepStage.wake,
  ),
  const SingleActivator(LogicalKeyboardKey.digit1): const _ScoreIntent(
    SleepStage.n1,
  ),
  const SingleActivator(LogicalKeyboardKey.digit2): const _ScoreIntent(
    SleepStage.n2,
  ),
  const SingleActivator(LogicalKeyboardKey.digit3): const _ScoreIntent(
    SleepStage.n3,
  ),
  const SingleActivator(LogicalKeyboardKey.keyR): const _ScoreIntent(
    SleepStage.rem,
  ),
  const SingleActivator(LogicalKeyboardKey.keyI): const _ScoreIntent(
    SleepStage.inconclusive,
  ),
  const SingleActivator(LogicalKeyboardKey.delete): const _ScoreIntent(
    SleepStage.unknown,
  ),
  const SingleActivator(LogicalKeyboardKey.keyA): const _EventIntent(0),
  const SingleActivator(LogicalKeyboardKey.f1): const _EventIntent(1),
  const SingleActivator(LogicalKeyboardKey.f2): const _EventIntent(2),
  const SingleActivator(LogicalKeyboardKey.f3): const _EventIntent(3),
  const SingleActivator(LogicalKeyboardKey.f4): const _EventIntent(4),
  const SingleActivator(LogicalKeyboardKey.f5): const _EventIntent(5),
  const SingleActivator(LogicalKeyboardKey.f6): const _EventIntent(6),
  const SingleActivator(LogicalKeyboardKey.f7): const _EventIntent(7),
  const SingleActivator(LogicalKeyboardKey.f8): const _EventIntent(8),
  const SingleActivator(LogicalKeyboardKey.f9): const _EventIntent(9),
  const SingleActivator(LogicalKeyboardKey.f10): const _EventIntent(10),
  const SingleActivator(LogicalKeyboardKey.f11): const _EventIntent(11),
  const SingleActivator(LogicalKeyboardKey.f12): const _EventIntent(12),
  const SingleActivator(LogicalKeyboardKey.backspace):
      const _EraseEventsIntent(),
  const SingleActivator(LogicalKeyboardKey.keyZ): const _ZoomSelectionIntent(),
  // Detections
  const SingleActivator(LogicalKeyboardKey.keyK, control: true):
      const _KComplexDetectionIntent(),
  const SingleActivator(LogicalKeyboardKey.keyS, control: true, shift: true):
      const _SpindleDetectionIntent(),
  // Configuration & Filters
  const SingleActivator(LogicalKeyboardKey.keyC, control: true):
      const _ConfigIntent(),
  const SingleActivator(LogicalKeyboardKey.keyF, control: true):
      const _FilterIntent(),
  // Navigation
  const SingleActivator(LogicalKeyboardKey.arrowRight):
      const _NextEpochIntent(),
  const SingleActivator(LogicalKeyboardKey.arrowLeft):
      const _PreviousEpochIntent(),
  // Confidence uncertainty toggle
  const SingleActivator(LogicalKeyboardKey.keyQ):
      const _ToggleUncertaintyIntent(),
};

// ─────────────────────────────────────────────────────────────────────────────

String detectBackendExecutable() {
  final currentDir = Directory.current.path;

  // 1. Packaged location checks
  final execDir = File(Platform.resolvedExecutable).parent.path;
  String packagedBin = '';
  if (Platform.isWindows) {
    packagedBin = '$execDir\\autoscore-backend.exe';
  } else if (Platform.isMacOS) {
    packagedBin = '$execDir/autoscore-backend';
    if (!File(packagedBin).existsSync()) {
      packagedBin = '$execDir/../Resources/autoscore-backend';
    }
  } else {
    packagedBin = '$execDir/autoscore-backend';
  }

  if (File(packagedBin).existsSync()) {
    return packagedBin;
  }

  // 2. Dev environment check (virtual environment python stager + script)
  final devPaths = Platform.isWindows
      ? [
          '$currentDir\\..\\backend\\sleep_env\\Scripts\\python.exe',
          '$currentDir\\backend\\sleep_env\\Scripts\\python.exe',
          '$currentDir\\python_backend\\sleep_env\\Scripts\\python.exe',
          '$currentDir\\sleep_env\\Scripts\\python.exe',
        ]
      : [
          '$currentDir/../backend/sleep_env/bin/python',
          '$currentDir/backend/sleep_env/bin/python',
          '$currentDir/python_backend/sleep_env/bin/python',
          '$currentDir/sleep_env/bin/python',
        ];

  for (final path in devPaths) {
    if (File(path).existsSync()) {
      return path;
    }
  }

  // 3. Fallback to system python3 or autoscore-backend on PATH
  return Platform.isWindows ? 'python.exe' : 'python3';
}

String detectBackendScript() {
  final currentDir = Directory.current.path;
  final scriptPaths = [
    '$currentDir/../backend/cli.py',
    '$currentDir/backend/cli.py',
    '$currentDir/python_backend/cli.py',
  ];
  for (final path in scriptPaths) {
    if (File(path).existsSync()) {
      return path;
    }
  }
  return '';
}

String detectAnalyseNidraExecutable() {
  final executableDir = File(Platform.resolvedExecutable).parent.path;
  final candidates = [
    if (Platform.isWindows) '$executableDir\\analyse-nidra.exe',
    if (!Platform.isWindows) '$executableDir/analyse-nidra',
    if (Platform.isMacOS) '$executableDir/../Resources/analyse-nidra',
    '${Directory.current.path}/../analyseNidra/target/release/analyse-nidra',
    '${Directory.current.path}/analyseNidra/target/release/analyse-nidra',
    '/Users/arunsasidharan/Code/ActiveProjects/analyseNidra/target/release/analyse-nidra',
  ];
  for (final candidate in candidates) {
    if (File(candidate).existsSync()) return candidate;
  }
  return Platform.isWindows ? 'analyse-nidra.exe' : 'analyse-nidra';
}

String _sidecarPath(String path, String suffix) {
  final dot = path.lastIndexOf('.');
  final base = dot >= 0 ? path.substring(0, dot) : path;
  return '$base$suffix';
}

String? _detectMatchingEdf(String scoringPath) {
  final scoringFile = File(scoringPath);
  final directory = scoringFile.parent;
  if (!directory.existsSync()) return null;
  final scoringStem = _basename(_sidecarPath(scoringPath, ''));
  final normalizedStem = scoringStem.replaceFirst(
    RegExp(
      r'_(yasa|gssc|tinysleepnet|seqsleepnet|sleeptransformer|usleep|luna|dreamento|sleepeegpy)(?:_sleepgpt)?$',
      caseSensitive: false,
    ),
    '',
  );
  final candidates = directory
      .listSync()
      .whereType<File>()
      .where(
        (file) =>
            file.path != scoringPath &&
            file.path.toLowerCase().endsWith('.edf'),
      )
      .toList();
  File? best;
  var bestLength = -1;
  for (final candidate in candidates) {
    final stem = _basename(_sidecarPath(candidate.path, ''));
    if (stem == normalizedStem ||
        scoringStem.startsWith(stem) ||
        stem.startsWith(normalizedStem)) {
      if (stem.length > bestLength) {
        best = candidate;
        bestLength = stem.length;
      }
    }
  }
  return best?.path;
}

List<String> _analyseNidraArguments(
  _AnalyseNidraJob job,
  List<String> channels,
  List<String> references,
) {
  final base = _sidecarPath(job.edfPath, '');
  return [
    job.edfPath,
    job.mappedScoringPath,
    '${base}_analyse_core.json',
    '${base}_analyse_pac.json',
    '${base}_analyse_slow_waves.json',
    '${base}_analyse_spindles.json',
    '${base}_analyse_regional.csv',
    '--channels',
    channels.join(','),
    '--references',
    references.join(','),
  ];
}

class _AnalyseNidraJob {
  const _AnalyseNidraJob({
    required this.edfPath,
    required this.scoringPath,
    required this.mappedScoringPath,
  });

  final String edfPath;
  final String scoringPath;
  final String mappedScoringPath;
}

class _CommandJob {
  const _CommandJob({
    required this.label,
    required this.executable,
    required this.arguments,
  });

  final String label;
  final String executable;
  final List<String> arguments;
}

class _CommandBatchProgressDialog extends StatefulWidget {
  const _CommandBatchProgressDialog({
    super.key,
    required this.title,
    required this.jobs,
    required this.onFinished,
  });

  final String title;
  final List<_CommandJob> jobs;
  final void Function(int failed) onFinished;

  @override
  State<_CommandBatchProgressDialog> createState() =>
      _CommandBatchProgressDialogState();
}

class _CommandBatchProgressDialogState
    extends State<_CommandBatchProgressDialog> {
  final List<String> _logs = [];
  int _completed = 0;
  int _failed = 0;
  bool _finished = false;
  String _current = '';

  @override
  void initState() {
    super.initState();
    unawaited(_run());
  }

  Future<void> _run() async {
    final backend = EegBackend();
    for (final job in widget.jobs) {
      if (!mounted) return;
      setState(() {
        _current = job.label;
        _logs.add('--- ${job.label} ---');
      });
      final exitCode = await backend.runCommandStreamAsync(
        executable: job.executable,
        arguments: job.arguments,
        onLine: (line) {
          if (mounted) setState(() => _logs.add(line));
        },
      );
      if (!mounted) return;
      setState(() {
        _completed++;
        if (exitCode != 0) _failed++;
        _logs.add(
          exitCode == 0
              ? 'Completed ${job.label}'
              : 'Failed ${job.label} with exit code $exitCode',
        );
      });
    }
    if (mounted) setState(() => _finished = true);
  }

  @override
  Widget build(BuildContext context) {
    final progress = widget.jobs.isEmpty
        ? 0.0
        : _completed / widget.jobs.length;
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 760,
        height: 500,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _finished
                  ? 'Finished ${widget.jobs.length} job(s)'
                  : 'Processing $_current (${_completed + 1}/${widget.jobs.length})',
            ),
            const SizedBox(height: 8),
            LinearProgressIndicator(value: _finished ? 1 : progress),
            const SizedBox(height: 12),
            Expanded(
              child: Container(
                color: Colors.black87,
                padding: const EdgeInsets.all(8),
                child: ListView.builder(
                  itemCount: _logs.length,
                  itemBuilder: (_, index) => Text(
                    _logs[index],
                    style: const TextStyle(
                      color: Colors.lightGreenAccent,
                      fontFamily: 'Courier',
                      fontSize: 11,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _finished
              ? () {
                  Navigator.of(context).pop();
                  widget.onFinished(_failed);
                }
              : null,
          child: Text(_finished ? 'Close' : 'Processing…'),
        ),
      ],
    );
  }
}

String _basename(String path) => path.split(Platform.pathSeparator).last;

Future<List<(double, double)>> _runKComplexIsolate(
  List<double> signal,
  double sfreq,
  double amin,
  double dmax_s,
  double q,
  double fmax,
) {
  return Isolate.run(() {
    return sp.detectKComplex(
      signal,
      sfreq,
      amin: amin,
      dmax_s: dmax_s,
      q: q,
      fmax: fmax,
    );
  });
}

Future<List<(double, double)>> _runSpindleIsolate(
  List<double> signal,
  double sfreq,
  double fmin,
  double fmax,
  double amin,
  double dmin_s,
  double dmax_s,
  double q,
) {
  return Isolate.run(() {
    return sp.detectSpindles(
      signal,
      sfreq,
      fmin: fmin,
      fmax: fmax,
      amin: amin,
      dmin_s: dmin_s,
      dmax_s: dmax_s,
      q: q,
    );
  });
}

// ─────────────────────────────────────────────────────────────────────────────
// Scoring Comparison Metrics & Report Card Dialog
// ─────────────────────────────────────────────────────────────────────────────

class _StageComparisonMetrics {
  _StageComparisonMetrics({
    required this.totalEpochs,
    required this.comparedEpochs,
    required this.overallAgreement,
    required this.cohensKappa,
    required this.confusionMatrix,
    required this.precision,
    required this.recall,
    required this.f1Score,
  });

  final int totalEpochs;
  final int comparedEpochs;
  final double overallAgreement;
  final double cohensKappa;
  final Map<SleepStage, Map<SleepStage, int>> confusionMatrix;
  final Map<SleepStage, double> precision;
  final Map<SleepStage, double> recall;
  final Map<SleepStage, double> f1Score;

  factory _StageComparisonMetrics.compute(
    List<SleepStage> current,
    List<SleepStage> comparison,
  ) {
    final stages = [
      SleepStage.wake,
      SleepStage.rem,
      SleepStage.n1,
      SleepStage.n2,
      SleepStage.n3,
    ];

    final total = current.length < comparison.length
        ? current.length
        : comparison.length;

    var validCount = 0;
    var matches = 0;

    final matrix = <SleepStage, Map<SleepStage, int>>{};
    for (final s1 in stages) {
      matrix[s1] = {};
      for (final s2 in stages) {
        matrix[s1]![s2] = 0;
      }
    }

    for (var i = 0; i < total; i++) {
      final sCurr = current[i];
      final sComp = comparison[i];

      if (!stages.contains(sCurr) || !stages.contains(sComp)) {
        continue;
      }

      validCount++;
      if (sCurr == sComp) {
        matches++;
      }
      matrix[sCurr]![sComp] = (matrix[sCurr]![sComp] ?? 0) + 1;
    }

    final agreement = validCount == 0 ? 0.0 : (matches / validCount) * 100.0;

    double kappa = 0.0;
    if (validCount > 0) {
      final po = matches / validCount;
      double pe = 0.0;
      for (final s in stages) {
        var rowSum = 0;
        for (final sComp in stages) {
          rowSum += matrix[s]![sComp] ?? 0;
        }
        var colSum = 0;
        for (final sCurr in stages) {
          colSum += matrix[sCurr]![s] ?? 0;
        }
        pe += (rowSum / validCount) * (colSum / validCount);
      }
      if (pe < 1.0) {
        kappa = (po - pe) / (1.0 - pe);
      } else {
        kappa = 1.0;
      }
    }

    final prec = <SleepStage, double>{};
    final rec = <SleepStage, double>{};
    final f1 = <SleepStage, double>{};

    for (final s in stages) {
      final tp = matrix[s]![s] ?? 0;

      var fp = 0;
      for (final sComp in stages) {
        if (sComp != s) {
          fp += matrix[s]![sComp] ?? 0;
        }
      }

      var fn = 0;
      for (final sCurr in stages) {
        if (sCurr != s) {
          fn += matrix[sCurr]![s] ?? 0;
        }
      }

      final p = (tp + fp) == 0 ? 0.0 : tp / (tp + fp);
      final r = (tp + fn) == 0 ? 0.0 : tp / (tp + fn);
      final f = (p + r) == 0 ? 0.0 : (2.0 * p * r) / (p + r);

      prec[s] = p * 100.0;
      rec[s] = r * 100.0;
      f1[s] = f * 100.0;
    }

    return _StageComparisonMetrics(
      totalEpochs: total,
      comparedEpochs: validCount,
      overallAgreement: agreement,
      cohensKappa: kappa,
      confusionMatrix: matrix,
      precision: prec,
      recall: rec,
      f1Score: f1,
    );
  }
}

class _ComparisonReportCardDialog extends StatelessWidget {
  const _ComparisonReportCardDialog({required this.metrics});

  final _StageComparisonMetrics metrics;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final textTheme = theme.textTheme;

    Color getKappaColor(double kappa) {
      if (kappa >= 0.8) return Colors.green.shade700;
      if (kappa >= 0.6) return Colors.blue.shade700;
      if (kappa >= 0.4) return Colors.orange.shade700;
      return Colors.red.shade700;
    }

    String getKappaStrength(double kappa) {
      if (kappa >= 0.8) return 'Almost Perfect';
      if (kappa >= 0.6) return 'Substantial';
      if (kappa >= 0.4) return 'Moderate';
      if (kappa >= 0.2) return 'Fair';
      if (kappa > 0) return 'Slight';
      return 'Poor/None';
    }

    final kappaColor = getKappaColor(metrics.cohensKappa);
    final kappaStrength = getKappaStrength(metrics.cohensKappa);

    final stages = [
      SleepStage.wake,
      SleepStage.rem,
      SleepStage.n1,
      SleepStage.n2,
      SleepStage.n3,
    ];

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        width: 800,
        padding: const EdgeInsets.all(24),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      const Icon(
                        Icons.assessment,
                        color: Colors.indigo,
                        size: 28,
                      ),
                      const SizedBox(width: 12),
                      Text(
                        'Scoring Comparison Report Card',
                        style: textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: Colors.indigo.shade900,
                        ),
                      ),
                    ],
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const Divider(height: 24, thickness: 1),

              GridView.count(
                crossAxisCount: 3,
                crossAxisSpacing: 16,
                mainAxisSpacing: 16,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                childAspectRatio: 2.2,
                children: [
                  _buildStatCard(
                    title: 'Compared Epochs',
                    value: '${metrics.comparedEpochs} / ${metrics.totalEpochs}',
                    subtitle: 'Valid matched epochs',
                    icon: Icons.list_alt,
                    iconColor: Colors.grey.shade700,
                  ),
                  _buildStatCard(
                    title: 'Overall Agreement',
                    value: '${metrics.overallAgreement.toStringAsFixed(1)}%',
                    subtitle: 'Total matching epochs',
                    icon: Icons.check_circle_outline,
                    iconColor: Colors.green.shade600,
                  ),
                  _buildStatCard(
                    title: "Cohen's Kappa (κ)",
                    value: metrics.cohensKappa.toStringAsFixed(3),
                    subtitle: '$kappaStrength agreement',
                    icon: Icons.psychology,
                    iconColor: kappaColor,
                  ),
                ],
              ),
              const SizedBox(height: 24),

              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: 11,
                    child: Card(
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        side: BorderSide(color: Colors.grey.shade200),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Confusion Matrix',
                              style: textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                                color: Colors.blueGrey.shade800,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Current Scorer (Rows) vs. Comparison (Columns)',
                              style: textTheme.bodySmall?.copyWith(
                                color: Colors.grey.shade600,
                              ),
                            ),
                            const SizedBox(height: 16),
                            _buildConfusionMatrixTable(stages),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    flex: 13,
                    child: Card(
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        side: BorderSide(color: Colors.grey.shade200),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Stage-Specific Metrics',
                              style: textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                                color: Colors.blueGrey.shade800,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Precision, Recall (Sensitivity), and F1-Score',
                              style: textTheme.bodySmall?.copyWith(
                                color: Colors.grey.shade600,
                              ),
                            ),
                            const SizedBox(height: 16),
                            _buildStageMetricsTable(stages),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),

              Align(
                alignment: Alignment.centerRight,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.indigo,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 12,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Close'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatCard({
    required String title,
    required String value,
    required String subtitle,
    required IconData icon,
    required Color iconColor,
  }) {
    return Card(
      elevation: 0,
      color: Colors.grey.shade50,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: Colors.grey.shade200),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: iconColor.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: iconColor, size: 24),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    value,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: const TextStyle(fontSize: 10, color: Colors.grey),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildConfusionMatrixTable(List<SleepStage> stages) {
    final headerStyle = TextStyle(
      fontWeight: FontWeight.bold,
      fontSize: 12,
      color: Colors.blueGrey.shade700,
    );

    return Table(
      border: TableBorder.all(
        color: Colors.grey.shade200,
        width: 1,
        borderRadius: BorderRadius.circular(4),
      ),
      columnWidths: const {
        0: FlexColumnWidth(1.2),
        1: FlexColumnWidth(1),
        2: FlexColumnWidth(1),
        3: FlexColumnWidth(1),
        4: FlexColumnWidth(1),
        5: FlexColumnWidth(1),
      },
      defaultVerticalAlignment: TableCellVerticalAlignment.middle,
      children: [
        TableRow(
          decoration: BoxDecoration(color: Colors.grey.shade100),
          children: [
            const TableCell(
              child: SizedBox(
                height: 32,
                child: Center(
                  child: Text(
                    'Cur \\ Cmp',
                    style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ),
            for (final s in stages)
              TableCell(
                child: Center(child: Text(s.shortLabel, style: headerStyle)),
              ),
          ],
        ),
        for (final sCurr in stages)
          TableRow(
            children: [
              TableCell(
                child: Container(
                  height: 36,
                  color: Colors.grey.shade50,
                  alignment: Alignment.center,
                  child: Text(sCurr.label, style: headerStyle),
                ),
              ),
              for (final sComp in stages) _buildConfusionCell(sCurr, sComp),
            ],
          ),
      ],
    );
  }

  Widget _buildConfusionCell(SleepStage sCurr, SleepStage sComp) {
    final count = metrics.confusionMatrix[sCurr]?[sComp] ?? 0;
    final isDiag = sCurr == sComp;

    double opacity = 0.0;
    Color cellColor = Colors.transparent;

    if (count > 0) {
      var maxInRow = 1;
      metrics.confusionMatrix[sCurr]?.forEach((_, val) {
        if (val > maxInRow) maxInRow = val;
      });

      opacity = count / maxInRow;
      opacity = 0.05 + opacity * 0.75;
      cellColor = isDiag
          ? Colors.green.shade500.withOpacity(opacity)
          : Colors.red.shade400.withOpacity(opacity);
    }

    return TableCell(
      child: Container(
        height: 36,
        color: cellColor,
        alignment: Alignment.center,
        child: Text(
          '$count',
          style: TextStyle(
            fontWeight: isDiag ? FontWeight.bold : FontWeight.normal,
            color: count == 0
                ? Colors.grey.shade400
                : (opacity > 0.5 ? Colors.white : Colors.black87),
            fontSize: 12,
          ),
        ),
      ),
    );
  }

  Widget _buildStageMetricsTable(List<SleepStage> stages) {
    final headerStyle = TextStyle(
      fontWeight: FontWeight.bold,
      fontSize: 12,
      color: Colors.blueGrey.shade700,
    );

    return Table(
      columnWidths: const {
        0: FlexColumnWidth(1.2),
        1: FlexColumnWidth(1),
        2: FlexColumnWidth(1),
        3: FlexColumnWidth(1),
      },
      defaultVerticalAlignment: TableCellVerticalAlignment.middle,
      children: [
        TableRow(
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(color: Colors.grey.shade300, width: 1.5),
            ),
          ),
          children: [
            const TableCell(
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  'Stage',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                ),
              ),
            ),
            TableCell(
              child: Center(child: Text('Precision', style: headerStyle)),
            ),
            TableCell(
              child: Center(child: Text('Recall', style: headerStyle)),
            ),
            TableCell(
              child: Center(child: Text('F1-Score', style: headerStyle)),
            ),
          ],
        ),
        for (final s in stages)
          TableRow(
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: Colors.grey.shade100)),
            ),
            children: [
              TableCell(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Row(
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: _colorForStage(s),
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        s.label,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              TableCell(
                child: Center(
                  child: Text(
                    '${metrics.precision[s]?.toStringAsFixed(1)}%',
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
              ),
              TableCell(
                child: Center(
                  child: Text(
                    '${metrics.recall[s]?.toStringAsFixed(1)}%',
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
              ),
              TableCell(
                child: Center(
                  child: Text(
                    '${metrics.f1Score[s]?.toStringAsFixed(1)}%',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: _colorForF1(metrics.f1Score[s] ?? 0),
                      fontSize: 12,
                    ),
                  ),
                ),
              ),
            ],
          ),
      ],
    );
  }

  Color _colorForStage(SleepStage stage) {
    switch (stage) {
      case SleepStage.wake:
        return const Color(0xFF56bf8b);
      case SleepStage.rem:
        return const Color(0xFF8bbf56);
      case SleepStage.n1:
        return const Color(0xFFaabcce);
      case SleepStage.n2:
        return const Color(0xFF405c79);
      case SleepStage.n3:
        return const Color(0xFF0b1c2c);
      default:
        return Colors.grey;
    }
  }

  Color _colorForF1(double score) {
    if (score >= 80.0) return Colors.green.shade700;
    if (score >= 60.0) return Colors.blue.shade700;
    if (score >= 40.0) return Colors.orange.shade700;
    return Colors.red.shade700;
  }
}

class _AutoScoringTask {
  final String executable;
  final List<String> arguments;
  final SendPort sendPort;

  _AutoScoringTask({
    required this.executable,
    required this.arguments,
    required this.sendPort,
  });

  (int, String) run() {
    final backend = EegBackend();
    var outPath = '';
    final exitCode = backend.runCommandStream(
      executable: executable,
      arguments: arguments,
      onLine: (line) {
        sendPort.send(line);
        if (line.contains('Saved ScoringHero JSON:')) {
          final match = RegExp(
            r'Saved ScoringHero JSON:\s*(.*)',
          ).firstMatch(line);
          if (match != null) {
            outPath = match.group(1)!.trim();
          }
        }
      },
    );
    return (exitCode, outPath);
  }
}

String _outputPathFromLogs(List<String> lines) {
  for (final line in lines.reversed) {
    final match = RegExp(r'Saved ScoringHero JSON:\s*(.*)').firstMatch(line);
    if (match != null) return match.group(1)!.trim();
  }
  return '';
}

class BatchProgressDialog extends StatefulWidget {
  const BatchProgressDialog({
    super.key,
    required this.files,
    required this.algorithm,
    required this.correction,
    required this.sleepgptAlpha,
    required this.sleepgptNgram,
    required this.eegChannels,
    required this.refChannels,
    required this.eogChannels,
    required this.emgChannels,
    required this.onFinished,
  });

  final List<String> files;
  final String algorithm;
  final String correction;
  final double sleepgptAlpha;
  final int sleepgptNgram;
  final List<String> eegChannels;
  final List<String> refChannels;
  final List<String> eogChannels;
  final List<String> emgChannels;
  final void Function() onFinished;

  @override
  State<BatchProgressDialog> createState() => _BatchProgressDialogState();
}

class _BatchProgressDialogState extends State<BatchProgressDialog> {
  final Map<String, String> _statuses = {};
  final List<String> _logLines = [];
  final StreamController<String> _logsStream = StreamController<String>();
  String _currentFile = '';
  int _currentIndex = 0;
  bool _isFinished = false;
  bool _isCancelled = false;

  @override
  void initState() {
    super.initState();
    for (final file in widget.files) {
      _statuses[file] = 'Pending';
    }
    _startBatch();
  }

  @override
  void dispose() {
    _logsStream.close();
    super.dispose();
  }

  Future<void> _startBatch() async {
    final executable = detectBackendExecutable();
    final script = detectBackendScript();

    for (int i = 0; i < widget.files.length; i++) {
      if (_isCancelled) break;

      final file = widget.files[i];
      if (!mounted) break;
      setState(() {
        _currentIndex = i;
        _currentFile = file;
        _statuses[file] = 'Scoring…';
        _logLines.clear();
        _logLines.add('--- Starting auto-scoring for ${_basename(file)} ---');
      });
      _logsStream.add('--- Starting auto-scoring for ${_basename(file)} ---');

      final args = <String>[];
      if (executable.endsWith('.py') ||
          script.isNotEmpty &&
              (executable.contains('python') ||
                  executable.contains('python3'))) {
        if (script.isNotEmpty) {
          args.add(script);
        }
      }
      args.add(file);
      args.addAll(['--algorithm', widget.algorithm]);
      args.addAll(['--sequence-correction', widget.correction]);
      if (widget.eegChannels.isNotEmpty) {
        args.addAll(['--eeg', widget.eegChannels.join(',')]);
      }
      if (widget.refChannels.isNotEmpty) {
        args.addAll(['--ref', widget.refChannels.join(',')]);
      }
      if (widget.eogChannels.isNotEmpty) {
        args.addAll(['--eog', widget.eogChannels.join(',')]);
      }
      if (widget.emgChannels.isNotEmpty) {
        args.addAll(['--emg', widget.emgChannels.join(',')]);
      }

      if (widget.correction == 'sleepgpt') {
        args.addAll(['--sleepgpt-alpha', widget.sleepgptAlpha.toString()]);
        args.addAll(['--sleepgpt-ngram', widget.sleepgptNgram.toString()]);
      }

      try {
        void onLine(String line) {
          if (!mounted) return;
          setState(() {
            _logLines.add(line);
          });
          _logsStream.add(line);
        }

        final exitCode = await EegBackend().runCommandStreamAsync(
          executable: executable,
          arguments: args,
          onLine: onLine,
        );
        final outputJsonPath = _outputPathFromLogs(_logLines);

        if (exitCode == 0 && outputJsonPath.isNotEmpty) {
          if (mounted) {
            setState(() {
              _statuses[file] = 'Completed';
              _logLines.add(
                '\nScoring finished successfully! Output saved to: $outputJsonPath',
              );
            });
            _logsStream.add(
              '\nScoring finished successfully! Output saved to: $outputJsonPath',
            );
          }
        } else {
          if (mounted) {
            setState(() {
              _statuses[file] = 'Failed';
              _logLines.add('\nScoring failed with exit code $exitCode');
            });
            _logsStream.add('\nScoring failed with exit code $exitCode');
          }
        }
      } catch (e) {
        if (mounted) {
          setState(() {
            _statuses[file] = 'Failed';
            _logLines.add('\nException occurred: $e');
          });
          _logsStream.add('\nException occurred: $e');
        }
      }
    }

    if (mounted) {
      setState(() {
        _isFinished = true;
      });
    }
  }

  String _basename(String path) {
    return path.split(Platform.pathSeparator).last;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        children: [
          const Icon(Icons.auto_awesome_motion, color: Colors.purple),
          const SizedBox(width: 8),
          Text(
            _isFinished
                ? 'Batch Scoring Finished'
                : 'Running Batch Auto-Scoring…',
          ),
        ],
      ),
      content: SizedBox(
        width: 800,
        height: 500,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Left column: list of files
            Expanded(
              flex: 2,
              child: Container(
                decoration: BoxDecoration(
                  border: Border(
                    right: BorderSide(color: Colors.grey.shade300),
                  ),
                ),
                padding: const EdgeInsets.only(right: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Files Queue (${_currentIndex + 1}/${widget.files.length})',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Expanded(
                      child: ListView.builder(
                        itemCount: widget.files.length,
                        itemBuilder: (context, index) {
                          final file = widget.files[index];
                          final status = _statuses[file] ?? 'Pending';
                          IconData icon = Icons.hourglass_empty;
                          Color color = Colors.grey;

                          if (status == 'Scoring…') {
                            icon = Icons.sync;
                            color = Colors.blue;
                          } else if (status == 'Completed') {
                            icon = Icons.check_circle;
                            color = Colors.green;
                          } else if (status == 'Failed') {
                            icon = Icons.error;
                            color = Colors.red;
                          }

                          final isCurrent = file == _currentFile;
                          return Container(
                            color: isCurrent ? Colors.purple.shade50 : null,
                            padding: const EdgeInsets.symmetric(
                              vertical: 6,
                              horizontal: 4,
                            ),
                            child: Row(
                              children: [
                                Icon(icon, size: 16, color: color),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        _basename(file),
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: isCurrent
                                              ? FontWeight.bold
                                              : FontWeight.normal,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      Text(
                                        status,
                                        style: TextStyle(
                                          fontSize: 10,
                                          color: color,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 12),
            // Right column: terminal logs
            Expanded(
              flex: 3,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  LinearProgressIndicator(
                    value: widget.files.isEmpty
                        ? 0
                        : _isFinished
                        ? 1
                        : _currentIndex / widget.files.length,
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Active Logs',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      color: Colors.black87,
                      width: double.infinity,
                      child: StreamBuilder<String>(
                        stream: _logsStream.stream,
                        builder: (context, snapshot) {
                          return Scrollbar(
                            thumbVisibility: true,
                            child: ListView.builder(
                              shrinkWrap: true,
                              itemCount: _logLines.length,
                              itemBuilder: (context, index) {
                                return Text(
                                  _logLines[index],
                                  style: const TextStyle(
                                    color: Colors.lightGreenAccent,
                                    fontFamily: 'Courier',
                                    fontSize: 11,
                                  ),
                                );
                              },
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        if (!_isFinished)
          TextButton(
            onPressed: () {
              setState(() {
                _isCancelled = true;
              });
              Navigator.of(context).pop();
            },
            child: const Text(
              'Cancel Batch',
              style: TextStyle(color: Colors.red),
            ),
          ),
        TextButton(
          onPressed: _isFinished
              ? () {
                  Navigator.of(context).pop();
                  widget.onFinished();
                }
              : null,
          child: Text(_isFinished ? 'Close' : 'Processing…'),
        ),
      ],
    );
  }
}
