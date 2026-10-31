// Render ikon peluncur Android & lembar pratinjau ikon dari painter yang sama
// dengan ikon di dalam game. Jalankan manual (bukan bagian test CI):
//
//   flutter test tool/render_icons_test.dart
//
// Menulis android/app/src/main/res/mipmap-*/ic_launcher.png dan
// build/icon_preview.png.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transport_manager/app/theme.dart';
import 'package:transport_manager/widgets/game_icons.dart';

Future<void> _capture(WidgetTester tester, Widget child, Size size, double pixelRatio, String path) async {
  final key = GlobalKey();
  await tester.binding.setSurfaceSize(size);
  await tester.pumpWidget(
    Directionality(
      textDirection: TextDirection.ltr,
      child: Center(child: RepaintBoundary(key: key, child: SizedBox.fromSize(size: size, child: child))),
    ),
  );
  await tester.runAsync(() async {
    final boundary = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: pixelRatio);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    File(path)
      ..createSync(recursive: true)
      ..writeAsBytesSync(bytes!.buffer.asUint8List());
  });
}

void main() {
  testWidgets('ikon peluncur', (tester) async {
    const sizes = {'mdpi': 48, 'hdpi': 72, 'xhdpi': 96, 'xxhdpi': 144, 'xxxhdpi': 192};
    for (final e in sizes.entries) {
      await _capture(
        tester,
        const AppLogo(size: 96),
        const Size(96, 96),
        e.value / 96,
        'android/app/src/main/res/mipmap-${e.key}/ic_launcher.png',
      );
    }
  });

  testWidgets('lembar pratinjau ikon', (tester) async {
    await _capture(
      tester,
      ColoredBox(
        color: AppColors.background,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const AppLogo(size: 96),
            const SizedBox(height: 16),
            Wrap(spacing: 12, runSpacing: 12, children: [
              for (final v in ['pickup_open', 'box_car', 'mini_truck', 'engkel_truck', 'container_truck'])
                SizedBox(width: 120, height: 60, child: VehicleIcon(v, width: 120)),
            ]),
            const SizedBox(height: 16),
            Wrap(spacing: 14, runSpacing: 14, children: [
              for (final g in GameGlyph.values) GlyphIcon(g, size: 40, color: AppColors.accent),
            ]),
          ]),
        ),
      ),
      const Size(680, 380),
      2,
      'build/icon_preview.png',
    );
  });
}
