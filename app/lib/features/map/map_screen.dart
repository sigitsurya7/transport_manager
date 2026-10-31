import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:sim_core/sim_core.dart';

import '../../widgets/game_icons.dart';
import '../../app/theme.dart';
import '../../game/game_session.dart';
import '../contracts/trip_card.dart';
import 'road_layer.dart';

/// Peta kota offline: jaringan jalan nyata dari map pack, rute trip aktif,
/// depot, tujuan, dan kendaraan yang bergerak mengikuti geometri jalan.
class MapScreen extends StatefulWidget {
  const MapScreen({super.key, required this.session, required this.active});

  final GameSession session;

  /// Hanya animasi saat tab terlihat.
  final bool active;

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> with SingleTickerProviderStateMixin {
  late final RoadLayer _roads;
  late final Ticker _ticker;
  final _frame = ValueNotifier<int>(0);

  /// Transformasi tampilan: layar = meter × [_scale] + [_offset].
  double _scale = 0.08;
  Offset _offset = Offset.zero;
  bool _placed = false;
  double _gestureStartScale = 1;
  Offset _gestureStartFocal = Offset.zero;
  Offset _gestureStartOffset = Offset.zero;
  int? _followVehicle;

  static const _minScale = 0.01, _maxScale = 3.0;

  GameSession get session => widget.session;

  Offset get _depotMeters =>
      _roads.projection.project(session.world.graph.node(session.world.depots.values.first.roadNode));

  @override
  void initState() {
    super.initState();
    _roads = RoadLayer.build(session.world.graph, session.world.graph.node(session.world.depots.values.first.roadNode));
    _ticker = createTicker((_) {
      final follow = _followVehicle;
      if (follow != null && mounted) {
        final pose = session.world.vehicleSnapshot(follow, at: session.displayTime).pose;
        if (pose != null) {
          final size = context.size;
          if (size != null) _offset = size.center(Offset.zero) - _roads.projection.project(pose.position) * _scale;
        }
      }
      _frame.value++;
    });
    if (widget.active) _ticker.start();
  }

  @override
  void didUpdateWidget(MapScreen old) {
    super.didUpdateWidget(old);
    if (widget.active && !_ticker.isActive) _ticker.start();
    if (!widget.active && _ticker.isActive) _ticker.stop();
  }

  @override
  void dispose() {
    _ticker.dispose();
    _frame.dispose();
    super.dispose();
  }

  void _center(Offset meters, Size size) => setState(() => _offset = size.center(Offset.zero) - meters * _scale);

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = constraints.biggest;
        if (!_placed) {
          _placed = true;
          _scale = (size.width / 9000).clamp(_minScale, _maxScale); // ±9 km selebar layar
          _offset = size.center(Offset.zero) - _depotMeters * _scale;
        }
        return Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                onScaleStart: (d) {
                  _gestureStartScale = _scale;
                  _gestureStartFocal = d.localFocalPoint;
                  _gestureStartOffset = _offset;
                  setState(() => _followVehicle = null);
                },
                onScaleUpdate: (d) => setState(() {
                  final newScale = (_gestureStartScale * d.scale).clamp(_minScale, _maxScale);
                  // Titik di bawah jari tetap di bawah jari saat zoom.
                  final focalMeters = (_gestureStartFocal - _gestureStartOffset) / _gestureStartScale;
                  _scale = newScale;
                  _offset = d.localFocalPoint - focalMeters * newScale;
                }),
                child: ClipRect(
                  child: CustomPaint(
                    painter: _RoadPainter(_roads, _scale, _offset),
                    foregroundPainter: _OverlayPainter(session, _roads, _scale, _offset, _frame),
                    child: const SizedBox.expand(),
                  ),
                ),
              ),
            ),
            Positioned(
              right: 12,
              bottom: 12,
              child: Column(
                children: [
                  _MapButton(
                    glyph: GameGlyph.depot,
                    tooltip: 'Ke depot',
                    onTap: () {
                      _followVehicle = null;
                      _center(_depotMeters, size);
                    },
                  ),
                  const SizedBox(height: 8),
                  _MapButton(
                    glyph: GameGlyph.fleet,
                    tooltip: 'Ikuti kendaraan',
                    selected: _followVehicle != null,
                    onTap: () {
                      final onRoad = session.world.vehicles.keys.where(
                        (id) => session.world.vehicleSnapshot(id).pose != null,
                      );
                      setState(() => _followVehicle = onRoad.isEmpty ? null : onRoad.first);
                      if (onRoad.isEmpty) {
                        ScaffoldMessenger.of(context)
                            .showSnackBar(const SnackBar(content: Text('Tidak ada kendaraan di jalan.')));
                      }
                    },
                  ),
                ],
              ),
            ),
            Positioned(left: 12, top: 12, right: 72, child: _StatusPanel(session: session)),
          ],
        );
      },
    );
  }
}

class _MapButton extends StatelessWidget {
  const _MapButton({required this.glyph, required this.tooltip, required this.onTap, this.selected = false});

  final GameGlyph glyph;
  final String tooltip;
  final VoidCallback onTap;
  final bool selected;

  @override
  Widget build(BuildContext context) => Material(
    color: selected ? AppColors.accent : AppColors.surfaceHigh,
    shape: const CircleBorder(side: BorderSide(color: AppColors.outline)),
    child: IconButton(
      tooltip: tooltip,
      onPressed: onTap,
      icon: GlyphIcon(glyph, color: selected ? AppColors.onAccent : AppColors.text),
    ),
  );
}

class _StatusPanel extends StatelessWidget {
  const _StatusPanel({required this.session});

  final GameSession session;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: session,
    builder: (_, _) {
      final active = session.world.trips.values.where((t) => t.isActive).toList();
      if (active.isEmpty) return const SizedBox.shrink();
      final t = active.first;
      return DecoratedBox(
        decoration: BoxDecoration(
          color: AppColors.surface.withValues(alpha: 0.92),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.outline),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              VehicleIcon(session.world.vehicles[t.vehicleId]!.model.visual, width: 36),
              const SizedBox(width: 8),
              Expanded(child: Text(phaseLabel[t.phase]!, overflow: TextOverflow.ellipsis)),
            ],
          ),
        ),
      );
    },
  );
}

class _RoadPainter extends CustomPainter {
  /// Jalan hanya digambar ulang saat transformasi berubah (lihat shouldRepaint),
  /// tidak ikut tiap frame seperti overlay kendaraan.
  _RoadPainter(this.roads, this.scale, this.offset);

  final RoadLayer roads;
  final double scale;
  final Offset offset;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = const Color(0xFF0D141B));
    canvas.save();
    canvas.translate(offset.dx, offset.dy);
    canvas.scale(scale);
    for (final g in RoadGroup.values) {
      final style = roadStyles[g]!;
      if (scale < style.minScale) continue;
      canvas.drawPath(
        roads.paths[g]!,
        Paint()
          ..color = style.color
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..strokeWidth = style.widthPx / scale * (scale > 0.3 ? 1.6 : 1),
      );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_RoadPainter old) => old.scale != scale || old.offset != offset || old.roads != roads;
}

class _OverlayPainter extends CustomPainter {
  _OverlayPainter(this.session, this.roads, this.scale, this.offset, Listenable repaint) : super(repaint: repaint);

  final GameSession session;
  final RoadLayer roads;
  final double scale;
  final Offset offset;

  Offset _screen(LatLng p) => roads.projection.project(p) * scale + offset;

  @override
  void paint(Canvas canvas, Size size) {
    final world = session.world;
    final t = session.displayTime;

    // Rute trip aktif (pergi biru, pulang ungu).
    for (final trip in world.trips.values.where((tr) => tr.isActive)) {
      final showOut = trip.phase.index <= TripPhase.outbound.index;
      for (final outbound in [true, false]) {
        final points = world.trackFor(trip.id, outbound: outbound).points;
        if (points.length < 2) continue;
        final path = Path()..moveTo(_screen(points.first).dx, _screen(points.first).dy);
        for (final p in points.skip(1)) {
          final s = _screen(p);
          path.lineTo(s.dx, s.dy);
        }
        final color = outbound ? AppColors.routeOut : AppColors.routeBack;
        final emphasis = outbound == showOut;
        canvas.drawPath(
          path,
          Paint()
            ..color = color.withValues(alpha: emphasis ? 0.95 : 0.35)
            ..style = PaintingStyle.stroke
            ..strokeWidth = emphasis ? 4.5 : 3
            ..strokeCap = StrokeCap.round
            ..strokeJoin = StrokeJoin.round,
        );
      }
      final dest = _screen(world.graph.node(world.contracts[trip.contractId]!.destinationNode));
      _pin(canvas, dest, AppColors.routeOut, GameGlyph.store);
    }

    // Depot.
    for (final d in world.depots.values) {
      _pin(canvas, _screen(world.graph.node(d.roadNode)), AppColors.accent, GameGlyph.depot);
    }

    // Kendaraan di jalan / di pelanggan.
    for (final v in world.vehicles.values) {
      final snap = world.vehicleSnapshot(v.id, at: t);
      final pose = snap.pose;
      if (pose == null) continue;
      _vehicle(canvas, _screen(pose.position), pose.headingDeg, moving: snap.activity == VehicleActivity.onRoad);
    }
  }

  void _pin(Canvas canvas, Offset at, Color color, GameGlyph glyph) {
    canvas.drawCircle(at, 15, Paint()..color = Colors.black.withValues(alpha: 0.35));
    canvas.drawCircle(at, 13, Paint()..color = color);
    paintGlyph(canvas, glyph, Rect.fromCenter(center: at, width: 17, height: 17), AppColors.onAccent);
  }

  void _vehicle(Canvas canvas, Offset at, double headingDeg, {required bool moving}) {
    canvas.drawCircle(at, 11, Paint()..color = Colors.white);
    canvas.drawCircle(at, 9, Paint()..color = AppColors.accent);
    if (!moving) return;
    final a = headingDeg * math.pi / 180;
    final dir = Offset(math.sin(a), -math.cos(a));
    final side = Offset(-dir.dy, dir.dx);
    final tip = at + dir * 18;
    final path = Path()
      ..moveTo(tip.dx, tip.dy)
      ..lineTo((at + dir * 9 + side * 6).dx, (at + dir * 9 + side * 6).dy)
      ..lineTo((at + dir * 9 - side * 6).dx, (at + dir * 9 - side * 6).dy)
      ..close();
    canvas.drawPath(path, Paint()..color = Colors.white);
  }

  @override
  bool shouldRepaint(_OverlayPainter old) => true;
}
