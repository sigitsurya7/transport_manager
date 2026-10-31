import 'package:sim_core/sim_core.dart';
import 'package:test/test.dart';

class _E extends SimEvent {
  const _E(this.name, {this.spawn});

  final String name;

  /// Bila diisi, handler menjadwalkan event baru `+spawn` detik kemudian.
  final int? spawn;

  @override
  String get type => name;
}

List<String> _run(EventQueue q, int until) {
  final log = <String>[];
  q.runUntil(until, (s, queue) {
    log.add('${s.time}:${(s.event as _E).name}');
    final e = s.event as _E;
    if (e.spawn != null) queue.schedule(s.time + e.spawn!, _E('${e.name}+'));
  });
  return log;
}

void main() {
  test('urut berdasarkan waktu, prioritas, lalu urutan jadwal', () {
    final q = EventQueue()
      ..schedule(10, const _E('c'))
      ..schedule(5, const _E('a'))
      ..schedule(10, const _E('b'), priority: -1)
      ..schedule(10, const _E('d'));
    expect(_run(q, 100), ['5:a', '10:b', '10:c', '10:d']);
  });

  test('event yang dijadwalkan handler di dalam jendela ikut diproses', () {
    final q = EventQueue()..schedule(0, const _E('depart', spawn: 30));
    expect(_run(q, 60), ['0:depart', '30:depart+']);
  });

  test('event di luar jendela menunggu', () {
    final q = EventQueue()
      ..schedule(10, const _E('a'))
      ..schedule(50, const _E('b'));
    expect(_run(q, 20), ['10:a']);
    expect(q.length, 1);
    expect(q.processedUntil, 20);
    expect(_run(q, 50), ['50:b']);
  });

  test('tidak boleh menjadwalkan ke masa lalu', () {
    final q = EventQueue();
    _run(q, 100);
    expect(() => q.schedule(99, const _E('x')), throwsArgumentError);
    expect(() => q.schedule(100, const _E('ok')), returnsNormally);
  });

  test('satu catch-up panjang == banyak catch-up pendek', () {
    EventQueue build() {
      final q = EventQueue();
      for (var i = 0; i < 50; i++) {
        q.schedule((i * 37) % 500, _E('e$i', spawn: i % 7 == 0 ? 45 : null),
            priority: i % 3);
      }
      return q;
    }

    final once = _run(build(), 1000);
    final q2 = build();
    final chunked = <String>[];
    for (var t = 0; t <= 1000; t += 13) {
      chunked.addAll(_run(q2, t));
    }
    chunked.addAll(_run(q2, 1000));
    expect(chunked, once);
  });

  test('snapshot dan restore mempertahankan urutan', () {
    final q = EventQueue()
      ..schedule(3, const _E('x'))
      ..schedule(1, const _E('y'));
    final restored = EventQueue()..restore(q.snapshot());
    expect(_run(restored, 10), ['1:y', '3:x']);
    expect(restored.nextSeq, q.nextSeq);
  });
}
