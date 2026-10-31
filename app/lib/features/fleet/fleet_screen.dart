import 'package:flutter/material.dart';
import 'package:sim_core/sim_core.dart';

import '../../widgets/game_icons.dart';
import '../../app/theme.dart';
import '../../game/game_session.dart';
import '../../util/format.dart';
import '../contracts/trip_card.dart';

/// Armada & karyawan: kendaraan, sopir, staf gudang, kapasitas kantor.
class FleetScreen extends StatelessWidget {
  const FleetScreen({super.key, required this.session});

  final GameSession session;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: session,
        builder: (context, _) {
          final world = session.world;
          final depot = session.depot;
          final cfg = session.data.content.employees;
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            children: [
              _Header(
                'KENDARAAN',
                trailing: TextButton.icon(
                  onPressed: () => _showBuySheet(context, session),
                  icon: const GlyphIcon(GameGlyph.fleet, size: 18, color: AppColors.accent),
                  label: const Text('Beli'),
                ),
              ),
              for (final v in world.vehicles.values) _VehicleTile(session: session, vehicle: v),
              Padding(
                padding: const EdgeInsets.only(top: 4, bottom: 20),
                child: Text('Slot parkir terpakai ${depot.slots.whereType<int>().length}/${depot.parkingSlots}',
                    style: const TextStyle(color: AppColors.textMuted, fontSize: 13)),
              ),
              _Header(
                'KARYAWAN',
                trailing: Text('Kantor ${world.staffCount(depot)}/${world.staffMax(depot)}',
                    style: const TextStyle(color: AppColors.textMuted)),
              ),
              Card(
                child: Column(children: [
                  for (final d in world.drivers.values)
                    ListTile(
                      leading: const GlyphIcon(GameGlyph.driver, color: AppColors.accent),
                      title: Text(d.name),
                      subtitle: Text(
                        d.isAvailable ? 'Sopir · siap' : 'Sopir · ${_tripStatus(world, d.tripId!)}',
                        style: const TextStyle(color: AppColors.textMuted),
                      ),
                      trailing: Text('${(d.drivingSeconds / 3600).toStringAsFixed(1).replaceAll('.', ',')} j',
                          style: const TextStyle(color: AppColors.textMuted)),
                    ),
                  const Divider(),
                  ListTile(
                    leading: const GlyphIcon(GameGlyph.staff, color: AppColors.accent),
                    title: Text('Staf gudang: ${depot.warehouseStaff}'),
                    subtitle: Text(
                      'Muat ×${cfg.loadingFactor(depot.warehouseStaff).toStringAsFixed(1).replaceAll('.', ',')} '
                      '(efektif s.d. ${cfg.loadingStaffMaxEffective} orang)',
                      style: const TextStyle(color: AppColors.textMuted),
                    ),
                    trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                      IconButton(
                        tooltip: 'Berhentikan',
                        onPressed: depot.warehouseStaff > 0 ? session.releaseWarehouseStaff : null,
                        icon: const Icon(Icons.remove_circle_outline_rounded),
                      ),
                      IconButton(
                        tooltip: 'Rekrut',
                        onPressed: world.hireProblems(depot.id).isEmpty
                            ? () => session.hire(EmployeeRole.warehouseStaff)
                            : null,
                        icon: const Icon(Icons.add_circle_outline_rounded),
                      ),
                    ]),
                  ),
                ]),
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: world.hireProblems(depot.id).isEmpty ? () => session.hire(EmployeeRole.driver) : null,
                icon: const GlyphIcon(GameGlyph.driver, size: 20, color: AppColors.accent),
                label: Text(world.hireProblems(depot.id).isEmpty
                    ? 'Rekrut sopir (${formatRupiah(cfg.dailyWageIdr[EmployeeRole.driver]!)}/hari)'
                    : 'Kantor penuh: upgrade kantor'),
              ),
              const SizedBox(height: 12),
              Text('Gaji harian total ${formatRupiah(world.dailyPayrollIdr())} · dibayar tiap pukul 00.00',
                  style: const TextStyle(color: AppColors.textMuted, fontSize: 13)),
            ],
          );
        },
      );

  static String _tripStatus(SimWorld world, int tripId) {
    final trip = world.trips[tripId];
    return trip == null ? 'bertugas' : phaseLabel[trip.phase]!.toLowerCase();
  }
}

class _Header extends StatelessWidget {
  const _Header(this.text, {this.trailing});

  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(children: [
          Expanded(
            child: Text(text,
                style: const TextStyle(color: AppColors.textMuted, fontWeight: FontWeight.w700, letterSpacing: 1.2, fontSize: 12)),
          ),
          ?trailing,
        ]),
      );
}

class _VehicleTile extends StatelessWidget {
  const _VehicleTile({required this.session, required this.vehicle});

  final GameSession session;
  final Vehicle vehicle;

  @override
  Widget build(BuildContext context) {
    final snap = session.world.vehicleSnapshot(vehicle.id);
    final status = snap.phase == null ? 'Siap di slot ${vehicle.slotIndex + 1}' : phaseLabel[snap.phase]!;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Card(
        child: ListTile(
          leading: VehicleIcon(vehicle.model.visual, width: 52),
          title: Text(vehicle.model.name, style: const TextStyle(fontWeight: FontWeight.w600)),
          subtitle: Text('$status · ${formatKg(vehicle.model.payloadKg)}', style: const TextStyle(color: AppColors.textMuted)),
          trailing: Text('${(vehicle.odometerM / 1000).toStringAsFixed(0)} km', style: const TextStyle(color: AppColors.textMuted)),
        ),
      ),
    );
  }
}

const _purchaseText = {
  PurchaseProblem.noFreeSlot: 'Parkir penuh',
  PurchaseProblem.insufficientCash: 'Kas tidak cukup',
  PurchaseProblem.unknownModel: 'Tidak tersedia',
};

Future<void> _showBuySheet(BuildContext context, GameSession session) => showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      builder: (context) => ListenableBuilder(
        listenable: session,
        builder: (context, _) {
          final models = session.data.content.vehicleModels.values.toList()..sort((a, b) => a.priceIdr.compareTo(b.priceIdr));
          return SafeArea(
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
              children: [
                Text('Beli kendaraan baru', style: Theme.of(context).textTheme.titleLarge!.copyWith(fontWeight: FontWeight.w800)),
                const SizedBox(height: 4),
                Text('Kas ${formatRupiah(session.world.cashIdr)}', style: const TextStyle(color: AppColors.textMuted)),
                const SizedBox(height: 12),
                for (final m in models)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Card(
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Row(children: [
                            VehicleIcon(m.visual, width: 64),
                            const SizedBox(width: 12),
                            Expanded(child: Text(m.name, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16))),
                            Text(formatRupiah(m.priceIdr), style: const TextStyle(color: AppColors.accent, fontWeight: FontWeight.w800)),
                          ]),
                          const SizedBox(height: 4),
                          Text(
                            '${m.vehicleClass.label} · muatan ${formatKg(m.payloadKg)} · '
                            '${m.fuelLPer100Km.toStringAsFixed(1).replaceAll('.', ',')} L/100 km',
                            style: const TextStyle(color: AppColors.textMuted),
                          ),
                          const SizedBox(height: 10),
                          Builder(builder: (context) {
                            final problems = session.world.purchaseProblems(session.depot.id, m.id);
                            return SizedBox(
                              width: double.infinity,
                              child: FilledButton(
                                onPressed: problems.isEmpty
                                    ? () {
                                        session.buyVehicle(m.id);
                                        Navigator.pop(context);
                                      }
                                    : null,
                                child: Text(problems.isEmpty ? 'Beli' : _purchaseText[problems.first]!),
                              ),
                            );
                          }),
                        ]),
                      ),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
