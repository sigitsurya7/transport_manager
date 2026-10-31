/// Event simulasi. Harus berupa data murni yang bisa diserialisasi.
abstract class SimEvent {
  const SimEvent();

  /// Nama tipe untuk serialisasi dan logging.
  String get type;
}

/// Event yang sudah dijadwalkan.
class ScheduledEvent {
  const ScheduledEvent({
    required this.time,
    required this.priority,
    required this.seq,
    required this.event,
  });

  /// Detik game.
  final int time;

  /// Lebih kecil diproses lebih dulu bila waktunya sama.
  final int priority;

  /// Nomor urut monoton; pemecah seri terakhir agar urutan deterministik.
  final int seq;

  final SimEvent event;

  int compareTo(ScheduledEvent other) {
    if (time != other.time) return time.compareTo(other.time);
    if (priority != other.priority) return priority.compareTo(other.priority);
    return seq.compareTo(other.seq);
  }

  @override
  String toString() => 'ScheduledEvent(t=$time p=$priority #$seq ${event.type})';
}

typedef EventHandler = void Function(ScheduledEvent scheduled, EventQueue queue);

/// Antrean prioritas event diskret.
///
/// Urutan: `(time, priority, seq)`. Satu jalur kode yang sama dipakai untuk
/// bermain aktif dan catch-up offline, sehingga hasilnya identik.
class EventQueue {
  EventQueue({int nextSeq = 0, int processedUntil = 0})
      : _nextSeq = nextSeq,
        _processedUntil = processedUntil;

  final List<ScheduledEvent> _heap = [];
  int _nextSeq;
  int _processedUntil;

  int get nextSeq => _nextSeq;
  int get processedUntil => _processedUntil;
  int get length => _heap.length;
  bool get isEmpty => _heap.isEmpty;

  ScheduledEvent? get peek => _heap.isEmpty ? null : _heap.first;

  /// Jadwalkan [event] pada detik game [time].
  ///
  /// Menjadwalkan ke masa lalu (sebelum waktu yang sudah diproses) ditolak,
  /// karena akan merusak urutan event.
  ScheduledEvent schedule(int time, SimEvent event, {int priority = 0}) {
    if (time < _processedUntil) {
      throw ArgumentError.value(
          time, 'time', 'sebelum waktu yang sudah diproses ($_processedUntil)');
    }
    final scheduled = ScheduledEvent(
      time: time,
      priority: priority,
      seq: _nextSeq++,
      event: event,
    );
    _push(scheduled);
    return scheduled;
  }

  /// Muat ulang event dari save (urutan `seq` asli dipertahankan).
  void restore(Iterable<ScheduledEvent> events) {
    for (final e in events) {
      _push(e);
      if (e.seq >= _nextSeq) _nextSeq = e.seq + 1;
    }
  }

  /// Proses semua event dengan `time <= until`, termasuk event baru yang
  /// dijadwalkan handler di dalam jendela waktu ini. Mengembalikan jumlah
  /// event yang diproses.
  int runUntil(int until, EventHandler handler) {
    var count = 0;
    while (_heap.isNotEmpty && _heap.first.time <= until) {
      final next = _pop();
      _processedUntil = next.time;
      handler(next, this);
      count++;
    }
    if (until > _processedUntil) _processedUntil = until;
    return count;
  }

  /// Salinan terurut untuk disimpan.
  List<ScheduledEvent> snapshot() {
    final copy = List.of(_heap)..sort((a, b) => a.compareTo(b));
    return copy;
  }

  // ---- binary heap

  void _push(ScheduledEvent e) {
    _heap.add(e);
    var i = _heap.length - 1;
    while (i > 0) {
      final parent = (i - 1) >> 1;
      if (_heap[i].compareTo(_heap[parent]) >= 0) break;
      _swap(i, parent);
      i = parent;
    }
  }

  ScheduledEvent _pop() {
    final top = _heap.first;
    final last = _heap.removeLast();
    if (_heap.isNotEmpty) {
      _heap[0] = last;
      var i = 0;
      while (true) {
        final l = 2 * i + 1;
        final r = l + 1;
        var smallest = i;
        if (l < _heap.length && _heap[l].compareTo(_heap[smallest]) < 0) smallest = l;
        if (r < _heap.length && _heap[r].compareTo(_heap[smallest]) < 0) smallest = r;
        if (smallest == i) break;
        _swap(i, smallest);
        i = smallest;
      }
    }
    return top;
  }

  void _swap(int a, int b) {
    final t = _heap[a];
    _heap[a] = _heap[b];
    _heap[b] = t;
  }
}
