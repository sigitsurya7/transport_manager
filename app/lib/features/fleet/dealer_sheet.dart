import 'package:flutter/material.dart';
import 'package:sim_core/sim_core.dart';

import '../../app/theme.dart';
import '../../game/game_session.dart';
import '../../util/format.dart';
import '../../widgets/game_icons.dart';

/// Dealer kendaraan: kategori, kartu spesifikasi, dan tabel perbandingan.
Future<void> showDealerSheet(BuildContext context, GameSession session) => showModalBottomSheet<void>(
  context: context,
  showDragHandle: true,
  isScrollControlled: true,
  backgroundColor: AppColors.surface,
  builder: (_) => DraggableScrollableSheet(
    expand: false,
    initialChildSize: 0.92,
    maxChildSize: 0.95,
    builder: (context, controller) => _Dealer(session: session, controller: controller),
  ),
);

String _num(double v, [int digits = 1]) => v.toStringAsFixed(digits).replaceAll('.', ',');

/// Teks status pembelian (atau `null` bila bisa dibeli).
String? purchaseBlocker(GameSession session, VehicleModel m) {
  final problems = session.world.purchaseProblems(session.depot.id, m.id);
  if (problems.isEmpty) return null;
  return switch (problems.first) {
    PurchaseProblem.needsTruckTerminal => 'Butuh terminal truk',
    PurchaseProblem.facilityLevelTooLow =>
      'Butuh ${session.data.content.facilities[FacilityType.parse(m.unlock.facilityId!)].name.toLowerCase()} '
          'level ${m.unlock.level}',
    PurchaseProblem.noFreeSlot => 'Parkir penuh',
    PurchaseProblem.insufficientCash => 'Kas tidak cukup',
    PurchaseProblem.unknownModel => 'Tidak tersedia',
  };
}

class _Dealer extends StatefulWidget {
  const _Dealer({required this.session, required this.controller});

  final GameSession session;
  final ScrollController controller;

  @override
  State<_Dealer> createState() => _DealerState();
}

class _DealerState extends State<_Dealer> {
  String _category = 'pickup';
  bool _compare = false;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.session,
    builder: (context, _) {
      final session = widget.session;
      final catalog = session.data.content.vehicleCatalog;
      final models = catalog.models.values.where((m) => m.category == _category).toList()
        ..sort((a, b) => a.priceIdr.compareTo(b.priceIdr));
      return ListView(
        controller: widget.controller,
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Dealer kendaraan',
                  style: Theme.of(context).textTheme.titleLarge!.copyWith(fontWeight: FontWeight.w800),
                ),
              ),
              SegmentedButton<bool>(
                showSelectedIcon: false,
                style: const ButtonStyle(visualDensity: VisualDensity.compact),
                segments: const [
                  ButtonSegment(value: false, icon: Icon(Icons.view_agenda_outlined, size: 18)),
                  ButtonSegment(value: true, icon: Icon(Icons.table_chart_outlined, size: 18)),
                ],
                selected: {_compare},
                onSelectionChanged: (s) => setState(() => _compare = s.first),
              ),
            ],
          ),
          Text(
            'Kas ${formatRupiah(session.world.cashIdr)} · '
            'parkir ${session.depot.slots.whereType<int>().length}/${session.depot.parkingSlots}',
            style: const TextStyle(color: AppColors.textMuted),
          ),
          const SizedBox(height: 10),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final c in catalog.categories)
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: ChoiceChip(
                      label: Text('${c.name} (${catalog.models.values.where((m) => m.category == c.id).length})'),
                      selected: c.id == _category,
                      onSelected: (_) => setState(() => _category = c.id),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          if (_compare)
            _CompareTable(session: session, models: models)
          else
            for (final m in models)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _ModelCard(session: session, model: m),
              ),
        ],
      );
    },
  );
}

class _ModelCard extends StatelessWidget {
  const _ModelCard({required this.session, required this.model});

  final GameSession session;
  final VehicleModel model;

  @override
  Widget build(BuildContext context) {
    final m = model;
    final content = session.data.content;
    final blocker = purchaseBlocker(session, m);
    final locked = m.unlock.terminal || (m.unlock.facilityId != null && blocker != null && blocker.startsWith('Butuh'));
    final fuel100 = content.economy.fuelCostIdr(100000, m.fuelLPer100Km);
    final service =
        (content.maintenance.action('service').costIdr * (content.maintenance.classCostFactor[m.vehicleClass] ?? 1))
            .round();
    Widget stat(String label, String value) => SizedBox(
      width: 104,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(color: AppColors.textMuted, fontSize: 11)),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
        ],
      ),
    );
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Opacity(opacity: locked ? 0.55 : 1, child: VehicleIcon(m.visual, width: 112)),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(m.name, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                      Text(
                        '${m.subcategory} · ${m.chassis.name}',
                        style: const TextStyle(color: AppColors.textMuted, fontSize: 12),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        formatRupiah(m.priceIdr),
                        style: const TextStyle(color: AppColors.accent, fontWeight: FontWeight.w800),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              runSpacing: 8,
              children: [
                stat('Muatan', formatKg(m.payloadKg)),
                stat('BBM', '${_num(m.fuelLPer100Km)} L/100 km'),
                stat('BBM per 100 km', formatRupiahCompact(fuel100)),
                stat('Servis rutin', formatRupiahCompact(service)),
                stat('P × L × T', '${_num(m.lengthM)} × ${_num(m.widthM)} × ${_num(m.heightM)} m'),
                stat('Kecepatan', '${m.maxSpeedKmh} km/jam · gol. ${m.tollGolongan}'),
              ],
            ),
            const SizedBox(height: 8),
            Text('Bodi: ${m.body.name}', style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
            const SizedBox(height: 4),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                for (final k in m.cargoKinds)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(color: AppColors.surfaceHigh, borderRadius: BorderRadius.circular(8)),
                    child: Text(content.vehicleCatalog.cargoKindNames[k]!, style: const TextStyle(fontSize: 11)),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: blocker == null
                    ? () {
                        session.buyVehicle(m.id);
                        Navigator.pop(context);
                      }
                    : null,
                icon: Icon(locked ? Icons.lock_outline_rounded : Icons.shopping_cart_outlined, size: 18),
                label: Text(blocker ?? 'Beli'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CompareTable extends StatelessWidget {
  const _CompareTable({required this.session, required this.models});

  final GameSession session;
  final List<VehicleModel> models;

  @override
  Widget build(BuildContext context) {
    final content = session.data.content;
    const muted = TextStyle(color: AppColors.textMuted, fontSize: 12);
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        columnSpacing: 18,
        horizontalMargin: 4,
        headingRowHeight: 36,
        dataRowMinHeight: 64,
        dataRowMaxHeight: 72,
        columns: const [
          DataColumn(label: Text('Model', style: muted)),
          DataColumn(label: Text('Harga', style: muted), numeric: true),
          DataColumn(label: Text('Muatan', style: muted), numeric: true),
          DataColumn(label: Text('Rp/ton·km BBM', style: muted), numeric: true),
          DataColumn(label: Text('Panjang', style: muted), numeric: true),
          DataColumn(label: Text('Jenis muatan', style: muted)),
          DataColumn(label: Text('Status', style: muted)),
        ],
        rows: [
          for (final m in models)
            DataRow(
              cells: [
                DataCell(
                  Row(
                    children: [
                      VehicleIcon(m.visual, width: 72),
                      const SizedBox(width: 8),
                      SizedBox(
                        width: 130,
                        child: Text(m.name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12)),
                      ),
                    ],
                  ),
                ),
                DataCell(Text(formatRupiahCompact(m.priceIdr))),
                DataCell(Text(formatKg(m.payloadKg))),
                DataCell(
                  Text(
                    formatRupiah((content.economy.fuelCostIdr(1000, m.fuelLPer100Km) / (m.payloadKg / 1000)).round()),
                  ),
                ),
                DataCell(Text('${_num(m.lengthM)} m')),
                DataCell(
                  Text(
                    m.cargoKinds.map((k) => content.vehicleCatalog.cargoKindNames[k]!).join(', '),
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
                DataCell(
                  Text(
                    purchaseBlocker(session, m) ?? 'Bisa dibeli',
                    style: TextStyle(
                      fontSize: 12,
                      color: purchaseBlocker(session, m) == null ? AppColors.positive : AppColors.textMuted,
                    ),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}
