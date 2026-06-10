// lib/src/detection_dialogs.dart

import 'package:flutter/material.dart';

class MtKcdDialog extends StatefulWidget {
  const MtKcdDialog({
    super.key,
    required this.channelLabels,
    required this.hasStages,
    required this.onRun,
  });

  final List<String> channelLabels;
  final bool hasStages;
  final void Function(Map<String, dynamic> settings) onRun;

  @override
  State<MtKcdDialog> createState() => _MtKcdDialogState();
}

class _MtKcdDialogState extends State<MtKcdDialog> {
  late String _selectedChannel;
  String _selectedMarker = 'F1';

  // Detection parameters
  double _amin = 125.0;
  double _dmax = 2.0;
  int _q = 90;
  double _fmax = 3.0;

  // Stage filtering
  bool _useStageFilter = false;
  final Map<String, bool> _stages = {
    'Wake': false,
    'N1': false,
    'N2': true,
    'N3': true,
    'REM': false,
    'Inconclusive': false,
  };

  @override
  void initState() {
    super.initState();
    _selectedChannel = widget.channelLabels.isNotEmpty
        ? widget.channelLabels.first
        : '';
    _useStageFilter = widget.hasStages;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        children: [
          const Icon(Icons.analytics, color: Colors.blue),
          const SizedBox(width: 8),
          const Text('K-Complex Detection (MT-KCD)'),
        ],
      ),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // EEG channel selector
              const Text(
                'EEG Channel',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
              ),
              const SizedBox(height: 6),
              DropdownButtonFormField<String>(
                value: _selectedChannel,
                isExpanded: true,
                decoration: const InputDecoration(
                  isDense: true,
                  border: OutlineInputBorder(),
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 8,
                  ),
                ),
                items: widget.channelLabels.map((ch) {
                  return DropdownMenuItem(
                    value: ch,
                    child: Text(ch, style: const TextStyle(fontSize: 13)),
                  );
                }).toList(),
                onChanged: (v) {
                  if (v != null) setState(() => _selectedChannel = v);
                },
              ),
              const SizedBox(height: 14),

              // Target event marker dropdown
              const Text(
                'Save detections to event marker',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
              ),
              const SizedBox(height: 6),
              DropdownButtonFormField<String>(
                value: _selectedMarker,
                decoration: const InputDecoration(
                  isDense: true,
                  border: OutlineInputBorder(),
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 8,
                  ),
                ),
                items: [
                  const DropdownMenuItem(
                    value: 'Artifact',
                    child: Text('Artifact (A)', style: TextStyle(fontSize: 13)),
                  ),
                  for (var i = 1; i <= 12; i++)
                    DropdownMenuItem(
                      value: 'F$i',
                      child: Text(
                        'Event $i (F$i)',
                        style: const TextStyle(fontSize: 13),
                      ),
                    ),
                ],
                onChanged: (v) {
                  if (v != null) setState(() => _selectedMarker = v);
                },
              ),
              const SizedBox(height: 14),

              // Threshold group
              Card(
                margin: EdgeInsets.zero,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  side: BorderSide(color: Colors.grey.shade300),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Detection Thresholds',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(height: 12),
                      _doubleInputRow(
                        label: 'Min. amplitude (Amin):',
                        value: _amin,
                        suffix: ' µV',
                        tooltip:
                            'Minimum peak-to-peak amplitude (AASM standard requires ≥ 75 µV).',
                        onChanged: (v) => setState(() => _amin = v),
                      ),
                      const SizedBox(height: 10),
                      _doubleInputRow(
                        label: 'Max. duration (Dmax):',
                        value: _dmax,
                        suffix: ' s',
                        tooltip:
                            'Maximum allowed duration of a K-complex (default 2 s).',
                        onChanged: (v) => setState(() => _dmax = v),
                      ),
                      const SizedBox(height: 10),
                      _intInputRow(
                        label: 'Region percentile (q):',
                        value: _q,
                        suffix: ' %',
                        tooltip:
                            'Percentile threshold for candidate-region identification (default 90%).',
                        onChanged: (v) => setState(() => _q = v),
                      ),
                      const SizedBox(height: 10),
                      _doubleInputRow(
                        label: 'Max. KC frequency (fmax):',
                        value: _fmax,
                        suffix: ' Hz',
                        tooltip:
                            'Upper frequency limit for K-Complex spectral delta power (default 3.0 Hz).',
                        onChanged: (v) => setState(() => _fmax = v),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 14),

              // Stage filter
              CheckboxListTile(
                title: const Text(
                  'Keep detections in sleep stages only',
                  style: TextStyle(fontSize: 13),
                ),
                contentPadding: EdgeInsets.zero,
                dense: true,
                value: _useStageFilter,
                onChanged: widget.hasStages
                    ? (v) => setState(() => _useStageFilter = v ?? false)
                    : null,
                subtitle: widget.hasStages
                    ? null
                    : const Text(
                        'No stages scored yet.',
                        style: TextStyle(color: Colors.grey, fontSize: 11),
                      ),
              ),
              if (_useStageFilter)
                Container(
                  padding: const EdgeInsets.only(left: 16),
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    children: _stages.keys.map((stage) {
                      return Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Checkbox(
                            value: _stages[stage],
                            onChanged: (v) {
                              setState(() => _stages[stage] = v ?? false);
                            },
                          ),
                          Text(stage, style: const TextStyle(fontSize: 12)),
                        ],
                      );
                    }).toList(),
                  ),
                ),
              const SizedBox(height: 12),

              // Explanation
              Text(
                'MT-KCD detects KCs via multitaper spectral analysis. '
                'Based on: Oliveira et al. (2020), Expert Syst. Appl. 151, 113331.',
                style: TextStyle(color: Colors.grey.shade600, fontSize: 11),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: () {
            if (_selectedChannel.isEmpty) return;

            // Collect selected stages
            List<String>? filteredStages;
            if (_useStageFilter) {
              filteredStages = _stages.entries
                  .where((e) => e.value)
                  .map((e) => e.key)
                  .toList();
              if (filteredStages.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Select at least one stage for filtering.'),
                  ),
                );
                return;
              }
            }

            widget.onRun({
              'channel': _selectedChannel,
              'marker': _selectedMarker,
              'amin': _amin,
              'dmax_s': _dmax,
              'q': _q.toDouble(),
              'fmax': _fmax,
              'filter_stages': filteredStages,
            });
            Navigator.of(context).pop();
          },
          child: const Text('OK'),
        ),
      ],
    );
  }

  Widget _doubleInputRow({
    required String label,
    required double value,
    required String suffix,
    required String tooltip,
    required ValueChanged<double> onChanged,
  }) {
    return Row(
      children: [
        Expanded(
          flex: 3,
          child: Row(
            children: [
              Text(label, style: const TextStyle(fontSize: 12)),
              const SizedBox(width: 4),
              Tooltip(
                message: tooltip,
                child: const Icon(
                  Icons.info_outline,
                  size: 14,
                  color: Colors.blue,
                ),
              ),
            ],
          ),
        ),
        SizedBox(
          width: 90,
          height: 32,
          child: TextFormField(
            initialValue: value.toString(),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            style: const TextStyle(fontSize: 12),
            decoration: InputDecoration(
              isDense: true,
              contentPadding: const EdgeInsets.all(8),
              border: const OutlineInputBorder(),
              suffixText: suffix,
            ),
            onChanged: (text) {
              final d = double.tryParse(text);
              if (d != null) onChanged(d);
            },
          ),
        ),
      ],
    );
  }

  Widget _intInputRow({
    required String label,
    required int value,
    required String suffix,
    required String tooltip,
    required ValueChanged<int> onChanged,
  }) {
    return Row(
      children: [
        Expanded(
          flex: 3,
          child: Row(
            children: [
              Text(label, style: const TextStyle(fontSize: 12)),
              const SizedBox(width: 4),
              Tooltip(
                message: tooltip,
                child: const Icon(
                  Icons.info_outline,
                  size: 14,
                  color: Colors.blue,
                ),
              ),
            ],
          ),
        ),
        SizedBox(
          width: 90,
          height: 32,
          child: TextFormField(
            initialValue: value.toString(),
            keyboardType: TextInputType.number,
            style: const TextStyle(fontSize: 12),
            decoration: InputDecoration(
              isDense: true,
              contentPadding: const EdgeInsets.all(8),
              border: const OutlineInputBorder(),
              suffixText: suffix,
            ),
            onChanged: (text) {
              final val = int.tryParse(text);
              if (val != null) onChanged(val);
            },
          ),
        ),
      ],
    );
  }
}

class MtSpindleDialog extends StatefulWidget {
  const MtSpindleDialog({
    super.key,
    required this.channelLabels,
    required this.hasStages,
    required this.onRun,
  });

  final List<String> channelLabels;
  final bool hasStages;
  final void Function(Map<String, dynamic> settings) onRun;

  @override
  State<MtSpindleDialog> createState() => _MtSpindleDialogState();
}

class _MtSpindleDialogState extends State<MtSpindleDialog> {
  late String _selectedChannel;
  String _selectedMarker = 'F3';

  // Detection parameters
  double _fmin = 11.0;
  double _fmax = 16.0;
  double _amin = 10.0;
  double _dmin = 0.5;
  double _dmax = 2.0;
  int _q = 95;

  // Stage filtering
  bool _useStageFilter = false;
  final Map<String, bool> _stages = {
    'Wake': false,
    'N1': false,
    'N2': true,
    'N3': true,
    'REM': false,
    'Inconclusive': false,
  };

  @override
  void initState() {
    super.initState();
    _selectedChannel = widget.channelLabels.isNotEmpty
        ? widget.channelLabels.first
        : '';
    _useStageFilter = widget.hasStages;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        children: [
          const Icon(Icons.waves, color: Colors.blue),
          const SizedBox(width: 8),
          const Text('Spindle Detection (MT-Spindle)'),
        ],
      ),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // EEG channel selector
              const Text(
                'EEG Channel',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
              ),
              const SizedBox(height: 6),
              DropdownButtonFormField<String>(
                value: _selectedChannel,
                isExpanded: true,
                decoration: const InputDecoration(
                  isDense: true,
                  border: OutlineInputBorder(),
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 8,
                  ),
                ),
                items: widget.channelLabels.map((ch) {
                  return DropdownMenuItem(
                    value: ch,
                    child: Text(ch, style: const TextStyle(fontSize: 13)),
                  );
                }).toList(),
                onChanged: (v) {
                  if (v != null) setState(() => _selectedChannel = v);
                },
              ),
              const SizedBox(height: 14),

              // Target event marker dropdown
              const Text(
                'Save detections to event marker',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
              ),
              const SizedBox(height: 6),
              DropdownButtonFormField<String>(
                value: _selectedMarker,
                decoration: const InputDecoration(
                  isDense: true,
                  border: OutlineInputBorder(),
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 8,
                  ),
                ),
                items: [
                  const DropdownMenuItem(
                    value: 'Artifact',
                    child: Text('Artifact (A)', style: TextStyle(fontSize: 13)),
                  ),
                  for (var i = 1; i <= 12; i++)
                    DropdownMenuItem(
                      value: 'F$i',
                      child: Text(
                        'Event $i (F$i)',
                        style: const TextStyle(fontSize: 13),
                      ),
                    ),
                ],
                onChanged: (v) {
                  if (v != null) setState(() => _selectedMarker = v);
                },
              ),
              const SizedBox(height: 14),

              // Threshold group
              Card(
                margin: EdgeInsets.zero,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  side: BorderSide(color: Colors.grey.shade300),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Detection Thresholds',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(height: 12),
                      _doubleInputRow(
                        label: 'Min. frequency (fmin):',
                        value: _fmin,
                        suffix: ' Hz',
                        tooltip:
                            'Lower bound of the spindle sigma frequency band (default 11.0 Hz).',
                        onChanged: (v) => setState(() => _fmin = v),
                      ),
                      const SizedBox(height: 10),
                      _doubleInputRow(
                        label: 'Max. frequency (fmax):',
                        value: _fmax,
                        suffix: ' Hz',
                        tooltip:
                            'Upper bound of the spindle sigma frequency band (default 16.0 Hz).',
                        onChanged: (v) => setState(() => _fmax = v),
                      ),
                      const SizedBox(height: 10),
                      _doubleInputRow(
                        label: 'Min. amplitude (Amin):',
                        value: _amin,
                        suffix: ' µV',
                        tooltip:
                            'Minimum peak envelope amplitude of the filtered sigma-band signal (default 10 µV).',
                        onChanged: (v) => setState(() => _amin = v),
                      ),
                      const SizedBox(height: 10),
                      _doubleInputRow(
                        label: 'Min. duration (Dmin):',
                        value: _dmin,
                        suffix: ' s',
                        tooltip:
                            'Minimum allowed duration of a spindle (default 0.5 s).',
                        onChanged: (v) => setState(() => _dmin = v),
                      ),
                      const SizedBox(height: 10),
                      _doubleInputRow(
                        label: 'Max. duration (Dmax):',
                        value: _dmax,
                        suffix: ' s',
                        tooltip:
                            'Maximum allowed duration of a spindle (default 2.0 s).',
                        onChanged: (v) => setState(() => _dmax = v),
                      ),
                      const SizedBox(height: 10),
                      _intInputRow(
                        label: 'Region percentile (q):',
                        value: _q,
                        suffix: ' %',
                        tooltip:
                            'Percentile threshold for candidate-region identification (default 95%).',
                        onChanged: (v) => setState(() => _q = v),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 14),

              // Stage filter
              CheckboxListTile(
                title: const Text(
                  'Keep detections in sleep stages only',
                  style: TextStyle(fontSize: 13),
                ),
                contentPadding: EdgeInsets.zero,
                dense: true,
                value: _useStageFilter,
                onChanged: widget.hasStages
                    ? (v) => setState(() => _useStageFilter = v ?? false)
                    : null,
                subtitle: widget.hasStages
                    ? null
                    : const Text(
                        'No stages scored yet.',
                        style: TextStyle(color: Colors.grey, fontSize: 11),
                      ),
              ),
              if (_useStageFilter)
                Container(
                  padding: const EdgeInsets.only(left: 16),
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    children: _stages.keys.map((stage) {
                      return Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Checkbox(
                            value: _stages[stage],
                            onChanged: (v) {
                              setState(() => _stages[stage] = v ?? false);
                            },
                          ),
                          Text(stage, style: const TextStyle(fontSize: 12)),
                        ],
                      );
                    }).toList(),
                  ),
                ),
              const SizedBox(height: 12),

              // Explanation
              Text(
                'MT-Spindle detects spindles using median-normalized multitaper sigma power '
                'and Hilbert envelope boundary detection.',
                style: TextStyle(color: Colors.grey.shade600, fontSize: 11),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: () {
            if (_selectedChannel.isEmpty) return;
            if (_fmin >= _fmax) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('fmin must be less than fmax.')),
              );
              return;
            }
            if (_dmin >= _dmax) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Dmin must be less than Dmax.')),
              );
              return;
            }

            // Collect selected stages
            List<String>? filteredStages;
            if (_useStageFilter) {
              filteredStages = _stages.entries
                  .where((e) => e.value)
                  .map((e) => e.key)
                  .toList();
              if (filteredStages.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Select at least one stage for filtering.'),
                  ),
                );
                return;
              }
            }

            widget.onRun({
              'channel': _selectedChannel,
              'marker': _selectedMarker,
              'fmin': _fmin,
              'fmax': _fmax,
              'amin': _amin,
              'dmin_s': _dmin,
              'dmax_s': _dmax,
              'q': _q.toDouble(),
              'filter_stages': filteredStages,
            });
            Navigator.of(context).pop();
          },
          child: const Text('OK'),
        ),
      ],
    );
  }

  Widget _doubleInputRow({
    required String label,
    required double value,
    required String suffix,
    required String tooltip,
    required ValueChanged<double> onChanged,
  }) {
    return Row(
      children: [
        Expanded(
          flex: 3,
          child: Row(
            children: [
              Text(label, style: const TextStyle(fontSize: 12)),
              const SizedBox(width: 4),
              Tooltip(
                message: tooltip,
                child: const Icon(
                  Icons.info_outline,
                  size: 14,
                  color: Colors.blue,
                ),
              ),
            ],
          ),
        ),
        SizedBox(
          width: 90,
          height: 32,
          child: TextFormField(
            initialValue: value.toString(),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            style: const TextStyle(fontSize: 12),
            decoration: InputDecoration(
              isDense: true,
              contentPadding: const EdgeInsets.all(8),
              border: const OutlineInputBorder(),
              suffixText: suffix,
            ),
            onChanged: (text) {
              final d = double.tryParse(text);
              if (d != null) onChanged(d);
            },
          ),
        ),
      ],
    );
  }

  Widget _intInputRow({
    required String label,
    required int value,
    required String suffix,
    required String tooltip,
    required ValueChanged<int> onChanged,
  }) {
    return Row(
      children: [
        Expanded(
          flex: 3,
          child: Row(
            children: [
              Text(label, style: const TextStyle(fontSize: 12)),
              const SizedBox(width: 4),
              Tooltip(
                message: tooltip,
                child: const Icon(
                  Icons.info_outline,
                  size: 14,
                  color: Colors.blue,
                ),
              ),
            ],
          ),
        ),
        SizedBox(
          width: 90,
          height: 32,
          child: TextFormField(
            initialValue: value.toString(),
            keyboardType: TextInputType.number,
            style: const TextStyle(fontSize: 12),
            decoration: InputDecoration(
              isDense: true,
              contentPadding: const EdgeInsets.all(8),
              border: const OutlineInputBorder(),
              suffixText: suffix,
            ),
            onChanged: (text) {
              final val = int.tryParse(text);
              if (val != null) onChanged(val);
            },
          ),
        ),
      ],
    );
  }
}

class AutoScoringDialog extends StatefulWidget {
  const AutoScoringDialog({
    super.key,
    required this.channelLabels,
    required this.onRun,
  });

  final List<String> channelLabels;
  final void Function(Map<String, dynamic> settings) onRun;

  @override
  State<AutoScoringDialog> createState() => _AutoScoringDialogState();
}

class _AutoScoringDialogState extends State<AutoScoringDialog> {
  String _algorithm = 'yasa';
  String _correction = 'none';
  double _sleepgptAlpha = 0.1;
  int _sleepgptNgram = 30;

  final Map<String, bool> _eegChannels = {};
  final Map<String, bool> _refChannels = {};
  final Map<String, bool> _eogChannels = {};
  final Map<String, bool> _emgChannels = {};

  @override
  void initState() {
    super.initState();
    for (final ch in widget.channelLabels) {
      final upper = ch.toUpperCase();

      bool isEog =
          upper.contains('EOG') ||
          upper.contains('LOC') ||
          upper.contains('ROC') ||
          upper.contains('E1') ||
          upper.contains('E2');
      bool isEmg =
          upper.contains('EMG') ||
          upper.contains('CHIN') ||
          upper.contains('MYO');
      bool isRef =
          upper == 'M1' ||
          upper == 'M2' ||
          upper == 'A1' ||
          upper == 'A2' ||
          upper == 'REF' ||
          upper.startsWith('REF ');

      bool isEeg = !isEog && !isEmg && !isRef;

      _eegChannels[ch] = isEeg;
      _refChannels[ch] = isRef;
      _eogChannels[ch] = isEog;
      _emgChannels[ch] = isEmg;
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        children: [
          const Icon(Icons.psychology, color: Colors.purple),
          const SizedBox(width: 8),
          const Text('Automated Sleep Scoring'),
        ],
      ),
      content: SizedBox(
        width: 600,
        height: 520,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // Alg & Correction
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Base Scorer Algorithm',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                          ),
                        ),
                        const SizedBox(height: 6),
                        DropdownButtonFormField<String>(
                          value: _algorithm,
                          decoration: const InputDecoration(
                            isDense: true,
                            border: OutlineInputBorder(),
                            contentPadding: EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 8,
                            ),
                          ),
                          items: const [
                            DropdownMenuItem(
                              value: 'yasa',
                              child: Text(
                                'YASA LightGBM Consensus',
                                style: TextStyle(fontSize: 13),
                              ),
                            ),
                            DropdownMenuItem(
                              value: 'usleep',
                              child: Text(
                                'Offline U-Sleep Consensus',
                                style: TextStyle(fontSize: 13),
                              ),
                            ),
                            DropdownMenuItem(
                              value: 'luna',
                              child: Text(
                                'Luna POPS Stager',
                                style: TextStyle(fontSize: 13),
                              ),
                            ),
                            DropdownMenuItem(
                              value: 'gssc',
                              child: Text(
                                'Greifswald Classifier (GSSC)',
                                style: TextStyle(fontSize: 13),
                              ),
                            ),
                            DropdownMenuItem(
                              value: 'tinysleepnet',
                              child: Text(
                                'TinySleepNet (PhysioEx)',
                                style: TextStyle(fontSize: 13),
                              ),
                            ),
                            DropdownMenuItem(
                              value: 'seqsleepnet',
                              child: Text(
                                'SeqSleepNet (PhysioEx)',
                                style: TextStyle(fontSize: 13),
                              ),
                            ),
                            DropdownMenuItem(
                              value: 'sleeptransformer',
                              child: Text(
                                'SleepTransformer (PhysioEx)',
                                style: TextStyle(fontSize: 13),
                              ),
                            ),
                            DropdownMenuItem(
                              value: 'dreamento',
                              child: Text(
                                'Dreamento (YASA-based)',
                                style: TextStyle(fontSize: 13),
                              ),
                            ),
                            DropdownMenuItem(
                              value: 'sleepeegpy',
                              child: Text(
                                'SleepEEGpy (YASA-based)',
                                style: TextStyle(fontSize: 13),
                              ),
                            ),
                          ],
                          onChanged: (v) {
                            if (v != null) setState(() => _algorithm = v);
                          },
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Sequence Correction',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                          ),
                        ),
                        const SizedBox(height: 6),
                        DropdownButtonFormField<String>(
                          value: _correction,
                          decoration: const InputDecoration(
                            isDense: true,
                            border: OutlineInputBorder(),
                            contentPadding: EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 8,
                            ),
                          ),
                          items: const [
                            DropdownMenuItem(
                              value: 'none',
                              child: Text(
                                'None (Raw consensus predictions)',
                                style: TextStyle(fontSize: 13),
                              ),
                            ),
                            DropdownMenuItem(
                              value: 'sleepgpt',
                              child: Text(
                                'SleepGPT Language Model',
                                style: TextStyle(fontSize: 13),
                              ),
                            ),
                          ],
                          onChanged: (v) {
                            if (v != null) setState(() => _correction = v);
                          },
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              if (_correction == 'sleepgpt') ...[
                // SleepGPT specific settings
                Card(
                  margin: EdgeInsets.zero,
                  elevation: 0,
                  color: Colors.purple.shade50,
                  shape: RoundedRectangleBorder(
                    side: BorderSide(color: Colors.purple.shade100),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'SleepGPT Sequence Parameters',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                            color: Colors.purple,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            const Expanded(
                              flex: 3,
                              child: Row(
                                children: [
                                  Text(
                                    'Language model weight (alpha):',
                                    style: TextStyle(fontSize: 12),
                                  ),
                                  SizedBox(width: 4),
                                  Tooltip(
                                    message:
                                        'Interpolation weight for SleepGPT predictions (0.1 = 10% model influence, 90% base stager).',
                                    child: Icon(
                                      Icons.info_outline,
                                      size: 14,
                                      color: Colors.purple,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            SizedBox(
                              width: 90,
                              height: 32,
                              child: TextFormField(
                                initialValue: _sleepgptAlpha.toString(),
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                      decimal: true,
                                    ),
                                style: const TextStyle(fontSize: 12),
                                decoration: const InputDecoration(
                                  isDense: true,
                                  contentPadding: EdgeInsets.all(8),
                                  border: OutlineInputBorder(),
                                ),
                                onChanged: (text) {
                                  final d = double.tryParse(text);
                                  if (d != null && d >= 0.0 && d <= 1.0) {
                                    setState(() => _sleepgptAlpha = d);
                                  }
                                },
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            const Expanded(
                              flex: 3,
                              child: Row(
                                children: [
                                  Text(
                                    'Context sequence length (n-gram):',
                                    style: TextStyle(fontSize: 12),
                                  ),
                                  SizedBox(width: 4),
                                  Tooltip(
                                    message:
                                        'Number of past epochs SleepGPT looks at to predict the next stage transition (default 30).',
                                    child: Icon(
                                      Icons.info_outline,
                                      size: 14,
                                      color: Colors.purple,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            SizedBox(
                              width: 90,
                              height: 32,
                              child: TextFormField(
                                initialValue: _sleepgptNgram.toString(),
                                keyboardType: TextInputType.number,
                                style: const TextStyle(fontSize: 12),
                                decoration: const InputDecoration(
                                  isDense: true,
                                  contentPadding: EdgeInsets.all(8),
                                  border: OutlineInputBorder(),
                                ),
                                onChanged: (text) {
                                  final val = int.tryParse(text);
                                  if (val != null && val > 0) {
                                    setState(() => _sleepgptNgram = val);
                                  }
                                },
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
              ],

              // Channels selection grid
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: _buildChannelSelector(
                      'EEG Signal Channels',
                      _eegChannels,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _buildChannelSelector(
                      'Reference Signals',
                      _refChannels,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: _buildChannelSelector(
                      'EOG Channels (Differential)',
                      _eogChannels,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _buildChannelSelector(
                      'EMG Channels (Differential)',
                      _emgChannels,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              Text(
                'Note: Multi-channel configuration runs the stager across all selected EEG pairs/montages '
                'and takes the ensemble average (consensus).',
                style: TextStyle(
                  color: Colors.grey.shade600,
                  fontSize: 11,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: () {
            final eeg = _eegChannels.entries
                .where((e) => e.value)
                .map((e) => e.key)
                .toList();
            final ref = _refChannels.entries
                .where((e) => e.value)
                .map((e) => e.key)
                .toList();
            final eog = _eogChannels.entries
                .where((e) => e.value)
                .map((e) => e.key)
                .toList();
            final emg = _emgChannels.entries
                .where((e) => e.value)
                .map((e) => e.key)
                .toList();

            if (eeg.isEmpty) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Select at least one EEG channel.'),
                ),
              );
              return;
            }

            widget.onRun({
              'algorithm': _algorithm,
              'sequence_correction': _correction,
              'eeg': eeg,
              'ref': ref,
              'eog': eog,
              'emg': emg,
              'sleepgpt_alpha': _sleepgptAlpha,
              'sleepgpt_ngram': _sleepgptNgram,
            });
            Navigator.of(context).pop();
          },
          child: const Text('Run Scoring'),
        ),
      ],
    );
  }

  Widget _buildChannelSelector(String label, Map<String, bool> channels) {
    final list = channels.keys.toList();
    if (list.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Text(
                label,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            GestureDetector(
              onTap: () {
                setState(() {
                  for (final key in channels.keys) {
                    channels[key] = false;
                  }
                });
              },
              child: const MouseRegion(
                cursor: SystemMouseCursors.click,
                child: Text(
                  'Clear',
                  style: TextStyle(
                    color: Colors.blue,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Container(
          height: 110,
          decoration: BoxDecoration(
            border: Border.all(color: Colors.grey.shade300),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Scrollbar(
            thumbVisibility: true,
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: list.length,
              itemBuilder: (context, index) {
                final ch = list[index];
                return SizedBox(
                  height: 32,
                  child: CheckboxListTile(
                    title: Text(ch, style: const TextStyle(fontSize: 11)),
                    dense: true,
                    visualDensity: VisualDensity.compact,
                    value: channels[ch],
                    contentPadding: const EdgeInsets.symmetric(horizontal: 6),
                    onChanged: (v) {
                      setState(() {
                        channels[ch] = v ?? false;
                      });
                    },
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}

class BatchAutoScoringDialog extends StatefulWidget {
  const BatchAutoScoringDialog({
    super.key,
    required this.files,
    required this.channelLabels,
    required this.onRun,
  });

  final List<String> files;
  final List<String> channelLabels;
  final void Function(Map<String, dynamic> settings) onRun;

  @override
  State<BatchAutoScoringDialog> createState() => _BatchAutoScoringDialogState();
}

class AnalyseNidraDialog extends StatefulWidget {
  const AnalyseNidraDialog({
    super.key,
    required this.channelLabels,
    required this.batchCount,
    required this.onRun,
  });

  final List<String> channelLabels;
  final int batchCount;
  final void Function(List<String> channels, List<String> references) onRun;

  @override
  State<AnalyseNidraDialog> createState() => _AnalyseNidraDialogState();
}

class _AnalyseNidraDialogState extends State<AnalyseNidraDialog> {
  late final Map<String, bool> _channels;
  late final Map<String, bool> _references;

  @override
  void initState() {
    super.initState();
    _channels = {};
    _references = {};
    for (final channel in widget.channelLabels) {
      final upper = channel.toUpperCase();
      final isReference =
          upper == 'A1' ||
          upper == 'A2' ||
          upper == 'M1' ||
          upper == 'M2' ||
          upper.contains('REF');
      final isDefaultEeg = RegExp(r'^(F3|F4|C3|C4|O1|O2)$').hasMatch(upper);
      _channels[channel] = isDefaultEeg;
      _references[channel] = isReference;
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(
        widget.batchCount == 1
            ? 'Analyse current recording'
            : 'Batch analyse ${widget.batchCount} recordings',
      ),
      content: SizedBox(
        width: 620,
        height: 430,
        child: Row(
          children: [
            Expanded(child: _selector('EEG channels', _channels)),
            const SizedBox(width: 12),
            Expanded(child: _selector('Reference channels', _references)),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: () {
            final channels = _channels.entries
                .where((entry) => entry.value)
                .map((entry) => entry.key)
                .toList();
            final references = _references.entries
                .where((entry) => entry.value)
                .map((entry) => entry.key)
                .toList();
            if (channels.isEmpty || references.isEmpty) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text(
                    'Select at least one EEG and one reference channel.',
                  ),
                ),
              );
              return;
            }
            Navigator.of(context).pop();
            widget.onRun(channels, references);
          },
          child: const Text('Run analysis'),
        ),
      ],
    );
  }

  Widget _selector(String title, Map<String, bool> values) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Expanded(
          child: DecoratedBox(
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey.shade300),
            ),
            child: ListView(
              children: [
                for (final channel in values.keys)
                  CheckboxListTile(
                    dense: true,
                    title: Text(channel, style: const TextStyle(fontSize: 12)),
                    value: values[channel],
                    onChanged: (value) {
                      setState(() => values[channel] = value ?? false);
                    },
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _BatchAutoScoringDialogState extends State<BatchAutoScoringDialog> {
  String _algorithm = 'yasa';
  String _correction = 'none';
  double _sleepgptAlpha = 0.1;
  int _sleepgptNgram = 30;
  late final TextEditingController _eegController;
  late final TextEditingController _refController;
  late final TextEditingController _eogController;
  late final TextEditingController _emgController;

  @override
  void initState() {
    super.initState();
    final eeg = <String>[];
    final refs = <String>[];
    final eog = <String>[];
    final emg = <String>[];
    for (final channel in widget.channelLabels) {
      final upper = channel.toUpperCase();
      if (upper.contains('EOG') ||
          upper.contains('LOC') ||
          upper.contains('ROC') ||
          upper.contains('E1') ||
          upper.contains('E2')) {
        eog.add(channel);
      } else if (upper.contains('EMG') ||
          upper.contains('CHIN') ||
          upper.contains('MYO')) {
        emg.add(channel);
      } else if (upper == 'M1' ||
          upper == 'M2' ||
          upper == 'A1' ||
          upper == 'A2' ||
          upper == 'REF' ||
          upper.startsWith('REF ')) {
        refs.add(channel);
      } else {
        eeg.add(channel);
      }
    }
    _eegController = TextEditingController(text: eeg.join(','));
    _refController = TextEditingController(text: refs.join(','));
    _eogController = TextEditingController(text: eog.join(','));
    _emgController = TextEditingController(text: emg.join(','));
  }

  @override
  void dispose() {
    _eegController.dispose();
    _refController.dispose();
    _eogController.dispose();
    _emgController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        children: [
          const Icon(Icons.auto_awesome_motion, color: Colors.purple),
          const SizedBox(width: 8),
          Text('Batch Automated Scoring (${widget.files.length} files)'),
        ],
      ),
      content: SizedBox(
        width: 500,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Scoring will run in the background for each selected file. '
                'The channel choices below are initialized from the first file '
                'and applied to every selected recording.',
                style: TextStyle(color: Colors.grey.shade700, fontSize: 12),
              ),
              const SizedBox(height: 16),
              // Alg Selection
              const Text(
                'Base Scorer Algorithm',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
              ),
              const SizedBox(height: 6),
              DropdownButtonFormField<String>(
                value: _algorithm,
                decoration: const InputDecoration(
                  isDense: true,
                  border: OutlineInputBorder(),
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 8,
                  ),
                ),
                items: const [
                  DropdownMenuItem(
                    value: 'yasa',
                    child: Text(
                      'YASA LightGBM Consensus',
                      style: TextStyle(fontSize: 13),
                    ),
                  ),
                  DropdownMenuItem(
                    value: 'usleep',
                    child: Text(
                      'Offline U-Sleep Consensus',
                      style: TextStyle(fontSize: 13),
                    ),
                  ),
                  DropdownMenuItem(
                    value: 'luna',
                    child: Text(
                      'Luna POPS Stager',
                      style: TextStyle(fontSize: 13),
                    ),
                  ),
                  DropdownMenuItem(
                    value: 'gssc',
                    child: Text(
                      'Greifswald Classifier (GSSC)',
                      style: TextStyle(fontSize: 13),
                    ),
                  ),
                  DropdownMenuItem(
                    value: 'tinysleepnet',
                    child: Text(
                      'TinySleepNet (PhysioEx)',
                      style: TextStyle(fontSize: 13),
                    ),
                  ),
                  DropdownMenuItem(
                    value: 'seqsleepnet',
                    child: Text(
                      'SeqSleepNet (PhysioEx)',
                      style: TextStyle(fontSize: 13),
                    ),
                  ),
                  DropdownMenuItem(
                    value: 'sleeptransformer',
                    child: Text(
                      'SleepTransformer (PhysioEx)',
                      style: TextStyle(fontSize: 13),
                    ),
                  ),
                  DropdownMenuItem(
                    value: 'dreamento',
                    child: Text(
                      'Dreamento (YASA-based)',
                      style: TextStyle(fontSize: 13),
                    ),
                  ),
                  DropdownMenuItem(
                    value: 'sleepeegpy',
                    child: Text(
                      'SleepEEGpy (YASA-based)',
                      style: TextStyle(fontSize: 13),
                    ),
                  ),
                ],
                onChanged: (v) {
                  if (v != null) setState(() => _algorithm = v);
                },
              ),
              const SizedBox(height: 16),
              // Correction Selection
              const Text(
                'Sequence Correction',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
              ),
              const SizedBox(height: 6),
              DropdownButtonFormField<String>(
                value: _correction,
                decoration: const InputDecoration(
                  isDense: true,
                  border: OutlineInputBorder(),
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 8,
                  ),
                ),
                items: const [
                  DropdownMenuItem(
                    value: 'none',
                    child: Text(
                      'None (Raw consensus predictions)',
                      style: TextStyle(fontSize: 13),
                    ),
                  ),
                  DropdownMenuItem(
                    value: 'sleepgpt',
                    child: Text(
                      'SleepGPT Language Model',
                      style: TextStyle(fontSize: 13),
                    ),
                  ),
                ],
                onChanged: (v) {
                  if (v != null) setState(() => _correction = v);
                },
              ),
              const SizedBox(height: 16),

              if (_correction == 'sleepgpt') ...[
                Card(
                  margin: EdgeInsets.zero,
                  elevation: 0,
                  color: Colors.purple.shade50,
                  shape: RoundedRectangleBorder(
                    side: BorderSide(color: Colors.purple.shade100),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'SleepGPT Sequence Parameters',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                            color: Colors.purple,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            const Expanded(
                              flex: 3,
                              child: Text(
                                'Language model weight (alpha):',
                                style: TextStyle(fontSize: 12),
                              ),
                            ),
                            SizedBox(
                              width: 90,
                              height: 32,
                              child: TextFormField(
                                initialValue: _sleepgptAlpha.toString(),
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                      decimal: true,
                                    ),
                                style: const TextStyle(fontSize: 12),
                                decoration: const InputDecoration(
                                  isDense: true,
                                  contentPadding: EdgeInsets.all(8),
                                  border: OutlineInputBorder(),
                                ),
                                onChanged: (text) {
                                  final d = double.tryParse(text);
                                  if (d != null && d >= 0.0 && d <= 1.0) {
                                    setState(() => _sleepgptAlpha = d);
                                  }
                                },
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            const Expanded(
                              flex: 3,
                              child: Text(
                                'Context sequence length (n-gram):',
                                style: TextStyle(fontSize: 12),
                              ),
                            ),
                            SizedBox(
                              width: 90,
                              height: 32,
                              child: TextFormField(
                                initialValue: _sleepgptNgram.toString(),
                                keyboardType: TextInputType.number,
                                style: const TextStyle(fontSize: 12),
                                decoration: const InputDecoration(
                                  isDense: true,
                                  contentPadding: EdgeInsets.all(8),
                                  border: OutlineInputBorder(),
                                ),
                                onChanged: (text) {
                                  final val = int.tryParse(text);
                                  if (val != null && val > 0) {
                                    setState(() => _sleepgptNgram = val);
                                  }
                                },
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 16),
              const Text(
                'Channels applied to every file',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
              ),
              const SizedBox(height: 6),
              Text(
                'Comma-separated channel names. Files missing a selected channel '
                'will report a clear failure in the batch log.',
                style: TextStyle(color: Colors.grey.shade700, fontSize: 11),
              ),
              const SizedBox(height: 8),
              _batchChannelField('EEG channels', _eegController),
              _batchChannelField('Reference channels', _refController),
              _batchChannelField('EOG channels', _eogController),
              _batchChannelField('EMG channels', _emgController),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: () {
            List<String> channels(TextEditingController controller) =>
                controller.text
                    .split(',')
                    .map((value) => value.trim())
                    .where((value) => value.isNotEmpty)
                    .toList();
            final eeg = channels(_eegController);
            if (eeg.isEmpty) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Enter at least one EEG channel.'),
                ),
              );
              return;
            }
            widget.onRun({
              'algorithm': _algorithm,
              'sequence_correction': _correction,
              'sleepgpt_alpha': _sleepgptAlpha,
              'sleepgpt_ngram': _sleepgptNgram,
              'eeg': eeg,
              'ref': channels(_refController),
              'eog': channels(_eogController),
              'emg': channels(_emgController),
            });
            Navigator.of(context).pop();
          },
          child: const Text('Run Batch Scoring'),
        ),
      ],
    );
  }

  Widget _batchChannelField(String label, TextEditingController controller) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: TextField(
        controller: controller,
        decoration: InputDecoration(
          labelText: label,
          isDense: true,
          border: const OutlineInputBorder(),
        ),
      ),
    );
  }
}
