/// Depot perusahaan. Tahap 2b: slot parkir saja; gerbang, dock, gudang
/// sebagai fasilitas ber-level masuk Tahap 3.
class Depot {
  Depot({
    required this.id,
    required this.name,
    required this.cityId,
    required this.roadNode,
    required int parkingSlots,
    List<int?>? slots,
  }) : slots = slots ?? List<int?>.filled(parkingSlots, null) {
    if (this.slots.length != parkingSlots) {
      throw ArgumentError('Jumlah slot tidak cocok: ${this.slots.length} ≠ $parkingSlots');
    }
  }

  final int id;
  final String name;
  final String cityId;

  /// Node graph jalan terdekat dengan gerbang depot.
  final int roadNode;

  /// Isi tiap slot parkir: id kendaraan atau `null` bila kosong.
  final List<int?> slots;

  int get parkingSlots => slots.length;

  int? get firstFreeSlot {
    final i = slots.indexOf(null);
    return i < 0 ? null : i;
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'city': cityId,
        'road_node': roadNode,
        'slots': slots,
      };

  factory Depot.fromJson(Map<String, dynamic> j) {
    final slots = (j['slots'] as List).cast<int?>();
    return Depot(
      id: j['id'] as int,
      name: j['name'] as String,
      cityId: j['city'] as String,
      roadNode: j['road_node'] as int,
      parkingSlots: slots.length,
      slots: List.of(slots),
    );
  }
}
