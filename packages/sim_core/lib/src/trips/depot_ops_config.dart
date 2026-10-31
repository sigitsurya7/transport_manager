/// Durasi aktivitas depot & bongkar muat (`content/depot_ops.json`), detik game.
///
/// Waktu lewat gerbang ditentukan level gerbang (`facilities.json`); waktu
/// muat di depot dipercepat level dock & staf gudang (lihat `SimWorld`).
class DepotOpsConfig {
  const DepotOpsConfig({
    this.slotToDockS = 120,
    this.loadingBaseS = 600,
    this.loadingPerTonS = 900,
    this.dockToGateS = 60,
    this.unloadingBaseS = 600,
    this.unloadingPerTonS = 900,
    this.gateToSlotS = 120,
    this.inspectionS = 600,
  });

  factory DepotOpsConfig.fromJson(Map<String, dynamic> j) {
    int v(String k) => (j[k] as num).toInt();
    return DepotOpsConfig(
      slotToDockS: v('slot_to_dock_s'),
      loadingBaseS: v('loading_base_s'),
      loadingPerTonS: v('loading_per_ton_s'),
      dockToGateS: v('dock_to_gate_s'),
      unloadingBaseS: v('unloading_base_s'),
      unloadingPerTonS: v('unloading_per_ton_s'),
      gateToSlotS: v('gate_to_slot_s'),
      inspectionS: v('inspection_s'),
    );
  }

  final int slotToDockS;
  final int loadingBaseS;
  final int loadingPerTonS;
  final int dockToGateS;
  final int unloadingBaseS;
  final int unloadingPerTonS;
  final int gateToSlotS;
  final int inspectionS;

  int loadingS(int cargoKg) => loadingBaseS + (loadingPerTonS * cargoKg / 1000).round();
  int unloadingS(int cargoKg) => unloadingBaseS + (unloadingPerTonS * cargoKg / 1000).round();
}
