/// Parameter ekonomi (`content/economy.json`). Uang dalam rupiah integer.
class EconomyConfig {
  const EconomyConfig({
    required this.startingCashIdr,
    required this.fuelPriceIdrPerL,
    required this.contractBaseFeeIdr,
    required this.contractPerKmIdr,
    required this.contractPerTonKmIdr,
    required this.deadlineSlack,
    required this.deadlineMinS,
    required this.latePenaltyPerHourPct,
  });

  factory EconomyConfig.fromJson(Map<String, dynamic> j) {
    final c = j['contract'] as Map<String, dynamic>;
    return EconomyConfig(
      startingCashIdr: (j['starting_cash_idr'] as num).toInt(),
      fuelPriceIdrPerL: (j['fuel_price_idr_per_l'] as num).toInt(),
      contractBaseFeeIdr: (c['base_fee_idr'] as num).toInt(),
      contractPerKmIdr: (c['per_km_idr'] as num).toInt(),
      contractPerTonKmIdr: (c['per_ton_km_idr'] as num).toInt(),
      deadlineSlack: (c['deadline_slack'] as num).toDouble(),
      deadlineMinS: (c['deadline_min_s'] as num).toInt(),
      latePenaltyPerHourPct: (c['late_penalty_per_hour_pct'] as num).toInt(),
    );
  }

  final int startingCashIdr;
  final int fuelPriceIdrPerL;
  final int contractBaseFeeIdr;
  final int contractPerKmIdr;
  final int contractPerTonKmIdr;

  /// Tenggat = estimasi durasi pengantaran × slack (minimal [deadlineMinS]).
  final double deadlineSlack;
  final int deadlineMinS;
  final int latePenaltyPerHourPct;

  int fuelCostIdr(double distanceM, double litresPer100Km) =>
      (distanceM / 1000 * litresPer100Km / 100 * fuelPriceIdrPerL).round();
}
