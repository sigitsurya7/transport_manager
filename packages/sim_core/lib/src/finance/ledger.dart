/// Akun buku besar. Laporan laba rugi Tahap 4 disusun dari entri ini.
enum LedgerAccount {
  openingBalance,
  contractRevenue,
  fuel,
  toll,
  wages,
  vehiclePurchase,
  facilityUpgrade,

  /// Dana tambahan dari mode pengembang (build DEV_TOOLS); bukan pendapatan.
  devAdjustment,
}

class LedgerEntry {
  const LedgerEntry({
    required this.time,
    required this.account,
    required this.amountIdr,
    required this.ref,
  });

  final int time;
  final LedgerAccount account;

  /// Positif = uang masuk, negatif = uang keluar.
  final int amountIdr;

  /// Referensi sumber, mis. `trip:3`.
  final String ref;

  Map<String, dynamic> toJson() =>
      {'t': time, 'account': account.name, 'amount_idr': amountIdr, 'ref': ref};

  factory LedgerEntry.fromJson(Map<String, dynamic> j) => LedgerEntry(
        time: j['t'] as int,
        account: LedgerAccount.values.byName(j['account'] as String),
        amountIdr: j['amount_idr'] as int,
        ref: j['ref'] as String,
      );
}

/// Kas perusahaan = jumlah semua entri; tidak ada kas yang berubah tanpa entri.
class Ledger {
  Ledger([Iterable<LedgerEntry> entries = const []]) {
    entries.forEach(post);
  }

  final List<LedgerEntry> _entries = [];
  int _cash = 0;

  int get cashIdr => _cash;
  List<LedgerEntry> get entries => List.unmodifiable(_entries);

  void post(LedgerEntry e) {
    _entries.add(e);
    _cash += e.amountIdr;
  }

  int total(LedgerAccount account, {String? ref}) => _entries
      .where((e) => e.account == account && (ref == null || e.ref == ref))
      .fold(0, (sum, e) => sum + e.amountIdr);

  List<Map<String, dynamic>> toJson() => [for (final e in _entries) e.toJson()];

  factory Ledger.fromJson(List<dynamic> json) =>
      Ledger([for (final e in json) LedgerEntry.fromJson(e as Map<String, dynamic>)]);
}
