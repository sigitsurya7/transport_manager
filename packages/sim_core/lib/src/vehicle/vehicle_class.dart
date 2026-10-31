/// Kelas kendaraan, diurutkan dari terkecil ke terbesar.
///
/// Urutan enum dipakai untuk aturan "minimal kelas X".
enum VehicleClass {
  pickupOpen('pickup_open', 'Pikap losbak'),
  pickupBox('pickup_box', 'Pikap box'),
  miniTruck('mini_truck', 'Mini truck'),
  lightTruck('light_truck', 'Light truck'),
  mediumTruck('medium_truck', 'Medium truck'),
  heavyRigid('heavy_rigid', 'Heavy rigid truck'),
  tractorHead('tractor_head', 'Tractor head');

  const VehicleClass(this.id, this.label);

  final String id;
  final String label;

  bool isAtLeast(VehicleClass other) => index >= other.index;

  static VehicleClass parse(String id) => VehicleClass.values.firstWhere(
        (c) => c.id == id,
        orElse: () => throw FormatException('Kelas kendaraan tidak dikenal: $id'),
      );
}
