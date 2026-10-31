/// Sumber izin pengali kecepatan waktu (2×–10×).
///
/// Disiapkan untuk monetisasi di masa depan (micro-transaction atau
/// rewarded ads). Simulation core hanya bertanya "pengali mana yang boleh";
/// cara mendapatkannya bukan urusan core.
abstract interface class SpeedEntitlementProvider {
  Set<int> get allowedMultipliers;
}

/// Implementasi saat ini: hanya 1×. Belum ada SDK iklan/billing.
class FreeSpeedEntitlement implements SpeedEntitlementProvider {
  const FreeSpeedEntitlement();

  @override
  Set<int> get allowedMultipliers => const {1};
}
