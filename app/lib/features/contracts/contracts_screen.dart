import 'package:flutter/material.dart';
import 'package:sim_core/sim_core.dart';

import '../../app/theme.dart';
import '../../game/game_session.dart';
import '../../util/format.dart';
import '../../widgets/game_icons.dart';
import 'dispatch_sheet.dart';
import 'trip_card.dart';
import 'warehouse_sheet.dart';

class ContractsScreen extends StatelessWidget {
  const ContractsScreen({super.key, required this.session, required this.onShowMap});

  final GameSession session;
  final VoidCallback onShowMap;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: session,
      builder: (context, _) {
        final world = session.world;
        final active = world.trips.values.where((t) => t.isActive).toList();
        final offers = session.offers;
        final agreementOffers = session.agreementOffers;
        final running = session.activeAgreements;
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          children: [
            if (active.isNotEmpty) ...[
              const _Header('SEDANG BERJALAN'),
              for (final t in active)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: TripCard(session: session, trip: t, onShowMap: onShowMap),
                ),
              const SizedBox(height: 12),
            ],
            if (running.isNotEmpty) ...[
              const _Header('KONTRAK BERULANG'),
              for (final a in running)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _RunningAgreementCard(session: session, agreement: a),
                ),
              const SizedBox(height: 12),
            ],
            _WarehouseCard(session: session),
            const SizedBox(height: 16),
            Row(
              children: [
                const Expanded(child: _Header('TAWARAN KONTRAK')),
                TextButton.icon(
                  onPressed: offers.length < GameSession.offerCount ||
                          agreementOffers.length < GameSession.agreementOfferCount
                      ? session.refreshOffers
                      : null,
                  icon: const Icon(Icons.refresh_rounded, size: 18),
                  label: const Text('Cari kontrak'),
                ),
              ],
            ),
            if (offers.isEmpty && agreementOffers.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Text('Belum ada tawaran. Tekan “Cari kontrak”.', style: TextStyle(color: AppColors.textMuted)),
              ),
            for (final a in agreementOffers)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _AgreementOfferCard(session: session, agreement: a),
              ),
            for (final c in offers)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _OfferCard(session: session, contract: c),
              ),
          ],
        );
      },
    );
  }
}

class _Header extends StatelessWidget {
  const _Header(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(
      text,
      style: const TextStyle(color: AppColors.textMuted, fontWeight: FontWeight.w700, letterSpacing: 1.2, fontSize: 12),
    ),
  );
}

class _KindBadge extends StatelessWidget {
  const _KindBadge(this.label, this.color);

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
    decoration: BoxDecoration(color: color.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(6)),
    child: Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 11)),
  );
}

class _OfferCard extends StatelessWidget {
  const _OfferCard({required this.session, required this.contract});

  final GameSession session;
  final Contract contract;

  @override
  Widget build(BuildContext context) {
    final tier = session.data.content.tierRules.tierFor(contract.scope);
    final (label, color) = kindLabel(contract.kind);
    final world = session.world;
    final from = contract.pickupNode ?? world.depots.values.first.roadNode;
    final distance = haversineMeters(world.graph.node(from), world.graph.node(contract.destinationNode));
    final route = switch (contract.kind) {
      ContractKind.haul => '${contract.pickupName} → ${contract.customer}',
      ContractKind.storeOrder => 'Dari gudang / ${contract.pickupName} → ${contract.customer}',
      _ => contract.customer,
    };
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => showDispatchSheet(context, session, contract),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  _KindBadge(label, color),
                  const Spacer(),
                  Text(
                    formatRupiah(contract.payIdr),
                    style: const TextStyle(fontWeight: FontWeight.w800, color: AppColors.accent, fontSize: 16),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(contract.customer, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
              Text(route, style: const TextStyle(color: AppColors.textMuted)),
              const SizedBox(height: 4),
              Text(
                '${describeLines(session, contract.lines)} · ${formatKg(contract.weightKg)}',
                style: const TextStyle(color: AppColors.textMuted),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  _Chip(Icons.straighten_rounded, '± ${formatKm(distance)} garis lurus'),
                  _Chip(Icons.timer_outlined, 'Tenggat ${formatDuration(contract.allowedS)}'),
                  _Chip(Icons.category_outlined, tier.label.split(' (').first),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AgreementOfferCard extends StatelessWidget {
  const _AgreementOfferCard({required this.session, required this.agreement});

  final GameSession session;
  final Agreement agreement;

  @override
  Widget build(BuildContext context) {
    final a = agreement;
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => showAgreementSheet(context, session, a),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const _KindBadge('Kontrak berulang', AppColors.accent),
                  const Spacer(),
                  Text(
                    '${formatRupiah(a.payPerRunIdr)} × ${a.runsTotal}',
                    style: const TextStyle(fontWeight: FontWeight.w800, color: AppColors.accent, fontSize: 16),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(a.customer, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
              Text('${a.pickupName} → ${a.customer}', style: const TextStyle(color: AppColors.textMuted)),
              const SizedBox(height: 4),
              Text(
                '${describeLines(session, a.lines)} · ${formatKg(a.weightKg)}',
                style: const TextStyle(color: AppColors.textMuted),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  _Chip(Icons.event_repeat_rounded, 'Tiap ${a.intervalDays} hari'),
                  _Chip(Icons.local_shipping_outlined, 'Kendaraan tetap'),
                  _Chip(Icons.timer_outlined, 'Tenggat ${formatDuration(a.allowedS)}'),
                ],
              ),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(onPressed: () => session.cancelAgreement(a.id), child: const Text('Tolak')),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RunningAgreementCard extends StatelessWidget {
  const _RunningAgreementCard({required this.session, required this.agreement});

  final GameSession session;
  final Agreement agreement;

  @override
  Widget build(BuildContext context) {
    final a = agreement;
    final world = session.world;
    final vehicle = world.vehicles[a.vehicleId];
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                if (vehicle != null) VehicleIcon(vehicle.model.visual, width: 40),
                const SizedBox(width: 8),
                Expanded(
                  child: Text('${a.pickupName} → ${a.customer}', style: const TextStyle(fontWeight: FontWeight.w700)),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              'Pengiriman ${a.runsDispatched}/${a.runsTotal} · tiap ${a.intervalDays} hari'
              '${a.runsMissed > 0 ? ' · terlewat ${a.runsMissed}×' : ''}',
              style: TextStyle(color: a.runsMissed > 0 ? AppColors.negative : AppColors.textMuted),
            ),
            if (a.nextRunAt != null)
              Text(
                'Berikutnya ${formatGameTime(a.nextRunAt!, fromSimSeconds: world.now)} · ${vehicle?.model.name ?? 'kendaraan dijual'}',
                style: const TextStyle(color: AppColors.textMuted),
              ),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () async {
                  final ok = await showDialog<bool>(
                    context: context,
                    builder: (context) => AlertDialog(
                      title: const Text('Putus kontrak?'),
                      content: Text('Denda ${formatRupiah(world.cancelPenaltyIdr(a.id))}.'),
                      actions: [
                        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Batal')),
                        FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Putus')),
                      ],
                    ),
                  );
                  if (ok ?? false) session.cancelAgreement(a.id);
                },
                child: const Text('Putus kontrak'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _WarehouseCard extends StatelessWidget {
  const _WarehouseCard({required this.session});

  final GameSession session;

  @override
  Widget build(BuildContext context) {
    final world = session.world;
    final depot = session.depot;
    final used = world.stockVolumeM3(depot);
    final incoming = world.incomingVolumeM3(depot);
    final cap = world.warehouseCapacityM3(depot);
    final cargo = session.data.content.cargoTypes;
    final items = depot.stock.entries.toList()..sort((a, b) => a.key.compareTo(b.key));
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const GlyphIcon(GameGlyph.warehouse, size: 22),
                const SizedBox(width: 8),
                const Expanded(child: Text('Gudang', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16))),
                FilledButton.tonalIcon(
                  onPressed: () => showRestockSheet(context, session),
                  icon: const Icon(Icons.add_shopping_cart_rounded, size: 18),
                  label: const Text('Isi stok'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            LinearProgressIndicator(
              value: cap <= 0 ? 0 : ((used + incoming) / cap).clamp(0.0, 1.0),
              minHeight: 6,
              borderRadius: BorderRadius.circular(3),
            ),
            const SizedBox(height: 4),
            Text(
              '${used.toStringAsFixed(1)} / ${cap.toStringAsFixed(0)} m³'
              '${incoming > 0 ? ' · ${incoming.toStringAsFixed(1)} m³ dalam perjalanan' : ''}'
              ' · nilai ${formatRupiah(world.stockValueIdr(depot))}',
              style: const TextStyle(color: AppColors.textMuted, fontSize: 12),
            ),
            if (items.isEmpty)
              const Padding(
                padding: EdgeInsets.only(top: 6),
                child: Text(
                  'Gudang masih kosong. Pesanan toko dibeli langsung di supplier; isi stok agar lebih murah.',
                  style: TextStyle(color: AppColors.textMuted),
                ),
              ),
            for (final e in items)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text('${e.value} ${cargo[e.key]!.unit} ${cargo[e.key]!.name}'),
              ),
          ],
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip(this.icon, this.text);

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: BoxDecoration(color: AppColors.surfaceHigh, borderRadius: BorderRadius.circular(8)),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: AppColors.textMuted),
        const SizedBox(width: 4),
        Text(text, style: const TextStyle(fontSize: 12)),
      ],
    ),
  );
}
