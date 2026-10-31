/// Tarif tol per km per golongan kendaraan (rupiah).
///
/// Nilai default adalah **pendekatan** untuk spike. Tarif per ruas yang
/// sebenarnya akan dimuat dari map pack bila tersedia.
class TollTariff {
  const TollTariff(this.rupiahPerKm);

  const TollTariff.approximate()
      : rupiahPerKm = const {1: 1000, 2: 1500, 3: 1500, 4: 2000, 5: 2000};

  /// Kunci: golongan tol (1–5).
  final Map<int, int> rupiahPerKm;

  int cost(double lengthM, int golongan) {
    final rate = rupiahPerKm[golongan];
    if (rate == null) throw ArgumentError.value(golongan, 'golongan');
    return (lengthM / 1000 * rate).round();
  }
}
