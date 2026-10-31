import 'package:flutter/material.dart';
import 'package:sim_core/sim_core.dart';

import '../../app/theme.dart';
import '../../game/game_session.dart';
import '../../util/format.dart';

const _accountLabel = {
  LedgerAccount.openingBalance: 'Modal awal',
  LedgerAccount.contractRevenue: 'Pendapatan kontrak',
  LedgerAccount.fuel: 'BBM',
  LedgerAccount.toll: 'Tol',
};

class FinanceScreen extends StatelessWidget {
  const FinanceScreen({super.key, required this.session});

  final GameSession session;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: session,
        builder: (context, _) {
          final ledger = session.world.ledger;
          final revenue = ledger.total(LedgerAccount.contractRevenue);
          final costs = ledger.total(LedgerAccount.fuel) + ledger.total(LedgerAccount.toll);
          final entries = ledger.entries.reversed.toList();
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Text('Kas', style: TextStyle(color: AppColors.textMuted)),
                    Text(formatRupiah(ledger.cashIdr),
                        style: Theme.of(context).textTheme.headlineSmall!.copyWith(fontWeight: FontWeight.w800)),
                    const SizedBox(height: 12),
                    Row(children: [
                      Expanded(child: _Stat('Pendapatan', revenue, AppColors.positive)),
                      Expanded(child: _Stat('Biaya operasi', costs, AppColors.negative)),
                      Expanded(child: _Stat('Laba operasi', revenue + costs, null)),
                    ]),
                  ]),
                ),
              ),
              const SizedBox(height: 16),
              const Text('BUKU BESAR',
                  style: TextStyle(color: AppColors.textMuted, fontWeight: FontWeight.w700, letterSpacing: 1.2, fontSize: 12)),
              const SizedBox(height: 4),
              for (final e in entries)
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text(_accountLabel[e.account]!),
                  subtitle: Text(formatGameClock(e.time), style: const TextStyle(color: AppColors.textMuted)),
                  trailing: Text(
                    formatRupiah(e.amountIdr),
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: e.amountIdr >= 0 ? AppColors.positive : AppColors.negative,
                    ),
                  ),
                ),
            ],
          );
        },
      );
}

class _Stat extends StatelessWidget {
  const _Stat(this.label, this.value, this.color);

  final String label;
  final int value;
  final Color? color;

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
        const SizedBox(height: 2),
        Text(formatRupiah(value), style: TextStyle(fontWeight: FontWeight.w700, color: color, fontSize: 13)),
      ]);
}
