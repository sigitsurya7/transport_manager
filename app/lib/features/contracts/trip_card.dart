import 'package:flutter/material.dart';
import 'package:sim_core/sim_core.dart';

import '../../widgets/game_icons.dart';
import '../../app/theme.dart';
import '../../game/game_session.dart';
import '../../util/format.dart';

const phaseLabel = {
  TripPhase.waitDock: 'Antre loading dock',
  TripPhase.toDock: 'Menuju loading dock',
  TripPhase.loading: 'Memuat barang',
  TripPhase.toGate: 'Menuju gerbang',
  TripPhase.waitGateOut: 'Antre di gerbang',
  TripPhase.gateOut: 'Pemeriksaan gerbang keluar',
  TripPhase.outbound: 'Dalam perjalanan ke tujuan',
  TripPhase.unloading: 'Bongkar di tujuan',
  TripPhase.inbound: 'Kembali ke depot',
  TripPhase.waitGateIn: 'Antre masuk depot',
  TripPhase.gateIn: 'Pemeriksaan gerbang masuk',
  TripPhase.toSlot: 'Menuju slot parkir',
  TripPhase.inspection: 'Pemeriksaan kendaraan',
  TripPhase.completed: 'Selesai',
};

/// Status trip berjalan: fase, progres, perkiraan selesai.
class TripCard extends StatelessWidget {
  const TripCard({super.key, required this.session, required this.trip, this.onShowMap});

  final GameSession session;
  final Trip trip;
  final VoidCallback? onShowMap;

  @override
  Widget build(BuildContext context) {
    final world = session.world;
    final contract = world.contracts[trip.contractId]!;
    final vehicle = world.vehicles[trip.vehicleId]!;
    final snap = world.vehicleSnapshot(vehicle.id);
    final phases = TripPhase.values.where((p) => p != TripPhase.completed && !p.waiting).toList();
    final index = phases.indexOf(trip.phase);
    // Fase antrean: tampilkan progres fase sebelumnya yang sudah selesai.
    final done = index >= 0
        ? index + snap.phaseProgress
        : phases.indexOf(TripPhase.values[trip.phase.index + 1]).toDouble();
    final overall = done / phases.length;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                VehicleIcon(vehicle.model.visual, width: 44),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '${vehicle.model.name} → ${contract.customer}',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (onShowMap != null)
                  IconButton(
                    tooltip: 'Lihat di peta',
                    visualDensity: VisualDensity.compact,
                    onPressed: onShowMap,
                    icon: const GlyphIcon(GameGlyph.map, size: 20),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Text(phaseLabel[trip.phase]!, style: const TextStyle(color: AppColors.textMuted)),
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(value: overall, minHeight: 6, backgroundColor: AppColors.outline),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Text(
                  'Tenggat ${formatGameTime(contract.deadline!, fromSimSeconds: world.now)}',
                  style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
                ),
                const Spacer(),
                Text(
                  trip.phase.waiting ? 'Menunggu antrean' : 'Fase selesai ${formatGameTime(trip.phaseEnd)}',
                  style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
