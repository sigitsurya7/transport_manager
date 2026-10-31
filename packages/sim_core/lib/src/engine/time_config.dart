/// Konfigurasi waktu simulasi.
///
/// Semua waktu simulasi disimpan sebagai detik game (`int`).
class TimeConfig {
  const TimeConfig({
    this.timeScale = 10,
    this.maxOfflineCatchUp = const Duration(hours: 48),
  }) : assert(timeScale > 0);

  /// Detik game per detik nyata.
  ///
  /// `10` berarti 1 menit nyata = 10 menit game, sehingga perjalanan
  /// Jakarta → Bandung via tol (±2 jam game) memakan ±12 menit nyata.
  final int timeScale;

  /// Batas waktu nyata yang diproses saat pemain kembali setelah offline.
  final Duration maxOfflineCatchUp;
}
