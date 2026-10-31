import 'frame_stats.dart';

/// Benchmark tanpa sentuhan layar: aktif bila app di-build dengan
/// `--dart-define=AUTO_BENCH=true`. Hasil dicetak ke log sebagai baris `BENCH`
/// sehingga bisa diambil lewat `adb logcat`.
const autoBenchEnabled = bool.fromEnvironment('AUTO_BENCH');

const autoBenchVehicleCounts = [1, 10, 30];

Future<List<BenchmarkResult>> runAutoBenchmark({
  required String engine,
  required FrameStats stats,
  required int loadTimeMs,
  required Future<void> Function(int count) setVehicles,
  Duration warmup = const Duration(seconds: 5),
  Duration measure = const Duration(seconds: 30),
}) async {
  // ignore: avoid_print
  print('BENCH load,$engine,$loadTimeMs');
  // ignore: avoid_print
  print('BENCH ${BenchmarkResult.csvHeader}');
  final results = <BenchmarkResult>[];
  for (final count in autoBenchVehicleCounts) {
    await setVehicles(count);
    await Future<void>.delayed(warmup);
    stats.startRecording();
    await Future<void>.delayed(measure);
    final r = stats.stopRecording(engine: engine, vehicles: count);
    results.add(r);
    // ignore: avoid_print
    print('BENCH ${r.toCsvRow()}');
  }
  // ignore: avoid_print
  print('BENCH done,$engine');
  return results;
}
