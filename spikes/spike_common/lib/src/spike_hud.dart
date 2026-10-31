import 'dart:async';

import 'package:flutter/material.dart';

import 'frame_stats.dart';

/// HUD bersama: fps langsung, jumlah kendaraan, tombol benchmark 30 detik.
class SpikeHud extends StatefulWidget {
  const SpikeHud({
    super.key,
    required this.engine,
    required this.stats,
    required this.vehicles,
    required this.onVehiclesChanged,
    this.loadTimeMs,
  });

  final String engine;
  final FrameStats stats;
  final int vehicles;
  final ValueChanged<int> onVehiclesChanged;
  final int? loadTimeMs;

  @override
  State<SpikeHud> createState() => _SpikeHudState();
}

class _SpikeHudState extends State<SpikeHud> {
  Timer? _refresh;
  bool _running = false;
  final List<BenchmarkResult> _results = [];

  @override
  void initState() {
    super.initState();
    _refresh = Timer.periodic(const Duration(milliseconds: 500), (_) => setState(() {}));
  }

  @override
  void dispose() {
    _refresh?.cancel();
    super.dispose();
  }

  Future<void> _benchmark() async {
    setState(() => _running = true);
    widget.stats.startRecording();
    await Future<void>.delayed(const Duration(seconds: 30));
    final r = widget.stats.stopRecording(engine: widget.engine, vehicles: widget.vehicles);
    // ignore: avoid_print
    print('BENCH ${BenchmarkResult.csvHeader}\nBENCH ${r.toCsvRow()}');
    if (mounted) {
      setState(() {
        _running = false;
        _results.add(r);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme.bodySmall!.copyWith(color: Colors.white);
    return SafeArea(
      child: Align(
        alignment: Alignment.topLeft,
        child: Container(
          margin: const EdgeInsets.all(12),
          padding: const EdgeInsets.all(12),
          width: 260,
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.6),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(widget.engine, style: text.copyWith(fontWeight: FontWeight.bold)),
              Text('FPS: ${widget.stats.liveFps.toStringAsFixed(0)}', style: text),
              if (widget.loadTimeMs != null) Text('Load: ${widget.loadTimeMs} ms', style: text),
              Text('Kendaraan: ${widget.vehicles}', style: text),
              Slider(
                value: widget.vehicles.toDouble(),
                min: 1,
                max: 30,
                divisions: 29,
                onChanged: _running ? null : (v) => widget.onVehiclesChanged(v.round()),
              ),
              FilledButton(
                onPressed: _running ? null : _benchmark,
                child: Text(_running ? 'Mengukur 30 detik…' : 'Benchmark 30 detik'),
              ),
              for (final r in _results)
                Text(
                  '${r.vehicles} kend: ${r.avgFps.toStringAsFixed(1)} fps, '
                  'p90 ${r.p90FrameMs.toStringAsFixed(1)} ms, jank ${r.jankPercent.toStringAsFixed(0)}%',
                  style: text,
                ),
            ],
          ),
        ),
      ),
    );
  }
}
