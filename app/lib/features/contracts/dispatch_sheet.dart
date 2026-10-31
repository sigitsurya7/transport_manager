import 'package:flutter/material.dart';
import 'package:sim_core/sim_core.dart';

import '../../widgets/game_icons.dart';
import '../../app/theme.dart';
import '../../game/game_session.dart';
import '../../util/format.dart';
import '../fleet/staff_section.dart' show formatSkill;

Future<void> showDispatchSheet(BuildContext context, GameSession session, Contract contract) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: AppColors.surface,
      builder: (_) => _DispatchSheet(session: session, contract: contract),
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
  DispatchProblem.noRoute: 'Tidak ada rute jalan ke tujuan untuk kendaraan ini.',
};

class _DispatchSheet extends StatefulWidget {
  const _DispatchSheet({required this.session, required this.contract});

  final GameSession session;
  final Contract contract;

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

  @override
  Widget build(BuildContext context) {
    final session = widget.session;
    final contract = widget.contract;
    final check = session.check(contract, _vehicle, _driver);
    final quotes = [check.viaToll, check.nonToll].whereType<DispatchQuote>().toList();
    // Rute "tol" yang ternyata tidak melewati tol sama dengan non-tol: tampilkan satu saja.
    if (check.viaToll != null && !check.viaToll!.outboundRoute.usesToll && !check.viaToll!.inboundRoute.usesToll) {
      quotes.remove(check.viaToll);
    }
    final mode = _mode ?? (quotes.isEmpty ? null : _best(quotes).mode);
    final cargo = session.data.content.cargoTypes[contract.cargoId]!;

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              contract.customer,
              style: Theme.of(context).textTheme.titleLarge!.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 4),
            Text(
              '${contract.units} ${cargo.unit} ${cargo.name} · ${formatKg(contract.weightKg)} · bayaran ${formatRupiah(contract.payIdr)}',
              style: const TextStyle(color: AppColors.textMuted),
            ),
            Text(
              'Penalti telat ${formatRupiah(contract.latePenaltyPerHourIdr)} per jam',
              style: const TextStyle(color: AppColors.textMuted),
            ),
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
            if (check.problems.isNotEmpty)
              for (final p in check.problems)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    children: [
                      const Icon(Icons.error_outline_rounded, color: AppColors.negative, size: 20),
                      const SizedBox(width: 8),
                      Expanded(child: Text(_problemText[p]!)),
                    ],
                  ),
                ),
            if (quotes.isNotEmpty) ...[
              const Text(
                'PILIH RUTE',
                style: TextStyle(
                  color: AppColors.textMuted,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.2,
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 8),
              for (final q in quotes)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _QuoteCard(
                    quote: q,
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
                        session.dispatch(contract, _vehicle, _driver, mode);
                        Navigator.pop(context);
                      }
                    : null,
                icon: const Icon(Icons.play_arrow_rounded),
                label: const Text('Terima & berangkatkan'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  DispatchQuote _best(List<DispatchQuote> quotes) => quotes.reduce((a, b) => a.profitIdr >= b.profitIdr ? a : b);
}

class _QuoteCard extends StatelessWidget {
  const _QuoteCard({
    required this.quote,
    required this.tiredAt,
    required this.timeScale,
    required this.selected,
    required this.onTap,
  });

  final DispatchQuote quote;
  final double tiredAt;
  final int timeScale;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final usesToll = quote.outboundRoute.usesToll || quote.inboundRoute.usesToll;
    final total = quote.completionEta - quote.dispatchAt;
    Widget line(String label, String value, {Color? color, bool bold = false}) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(
            child: Text(label, style: const TextStyle(color: AppColors.textMuted)),
          ),
          Text(
            value,
            style: TextStyle(color: color, fontWeight: bold ? FontWeight.w800 : FontWeight.w500),
          ),
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
                  Text(
                    usesToll ? 'Via tol' : 'Non-tol',
                    style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                  ),
                  const Spacer(),
                  if (!quote.onTime)
                    const Text(
                      'TERLAMBAT',
                      style: TextStyle(color: AppColors.negative, fontWeight: FontWeight.w800, fontSize: 12),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              line('Jarak pergi-pulang', formatKm(quote.distanceM)),
              line(
                'Tiba di tujuan',
                formatGameTime(quote.deliveryEta, fromSimSeconds: quote.dispatchAt),
                color: quote.onTime ? null : AppColors.negative,
              ),
              line('Tenggat', formatGameTime(quote.deadline, fromSimSeconds: quote.dispatchAt)),
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
              line('Pendapatan', formatRupiah(quote.revenueIdr)),
              line('BBM', '-${formatRupiah(quote.fuelIdr)}'),
              if (quote.tollIdr > 0) line('Tol', '-${formatRupiah(quote.tollIdr)}'),
              line(
                'Untung',
                formatRupiah(quote.profitIdr),
                color: quote.profitIdr >= 0 ? AppColors.positive : AppColors.negative,
                bold: true,
              ),
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
