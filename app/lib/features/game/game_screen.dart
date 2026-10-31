import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../game/game_session.dart';
import '../../util/format.dart';
import '../contracts/contracts_screen.dart';
import '../depot/depot_screen.dart';
import '../finance/finance_screen.dart';
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

  Future<void> _exit() async {
    await session.close();
    if (mounted) Navigator.of(context).pop();
  }

  void _goTo(int tab) => setState(() => _tab = tab);

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _exit();
      },
      child: Scaffold(
        appBar: AppBar(
          titleSpacing: 16,
          title: ListenableBuilder(
            listenable: session,
            builder: (_, _) => Row(children: [
              const Icon(Icons.schedule_rounded, size: 18, color: AppColors.textMuted),
              const SizedBox(width: 6),
              Text(formatGameClock(session.world.now),
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
              const Spacer(),
              const Icon(Icons.account_balance_wallet_rounded, size: 18, color: AppColors.accent),
              const SizedBox(width: 6),
              Text(formatRupiah(session.world.cashIdr),
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
            ]),
          ),
          actions: [
            IconButton(tooltip: 'Simpan & keluar', onPressed: _exit, icon: const Icon(Icons.logout_rounded)),
          ],
        ),
        body: IndexedStack(
          index: _tab,
          children: [
            DepotScreen(session: session, active: _tab == 0, onOpenContracts: () => _goTo(2)),
            MapScreen(session: session, active: _tab == 1),
            ContractsScreen(session: session, onShowMap: () => _goTo(1)),
            FinanceScreen(session: session),
          ],
        ),
        bottomNavigationBar: NavigationBar(
          selectedIndex: _tab,
          onDestinationSelected: _goTo,
          destinations: const [
            NavigationDestination(icon: Icon(Icons.warehouse_outlined), selectedIcon: Icon(Icons.warehouse_rounded), label: 'Depot'),
            NavigationDestination(icon: Icon(Icons.map_outlined), selectedIcon: Icon(Icons.map_rounded), label: 'Peta'),
            NavigationDestination(icon: Icon(Icons.assignment_outlined), selectedIcon: Icon(Icons.assignment_rounded), label: 'Kontrak'),
            NavigationDestination(icon: Icon(Icons.payments_outlined), selectedIcon: Icon(Icons.payments_rounded), label: 'Keuangan'),
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
            Text('Selama kamu pergi', style: Theme.of(context).textTheme.titleLarge!.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            Text(
              hours >= 1 ? '${hours.toStringAsFixed(1).replaceAll('.', ',')} jam berlalu' : '${summary.realElapsed.inMinutes} menit berlalu',
              style: const TextStyle(color: AppColors.textMuted),
            ),
            if (summary.truncated)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text('Waktu offline dibatasi 48 jam; sisanya tidak dihitung.',
                    style: TextStyle(color: AppColors.accent)),
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
                        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          SizedBox(
                            width: 56,
                            child: Text(formatGameTime(e.time), style: const TextStyle(color: AppColors.textMuted)),
                          ),
                          Expanded(child: Text(logText(session.world, e))),
                        ]),
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
