import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:sim_core/sim_core.dart';

import '../../app/theme.dart';
import '../../game/game_session.dart';
import '../../util/format.dart';
import 'dispatch_sheet.dart';

/// Pilih supplier, barang, dan jumlah untuk mengisi stok gudang; lalu
/// lanjut ke lembar dispatch (kendaraan, sopir, rute).
Future<void> showRestockSheet(BuildContext context, GameSession session) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  backgroundColor: AppColors.surface,
  builder: (_) => _RestockSheet(session: session),
);

class _RestockSheet extends StatefulWidget {
  const _RestockSheet({required this.session});

  final GameSession session;

  @override
  State<_RestockSheet> createState() => _RestockSheetState();
}

class _RestockSheetState extends State<_RestockSheet> {
  Supplier? _supplier;
  String? _cargo;
  int _units = 0;

  List<Supplier> get _suppliers => widget.session.world
      .suppliersFor(widget.session.depot.id)
      .where((s) => s.sells.any((c) => widget.session.data.content.cargoTypes[c]!.storable))
      .toList();

  @override
  Widget build(BuildContext context) {
    final session = widget.session;
    final world = session.world;
    final cargoTypes = session.data.content.cargoTypes;
    final suppliers = _suppliers;
    final supplier = _supplier ?? (suppliers.isEmpty ? null : suppliers.first);
    final options = supplier?.sells.where((c) => cargoTypes[c]!.storable).toList() ?? const <String>[];
    final cargoId = (_cargo != null && options.contains(_cargo)) ? _cargo : (options.isEmpty ? null : options.first);
    final cargo = cargoId == null ? null : cargoTypes[cargoId];
    final payload = world.vehicles.values.map((v) => v.model.payloadKg).fold(0, math.max);
    final freeM3 = world.warehouseFreeM3(session.depot);
    final maxUnits = cargo == null
        ? 0
        : math.max(0, math.min(payload ~/ cargo.unitWeightKg, (freeM3 / cargo.unitVolumeM3).floor()));
    final units = _units.clamp(0, maxUnits);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Isi stok gudang', style: Theme.of(context).textTheme.titleLarge!.copyWith(fontWeight: FontWeight.w800)),
            Text(
              'Ruang kosong ${freeM3.toStringAsFixed(1)} m³ · harga grosir '
              '${session.data.content.economy.restockDiscountPct}% lebih murah',
              style: const TextStyle(color: AppColors.textMuted),
            ),
            const SizedBox(height: 16),
            if (supplier == null)
              const Text('Belum ada supplier barang gudang di kota ini.')
            else ...[
              DropdownButtonFormField<Supplier>(
                initialValue: supplier,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Supplier', border: OutlineInputBorder()),
                items: [for (final s in suppliers) DropdownMenuItem(value: s, child: Text(s.name))],
                onChanged: (s) => setState(() {
                  _supplier = s;
                  _cargo = null;
                }),
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                key: ValueKey(supplier.id),
                initialValue: cargoId,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Barang', border: OutlineInputBorder()),
                items: [
                  for (final c in options)
                    DropdownMenuItem(
                      value: c,
                      child: Text(
                        '${cargoTypes[c]!.name} · ${formatRupiah(session.data.content.economy.restockPrice(cargoTypes[c]!.priceIdr))}/${cargoTypes[c]!.unit}',
                      ),
                    ),
                ],
                onChanged: (c) => setState(() => _cargo = c),
              ),
              const SizedBox(height: 10),
              if (cargo != null) ...[
                Text('Jumlah: $units ${cargo.unit} · ${formatKg(units * cargo.unitWeightKg)} · '
                    '${(units * cargo.unitVolumeM3).toStringAsFixed(1)} m³'),
                Slider(
                  value: units.toDouble(),
                  max: math.max(1, maxUnits).toDouble(),
                  divisions: math.max(1, maxUnits),
                  onChanged: maxUnits == 0 ? null : (v) => setState(() => _units = v.round()),
                ),
                Text(
                  'Modal ${formatRupiah(units * session.data.content.economy.restockPrice(cargo.priceIdr))}',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ],
            ],
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: supplier == null || cargo == null || units <= 0
                    ? null
                    : () {
                        final contract = session.planRestock(supplier, [OrderLine(cargo.id, units)]);
                        final navigator = Navigator.of(context);
                        navigator.pop();
                        showDispatchSheet(navigator.context, session, contract);
                      },
                child: const Text('Pilih kendaraan & rute'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
