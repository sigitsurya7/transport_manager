import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:persistence/persistence.dart';

import '../../app/providers.dart';
import '../../app/theme.dart';
import '../../game/game_session.dart';
import '../../util/format.dart';
import '../game/game_screen.dart';
import '../new_game/new_game_screen.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  bool _busy = false;

  Future<void> _open(Future<GameSession> Function() create) async {
    setState(() => _busy = true);
    try {
      final session = await create();
      if (!mounted) return;
      await Navigator.of(context).push(MaterialPageRoute(builder: (_) => GameScreen(session: session)));
    } on Object catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Gagal memuat: $e')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _newGame() async {
    final session = await Navigator.of(context)
        .push<GameSession>(MaterialPageRoute(builder: (_) => const NewGameScreen()));
    if (session != null && mounted) await _open(() async => session);
  }

  Future<void> _delete(SaveStore store, SaveMeta meta) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Hapus permainan?'),
        content: Text('“${meta.companyName}” akan dihapus permanen dari perangkat ini.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Batal')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.negative),
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Hapus'),
          ),
        ],
      ),
    );
    if (ok == true) setState(() => store.delete(meta.slotId));
  }

  @override
  Widget build(BuildContext context) {
    final data = ref.watch(gameDataProvider);
    final store = ref.watch(saveStoreProvider);
    final ready = data.hasValue && store.hasValue;
    final saves = store.value?.listSlots() ?? const <SaveMeta>[];

    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 32, 20, 24),
          children: [
            const Icon(Icons.local_shipping_rounded, size: 52, color: AppColors.accent),
            const SizedBox(height: 12),
            Text('Transport Manager',
                style: Theme.of(context).textTheme.headlineMedium!.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            const Text('Bangun perusahaan logistik dari satu pikap.',
                style: TextStyle(color: AppColors.textMuted)),
            const SizedBox(height: 28),
            FilledButton.icon(
              onPressed: ready && !_busy ? _newGame : null,
              icon: const Icon(Icons.add_road_rounded),
              label: const Text('Permainan baru'),
            ),
            if (data.hasError || store.hasError)
              Padding(
                padding: const EdgeInsets.only(top: 16),
                child: Text('Data game gagal dimuat: ${data.error ?? store.error}',
                    style: const TextStyle(color: AppColors.negative)),
              ),
            if (_busy) const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator())),
            if (saves.isNotEmpty) ...[
              const SizedBox(height: 32),
              const Text('LANJUTKAN',
                  style: TextStyle(color: AppColors.textMuted, fontWeight: FontWeight.w700, letterSpacing: 1.2)),
              const SizedBox(height: 8),
              for (final m in saves)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Card(
                    child: ListTile(
                      contentPadding: const EdgeInsets.fromLTRB(16, 6, 6, 6),
                      title: Text(m.companyName, style: const TextStyle(fontWeight: FontWeight.w700)),
                      subtitle: Text(
                        '${ready ? data.value!.city(m.cityId).name : m.cityId} · ${formatGameClock(m.simTime)}\n'
                        '${formatRupiah(m.cashIdr)}',
                        style: const TextStyle(color: AppColors.textMuted, height: 1.4),
                      ),
                      isThreeLine: true,
                      onTap: ready && !_busy
                          ? () => _open(() => GameSession.load(
                                data: data.value!,
                                store: store.value!,
                                bundle: DefaultAssetBundle.of(context),
                                slotId: m.slotId,
                              ))
                          : null,
                      trailing: IconButton(
                        tooltip: 'Hapus',
                        icon: const Icon(Icons.delete_outline_rounded, color: AppColors.textMuted),
                        onPressed: _busy ? null : () => _delete(store.value!, m),
                      ),
                    ),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}
