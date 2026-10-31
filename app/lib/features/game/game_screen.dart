import 'package:flutter/material.dart';

import '../../widgets/game_icons.dart';
import '../../app/theme.dart';
import '../../game/game_session.dart';
import '../../util/format.dart';
import '../contracts/contracts_screen.dart';
import '../depot/depot_screen.dart';
import '../finance/finance_screen.dart';
import '../fleet/fleet_screen.dart';
import '../map/map_screen.dart';
import 'log_text.dart';

class GameScreen extends StatefulWidget {
  const GameScreen({super.key, required this.session});

  final GameSession session;

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> {
  int _tab = 0;

  GameSession get session => widget.session;

  @override
  void initState() {
    super.initState();
    session.start();
    WidgetsBinding.instance.addPostFrameCallback((_) => _showOfflineSummary());
    session.addListener(_onSessionChanged);
  }

  @override
  void dispose() {
    session.removeListener(_onSessionChanged);
    session.dispose();
    super.dispose();
  }

  void _onSessionChanged() {
    // Ringkasan juga muncul setelah kembali dari background.
    if (mounted) _showOfflineSummary();
  }

  void _showOfflineSummary() {
    final summary = session.takeOfflineSummary();
    if (summary == null || !mounted) return;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surface,
      showDragHandle: true,
      builder: (_) => _OfflineSummarySheet(session: session, summary: summary),
    );
  }

  void _showSettings() => showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    backgroundColor: AppColors.surface,
    builder: (sheet) => ListenableBuilder(
      listenable: session,
      builder: (sheet, _) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Pengaturan', style: Theme.of(sheet).textTheme.titleLarge!.copyWith(fontWeight: FontWeight.w800)),
              const SizedBox(height: 4),
              Text(
                '${session.meta.companyName} · ${session.city.name}',
                style: const TextStyle(color: AppColors.textMuted),
              ),
              const SizedBox(height: 16),
              OutlinedButton(
                onPressed: () async {
                  final messenger = ScaffoldMessenger.of(context);
                  final navigator = Navigator.of(sheet);
                  await session.save();
                  navigator.pop();
                  messenger.showSnackBar(const SnackBar(content: Text('Permainan tersimpan.')));
                },
                child: const Text('Simpan sekarang'),
              ),
              const SizedBox(height: 10),
              FilledButton(
                onPressed: () {
                  Navigator.pop(sheet);
                  _exit();
                },
                child: const Text('Simpan & kembali ke menu utama'),
              ),
              const SizedBox(height: 8),
              const Text(
                'Game juga tersimpan otomatis. Waktu tetap berjalan saat game ditutup (maks. 48 jam).',
                style: TextStyle(color: AppColors.textMuted, fontSize: 12),
              ),
              if (GameSession.devTools) ...[
                const Divider(height: 32),
                const Text(
                  'MODE DEV',
                  style: TextStyle(
                    color: AppColors.accent,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.2,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 10),
                const Text('Kecepatan waktu'),
                const SizedBox(height: 6),
                SegmentedButton<int>(
                  segments: [
                    for (final m in session.clock.entitlement.allowedMultipliers.toList()..sort())
                      ButtonSegment(value: m, label: Text('$m×')),
                  ],
                  selected: {session.clock.speedMultiplier},
                  onSelectionChanged: (v) => session.setSpeed(v.single),
                ),
                const SizedBox(height: 14),
                const Text('Tambah uang (dicatat sebagai "Dana mode dev")'),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final amount in const [10000000, 100000000, 1000000000])
                      OutlinedButton(
                        onPressed: () => session.devAddCash(amount),
                        child: Text('+${formatRupiahCompact(amount)}'),
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    ),
  );

  Future<void> _exit() async {
    await session.close();
    if (mounted) Navigator.of(context).pop();
  }

  void _goTo(int tab) => setState(() => _tab = tab);

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      // Tombol kembali Android membuka pengaturan (bukan langsung keluar).
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _showSettings();
      },
      child: Scaffold(
        appBar: AppBar(
          automaticallyImplyLeading: false,
          titleSpacing: 16,
          title: ListenableBuilder(
            listenable: session,
            builder: (_, _) => Row(
              children: [
                Text(
                  formatGameClock(session.world.now),
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      const GlyphIcon(GameGlyph.finance, size: 20, color: AppColors.accent),
                      const SizedBox(width: 6),
                      Flexible(
                        // Angka kas panjang menyusut agar tidak menabrak tombol pengaturan.
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            formatRupiahCompact(session.world.cashIdr),
                            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          actions: [
            IconButton(
              tooltip: 'Pengaturan',
              onPressed: _showSettings,
              icon: const GlyphIcon(GameGlyph.settings, color: AppColors.text),
            ),
            const SizedBox(width: 4),
          ],
        ),
        body: IndexedStack(
          index: _tab,
          children: [
            DepotScreen(session: session, active: _tab == 0, onOpenContracts: () => _goTo(2)),
            MapScreen(session: session, active: _tab == 1),
            ContractsScreen(session: session, onShowMap: () => _goTo(1)),
            FleetScreen(session: session),
            FinanceScreen(session: session),
          ],
        ),
        bottomNavigationBar: NavigationBar(
          selectedIndex: _tab,
          onDestinationSelected: _goTo,
          destinations: const [
            NavigationDestination(icon: GlyphIcon(GameGlyph.depot), label: 'Depot'),
            NavigationDestination(icon: GlyphIcon(GameGlyph.map), label: 'Peta'),
            NavigationDestination(icon: GlyphIcon(GameGlyph.contracts), label: 'Kontrak'),
            NavigationDestination(icon: GlyphIcon(GameGlyph.fleet), label: 'Armada'),
            NavigationDestination(icon: GlyphIcon(GameGlyph.finance), label: 'Keuangan'),
          ],
        ),
      ),
    );
  }
}

class _OfflineSummarySheet extends StatelessWidget {
  const _OfflineSummarySheet({required this.session, required this.summary});

  final GameSession session;
  final OfflineSummary summary;

  @override
  Widget build(BuildContext context) {
    final hours = summary.realElapsed.inMinutes / 60;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Selama kamu pergi',
              style: Theme.of(context).textTheme.titleLarge!.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 4),
            Text(
              hours >= 1
                  ? '${hours.toStringAsFixed(1).replaceAll('.', ',')} jam berlalu'
                  : summary.realElapsed.inMinutes >= 1
                  ? '${summary.realElapsed.inMinutes} menit berlalu'
                  : 'Kurang dari 1 menit berlalu',
              style: const TextStyle(color: AppColors.textMuted),
            ),
            if (summary.truncated)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text(
                  'Waktu offline dibatasi 48 jam; sisanya tidak dihitung.',
                  style: TextStyle(color: AppColors.accent),
                ),
              ),
            const SizedBox(height: 12),
            if (summary.entries.isEmpty)
              const Text('Tidak ada kejadian. Armada menunggu perintahmu.')
            else
              ConstrainedBox(
                constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.4),
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final e in summary.entries)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SizedBox(
                              width: 56,
                              child: Text(formatGameTime(e.time), style: const TextStyle(color: AppColors.textMuted)),
                            ),
                            Expanded(child: Text(logText(session.world, e))),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton(onPressed: () => Navigator.pop(context), child: const Text('Lanjut bekerja')),
            ),
          ],
        ),
      ),
    );
  }
}
