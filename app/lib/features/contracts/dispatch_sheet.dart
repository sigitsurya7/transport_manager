import 'package:flutter/material.dart';
import 'package:sim_core/sim_core.dart';

import '../../widgets/game_icons.dart';
import '../../app/theme.dart';
import '../../game/game_session.dart';
import '../../util/format.dart';
import '../fleet/staff_section.dart' show formatSkill;

/// Lembar dispatch kontrak sekali jalan / isi stok gudang.
Future<void> showDispatchSheet(BuildContext context, GameSession session, Contract contract) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: AppColors.surface,
      builder: (_) => _DispatchSheet(session: session, contract: contract),
    );

/// Lembar menerima kontrak berulang (pengiriman pertama langsung berangkat).
Future<void> showAgreementSheet(BuildContext context, GameSession session, Agreement agreement) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: AppColors.surface,
      builder: (_) => _DispatchSheet(session: session, agreement: agreement),
    );

const _problemText = {
  DispatchProblem.contractNotOffered: 'Kontrak sudah tidak tersedia.',
  DispatchProblem.vehicleBusy: 'Kendaraan sedang bertugas.',
  DispatchProblem.vehicleInWorkshop: 'Kendaraan sedang di bengkel.',
  DispatchProblem.driverBusy: 'Sopir sedang bertugas.',
  DispatchProblem.driverNeedsRest: 'Sopir mencapai batas jam mengemudi dan wajib istirahat.',
  DispatchProblem.vehicleClassTooSmall: 'Kendaraan terlalu kecil untuk jangkauan kontrak ini.',
  DispatchProblem.overCapacity: 'Muatan melebihi kapasitas kendaraan.',
  DispatchProblem.cargoIncompatible: 'Bodi kendaraan tidak cocok untuk jenis barang ini.',
  DispatchProblem.noRoute: 'Tidak ada rute jalan untuk kendaraan ini.',
  DispatchProblem.insufficientCash: 'Kas tidak cukup untuk membeli barang di supplier.',
  DispatchProblem.warehouseFull: 'Ruang gudang tidak cukup.',
  DispatchProblem.wrongVehicle: 'Kontrak berulang ini memakai kendaraan lain.',
};

String describeLines(GameSession session, List<OrderLine> lines) => lines.map((l) {
  final c = session.data.content.cargoTypes[l.cargoId]!;
  return '${l.units} ${c.unit} ${c.name}';
}).join(', ');

/// Jenis pekerjaan untuk ditampilkan (label & warna).
(String, Color) kindLabel(ContractKind kind) => switch (kind) {
  ContractKind.haul => ('Jasa angkut', AppColors.routeOut),
  ContractKind.storeOrder => ('Pesanan toko', AppColors.positive),
  ContractKind.restock => ('Isi stok gudang', AppColors.routeBack),
  ContractKind.legacy => ('Pengiriman', AppColors.textMuted),
};

class _DispatchSheet extends StatefulWidget {
  const _DispatchSheet({required this.session, this.contract, this.agreement})
    : assert((contract == null) != (agreement == null));

  final GameSession session;
  final Contract? contract;
  final Agreement? agreement;

  @override
  State<_DispatchSheet> createState() => _DispatchSheetState();
}

class _DispatchSheetState extends State<_DispatchSheet> {
  late Vehicle _vehicle = widget.session.world.vehicles.values.firstWhere(
    (v) => v.isAvailable,
    orElse: () => widget.session.world.vehicles.values.first,
  );
  late Driver _driver = widget.session.world.drivers.values.firstWhere(
    (d) => d.isAvailable && widget.session.world.driverFatigue(d.id) < 1,
    orElse: () => widget.session.world.drivers.values.first,
  );
  RouteMode? _mode;
  bool _dispatched = false;

  @override
  void dispose() {
    // Rencana isi stok yang tidak jadi diberangkatkan dibuang.
    final c = widget.contract;
    if (!_dispatched && c != null && c.kind == ContractKind.restock) widget.session.discardRestock(c);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final session = widget.session;
    final contract = widget.contract;
    final agreement = widget.agreement;
    final check = agreement != null
        ? session.checkAgreement(agreement, _vehicle, _driver)
        : session.check(contract ?? (throw StateError('kontrak kosong')), _vehicle, _driver);
    final quotes = [check.viaToll, check.nonToll].whereType<DispatchQuote>().toList();
    // Rute "tol" yang ternyata tidak melewati tol sama dengan non-tol: tampilkan satu saja.
    if (check.viaToll != null && !check.viaToll!.usesToll) quotes.remove(check.viaToll);
    final mode = _mode ?? (quotes.isEmpty ? null : _best(quotes).mode);

    final kind = contract?.kind ?? ContractKind.haul;
    final (label, color) = agreement != null ? ('Kontrak berulang', AppColors.accent) : kindLabel(kind);
    final customer = agreement?.customer ?? contract?.customer ?? '';
    final lines = agreement?.lines ?? contract?.lines ?? const <OrderLine>[];
    final weight = agreement?.weightKg ?? contract?.weightKg ?? 0;
    final pickupName = agreement != null ? agreement.pickupName : contract?.pickupName;
    const muted = TextStyle(color: AppColors.textMuted);

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label.toUpperCase(),
                style: TextStyle(color: color, fontWeight: FontWeight.w800, letterSpacing: 1.1, fontSize: 12)),
            Text(customer, style: Theme.of(context).textTheme.titleLarge!.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            Text('${describeLines(session, lines)} · ${formatKg(weight)}', style: muted),
            if (pickupName != null && kind != ContractKind.storeOrder)
              Text(
                kind == ContractKind.restock ? 'Beli di $pickupName → gudang depot' : 'Jemput di $pickupName → antar ke $customer',
                style: muted,
              ),
            if (agreement != null) ...[
              Text(
                'Tiap ${agreement.intervalDays} hari × ${agreement.runsTotal} pengiriman · '
                '${formatRupiah(agreement.payPerRunIdr)} per pengiriman',
                style: muted,
              ),
              Text('Kendaraan yang dipilih dipakai untuk semua pengiriman.', style: muted),
            ] else if (contract != null && kind != ContractKind.restock) ...[
              Text(
                'Bayaran ${formatRupiah(contract.payIdr)}'
                '${contract.goodsValueIdr > 0 ? ' (barang ${formatRupiah(contract.goodsValueIdr)})' : ''}',
                style: muted,
              ),
              Text('Penalti telat ${formatRupiah(contract.latePenaltyPerHourIdr)} per jam', style: muted),
            ],
            const SizedBox(height: 16),
            _Picker<Vehicle>(
              icon: VehicleIcon(_vehicle.model.visual, width: 40),
              items: session.world.vehicles.values.toList(),
              value: _vehicle,
              label: (v) => '${v.model.name} · ${formatKg(v.model.payloadKg)}',
              available: (v) => v.isAvailable,
              onChanged: (v) => setState(() => _vehicle = v),
            ),
            const SizedBox(height: 8),
            _Picker<Driver>(
              icon: const GlyphIcon(GameGlyph.driver, size: 22),
              items: session.world.drivers.values.toList(),
              value: _driver,
              label: (d) => '${d.name} · skill ${formatSkill(d.skill)}',
              available: (d) => d.isAvailable,
              note: (d) => session.world.driverFatigue(d.id) >= 1 ? ' · wajib istirahat' : null,
              onChanged: (d) => setState(() => _driver = d),
            ),
            const SizedBox(height: 16),
            for (final p in check.problems)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  children: [
                    const Icon(Icons.error_outline_rounded, color: AppColors.negative, size: 20),
                    const SizedBox(width: 8),
                    Expanded(child: Text(_problemText[p] ?? p.name)),
                  ],
                ),
              ),
            if (quotes.isNotEmpty) ...[
              if (quotes.first.fulfillment case final f?) _FulfillmentCard(session: session, fulfillment: f),
              const Text(
                'PILIH RUTE',
                style: TextStyle(color: AppColors.textMuted, fontWeight: FontWeight.w700, letterSpacing: 1.2, fontSize: 12),
              ),
              const SizedBox(height: 8),
              for (final q in quotes)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _QuoteCard(
                    quote: q,
                    restock: kind == ContractKind.restock,
                    tiredAt: session.data.content.employees.driver.tiredAt,
                    timeScale: session.timeScale,
                    selected: q.mode == mode,
                    onTap: () => setState(() => _mode = q.mode),
                  ),
                ),
            ],
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: check.canDispatch && mode != null
                    ? () {
                        _dispatched = true;
                        if (agreement != null) {
                          session.acceptAgreement(agreement, _vehicle, _driver, mode);
                        } else if (contract != null) {
                          session.dispatch(contract, _vehicle, _driver, mode);
                        }
                        Navigator.pop(context);
                      }
                    : null,
                icon: const Icon(Icons.play_arrow_rounded),
                label: Text(switch ((agreement != null, kind)) {
                  (true, _) => 'Terima kontrak & kirim pertama',
                  (false, ContractKind.restock) => 'Berangkat beli barang',
                  _ => 'Terima & berangkatkan',
                }),
              ),
            ),
          ],
        ),
      ),
    );
  }

  DispatchQuote _best(List<DispatchQuote> quotes) => quotes.reduce((a, b) => a.profitIdr >= b.profitIdr ? a : b);
}

/// Sumber barang pesanan toko: dari gudang vs dibeli di supplier.
class _FulfillmentCard extends StatelessWidget {
  const _FulfillmentCard({required this.session, required this.fulfillment});

  final GameSession session;
  final Fulfillment fulfillment;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    margin: const EdgeInsets.only(bottom: 12),
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(color: AppColors.surfaceHigh, borderRadius: BorderRadius.circular(12)),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const GlyphIcon(GameGlyph.warehouse, size: 18),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                fulfillment.usesStock ? 'Dari gudang: ${describeLines(session, fulfillment.fromStock)}' : 'Gudang belum punya barang ini',
              ),
            ),
          ],
        ),
        if (fulfillment.needsPickup) ...[
          const SizedBox(height: 6),
          Row(
            children: [
              const GlyphIcon(GameGlyph.store, size: 18),
              const SizedBox(width: 6),
              Expanded(child: Text('Beli di supplier: ${describeLines(session, fulfillment.toBuy)}')),
            ],
          ),
        ],
      ],
    ),
  );
}

class _QuoteCard extends StatelessWidget {
  const _QuoteCard({
    required this.quote,
    required this.restock,
    required this.tiredAt,
    required this.timeScale,
    required this.selected,
    required this.onTap,
  });

  final DispatchQuote quote;
  final bool restock;
  final double tiredAt;
  final int timeScale;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final usesToll = quote.usesToll;
    final total = quote.completionEta - quote.dispatchAt;
    Widget line(String label, String value, {Color? color, bool bold = false}) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(child: Text(label, style: const TextStyle(color: AppColors.textMuted))),
          Text(value, style: TextStyle(color: color, fontWeight: bold ? FontWeight.w800 : FontWeight.w500)),
        ],
      ),
    );
    return Material(
      color: selected ? AppColors.accent.withValues(alpha: 0.10) : AppColors.surfaceHigh,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: selected ? AppColors.accent : AppColors.outline, width: selected ? 1.6 : 1),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            children: [
              Row(
                children: [
                  Icon(
                    usesToll ? Icons.add_road_rounded : Icons.alt_route_rounded,
                    color: usesToll ? AppColors.toll : AppColors.routeOut,
                  ),
                  const SizedBox(width: 8),
                  Text(usesToll ? 'Via tol' : 'Non-tol', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                  const Spacer(),
                  if (!restock && !quote.onTime)
                    const Text(
                      'TERLAMBAT',
                      style: TextStyle(color: AppColors.negative, fontWeight: FontWeight.w800, fontSize: 12),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              line('Jarak total', formatKm(quote.distanceM)),
              if (quote.pickupRoute != null)
                line('Jemput di supplier', formatGameTime(
                  quote.dispatchAt + quote.beforeDepartureS + quote.pickupS,
                  fromSimSeconds: quote.dispatchAt,
                )),
              if (!restock) ...[
                line(
                  'Tiba di tujuan',
                  formatGameTime(quote.deliveryEta, fromSimSeconds: quote.dispatchAt),
                  color: quote.onTime ? null : AppColors.negative,
                ),
                line('Tenggat', formatGameTime(quote.deadline, fromSimSeconds: quote.dispatchAt)),
              ],
              line('Selesai total', '${formatDuration(total)} (≈ ${formatRealDuration(total, timeScale)} nyata)'),
              line(
                'Kelelahan sopir saat kembali',
                '${(quote.fatigueAfter * 100).round()}%',
                color: quote.fatigueAfter >= 1
                    ? AppColors.negative
                    : quote.fatigueAfter >= tiredAt
                    ? AppColors.accent
                    : null,
              ),
              const Divider(height: 16),
              if (!restock) line('Pendapatan', formatRupiah(quote.revenueIdr)),
              if (quote.purchaseIdr > 0) line(restock ? 'Beli barang (grosir)' : 'Beli barang di supplier', '-${formatRupiah(quote.purchaseIdr)}'),
              line('BBM', '-${formatRupiah(quote.fuelIdr)}'),
              if (quote.tollIdr > 0) line('Tol', '-${formatRupiah(quote.tollIdr)}'),
              line(
                restock ? 'Total biaya' : 'Untung',
                formatRupiah(restock ? -quote.costIdr : quote.profitIdr),
                color: restock ? null : (quote.profitIdr >= 0 ? AppColors.positive : AppColors.negative),
                bold: true,
              ),
              if (quote.stockValueIdr > 0)
                line('Memakai stok senilai', formatRupiah(quote.stockValueIdr), color: AppColors.textMuted),
            ],
          ),
        ),
      ),
    );
  }
}

class _Picker<T> extends StatelessWidget {
  const _Picker({
    required this.icon,
    required this.items,
    required this.value,
    required this.label,
    required this.available,
    required this.onChanged,
    this.note,
  });

  final Widget icon;
  final List<T> items;
  final T value;
  final String Function(T) label;
  final bool Function(T) available;
  final ValueChanged<T> onChanged;
  final String? Function(T)? note;

  @override
  Widget build(BuildContext context) => DropdownButtonFormField<T>(
    initialValue: value,
    isExpanded: true,
    decoration: InputDecoration(
      prefixIcon: Padding(padding: const EdgeInsets.symmetric(horizontal: 10), child: icon),
      prefixIconConstraints: const BoxConstraints(minWidth: 60, minHeight: 40),
      border: const OutlineInputBorder(),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    ),
    items: [
      for (final item in items)
        DropdownMenuItem(
          value: item,
          child: Text(
            '${label(item)}${available(item) ? note?.call(item) ?? '' : ' · bertugas'}',
            overflow: TextOverflow.ellipsis,
          ),
        ),
    ],
    onChanged: (v) => v == null ? null : onChanged(v),
  );
}
