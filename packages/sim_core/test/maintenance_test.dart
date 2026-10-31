import 'dart:convert';

import 'package:sim_core/sim_core.dart';
import 'package:test/test.dart';

import 'support/test_world.dart';

void addCash(SimWorld w, int idr) =>
    w.ledger.post(LedgerEntry(time: w.now, account: LedgerAccount.openingBalance, amountIdr: idr, ref: 'test'));

/// Jalankan satu kontrak sampai kendaraan kembali siap.
void runTrip(SimWorld w, {int dest = 20, int weightKg = 500, int vehicle = vehicleId, int driver = driverId}) {
  final c = addContract(w, destinationNode: dest, weightKg: weightKg);
  w.dispatch(contractId: c.id, vehicleId: vehicle, driverId: driver, mode: RouteMode.nonToll);
  final trip = w.trips.values.last;
  while (trip.isActive) {
    w.advanceTo(w.queue.peek!.time);
  }
}

void main() {
  group('keausan', () {
    test('komponen aus setelah trip; ban & rem lebih cepat dari kelistrikan', () {
      final w = newWorld();
      runTrip(w, dest: 63);
      final c = w.vehicles[vehicleId]!.condition;
      for (final v in c.values) {
        expect(v, lessThan(1.0));
      }
      expect(c[VehicleComponent.tires]!, lessThan(c[VehicleComponent.electrical]!));
      expect(c[VehicleComponent.brakes]!, lessThan(c[VehicleComponent.engine]!));
    });

    test('muatan berat mempercepat keausan', () {
      final light = newWorld(), heavy = newWorld();
      runTrip(light, dest: 63, weightKg: 100);
      runTrip(heavy, dest: 63, weightKg: 900);
      expect(heavy.vehicles[vehicleId]!.condition[VehicleComponent.tires]!,
          lessThan(light.vehicles[vehicleId]!.condition[VehicleComponent.tires]!));
    });

    test('mesin & ban aus: BBM lebih boros, perjalanan lebih lambat', () {
      final w = newWorld();
      final c = addContract(w, destinationNode: 63);
      final fresh = w.check(contractId: c.id, vehicleId: vehicleId, driverId: driverId).nonToll!;
      final v = w.vehicles[vehicleId]!;
      v.condition[VehicleComponent.engine] = 0.3;
      v.condition[VehicleComponent.transmission] = 0.4;
      v.condition[VehicleComponent.tires] = 0.2;
      final worn = w.check(contractId: c.id, vehicleId: vehicleId, driverId: driverId).nonToll!;
      expect(worn.fuelIdr, greaterThan(fresh.fuelIdr));
      expect(worn.outboundS, greaterThan(fresh.outboundS));
      expect(w.fuelLPer100Km(v), greaterThan(v.model.fuelLPer100Km));
    });
  });

  group('perawatan', () {
    SimWorld wornWorld() {
      final w = newWorld();
      final v = w.vehicles[vehicleId]!;
      for (final c in VehicleComponent.values) {
        v.condition[c] = 0.4;
      }
      return w;
    }

    test('tanpa bengkel: servis di bengkel luar, lebih mahal & lama; kendaraan tak bisa ditugaskan', () {
      final w = wornWorld();
      final action = w.content.maintenance.action('service');
      final shop = w.facility(w.depots[1]!, FacilityType.workshop);
      expect(w.workshopBays(w.depots[1]!), 0);
      final q = w.maintenanceQuote(vehicleId, 'service');
      expect(q.costIdr, (action.costIdr * shop.doubleStat('cost_factor')).round());
      expect(q.durationS, greaterThan(action.minutes * 60));

      final cash = w.cashIdr;
      final job = w.startMaintenance(vehicleId, 'service');
      expect(w.cashIdr, cash - q.costIdr);
      expect(job.waiting, isFalse, reason: 'bengkel luar langsung mengerjakan');
      final c = addContract(w, destinationNode: 20);
      expect(w.check(contractId: c.id, vehicleId: vehicleId, driverId: driverId).problems,
          contains(DispatchProblem.vehicleInWorkshop));
      expect(w.vehicleSnapshot(vehicleId).inWorkshop, isTrue);

      w.advanceTo(job.finishAt!);
      final v = w.vehicles[vehicleId]!;
      expect(v.maintenance, isNull);
      expect(v.condition[VehicleComponent.engine], closeTo(0.4 + action.restore[VehicleComponent.engine]!, 1e-9));
      expect(v.condition[VehicleComponent.tires], 0.4, reason: 'servis rutin tidak mengganti ban');
      expect(w.ledger.total(LedgerAccount.maintenance), -q.costIdr);
    });

    test('bengkel 1 bay: kendaraan kedua antre sampai bay kosong', () {
      final w = wornWorld();
      addCash(w, 2000000000);
      w.advanceTo(w.startUpgrade(1, FacilityType.workshop).finishAt);
      final second = w.buyVehicle(1, 'pickup_box_1t');
      second.condition[VehicleComponent.tires] = 0.1;
      final a = w.startMaintenance(vehicleId, 'tires');
      final b = w.startMaintenance(second.id, 'tires');
      expect(a.waiting, isFalse);
      expect(b.waiting, isTrue);
      w.advanceTo(a.finishAt!);
      expect(b.waiting, isFalse);
      expect(b.startedAt, a.finishAt);
      w.advanceTo(b.finishAt!);
      expect(second.condition[VehicleComponent.tires], 1.0);
    });

    test('tindakan yang tidak diperlukan ditolak', () {
      final w = newWorld();
      expect(w.maintenanceProblems(vehicleId, 'tires'), contains(MaintenanceProblem.notNeeded));
    });

    test('save di tengah servis lalu load menghasilkan akhir yang sama', () {
      final w = wornWorld();
      final job = w.startMaintenance(vehicleId, 'overhaul');
      w.advanceTo(w.now + 600);
      final loaded = SimWorld.fromJson(
        jsonDecode(jsonEncode(w.toJson())) as Map<String, dynamic>,
        graph: w.graph,
        content: w.content,
      );
      w.advanceTo(job.finishAt! + 1);
      loaded.advanceTo(job.finishAt! + 1);
      expect(jsonEncode(loaded.toJson()), jsonEncode(w.toJson()));
      expect(loaded.vehicles[vehicleId]!.condition[VehicleComponent.engine], 1.0);
    });

    test('save lama tanpa data kondisi: semua komponen baru', () {
      final w = newWorld();
      final json = jsonDecode(jsonEncode(w.toJson())) as Map<String, dynamic>;
      for (final v in (json['vehicles'] as List).cast<Map<String, dynamic>>()) {
        v.remove('condition');
        v.remove('maintenance');
      }
      final loaded = SimWorld.fromJson(json, graph: w.graph, content: w.content);
      expect(loaded.vehicles[vehicleId]!.condition.values, everyElement(1.0));
      expect(loaded.depots[1]!.level(FacilityType.workshop), 1);
    });
  });
}
