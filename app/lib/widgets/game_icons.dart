import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:sim_core/sim_core.dart';

/// Set ikon khusus Transport Manager (digambar, bukan ikon generik).
/// Warna kendaraan mengikuti model 3D-nya agar mudah dikenali.

// ------------------------------------------------------------------ kendaraan

enum _Cab { nosed, semi, flat }

enum _Body { openBed, box, tallBox, woodBed, container }

class _VehicleStyle {
  const _VehicleStyle({
    required this.cab,
    required this.cabColor,
    required this.body,
    required this.bodyColor,
    this.accent,
    this.axles = const [15, 50],
    this.dualRear = false,
  });

  final _Cab cab;
  final Color cabColor;
  final _Body body;
  final Color bodyColor;
  final Color? accent;

  /// Posisi roda (x, satuan 64×32).
  final List<double> axles;
  final bool dualRear;
}

/// Warna & bentuk sama dengan model 3D (`tools/depot_glb`).
const _vehicleStyles = {
  'pickup_open': _VehicleStyle(
    cab: _Cab.nosed,
    cabColor: Color(0xFFF5F5F2),
    body: _Body.openBed,
    bodyColor: Color(0xFF8D939A),
    axles: [14, 49],
  ),
  'box_car': _VehicleStyle(
    cab: _Cab.semi,
    cabColor: Color(0xFFB7BEC6),
    body: _Body.box,
    bodyColor: Color(0xFFE9ECEF),
    accent: Color(0xFFF2B630),
  ),
  'mini_truck': _VehicleStyle(
    cab: _Cab.flat,
    cabColor: Color(0xFF2F6DB5),
    body: _Body.tallBox,
    bodyColor: Color(0xFFF0F0EC),
    accent: Color(0xFF2F6DB5),
    axles: [13, 52],
  ),
  'engkel_truck': _VehicleStyle(
    cab: _Cab.flat,
    cabColor: Color(0xFFE8A623),
    body: _Body.woodBed,
    bodyColor: Color(0xFFB8895A),
    axles: [15, 54],
    dualRear: true,
  ),
  'container_truck': _VehicleStyle(
    cab: _Cab.flat,
    cabColor: Color(0xFFC8432F),
    body: _Body.container,
    bodyColor: Color(0xFF2E7D7A),
    axles: [15, 54],
    dualRear: true,
  ),
};

/// Ikon kendaraan tampak samping sesuai jenis (`VehicleModel.visual`).
class VehicleIcon extends StatelessWidget {
  const VehicleIcon(this.visual, {super.key, this.width = 48});

  final String visual;
  final double width;

  @override
  Widget build(BuildContext context) => CustomPaint(size: Size(width, width / 2), painter: VehiclePainter(visual));
}

class VehiclePainter extends CustomPainter {
  const VehiclePainter(this.visual);

  final String visual;

  static const _ink = Color(0xFF0E1318);
  static const _window = Color(0xFF26343F);
  static const _tire = Color(0xFF1D1F22);
  static const _hub = Color(0xFFB9BEC4);

  @override
  void paint(Canvas canvas, Size size) {
    final s = _vehicleStyles[visual] ?? _vehicleStyles['box_car']!;
    canvas.save();
    canvas.scale(size.width / 64, size.height / 32);
    final outline = Paint()
      ..color = _ink
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.1
      ..strokeJoin = StrokeJoin.round;
    void shape(Path p, Color c) {
      canvas.drawPath(p, Paint()..color = c);
      canvas.drawPath(p, outline);
    }

    RRect r(double l, double t, double rr, double b, [double rad = 1.6]) =>
        RRect.fromLTRBR(l, t, rr, b, Radius.circular(rad));

    // sasis
    shape(Path()..addRRect(r(2, 21, 61, 25, 1)), const Color(0xFF2C3036));

    // kabin
    final (cabLeft, cabTop, front) = switch (s.cab) {
      _Cab.nosed => (37.0, 9.5, 61.0),
      _Cab.semi => (43.0, 8.0, 60.0),
      _Cab.flat => (s.body == _Body.tallBox ? 44.0 : 45.0, s.body == _Body.tallBox ? 5.0 : 4.0, 61.0),
    };

    // bodi muatan
    final bodyRight = cabLeft - 1;
    switch (s.body) {
      case _Body.openBed:
        shape(Path()..addRRect(r(5, 15, bodyRight - 1, 22, 1)), s.bodyColor);
        for (final (x, w, h) in [(8.0, 8.0, 6.0), (17.0, 7.0, 4.5), (25.0, 8.0, 6.5)]) {
          shape(Path()..addRRect(r(x, 15 - h, x + w, 15, 0.8)), const Color(0xFFC79B63));
        }
      case _Body.box || _Body.tallBox:
        final top = s.body == _Body.tallBox ? 3.0 : 6.0;
        shape(Path()..addRRect(r(4, top, bodyRight, 22, 1.4)), s.bodyColor);
        if (s.accent != null) {
          canvas.drawRect(Rect.fromLTRB(4.6, 14, bodyRight - 0.6, 16.5), Paint()..color = s.accent!);
        }
      case _Body.woodBed:
        shape(Path()..addRRect(r(2, 9, bodyRight, 22, 0.8)), s.bodyColor);
        final plank = Paint()
          ..color = const Color(0xFF7A5634)
          ..strokeWidth = 0.9;
        for (final y in [12.5, 16.0, 19.0]) {
          canvas.drawLine(Offset(2.6, y), Offset(bodyRight - 0.6, y), plank);
        }
        for (final x in [2.0, bodyRight]) {
          canvas.drawRect(Rect.fromLTRB(x - 0.8, 9, x + 0.8, 22), Paint()..color = const Color(0xFF39434D));
        }
      case _Body.container:
        shape(Path()..addRRect(r(2, 20, bodyRight + 0.5, 22.5, 0.6)), const Color(0xFF8D939A));
        shape(Path()..addRRect(r(4, 4, bodyRight - 2.5, 20, 0.8)), s.bodyColor);
        final rib = Paint()
          ..color = const Color(0xFF1F5552)
          ..strokeWidth = 1.0;
        for (var x = 7.0; x < bodyRight - 3; x += 3.3) {
          canvas.drawLine(Offset(x, 5.5), Offset(x, 18.5), rib);
        }
    }

    switch (s.cab) {
      case _Cab.nosed:
        // kabin + kap mesin pendek
        final cab = Path()
          ..moveTo(cabLeft, 22)
          ..lineTo(cabLeft, cabTop + 1.5)
          ..quadraticBezierTo(cabLeft, cabTop, cabLeft + 1.5, cabTop)
          ..lineTo(cabLeft + 9, cabTop)
          ..lineTo(cabLeft + 14, cabTop + 6.5)
          ..lineTo(front - 0.8, cabTop + 7.5)
          ..quadraticBezierTo(front, cabTop + 7.7, front, cabTop + 9)
          ..lineTo(front, 22)
          ..close();
        shape(cab, s.cabColor);
        canvas.drawPath(
          Path()
            ..moveTo(cabLeft + 5, cabTop + 1.8)
            ..lineTo(cabLeft + 8.6, cabTop + 1.8)
            ..lineTo(cabLeft + 12.6, cabTop + 6.3)
            ..lineTo(cabLeft + 5, cabTop + 6.3)
            ..close(),
          Paint()..color = _window,
        );
      case _Cab.semi || _Cab.flat:
        final slant = s.cab == _Cab.semi ? 5.0 : 1.4;
        final cab = Path()
          ..moveTo(cabLeft, 22)
          ..lineTo(cabLeft, cabTop + 1.5)
          ..quadraticBezierTo(cabLeft, cabTop, cabLeft + 1.5, cabTop)
          ..lineTo(front - slant - 0.5, cabTop)
          ..lineTo(front, cabTop + (s.cab == _Cab.semi ? 7.5 : 3))
          ..lineTo(front, 22)
          ..close();
        shape(cab, s.cabColor);
        canvas.drawPath(
          Path()
            ..moveTo(cabLeft + 5, cabTop + 1.8)
            ..lineTo(front - slant - 0.4, cabTop + 1.8)
            ..lineTo(front - (s.cab == _Cab.semi ? 1.8 : 0.9), cabTop + (s.cab == _Cab.semi ? 6.8 : 8))
            ..lineTo(cabLeft + 5, cabTop + (s.cab == _Cab.semi ? 6.8 : 8))
            ..close(),
          Paint()..color = _window,
        );
        if (s.cab == _Cab.flat) {
          canvas.drawRect(Rect.fromLTRB(front - 5.5, 15.5, front - 0.6, 17), Paint()..color = const Color(0xFF39434D));
        }
    }
    canvas.drawRect(Rect.fromLTWH(front - 2.2, 18.2, 2.2, 1.8), Paint()..color = const Color(0xFFFFF3C4));

    // roda
    for (final (i, x) in s.axles.indexed) {
      final rear = i == 0 && s.dualRear;
      canvas.drawCircle(Offset(x, 25), rear ? 4.8 : 4.4, Paint()..color = _tire);
      canvas.drawCircle(Offset(x, 25), 1.9, Paint()..color = _hub);
      if (rear) {
        canvas.drawCircle(
          Offset(x, 25),
          3.3,
          Paint()
            ..color = _hub.withValues(alpha: 0.5)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 0.6,
        );
      }
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(VehiclePainter old) => old.visual != visual;
}

// ------------------------------------------------------------------ glyph

/// Glyph satu warna untuk navigasi, fasilitas, & karyawan.
enum GameGlyph {
  depot,
  map,
  contracts,
  fleet,
  finance,
  parking,
  gate,
  dock,
  warehouse,
  office,
  construction,
  driver,
  staff,
  store,
  settings,
  workshop,
}

/// Gambar glyph langsung ke kanvas (mis. pin di peta) dalam kotak [rect].
void paintGlyph(Canvas canvas, GameGlyph glyph, Rect rect, Color color) {
  canvas.save();
  canvas.translate(rect.left, rect.top);
  _GlyphPainter(glyph, color).paint(canvas, rect.size);
  canvas.restore();
}

GameGlyph facilityGlyph(FacilityType t) => switch (t) {
  FacilityType.parking => GameGlyph.parking,
  FacilityType.gate => GameGlyph.gate,
  FacilityType.loadingDock => GameGlyph.dock,
  FacilityType.workshop => GameGlyph.workshop,
  FacilityType.warehouse => GameGlyph.warehouse,
  FacilityType.office => GameGlyph.office,
};

class GlyphIcon extends StatelessWidget {
  const GlyphIcon(this.glyph, {super.key, this.size = 24, this.color});

  final GameGlyph glyph;
  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) => CustomPaint(
    size: Size.square(size),
    painter: _GlyphPainter(glyph, color ?? IconTheme.of(context).color ?? Colors.white),
  );
}

class _GlyphPainter extends CustomPainter {
  const _GlyphPainter(this.glyph, this.color);

  final GameGlyph glyph;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 24, size.height / 24);
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final fill = Paint()..color = color;
    final thin = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..strokeCap = StrokeCap.round;

    switch (glyph) {
      case GameGlyph.depot:
        // gudang beratap pelana + pintu rol + pikap kecil
        canvas.drawPath(
          Path()
            ..moveTo(2, 10)
            ..lineTo(10, 4)
            ..lineTo(18, 10)
            ..lineTo(18, 20)
            ..lineTo(2, 20)
            ..close(),
          stroke,
        );
        canvas.drawRect(const Rect.fromLTRB(6, 13, 14, 20), stroke);
        for (final y in [15.3, 17.6]) {
          canvas.drawLine(Offset(6.5, y), Offset(13.5, y), thin);
        }
        canvas.drawRRect(RRect.fromLTRBR(15.5, 15, 22.5, 19.5, const Radius.circular(1)), fill);
        canvas.drawCircle(const Offset(17.3, 20.4), 1.3, fill);
        canvas.drawCircle(const Offset(21, 20.4), 1.3, fill);
      case GameGlyph.map:
        // peta lipat + rute putus-putus + pin
        canvas.drawPath(
          Path()
            ..moveTo(2, 6)
            ..lineTo(8, 4)
            ..lineTo(16, 6)
            ..lineTo(22, 4)
            ..lineTo(22, 19)
            ..lineTo(16, 21)
            ..lineTo(8, 19)
            ..lineTo(2, 21)
            ..close(),
          stroke,
        );
        final route = Path()
          ..moveTo(5, 17)
          ..quadraticBezierTo(9, 9, 13, 14)
          ..quadraticBezierTo(15.5, 17, 17.5, 12.5);
        for (final m in route.computeMetrics()) {
          for (var d = 0.0; d < m.length; d += 3.2) {
            canvas.drawPath(m.extractPath(d, math.min(d + 1.6, m.length)), thin);
          }
        }
        canvas.drawPath(
          Path()
            ..moveTo(17.5, 12.5)
            ..cubicTo(14.8, 9.5, 15.2, 6.2, 17.5, 6.2)
            ..cubicTo(19.8, 6.2, 20.2, 9.5, 17.5, 12.5),
          fill,
        );
      case GameGlyph.contracts:
        // papan klip + kardus + centang
        canvas.drawRRect(RRect.fromLTRBR(4, 4, 20, 22, const Radius.circular(2)), stroke);
        canvas.drawRRect(RRect.fromLTRBR(8.5, 2.5, 15.5, 6, const Radius.circular(1)), fill);
        canvas.drawRect(const Rect.fromLTRB(7.5, 9, 13, 14.5), stroke);
        canvas.drawLine(const Offset(10.25, 9), const Offset(10.25, 11.5), thin);
        canvas.drawPath(
          Path()
            ..moveTo(13.8, 18)
            ..lineTo(15.5, 19.6)
            ..lineTo(18.5, 15.6),
          stroke,
        );
        canvas.drawLine(const Offset(7.5, 18.5), const Offset(11.5, 18.5), thin);
      case GameGlyph.fleet:
        // truk box tampak samping
        canvas.drawRRect(RRect.fromLTRBR(1.5, 6, 14.5, 17, const Radius.circular(1.2)), stroke);
        canvas.drawPath(
          Path()
            ..moveTo(14.5, 9)
            ..lineTo(19, 9)
            ..lineTo(22.5, 13)
            ..lineTo(22.5, 17)
            ..lineTo(14.5, 17),
          stroke,
        );
        canvas.drawPath(
          Path()
            ..moveTo(16.5, 10.8)
            ..lineTo(18.3, 10.8)
            ..lineTo(20.2, 13)
            ..lineTo(16.5, 13)
            ..close(),
          fill,
        );
        for (final x in [6.0, 18.5]) {
          canvas.drawCircle(Offset(x, 18.5), 2.4, Paint()..color = color);
          canvas.drawCircle(Offset(x, 18.5), 0.9, Paint()..color = Colors.black.withValues(alpha: 0.55));
        }
      case GameGlyph.finance:
        // tumpukan koin + "Rp"
        for (final y in [18.5, 15.5, 12.5]) {
          canvas.drawOval(
            Rect.fromCenter(center: Offset(9, y), width: 13, height: 4.4),
            Paint()..color = color.withValues(alpha: 0.35),
          );
          canvas.drawOval(Rect.fromCenter(center: Offset(9, y), width: 13, height: 4.4), thin);
        }
        canvas.drawCircle(const Offset(16.5, 8), 5.6, stroke);
        _text(canvas, 'Rp', const Offset(16.5, 8), 5.4, color);
      case GameGlyph.parking:
        canvas.drawRRect(RRect.fromLTRBR(3, 3, 21, 21, const Radius.circular(4)), stroke);
        canvas.drawPath(
          Path()
            ..moveTo(9, 17.5)
            ..lineTo(9, 6.5)
            ..lineTo(13.2, 6.5)
            ..cubicTo(17, 6.5, 17, 12.4, 13.2, 12.4)
            ..lineTo(9, 12.4),
          stroke,
        );
      case GameGlyph.gate:
        // tiang + palang bergaris
        canvas.drawRRect(RRect.fromLTRBR(2.5, 9, 6.5, 21, const Radius.circular(1)), fill);
        canvas.drawRRect(RRect.fromLTRBR(6, 9.6, 22.5, 13.4, const Radius.circular(1.6)), stroke);
        for (final x in [9.0, 15.0]) {
          canvas.drawRect(Rect.fromLTRB(x, 10.4, x + 3, 12.6), fill);
        }
        canvas.drawLine(const Offset(2, 21), const Offset(9, 21), stroke);
      case GameGlyph.dock:
        // pintu rol + platform + bak truk mundur
        canvas.drawRect(const Rect.fromLTRB(3, 3, 15, 15), stroke);
        for (final y in [6.0, 9.0, 12.0]) {
          canvas.drawLine(Offset(3.6, y), Offset(14.4, y), thin);
        }
        canvas.drawRect(const Rect.fromLTRB(2, 15, 16, 18.5), fill);
        canvas.drawRRect(RRect.fromLTRBR(13, 9, 22.5, 18.5, const Radius.circular(1)), stroke);
        canvas.drawCircle(const Offset(19.5, 20), 2, fill);
      case GameGlyph.warehouse:
        canvas.drawPath(
          Path()
            ..moveTo(2, 10)
            ..lineTo(12, 3.5)
            ..lineTo(22, 10)
            ..lineTo(22, 21)
            ..lineTo(2, 21)
            ..close(),
          stroke,
        );
        for (final y in [13.5, 17.5]) {
          canvas.drawLine(Offset(6, y), Offset(18, y), thin);
        }
        for (final x in [6.0, 12.0, 18.0]) {
          canvas.drawLine(Offset(x, 11.5), Offset(x, 21), thin);
        }
      case GameGlyph.office:
        canvas.drawRect(const Rect.fromLTRB(4, 3, 16, 21), stroke);
        canvas.drawRect(const Rect.fromLTRB(16, 10, 21, 21), stroke);
        for (final y in [6.5, 10.5, 14.5]) {
          for (final x in [7.0, 11.5]) {
            canvas.drawRect(Rect.fromLTWH(x, y, 2.4, 2), fill);
          }
        }
        canvas.drawRect(const Rect.fromLTRB(8.6, 17.5, 11.4, 21), fill);
      case GameGlyph.construction:
        canvas.drawPath(
          Path()
            ..moveTo(12, 3)
            ..lineTo(18, 19)
            ..lineTo(6, 19)
            ..close(),
          fill,
        );
        canvas.drawRect(const Rect.fromLTRB(3, 19, 21, 21.5), fill);
        final band = Paint()..color = Colors.black.withValues(alpha: 0.35);
        canvas.drawPath(
          Path()
            ..moveTo(9.4, 10)
            ..lineTo(14.6, 10)
            ..lineTo(15.5, 12.5)
            ..lineTo(8.5, 12.5)
            ..close(),
          band,
        );
      case GameGlyph.driver:
        // setir
        canvas.drawCircle(const Offset(12, 12), 9, stroke);
        canvas.drawCircle(const Offset(12, 12), 2.6, fill);
        canvas.drawLine(const Offset(3.5, 11), const Offset(9.6, 11.6), stroke);
        canvas.drawLine(const Offset(20.5, 11), const Offset(14.4, 11.6), stroke);
        canvas.drawLine(const Offset(12, 14.6), const Offset(12, 20.8), stroke);
      case GameGlyph.workshop:
        // kunci pas diagonal
        canvas.save();
        canvas.translate(12, 12);
        canvas.rotate(-math.pi / 4);
        canvas.drawRRect(RRect.fromLTRBR(-1.6, -4, 1.6, 9.5, const Radius.circular(1.4)), fill);
        canvas.drawCircle(const Offset(0, -6.2), 4.3, fill);
        canvas.drawRect(
          const Rect.fromLTRB(-1.5, -11, 1.5, -6),
          Paint()
            ..color = Colors.black.withValues(alpha: 0.6)
            ..blendMode = BlendMode.srcOver,
        );
        canvas.restore();
      case GameGlyph.settings:
        // roda gigi: cincin tebal + 8 gigi persegi
        canvas.drawCircle(
          const Offset(12, 12),
          5.6,
          Paint()
            ..color = color
            ..style = PaintingStyle.stroke
            ..strokeWidth = 3.4,
        );
        for (var i = 0; i < 8; i++) {
          canvas.save();
          canvas.translate(12, 12);
          canvas.rotate(i * math.pi / 4);
          canvas.drawRRect(RRect.fromLTRBR(-1.7, -10.4, 1.7, -6.4, const Radius.circular(0.8)), fill);
          canvas.restore();
        }
      case GameGlyph.store:
        // toko dengan kanopi bergaris
        canvas.drawRect(const Rect.fromLTRB(4, 11, 20, 21), stroke);
        final awning = Path()
          ..moveTo(2.5, 10.5)
          ..lineTo(4.5, 4)
          ..lineTo(19.5, 4)
          ..lineTo(21.5, 10.5)
          ..close();
        canvas.drawPath(awning, fill);
        for (final x in [8.0, 12.0, 16.0]) {
          canvas.drawLine(
            Offset(x, 4.5),
            Offset(x + 0.6, 10),
            Paint()
              ..color = Colors.black.withValues(alpha: 0.35)
              ..strokeWidth = 1.4,
          );
        }
        canvas.drawRect(const Rect.fromLTRB(10, 15, 14, 21), fill);
      case GameGlyph.staff:
        // helm proyek
        canvas.drawPath(
          Path()
            ..moveTo(4, 16)
            ..cubicTo(4, 7, 20, 7, 20, 16)
            ..close(),
          fill,
        );
        canvas.drawRRect(RRect.fromLTRBR(2, 16, 22, 19, const Radius.circular(1.5)), fill);
        canvas.drawLine(
          const Offset(12, 7.6),
          const Offset(12, 15),
          Paint()
            ..color = Colors.black.withValues(alpha: 0.35)
            ..strokeWidth = 1.6,
        );
    }
    canvas.restore();
  }

  static void _text(Canvas canvas, String text, Offset center, double size, Color color) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(fontSize: size, fontWeight: FontWeight.w900, color: color),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, center - Offset(tp.width / 2, tp.height / 2));
  }

  @override
  bool shouldRepaint(_GlyphPainter old) => old.glyph != glyph || old.color != color;
}

// ------------------------------------------------------------------ logo

/// Logo app: kotak amber, jalan berkelok menuju pin tujuan, pikap box.
class AppLogo extends StatelessWidget {
  const AppLogo({super.key, this.size = 64, this.rounded = true});

  final double size;
  final bool rounded;

  @override
  Widget build(BuildContext context) => CustomPaint(
    size: Size.square(size),
    painter: AppLogoPainter(rounded: rounded),
  );
}

class AppLogoPainter extends CustomPainter {
  const AppLogoPainter({this.rounded = true});

  final bool rounded;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 100, size.height / 100);
    final bg = RRect.fromLTRBR(0, 0, 100, 100, Radius.circular(rounded ? 22 : 0));
    canvas.drawRRect(
      bg,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFF7C64D), Color(0xFFE79A1E)],
        ).createShader(const Rect.fromLTWH(0, 0, 100, 100)),
    );
    canvas.clipRRect(bg);
    // jalan berkelok
    final road = Path()
      ..moveTo(-5, 92)
      ..cubicTo(30, 70, 20, 50, 55, 42)
      ..cubicTo(78, 37, 80, 26, 76, 18);
    canvas.drawPath(
      road,
      Paint()
        ..color = const Color(0xFF1B2733)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 17
        ..strokeCap = StrokeCap.round,
    );
    final metrics = road.computeMetrics().first;
    final dash = Paint()
      ..color = const Color(0xFFF7C64D)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.4
      ..strokeCap = StrokeCap.round;
    for (var d = 6.0; d < metrics.length - 8; d += 11) {
      canvas.drawPath(metrics.extractPath(d, d + 5), dash);
    }
    // pin tujuan
    final pin = Path()
      ..moveTo(76, 30)
      ..cubicTo(64, 16, 66, 4, 76, 4)
      ..cubicTo(86, 4, 88, 16, 76, 30)
      ..close();
    canvas.drawPath(pin, Paint()..color = const Color(0xFFC8432F));
    canvas.drawCircle(const Offset(76, 13), 4, Paint()..color = const Color(0xFFFDF6E3));
    // pikap box
    canvas.save();
    canvas.translate(10, 46);
    canvas.rotate(-0.22);
    const VehiclePainter('box_car').paint(canvas, const Size(54, 27));
    canvas.restore();
    canvas.restore();
  }

  @override
  bool shouldRepaint(AppLogoPainter old) => old.rounded != rounded;
}
