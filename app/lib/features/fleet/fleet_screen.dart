import 'package:flutter/material.dart';
import 'package:sim_core/sim_core.dart';

import '../../widgets/game_icons.dart';
import '../../app/theme.dart';
import '../../game/game_session.dart';
import '../../util/format.dart';
import '../contracts/trip_card.dart';
import 'dealer_sheet.dart';
import 'staff_section.dart';
import 'vehicle_sheet.dart';

/// Armada & karyawan: kendaraan, sopir, staf gudang, mekanik, kapasitas kantor.
class FleetScreen extends StatelessWidget {
  const FleetScreen({super.key, required this.session});

  final GameSession session;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: session,
    builder: (context, _) {
      final world = session.world;
      final depot = session.depot;
      return ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          _Header(
            'KENDARAAN',
            trailing: TextButton.icon(
              onPressed: () => showDealerSheet(context, session),
              icon: const GlyphIcon(GameGlyph.fleet, size: 18, color: AppColors.accent),
              label: const Text('Beli'),
            ),
          ),
          for (final v in world.vehicles.values) _VehicleTile(session: session, vehicle: v),
          Padding(
            padding: const EdgeInsets.only(top: 4, bottom: 20),
            child: Text(
              'Slot parkir terpakai ${depot.slots.whereType<int>().length}/${depot.parkingSlots}',
              style: const TextStyle(color: AppColors.textMuted, fontSize: 13),
            ),
          ),
          _Header(
            'KARYAWAN',
            trailing: Text(
              'Kantor ${world.staffCount(depot)}/${world.staffMax(depot)}',
              style: const TextStyle(color: AppColors.textMuted),
            ),
          ),
          StaffSection(session: session),
          const SizedBox(height: 12),
          Text(
            'Gaji harian total ${formatRupiah(world.dailyPayrollIdr())} · dibayar tiap pukul 00.00',
            style: const TextStyle(color: AppColors.textMuted, fontSize: 13),
          ),
        ],
      );
    },
  );
}

class _Header extends StatelessWidget {
  const _Header(this.text, {this.trailing});

  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Row(
      children: [
        Expanded(
          child: Text(
            text,
            style: const TextStyle(
              color: AppColors.textMuted,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.2,
              fontSize: 12,
            ),
          ),
        ),
        ?trailing,
      ],
    ),
  );
}

class _VehicleTile extends StatelessWidget {
  const _VehicleTile({required this.session, required this.vehicle});

  final GameSession session;
  final Vehicle vehicle;

  @override
  Widget build(BuildContext context) {
    final snap = session.world.vehicleSnapshot(vehicle.id);
    final status = snap.inWorkshop
        ? 'Di bengkel'
        : snap.phase == null
        ? 'Siap di slot ${vehicle.slotIndex + 1}'
        : phaseLabel[snap.phase]!;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Card(
        child: ListTile(
          onTap: () => showVehicleSheet(context, session, vehicle),
          leading: VehicleIcon(vehicle.model.visual, width: 52),
          title: Text(vehicle.model.name, style: const TextStyle(fontWeight: FontWeight.w600)),
          subtitle: Text(
            '$status · ${formatKg(vehicle.model.payloadKg)}',
            style: const TextStyle(color: AppColors.textMuted),
          ),
          trailing: Text(
            '${(vehicle.odometerM / 1000).toStringAsFixed(0)} km',
            style: const TextStyle(color: AppColors.textMuted),
          ),
        ),
      ),
    );
  }
}
