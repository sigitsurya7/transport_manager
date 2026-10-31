/// Sopir. Tahap 2b: ketersediaan & total jam mengemudi; skill, gaji, dan
/// kelelahan sebagai faktor risiko masuk Tahap 4.
class Driver {
  Driver({
    required this.id,
    required this.name,
    required this.depotId,
    this.drivingSeconds = 0,
    this.tripId,
  });

  final int id;
  final String name;
  final int depotId;

  /// Total detik game mengemudi sepanjang karier.
  int drivingSeconds;

  int? tripId;

  bool get isAvailable => tripId == null;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'depot': depotId,
        'driving_s': drivingSeconds,
        'trip': tripId,
      };

  factory Driver.fromJson(Map<String, dynamic> j) => Driver(
        id: j['id'] as int,
        name: j['name'] as String,
        depotId: j['depot'] as int,
        drivingSeconds: j['driving_s'] as int,
        tripId: j['trip'] as int?,
      );
}
