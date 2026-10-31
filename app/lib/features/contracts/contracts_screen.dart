import 'package:flutter/material.dart';
import 'package:sim_core/sim_core.dart';

import '../../app/theme.dart';
import '../../game/game_session.dart';
import '../../util/format.dart';
import 'dispatch_sheet.dart';
import 'trip_card.dart';

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
            Row(children: [
              const Expanded(child: _Header('TAWARAN KONTRAK')),
              TextButton.icon(
                onPressed: offers.length < GameSession.offerCount ? session.refreshOffers : null,
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: const Text('Cari kontrak'),
              ),
            ]),
            if (offers.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Text('Belum ada tawaran. Tekan “Cari kontrak”.', style: TextStyle(color: AppColors.textMuted)),
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
        child: Text(text,
            style: const TextStyle(color: AppColors.textMuted, fontWeight: FontWeight.w700, letterSpacing: 1.2, fontSize: 12)),
      );
}

class _OfferCard extends StatelessWidget {
  const _OfferCard({required this.session, required this.contract});

  final GameSession session;
  final Contract contract;

  @override
  Widget build(BuildContext context) {
    final cargo = session.data.content.cargoTypes[contract.cargoId]!;
    final tier = session.data.content.tierRules.tierFor(contract.scope);
    final distance = haversineMeters(
      session.world.graph.node(session.world.depots.values.first.roadNode),
      session.world.graph.node(contract.destinationNode),
    );
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => showDispatchSheet(context, session, contract),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(
                child: Text(contract.customer, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
              ),
              Text(formatRupiah(contract.payIdr),
                  style: const TextStyle(fontWeight: FontWeight.w800, color: AppColors.accent, fontSize: 16)),
            ]),
            const SizedBox(height: 6),
            Text('${contract.units} ${cargo.unit} ${cargo.name} · ${formatKg(contract.weightKg)}',
                style: const TextStyle(color: AppColors.textMuted)),
            const SizedBox(height: 10),
            Wrap(spacing: 8, runSpacing: 6, children: [
              _Chip(Icons.straighten_rounded, '± ${formatKm(distance)} garis lurus'),
              _Chip(Icons.timer_outlined, 'Tenggat ${formatDuration(contract.allowedS)}'),
              _Chip(Icons.category_outlined, tier.label.split(' (').first),
            ]),
          ]),
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
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 14, color: AppColors.textMuted),
          const SizedBox(width: 4),
          Text(text, style: const TextStyle(fontSize: 12)),
        ]),
      );
}
