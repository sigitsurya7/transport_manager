import 'package:flutter/material.dart';
import 'package:sim_core/sim_core.dart';

import '../../widgets/game_icons.dart';
import '../../app/theme.dart';
import '../../game/game_session.dart';
import '../../util/format.dart';

Future<void> showFacilitiesSheet(BuildContext context, GameSession session) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  backgroundColor: AppColors.surface,
  builder: (_) => DraggableScrollableSheet(
    expand: false,
    initialChildSize: 0.75,
    maxChildSize: 0.95,
    builder: (context, controller) => _FacilitiesSheet(session: session, controller: controller),
  ),
);

/// Ringkasan statistik satu level dalam kalimat pendek.
String _x(double v) => '×${v.toStringAsFixed(2).replaceAll('.', ',')}';

String facilityStats(FacilityType type, FacilityLevel l) => switch (type) {
  FacilityType.parking =>
    '${l.intStat('slots')} slot parkir · jalur internal ${_x(l.stats['yard_speed']?.toDouble() ?? 1.0)}',
  FacilityType.gate => '${l.intStat('lanes')} jalur · lewat ${formatDuration(l.intStat('pass_s'))} per kendaraan',
  FacilityType.loadingDock => '${l.intStat('docks')} dock · kecepatan muat ${_x(l.doubleStat('speed'))}',
  FacilityType.workshop =>
    l.intStat('bays') == 0
        ? 'Servis di bengkel luar · biaya ${_x(l.doubleStat('cost_factor'))} · kecepatan ${_x(l.doubleStat('speed'))}'
        : '${l.intStat('bays')} bay · kecepatan ${_x(l.doubleStat('speed'))} · biaya ${_x(l.doubleStat('cost_factor'))}',
  FacilityType.warehouse => 'Kapasitas ${l.intStat('capacity_m3')} m³',
  FacilityType.office => 'Maks. ${l.intStat('staff_max')} karyawan',
};

const _problemText = {
  UpgradeProblem.maxLevel: 'Sudah level tertinggi',
  UpgradeProblem.constructionBusy: 'Tunggu konstruksi lain selesai',
  UpgradeProblem.insufficientCash: 'Kas tidak cukup',
};

class _FacilitiesSheet extends StatelessWidget {
  const _FacilitiesSheet({required this.session, required this.controller});

  final GameSession session;
  final ScrollController controller;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: session,
    builder: (context, _) {
      final depot = session.depot;
      return ListView(
        controller: controller,
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        children: [
          Text(
            'Fasilitas ${depot.name}',
            style: Theme.of(context).textTheme.titleLarge!.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 4),
          const Text(
            'Satu konstruksi dalam satu waktu. Fasilitas tetap beroperasi selama dibangun.',
            style: TextStyle(color: AppColors.textMuted),
          ),
          const SizedBox(height: 14),
          for (final type in FacilityType.values)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _FacilityCard(session: session, type: type),
            ),
        ],
      );
    },
  );
}

class _FacilityCard extends StatelessWidget {
  const _FacilityCard({required this.session, required this.type});

  final GameSession session;
  final FacilityType type;

  @override
  Widget build(BuildContext context) {
    final world = session.world;
    final depot = session.depot;
    final spec = session.data.content.facilities[type];
    final level = depot.level(type);
    final current = spec.level(level);
    final next = level < spec.maxLevel ? spec.level(level + 1) : null;
    final building = depot.construction?.type == type;
    final problems = world.upgradeProblems(depot.id, type);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                GlyphIcon(facilityGlyph(type), size: 26, color: AppColors.accent),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(spec.name, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                ),
                _LevelDots(level: level, max: spec.maxLevel),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              '${current.label} · ${facilityStats(type, current)}',
              style: const TextStyle(color: AppColors.textMuted),
            ),
            if (next != null) ...[
              const Divider(height: 20),
              Row(
                children: [
                  const Icon(Icons.arrow_upward_rounded, size: 16, color: AppColors.positive),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text('Level ${level + 1}: ${next.label}', style: const TextStyle(fontWeight: FontWeight.w700)),
                  ),
                  _UpgradeKind(changesLook: spec.changesLook(level + 1)),
                ],
              ),
              const SizedBox(height: 2),
              Text(facilityStats(type, next)),
              const SizedBox(height: 4),
              Text(
                '${formatRupiah(next.costIdr)} · dibangun ${formatDuration(next.buildMinutes * 60)} '
                '(≈ ${formatRealDuration(next.buildMinutes * 60, session.timeScale)} nyata)',
                style: const TextStyle(color: AppColors.textMuted, fontSize: 13),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: building
                    ? const OutlinedButton(onPressed: null, child: Text('Sedang dibangun…'))
                    : FilledButton(
                        onPressed: problems.isEmpty ? () => session.startUpgrade(type) : null,
                        child: Text(problems.isEmpty ? 'Bangun' : _problemText[problems.first]!),
                      ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Jenis upgrade: hanya statistik, atau sekaligus mengganti tampilan.
class _UpgradeKind extends StatelessWidget {
  const _UpgradeKind({required this.changesLook});

  final bool changesLook;

  @override
  Widget build(BuildContext context) {
    final color = changesLook ? AppColors.accent : AppColors.textMuted;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(6)),
      child: Text(
        changesLook ? 'Ganti tampilan' : 'Statistik',
        style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w700),
      ),
    );
  }
}

/// "Lv 5/15" + bar kecil (15 titik terlalu lebar di layar HP).
class _LevelDots extends StatelessWidget {
  const _LevelDots({required this.level, required this.max});

  final int level;
  final int max;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Text('Lv $level/$max', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12)),
      const SizedBox(width: 6),
      SizedBox(
        width: 54,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(3),
          child: LinearProgressIndicator(
            value: level / max,
            minHeight: 6,
            backgroundColor: AppColors.outline,
            color: AppColors.accent,
          ),
        ),
      ),
    ],
  );
}
