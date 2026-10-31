import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../widgets/game_icons.dart';
import '../../app/providers.dart';
import '../../app/theme.dart';
import '../../data/game_data.dart';
import '../../game/game_session.dart';
import '../../util/format.dart';

/// Alur permainan baru: negara → wilayah → kota → lokasi depot → nama perusahaan.
/// Mengembalikan [GameSession] yang sudah dibuat & tersimpan.
class NewGameScreen extends ConsumerStatefulWidget {
  const NewGameScreen({super.key});

  @override
  ConsumerState<NewGameScreen> createState() => _NewGameScreenState();
}

class _NewGameScreenState extends ConsumerState<NewGameScreen> {
  int _step = 0;
  Country? _country;
  Region? _region;
  City? _city;
  DepotSite? _site;
  final _name = TextEditingController(text: 'PT Angkut Nusantara');
  bool _creating = false;

  static const _titles = ['Pilih negara', 'Pilih wilayah', 'Pilih kota awal', 'Pilih lokasi depot', 'Nama perusahaan'];

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _next() => setState(() => _step++);

  Future<void> _create(GameData data) async {
    final name = _name.text.trim();
    if (name.isEmpty) return;
    setState(() => _creating = true);
    try {
      final store = await ref.read(saveStoreProvider.future);
      if (!mounted) return;
      final graph = await data.graph(DefaultAssetBundle.of(context), _city!.id);
      final session = await GameSession.newGame(
        data: data,
        store: store,
        graph: graph,
        city: _city!,
        site: _site!,
        companyName: name,
      );
      if (mounted) Navigator.of(context).pop(session);
    } on Object catch (e) {
      if (mounted) {
        setState(() => _creating = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Gagal membuat permainan: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = ref.watch(gameDataProvider).requireValue;
    return PopScope(
      canPop: _step == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && !_creating) setState(() => _step--);
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(_titles[_step]),
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(4),
            child: LinearProgressIndicator(value: (_step + 1) / _titles.length, backgroundColor: AppColors.outline),
          ),
        ),
        body: AnimatedSwitcher(
          duration: const Duration(milliseconds: 200),
          child: KeyedSubtree(key: ValueKey(_step), child: _body(data)),
        ),
      ),
    );
  }

  Widget _body(GameData data) => switch (_step) {
    0 => _choices([
      for (final c in data.countries)
        _Choice(
          title: c.name,
          subtitle: '${c.regions.where((r) => r.available).length} wilayah tersedia',
          icon: const _Flag(),
          onTap: () => setState(() {
            _country = c;
            _next();
          }),
        ),
    ]),
    1 => _choices([
      for (final r in _country!.regions)
        _Choice(
          title: r.name,
          subtitle: r.available
              ? '${r.cities.where((c) => c.hasMapPack).length} kota siap dimainkan'
              : 'Paket peta belum tersedia',
          icon: const GlyphIcon(GameGlyph.map),
          enabled: r.available,
          onTap: () => setState(() {
            _region = r;
            _next();
          }),
        ),
    ]),
    2 => _choices([
      for (final c in _region!.cities)
        _Choice(
          title: c.name,
          subtitle: c.hasMapPack ? c.province : '${c.province} · paket peta belum tersedia',
          icon: const GlyphIcon(GameGlyph.office),
          enabled: c.hasMapPack,
          onTap: () => setState(() {
            _city = c;
            _next();
          }),
        ),
    ]),
    3 => _choices([
      for (final s in _city!.depotSites)
        _Choice(
          title: 'Depot ${s.name}',
          subtitle: 'Lahan 40×30 m · 3 slot parkir · gudang kecil · 1 loading area',
          icon: const GlyphIcon(GameGlyph.depot),
          onTap: () => setState(() {
            _site = s;
            _next();
          }),
        ),
    ]),
    _ => ListView(
      padding: const EdgeInsets.all(20),
      children: [
        TextField(
          controller: _name,
          maxLength: 32,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(labelText: 'Nama perusahaan', border: OutlineInputBorder()),
        ),
        const SizedBox(height: 8),
        _Summary(city: _city!, site: _site!, content: data),
        const SizedBox(height: 24),
        FilledButton(
          onPressed: _creating ? null : () => _create(data),
          child: _creating
              ? const SizedBox.square(dimension: 22, child: CircularProgressIndicator(strokeWidth: 2.5))
              : const Text('Mulai usaha'),
        ),
      ],
    ),
  };

  Widget _choices(List<_Choice> items) => ListView.separated(
    padding: const EdgeInsets.all(16),
    itemCount: items.length,
    separatorBuilder: (_, _) => const SizedBox(height: 10),
    itemBuilder: (_, i) => items[i],
  );
}

class _Choice extends StatelessWidget {
  const _Choice({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.onTap,
    this.enabled = true,
  });

  final String title;
  final String subtitle;
  final Widget icon;
  final VoidCallback onTap;
  final bool enabled;

  @override
  Widget build(BuildContext context) => Opacity(
    opacity: enabled ? 1 : 0.45,
    child: Card(
      child: ListTile(
        enabled: enabled,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        leading: IconTheme(
          data: IconThemeData(color: enabled ? AppColors.accent : AppColors.textMuted),
          child: SizedBox(width: 30, child: Center(child: icon)),
        ),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Text(subtitle, style: const TextStyle(color: AppColors.textMuted)),
        trailing: enabled ? const Icon(Icons.chevron_right_rounded) : const Icon(Icons.lock_outline_rounded),
        onTap: enabled ? onTap : null,
      ),
    ),
  );
}

class _Summary extends StatelessWidget {
  const _Summary({required this.city, required this.site, required this.content});

  final City city;
  final DepotSite site;
  final GameData content;

  @override
  Widget build(BuildContext context) {
    final vehicle = content.content.vehicleModels['pickup_box_1t']!;
    Widget row(Widget icon, String text) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          SizedBox(width: 40, child: Center(child: icon)),
          const SizedBox(width: 10),
          Expanded(child: Text(text)),
        ],
      ),
    );
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Modal awal', style: TextStyle(color: AppColors.textMuted)),
            const SizedBox(height: 6),
            row(
              const GlyphIcon(GameGlyph.depot, size: 22, color: AppColors.accent),
              'Depot ${site.name}, ${city.name}',
            ),
            row(VehicleIcon(vehicle.visual, width: 40), '1 × ${vehicle.name}'),
            row(const GlyphIcon(GameGlyph.driver, size: 22, color: AppColors.accent), '1 sopir'),
            row(const GlyphIcon(GameGlyph.parking, size: 22, color: AppColors.accent), '3 slot parkir (2 kosong)'),
            row(
              const GlyphIcon(GameGlyph.finance, size: 22, color: AppColors.accent),
              'Modal ${formatRupiah(content.content.economy.startingCashIdr)}',
            ),
          ],
        ),
      ),
    );
  }
}

/// Bendera Indonesia (merah-putih).
class _Flag extends StatelessWidget {
  const _Flag();

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(3),
    child: const SizedBox(
      width: 28,
      height: 19,
      child: Column(
        children: [
          Expanded(
            child: ColoredBox(color: Color(0xFFD7262E), child: SizedBox.expand()),
          ),
          Expanded(
            child: ColoredBox(color: Color(0xFFF7F7F2), child: SizedBox.expand()),
          ),
        ],
      ),
    ),
  );
}
