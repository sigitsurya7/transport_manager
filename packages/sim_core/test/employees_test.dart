import 'dart:convert';

import 'package:sim_core/sim_core.dart';
import 'package:test/test.dart';

import 'maintenance_test.dart' show addCash, runTrip;
import 'support/test_world.dart';

void main() {
  group('rekrutmen sopir', () {
    test('calon deterministik per hari, berganti di hari berikutnya', () {
      final a = newWorld(), b = newWorld();
      final ca = a.driverCandidates(1), cb = b.driverCandidates(1);
      expect(ca, hasLength(a.content.employees.driver.candidates));
      expect([for (final c in ca) (c.name, c.skill)], [for (final c in cb) (c.name, c.skill)]);
      expect(ca.map((c) => c.name), isNot(contains('Budi')), reason: 'nama yang sudah dipakai tidak muncul');
      a.advanceTo(SimWorld.daySeconds);
      expect([for (final c in a.driverCandidates(1)) c.name], isNot([for (final c in ca) c.name]));
    });

    test('calon membawa skill & gaji sesuai aturan; hilang setelah direkrut', () {
      final w = newWorld();
      final rules = w.content.employees.driver;
      final c = w.driverCandidates(1)[1];
      expect(c.skill, inInclusiveRange(rules.hireSkillMin, rules.hireSkillMax));
      w.hire(1, EmployeeRole.driver, candidate: 1);
      final d = w.drivers.values.last;
      expect((d.name, d.skill, d.dailyWageIdr), (c.name, c.skill, c.dailyWageIdr));
      expect(w.driverCandidates(1).map((x) => x.name), isNot(contains(c.name)));
      expect(w.hireProblems(1, role: EmployeeRole.driver, candidate: 9), contains(HireProblem.noCandidate));
    });

    test('sopir lebih terampil bergaji lebih tinggi', () {
      final rules = newWorld().content.employees.driver;
      expect(rules.wageIdr(140000, 0.8), greaterThan(rules.wageIdr(140000, 0.2)));
    });

    test('memberhentikan sopir: tidak saat bertugas, tidak yang terakhir', () {
      final w = newWorld();
      expect(w.canReleaseDriver(driverId), isFalse, reason: 'satu-satunya sopir');
      w.hire(1, EmployeeRole.driver);
      final c = addContract(w, destinationNode: 20, weightKg: 300);
      w.dispatch(contractId: c.id, vehicleId: vehicleId, driverId: driverId, mode: RouteMode.nonToll);
      expect(w.canReleaseDriver(driverId), isFalse);
      final other = w.drivers.keys.last;
      w.releaseDriver(other);
      expect(w.drivers, hasLength(1));
    });
  });

  group('skill', () {
    test('sopir terampil menghemat BBM & mengurangi keausan; estimasi tetap persis', () {
      final novice = newWorld(), expert = newWorld();
      novice.drivers[driverId]!.skill = 0.1;
      expert.drivers[driverId]!.skill = 0.9;
      for (final w in [novice, expert]) {
        final c = addContract(w, destinationNode: 63, weightKg: 500);
        final q = w.check(contractId: c.id, vehicleId: vehicleId, driverId: driverId).nonToll!;
        runTrip(w, dest: 63);
        // runTrip membuat kontrak baru dengan tujuan & berat yang sama.
        expect(-w.ledger.total(LedgerAccount.fuel), q.fuelIdr);
      }
      expect(novice.ledger.total(LedgerAccount.fuel), lessThan(expert.ledger.total(LedgerAccount.fuel)));
      expect(novice.vehicles[vehicleId]!.condition[VehicleComponent.tires]!,
          lessThan(expert.vehicles[vehicleId]!.condition[VehicleComponent.tires]!));
    });

    test('skill naik dengan jam mengemudi', () {
      final w = newWorld();
      final before = w.drivers[driverId]!.skill;
      runTrip(w, dest: 63);
      final d = w.drivers[driverId]!;
      expect(d.skill, closeTo(before + w.content.employees.driver.skillGainPerHour * d.drivingSeconds / 3600, 1e-9));
    });
  });

  group('kelelahan', () {
    test('bertambah saat mengemudi, pulih saat istirahat', () {
      final w = newWorld();
      final rules = w.content.employees.driver;
      runTrip(w, dest: 63);
      final d = w.drivers[driverId]!;
      final tired = w.driverFatigue(driverId);
      expect(tired, closeTo(rules.fatigueFor(d.drivingSeconds), 1e-9));
      expect(tired, greaterThan(rules.recoveryFor(600)));
      w.advanceTo(w.now + 600);
      expect(w.driverFatigue(driverId), closeTo(tired - rules.recoveryFor(600), 1e-9));
      w.advanceTo(w.now + (rules.fullRestHours * 3600).round());
      expect(w.driverFatigue(driverId), 0);
    });

    test('estimasi menunjukkan kelelahan saat kembali', () {
      final w = newWorld();
      final c = addContract(w, destinationNode: 63, weightKg: 300);
      final q = w.check(contractId: c.id, vehicleId: vehicleId, driverId: driverId).nonToll!;
      expect(q.fatigueAfter, closeTo(w.content.employees.driver.fatigueFor(q.outboundS + q.inboundS), 1e-9));
    });

    test('sopir yang mencapai batas jam mengemudi wajib istirahat', () {
      final w = newWorld();
      w.drivers[driverId]!
        ..fatigue = 1.0
        ..restingSince = w.now;
      final c = addContract(w, destinationNode: 20, weightKg: 300);
      expect(w.check(contractId: c.id, vehicleId: vehicleId, driverId: driverId).problems,
          contains(DispatchProblem.driverNeedsRest));
      w.advanceTo(w.now + 3600);
      expect(w.check(contractId: c.id, vehicleId: vehicleId, driverId: driverId).problems, isEmpty);
    });
  });

  group('mekanik', () {
    test('mempercepat servis di bengkel sendiri sampai batas per bay', () {
      final w = newWorld();
      addCash(w, 2000000000);
      w.vehicles[vehicleId]!.condition[VehicleComponent.tires] = 0.2;
      final outside = w.maintenanceQuote(vehicleId, 'tires').durationS;
      w.hire(1, EmployeeRole.mechanic);
      expect(w.maintenanceQuote(vehicleId, 'tires').durationS, outside,
          reason: 'bengkel luar: mekanik tidak berpengaruh');
      w.releaseStaff(1, EmployeeRole.mechanic);
      upgradeTo(w, FacilityType.workshop, levelWith(w, FacilityType.workshop, 'bays', 1));
      final none = w.maintenanceQuote(vehicleId, 'tires').durationS;
      w.hire(1, EmployeeRole.mechanic);
      final one = w.maintenanceQuote(vehicleId, 'tires').durationS;
      w.hire(1, EmployeeRole.mechanic);
      final two = w.maintenanceQuote(vehicleId, 'tires').durationS;
      w.hire(1, EmployeeRole.mechanic);
      final three = w.maintenanceQuote(vehicleId, 'tires').durationS;
      expect(one, lessThan(none));
      expect(two, lessThan(one));
      expect(three, two, reason: 'bengkel 1 bay: efektif maksimal 2 mekanik');
    });

    test('gaji harian mencakup sopir (per orang), staf gudang, dan mekanik', () {
      final w = newWorld();
      w.hire(1, EmployeeRole.mechanic);
      w.hire(1, EmployeeRole.driver);
      final wage = w.content.employees.dailyWageIdr;
      expect(
        w.dailyPayrollIdr(),
        w.drivers.values.fold(0, (s, d) => s + d.dailyWageIdr) + wage[EmployeeRole.mechanic]!,
      );
      expect(w.staffCount(w.depots[1]!), 3);
    });
  });

  test('save/load menyimpan skill, gaji, kelelahan, mekanik; save lama dapat nilai default', () {
    final w = newWorld();
    w.hire(1, EmployeeRole.mechanic);
    runTrip(w, dest: 63);
    w.advanceTo(w.now + 1800);
    final json = jsonDecode(jsonEncode(w.toJson())) as Map<String, dynamic>;
    final loaded = SimWorld.fromJson(json, graph: w.graph, content: w.content);
    expect(jsonEncode(loaded.toJson()), jsonEncode(w.toJson()));
    expect(loaded.driverFatigue(driverId), w.driverFatigue(driverId));

    for (final d in json['drivers'] as List) {
      (d as Map).removeWhere((k, _) => const {'skill', 'wage_idr', 'fatigue', 'resting_since'}.contains(k));
    }
    for (final d in json['depots'] as List) {
      (d as Map).remove('mechanics');
    }
    final legacy = SimWorld.fromJson(json, graph: w.graph, content: w.content);
    final rules = w.content.employees.driver;
    expect(legacy.drivers[driverId]!.skill, rules.defaultSkill);
    expect(legacy.driverFatigue(driverId), 0);
    expect(legacy.depots[1]!.mechanics, 0);
  });
}
