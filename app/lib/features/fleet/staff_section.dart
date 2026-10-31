import 'package:flutter/material.dart';
import 'package:sim_core/sim_core.dart';

import '../../app/theme.dart';
import '../../game/game_session.dart';
import '../../util/format.dart';
import '../../widgets/game_icons.dart';
import '../contracts/trip_card.dart';
import 'vehicle_sheet.dart' show conditionColor;

String formatSkill(double skill) => '${(skill * 100).round()}';

/// Status singkat sopir: bertugas, wajib istirahat, lelah, atau siap.
String driverStatus(SimWorld world, Driver d) {
  if (!d.isAvailable) {
    final trip = world.trips[d.tripId];
    return trip == null ? 'Bertugas' : phaseLabel[trip.phase]!;
  }
  final fatigue = world.driverFatigue(d.id);
  if (fatigue >= 1) return 'Wajib istirahat';
  if (fatigue >= world.content.employees.driver.tiredAt) return 'Lelah · istirahat';
  return fatigue > 0.01 ? 'Siap · istirahat' : 'Siap';
}

/// Karyawan depot: sopir (skill, kelelahan), staf gudang, mekanik.
class StaffSection extends StatelessWidget {
  const StaffSection({super.key, required this.session});

  final GameSession session;

  @override
  Widget build(BuildContext context) {
    final world = session.world;
    final depot = session.depot;
    final cfg = session.data.content.employees;
    final officeFull = world.staffCount(depot) >= world.staffMax(depot);
    final bays = world.workshopBays(depot);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Card(
          child: Column(
            children: [
              for (final d in world.drivers.values) _DriverTile(session: session, driver: d),
              const Divider(),
              _CountTile(
                glyph: GameGlyph.staff,
                title: 'Staf gudang: ${depot.warehouseStaff}',
                subtitle:
                    'Muat ×${_x(cfg.loadingFactor(depot.warehouseStaff))} '
                    '(efektif s.d. ${cfg.loadingStaffMaxEffective} orang) · '
                    '${formatRupiah(cfg.dailyWageIdr[EmployeeRole.warehouseStaff]!)}/hari',
                onRemove: depot.warehouseStaff > 0 ? () => session.releaseStaff(EmployeeRole.warehouseStaff) : null,
                onAdd: officeFull ? null : () => session.hire(EmployeeRole.warehouseStaff),
              ),
              const Divider(),
              _CountTile(
                glyph: GameGlyph.workshop,
                title: 'Mekanik: ${depot.mechanics}',
                subtitle: bays == 0
                    ? 'Belum ada bengkel sendiri: servis di bengkel luar · '
                          '${formatRupiah(cfg.dailyWageIdr[EmployeeRole.mechanic]!)}/hari'
                    : 'Servis ×${_x(cfg.mechanicFactor(depot.mechanics, bays))} '
                          '(efektif s.d. ${bays * cfg.mechanicsPerBay} orang) · '
                          '${formatRupiah(cfg.dailyWageIdr[EmployeeRole.mechanic]!)}/hari',
                onRemove: depot.mechanics > 0 ? () => session.releaseStaff(EmployeeRole.mechanic) : null,
                onAdd: officeFull ? null : () => session.hire(EmployeeRole.mechanic),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        OutlinedButton.icon(
          onPressed: officeFull ? null : () => _showCandidates(context, session),
          icon: const GlyphIcon(GameGlyph.driver, size: 20, color: AppColors.accent),
          label: Text(officeFull ? 'Kantor penuh: upgrade kantor' : 'Rekrut sopir'),
        ),
      ],
    );
  }

  static String _x(double v) => v.toStringAsFixed(1).replaceAll('.', ',');
}

class _DriverTile extends StatelessWidget {
  const _DriverTile({required this.session, required this.driver});

  final GameSession session;
  final Driver driver;

  @override
  Widget build(BuildContext context) {
    final fatigue = session.world.driverFatigue(driver.id);
    return ListTile(
      onTap: () => _showDriver(context, session, driver),
      leading: const GlyphIcon(GameGlyph.driver, color: AppColors.accent),
      title: Text(driver.name),
      subtitle: Text(
        'Skill ${formatSkill(driver.skill)} · ${driverStatus(session.world, driver)}',
        style: const TextStyle(color: AppColors.textMuted),
      ),
      trailing: SizedBox(width: 64, child: _FatigueBar(fatigue)),
    );
  }
}

/// Bar kelelahan: hijau segar → merah wajib istirahat.
class _FatigueBar extends StatelessWidget {
  const _FatigueBar(this.fatigue);

  final double fatigue;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.end,
    children: [
      const Text('Lelah', style: TextStyle(color: AppColors.textMuted, fontSize: 11)),
      const SizedBox(height: 3),
      ClipRRect(
        borderRadius: BorderRadius.circular(3),
        child: LinearProgressIndicator(
          value: fatigue.clamp(0.0, 1.0),
          minHeight: 6,
          backgroundColor: AppColors.outline,
          color: conditionColor(1 - fatigue),
        ),
      ),
    ],
  );
}

class _CountTile extends StatelessWidget {
  const _CountTile({
    required this.glyph,
    required this.title,
    required this.subtitle,
    required this.onRemove,
    required this.onAdd,
  });

  final GameGlyph glyph;
  final String title;
  final String subtitle;
  final VoidCallback? onRemove;
  final VoidCallback? onAdd;

  @override
  Widget build(BuildContext context) => ListTile(
    leading: GlyphIcon(glyph, color: AppColors.accent),
    title: Text(title),
    subtitle: Text(subtitle, style: const TextStyle(color: AppColors.textMuted)),
    trailing: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(tooltip: 'Berhentikan', onPressed: onRemove, icon: const Icon(Icons.remove_circle_outline_rounded)),
        IconButton(tooltip: 'Rekrut', onPressed: onAdd, icon: const Icon(Icons.add_circle_outline_rounded)),
      ],
    ),
  );
}

Future<void> _showCandidates(BuildContext context, GameSession session) => showModalBottomSheet<void>(
  context: context,
  showDragHandle: true,
  isScrollControlled: true,
  backgroundColor: AppColors.surface,
  builder: (context) => ListenableBuilder(
    listenable: session,
    builder: (context, _) {
      final candidates = session.world.driverCandidates(session.depot.id);
      return SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
          children: [
            Text(
              'Calon sopir hari ini',
              style: Theme.of(context).textTheme.titleLarge!.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 4),
            const Text(
              'Sopir terampil lebih hemat BBM dan kendaraan lebih awet, tapi gajinya lebih tinggi. '
              'Skill naik seiring jam mengemudi. Calon berganti tiap hari.',
              style: TextStyle(color: AppColors.textMuted),
            ),
            const SizedBox(height: 12),
            if (candidates.isEmpty)
              const Text('Tidak ada calon hari ini.', style: TextStyle(color: AppColors.textMuted)),
            for (final (i, c) in candidates.indexed)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(c.name, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                              const SizedBox(height: 6),
                              _SkillBar(c.skill),
                              const SizedBox(height: 6),
                              Text(
                                '${formatRupiah(c.dailyWageIdr)}/hari',
                                style: const TextStyle(color: AppColors.textMuted),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        FilledButton(
                          onPressed:
                              session.world
                                  .hireProblems(session.depot.id, role: EmployeeRole.driver, candidate: i)
                                  .isEmpty
                              ? () {
                                  session.hire(EmployeeRole.driver, candidate: i);
                                  Navigator.pop(context);
                                }
                              : null,
                          child: const Text('Rekrut'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      );
    },
  ),
);

class _SkillBar extends StatelessWidget {
  const _SkillBar(this.skill);

  final double skill;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      SizedBox(width: 54, child: Text('Skill ${formatSkill(skill)}', style: const TextStyle(fontSize: 12))),
      Expanded(
        child: ClipRRect(
          borderRadius: BorderRadius.circular(3),
          child: LinearProgressIndicator(
            value: skill,
            minHeight: 6,
            backgroundColor: AppColors.outline,
            color: AppColors.accent,
          ),
        ),
      ),
    ],
  );
}

Future<void> _showDriver(BuildContext context, GameSession session, Driver driver) => showModalBottomSheet<void>(
  context: context,
  showDragHandle: true,
  backgroundColor: AppColors.surface,
  builder: (context) => ListenableBuilder(
    listenable: session,
    builder: (context, _) {
      final world = session.world;
      if (!world.drivers.containsKey(driver.id)) return const SizedBox.shrink();
      final rules = session.data.content.employees.driver;
      final fatigue = world.driverFatigue(driver.id);
      Widget line(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          children: [
            Expanded(
              child: Text(label, style: const TextStyle(color: AppColors.textMuted)),
            ),
            Text(value, style: const TextStyle(fontWeight: FontWeight.w600)),
          ],
        ),
      );
      final saving = (1 - rules.fuelFactor(driver.skill) / rules.fuelFactor(0)) * 100;
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(driver.name, style: Theme.of(context).textTheme.titleLarge!.copyWith(fontWeight: FontWeight.w800)),
              Text(driverStatus(world, driver), style: const TextStyle(color: AppColors.textMuted)),
              const SizedBox(height: 14),
              _SkillBar(driver.skill),
              const SizedBox(height: 10),
              line('Hemat BBM vs sopir baru', '${saving.toStringAsFixed(0)}%'),
              line('Jam mengemudi', '${(driver.drivingSeconds / 3600).toStringAsFixed(1).replaceAll('.', ',')} jam'),
              line('Kelelahan', '${(fatigue * 100).round()}%'),
              if (driver.isAvailable && fatigue > 0)
                line('Pulih penuh dalam', formatDuration((fatigue * rules.fullRestHours * 3600).round())),
              line('Gaji', '${formatRupiah(driver.dailyWageIdr)}/hari'),
              const SizedBox(height: 16),
              OutlinedButton(
                style: OutlinedButton.styleFrom(foregroundColor: AppColors.negative),
                onPressed: world.canReleaseDriver(driver.id)
                    ? () {
                        session.releaseDriver(driver.id);
                        Navigator.pop(context);
                      }
                    : null,
                child: Text(
                  !driver.isAvailable
                      ? 'Sedang bertugas'
                      : world.drivers.length <= 1
                      ? 'Sopir terakhir tidak bisa diberhentikan'
                      : 'Berhentikan',
                ),
              ),
            ],
          ),
        ),
      );
    },
  ),
);
