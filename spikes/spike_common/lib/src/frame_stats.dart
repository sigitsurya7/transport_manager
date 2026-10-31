import 'package:flutter/scheduler.dart';

/// Ringkasan benchmark.
class BenchmarkResult {
  const BenchmarkResult({
    required this.engine,
    required this.vehicles,
    required this.frames,
    required this.seconds,
    required this.avgFps,
    required this.p90FrameMs,
    required this.p99FrameMs,
    required this.jankPercent,
  });

  final String engine;
  final int vehicles;
  final int frames;
  final double seconds;
  final double avgFps;
  final double p90FrameMs;
  final double p99FrameMs;

  /// Persentase frame di atas 33,3 ms (di bawah 30 fps).
  final double jankPercent;

  String toCsvRow() => [
        engine,
        vehicles,
        frames,
        seconds.toStringAsFixed(1),
        avgFps.toStringAsFixed(1),
        p90FrameMs.toStringAsFixed(1),
        p99FrameMs.toStringAsFixed(1),
        jankPercent.toStringAsFixed(1),
      ].join(',');

  static const csvHeader = 'engine,vehicles,frames,seconds,avg_fps,p90_ms,p99_ms,jank_pct';
}

/// Mengukur waktu frame dari `FrameTiming` (build + raster) Flutter.
class FrameStats {
  final List<double> _totalMs = [];
  bool _recording = false;
  DateTime? _start;
  double _liveFps = 0;
  DateTime _liveWindowStart = DateTime.now();
  int _liveFrames = 0;

  double get liveFps => _liveFps;

  void attach() => SchedulerBinding.instance.addTimingsCallback(_onTimings);
  void detach() => SchedulerBinding.instance.removeTimingsCallback(_onTimings);

  void startRecording() {
    _totalMs.clear();
    _start = DateTime.now();
    _recording = true;
  }

  BenchmarkResult stopRecording({required String engine, required int vehicles}) {
    _recording = false;
    final seconds = DateTime.now().difference(_start!).inMilliseconds / 1000;
    final sorted = List.of(_totalMs)..sort();
    double pct(double p) =>
        sorted.isEmpty ? 0 : sorted[((sorted.length - 1) * p).round()];
    final jank = sorted.where((ms) => ms > 1000 / 30).length;
    return BenchmarkResult(
      engine: engine,
      vehicles: vehicles,
      frames: sorted.length,
      seconds: seconds,
      avgFps: seconds == 0 ? 0 : sorted.length / seconds,
      p90FrameMs: pct(0.9),
      p99FrameMs: pct(0.99),
      jankPercent: sorted.isEmpty ? 0 : jank * 100 / sorted.length,
    );
  }

  void _onTimings(List<FrameTiming> timings) {
    for (final t in timings) {
      if (_recording) _totalMs.add(t.totalSpan.inMicroseconds / 1000);
    }
    _liveFrames += timings.length;
    final now = DateTime.now();
    final elapsed = now.difference(_liveWindowStart).inMilliseconds;
    if (elapsed >= 1000) {
      _liveFps = _liveFrames * 1000 / elapsed;
      _liveFrames = 0;
      _liveWindowStart = now;
    }
  }
}
