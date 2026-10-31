/// Kontrak berulang (`economy.json` → `agreement`).
class AgreementConfig {
  const AgreementConfig({
    this.intervalDays = const [1, 2, 3, 7],
    this.runsMin = 4,
    this.runsMax = 12,
    this.payDiscountPct = 10,
    this.retryS = 1800,
    this.graceS = 10800,
    this.maxMissed = 3,
    this.cancelPenaltyPct = 100,
  });

  factory AgreementConfig.fromJson(Map<String, dynamic>? j) {
    if (j == null) return const AgreementConfig();
    int v(String k) => (j[k] as num).toInt();
    return AgreementConfig(
      intervalDays: (j['interval_days'] as List).cast<num>().map((n) => n.toInt()).toList(),
      runsMin: v('runs_min'),
      runsMax: v('runs_max'),
      payDiscountPct: v('pay_discount_pct'),
      retryS: v('retry_s'),
      graceS: v('grace_s'),
      maxMissed: v('max_missed'),
      cancelPenaltyPct: v('cancel_penalty_pct'),
    );
  }

  final List<int> intervalDays;
  final int runsMin;
  final int runsMax;

  /// Bayaran per pengiriman lebih murah dari kontrak sekali jalan (pendapatan pasti).
  final int payDiscountPct;

  /// Bila kendaraan/sopir belum siap saat jadwal: coba lagi tiap [retryS] …
  final int retryS;

  /// … sampai [graceS] setelah jadwal; lewat itu pengiriman dianggap terlewat.
  final int graceS;
  final int maxMissed;

  /// Denda memutus kontrak = persen bayaran satu pengiriman.
  final int cancelPenaltyPct;
}

/// Penyusutan & pasar kendaraan (`economy.json` → `vehicle_market`).
class VehicleMarketConfig {
  const VehicleMarketConfig({
    this.startYear = 2026,
    this.firstYearDropPct = 15,
    this.depreciationPerYearPct = 10,
    this.odometerLifeKm = 900000,
    this.conditionWeightPct = 40,
    this.floorPct = 10,
    this.dealerBuyPct = 85,
    this.usedMarkupPct = 10,
    this.usedListings = 4,
    this.usedAgeMin = 1,
    this.usedAgeMax = 12,
    this.usedKmPerYearMin = 20000,
    this.usedKmPerYearMax = 60000,
    this.usedConditionMin = 0.45,
    this.usedConditionMax = 0.95,
  });

  factory VehicleMarketConfig.fromJson(Map<String, dynamic>? j) {
    if (j == null) return const VehicleMarketConfig();
    int v(String k) => (j[k] as num).toInt();
    double d(String k) => (j[k] as num).toDouble();
    return VehicleMarketConfig(
      startYear: v('start_year'),
      firstYearDropPct: v('first_year_drop_pct'),
      depreciationPerYearPct: v('depreciation_per_year_pct'),
      odometerLifeKm: v('odometer_life_km'),
      conditionWeightPct: v('condition_weight_pct'),
      floorPct: v('floor_pct'),
      dealerBuyPct: v('dealer_buy_pct'),
      usedMarkupPct: v('used_markup_pct'),
      usedListings: v('used_listings'),
      usedAgeMin: v('used_age_min'),
      usedAgeMax: v('used_age_max'),
      usedKmPerYearMin: v('used_km_per_year_min'),
      usedKmPerYearMax: v('used_km_per_year_max'),
      usedConditionMin: d('used_condition_min'),
      usedConditionMax: d('used_condition_max'),
    );
  }

  /// Hari 1 game = 1 Januari tahun ini.
  final int startYear;
  final int firstYearDropPct;
  final int depreciationPerYearPct;
  final int odometerLifeKm;
  final int conditionWeightPct;
  final int floorPct;
  final int dealerBuyPct;
  final int usedMarkupPct;
  final int usedListings;
  final int usedAgeMin;
  final int usedAgeMax;
  final int usedKmPerYearMin;
  final int usedKmPerYearMax;
  final double usedConditionMin;
  final double usedConditionMax;
}

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
    this.storeMarkupPct = 15,
    this.restockDiscountPct = 8,
    this.agreement = const AgreementConfig(),
    this.vehicleMarket = const VehicleMarketConfig(),
  });

  factory EconomyConfig.fromJson(Map<String, dynamic> j) {
    final c = j['contract'] as Map<String, dynamic>;
    final g = j['goods'] as Map<String, dynamic>?;
    return EconomyConfig(
      startingCashIdr: (j['starting_cash_idr'] as num).toInt(),
      fuelPriceIdrPerL: (j['fuel_price_idr_per_l'] as num).toInt(),
      contractBaseFeeIdr: (c['base_fee_idr'] as num).toInt(),
      contractPerKmIdr: (c['per_km_idr'] as num).toInt(),
      contractPerTonKmIdr: (c['per_ton_km_idr'] as num).toInt(),
      deadlineSlack: (c['deadline_slack'] as num).toDouble(),
      deadlineMinS: (c['deadline_min_s'] as num).toInt(),
      latePenaltyPerHourPct: (c['late_penalty_per_hour_pct'] as num).toInt(),
      storeMarkupPct: (g?['store_markup_pct'] as num?)?.toInt() ?? 15,
      restockDiscountPct: (g?['restock_discount_pct'] as num?)?.toInt() ?? 8,
      agreement: AgreementConfig.fromJson(j['agreement'] as Map<String, dynamic>?),
      vehicleMarket: VehicleMarketConfig.fromJson(j['vehicle_market'] as Map<String, dynamic>?),
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

  /// Harga jual barang ke toko = harga dasar × (1 + markup).
  final int storeMarkupPct;

  /// Isi stok gudang = harga dasar × (1 − diskon grosir).
  final int restockDiscountPct;

  final AgreementConfig agreement;
  final VehicleMarketConfig vehicleMarket;

  int fuelCostIdr(double distanceM, double litresPer100Km) =>
      (distanceM / 1000 * litresPer100Km / 100 * fuelPriceIdrPerL).round();

  /// Ongkos kirim untuk [routeKm] km dan [weightKg] kg.
  int deliveryFeeIdr(double routeKm, int weightKg) =>
      contractBaseFeeIdr +
      (contractPerKmIdr * routeKm).round() +
      (contractPerTonKmIdr * weightKg / 1000 * routeKm).round();

  int storePrice(int basePriceIdr) => (basePriceIdr * (100 + storeMarkupPct) / 100).round();
  int restockPrice(int basePriceIdr) => (basePriceIdr * (100 - restockDiscountPct) / 100).round();
}
