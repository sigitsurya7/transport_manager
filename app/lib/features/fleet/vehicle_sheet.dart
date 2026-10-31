import 'package:flutter/material.dart';
import 'package:sim_core/sim_core.dart';

import '../../app/theme.dart';
import '../../game/game_session.dart';
import '../../util/format.dart';
import '../../widgets/game_icons.dart';

Future<void> showVehicleSheet(BuildContext context, GameSession session, Vehicle vehicle) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  backgroundColor: AppColors.surface,
  builder: (_) => DraggableScrollableSheet(
    expand: false,
    initialChildSize: 0.8,
    maxChildSize: 0.95,
    builder: (context, controller) => _VehicleSheet(session: session, vehicle: vehicle, controller: controller),
  ),
);

const _problemText = {
  MaintenanceProblem.vehicleBusy: 'Kendaraan sedang bertugas / di bengkel',
  MaintenanceProblem.insufficientCash: 'Kas tidak cukup',
  MaintenanceProblem.notNeeded: 'Belum perlu',
};

Color conditionColor(double v) => v >= 0.6
    ? AppColors.positive
    : v >= 0.3
    ? AppColors.accent
    : AppColors.negative;

/// Detail kendaraan: kondisi komponen, konsumsi BBM aktual, servis & perbaikan.
class _VehicleSheet extends StatelessWidget {
  const _VehicleSheet({required this.session, required this.vehicle, required this.controller});

  final GameSession session;
  final Vehicle vehicle;
  final ScrollController controller;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: session,
    builder: (context, _) {
      final world = session.world;
      final m = session.data.content.maintenance;
      final job = vehicle.maintenance;
      return ListView(
        controller: controller,
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        children: [
          Row(
            children: [
              VehicleIcon(vehicle.model.visual, width: 84),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      vehicle.model.name,
                      style: Theme.of(context).textTheme.titleLarge!.copyWith(fontWeight: FontWeight.w800),
                    ),
                    Text(
                      '${formatKm(vehicle.odometerM)} · '
                      'BBM ${world.fuelLPer100Km(vehicle).toStringAsFixed(1).replaceAll('.', ',')} L/100 km',
                      style: const TextStyle(color: AppColors.textMuted),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (job != null) ...[const SizedBox(height: 14), _JobCard(session: session, job: job)],
          const SizedBox(height: 18),
          const Text(
            'KONDISI KOMPONEN',
            style: TextStyle(color: AppColors.textMuted, fontWeight: FontWeight.w700, letterSpacing: 1.2, fontSize: 12),
          ),
          const SizedBox(height: 8),
          for (final c in VehicleComponent.values)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: Row(
                children: [
                  SizedBox(width: 130, child: Text(m.componentNames[c]!)),
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: vehicle.condition[c]!,
                        minHeight: 8,
                        backgroundColor: AppColors.outline,
                        color: conditionColor(vehicle.condition[c]!),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  SizedBox(
                    width: 42,
                    child: Text(
                      '${(vehicle.condition[c]! * 100).round()}%',
                      textAlign: TextAlign.right,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 18),
          Row(
            children: [
              const Expanded(
                child: Text(
                  'SERVIS & PERBAIKAN',
                  style: TextStyle(
                    color: AppColors.textMuted,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.2,
                    fontSize: 12,
                  ),
                ),
              ),
              Text(
                world.workshopBays(session.depot) == 0
                    ? 'Bengkel luar'
                    : 'Bengkel ${world.workshopBays(session.depot)} bay',
                style: const TextStyle(color: AppColors.textMuted, fontSize: 12),
              ),
            ],
          ),
          const SizedBox(height: 8),
          for (final action in m.actions.values)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _ActionTile(session: session, vehicle: vehicle, action: action),
            ),
        ],
      );
    },
  );
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({required this.session, required this.vehicle, required this.action});

  final GameSession session;
  final Vehicle vehicle;
  final MaintenanceAction action;

  @override
  Widget build(BuildContext context) {
    final q = session.world.maintenanceQuote(vehicle.id, action.id);
    final problems = session.world.maintenanceProblems(vehicle.id, action.id);
    final names = session.data.content.maintenance.componentNames;
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(action.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 2),
                  Text(
                    '${action.restore.keys.map((c) => names[c]!.toLowerCase()).join(', ')} · '
                    '${formatRupiah(q.costIdr)} · ${formatDuration(q.durationS)}',
                    style: const TextStyle(color: AppColors.textMuted, fontSize: 12),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            FilledButton(
              style: FilledButton.styleFrom(minimumSize: const Size(72, 40)),
              onPressed: problems.isEmpty ? () => session.startMaintenance(vehicle.id, action.id) : null,
              child: Text(
                problems.isEmpty ? 'Kerjakan' : _problemText[problems.first]!,
                style: const TextStyle(fontSize: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _JobCard extends StatelessWidget {
  const _JobCard({required this.session, required this.job});

  final GameSession session;
  final MaintenanceJob job;

  @override
  Widget build(BuildContext context) {
    final name = session.data.content.maintenance.action(job.actionId).name;
    final now = session.world.now;
    final progress = job.waiting ? 0.0 : ((now - job.startedAt!) / job.durationS).clamp(0.0, 1.0);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.accent.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.accent),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const GlyphIcon(GameGlyph.workshop, size: 18, color: AppColors.accent),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(name, style: const TextStyle(fontWeight: FontWeight.w700)),
                ),
                Text(
                  job.waiting ? 'Antre bay bengkel' : 'selesai ${formatGameTime(job.finishAt!, fromSimSeconds: now)}',
                  style: const TextStyle(color: AppColors.textMuted, fontSize: 12),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(value: progress, minHeight: 6, backgroundColor: AppColors.outline),
            ),
          ],
        ),
      ),
    );
  }
}
