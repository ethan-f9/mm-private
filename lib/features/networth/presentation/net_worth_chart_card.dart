import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:personal_finance_manager/core/money/currency_meta.dart';
import 'package:personal_finance_manager/core/utils/ui_helpers.dart';
import 'package:personal_finance_manager/core/widgets/amount_text.dart';
import 'package:personal_finance_manager/features/advisor/domain/advisor_input.dart';
import 'package:personal_finance_manager/features/networth/data/net_worth_history_providers.dart';
import 'package:personal_finance_manager/features/networth/domain/net_worth_history.dart';

/// Grafik riwayat net worth: pilih rentang, ketuk atau geser untuk melihat
/// nilai pada tanggal tertentu.
class NetWorthChartCard extends ConsumerStatefulWidget {
  const NetWorthChartCard({super.key});

  @override
  ConsumerState<NetWorthChartCard> createState() => _NetWorthChartCardState();
}

class _NetWorthChartCardState extends ConsumerState<NetWorthChartCard> {
  static const _ranges = <(String, int)>[
    ('1B', 30),
    ('3B', 90),
    ('6B', 180),
    ('1T', 365),
    ('Semua', 0),
  ];

  int _days = 90;
  int? _selected;

  void _select(double dx, double width, int count) {
    if (count < 2 || width <= 0) return;
    final index = ((dx / width) * (count - 1)).round().clamp(0, count - 1);
    if (index != _selected) setState(() => _selected = index);
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final history = ref.watch(netWorthHistoryProvider);
    final base = CurrencyMeta.baseCurrency;

    return history.when(
      loading: () => const SizedBox(
        height: 120,
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (e, _) => Text(errorMessage(e), style: text.bodySmall),
      data: (all) {
        final points = sliceHistory(all, _days, DateTime.now());
        if (points.length < 2) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(
              'Grafik net worth muncul setelah ada data lebih dari satu hari.',
              style: text.bodySmall,
            ),
          );
        }

        final index = (_selected != null && _selected! < points.length)
            ? _selected!
            : points.length - 1;
        final point = points[index];
        final first = points.first;
        final change = point.totalMinor - first.totalMinor;
        final changePct =
            first.totalMinor > 0 ? change / first.totalMinor * 100 : null;
        final changeColor = change < 0 ? Colors.red : Colors.green.shade600;
        final anyEstimated = points.any((p) => p.estimated);
        final anyIncomplete = points.any((p) => !p.complete);

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    DateFormat('EEEE, d MMM y', 'id_ID').format(point.date),
                    style: text.labelLarge,
                  ),
                ),
                AmountText(
                  minor: point.totalMinor,
                  currency: base,
                  style: text.titleSmall,
                ),
              ],
            ),
            const SizedBox(height: 2),
            Row(
              children: [
                Text('Sejak ${DateFormat('d MMM', 'id_ID').format(first.date)}: ',
                    style: text.bodySmall),
                AmountText(
                  minor: change,
                  currency: base,
                  style: text.bodySmall?.copyWith(color: changeColor),
                ),
                if (changePct != null)
                  Text(
                    '  ${pctText(changePct, signed: true)}',
                    style: text.bodySmall?.copyWith(color: changeColor),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 160,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final width = constraints.maxWidth;
                  return GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTapDown: (d) => _select(d.localPosition.dx, width, points.length),
                    onHorizontalDragStart: (d) =>
                        _select(d.localPosition.dx, width, points.length),
                    onHorizontalDragUpdate: (d) =>
                        _select(d.localPosition.dx, width, points.length),
                    child: CustomPaint(
                      size: Size(width, 160),
                      painter: _LineChartPainter(
                        values: [for (final p in points) p.totalMinor],
                        selected: index,
                        lineColor: Theme.of(context).colorScheme.primary,
                        gridColor: Theme.of(context).colorScheme.outline,
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                for (final (label, days) in _ranges)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(label),
                      selected: _days == days,
                      visualDensity: VisualDensity.compact,
                      onSelected: (_) => setState(() {
                        _days = days;
                        _selected = null;
                      }),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Wrap(
              spacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text('Kas', style: text.bodySmall),
                AmountText(
                  minor: point.cashMinor,
                  currency: base,
                  style: text.bodySmall,
                ),
                Text('\u2022', style: text.bodySmall),
                Text('Investasi', style: text.bodySmall),
                AmountText(
                  minor: point.investmentsMinor,
                  currency: base,
                  style: text.bodySmall,
                ),
              ],
            ),
            if (anyEstimated || anyIncomplete)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  anyIncomplete
                      ? 'Sebagian titik belum lengkap: ada currency tanpa kurs.'
                      : 'Sebagian titik adalah estimasi: kurs atau harga belum '
                          'tercatat pada tanggal itu (dipakai kurs terdekat atau '
                          'harga beli).',
                  style: text.bodySmall?.copyWith(color: Colors.orange.shade700),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _LineChartPainter extends CustomPainter {
  _LineChartPainter({
    required this.values,
    required this.selected,
    required this.lineColor,
    required this.gridColor,
  });

  final List<int> values;
  final int selected;
  final Color lineColor;
  final Color gridColor;

  @override
  void paint(Canvas canvas, Size size) {
    if (values.length < 2) return;

    final minV = values.reduce(math.min);
    final maxV = values.reduce(math.max);
    final span = (maxV - minV) == 0 ? 1 : (maxV - minV);
    const padTop = 8.0;
    const padBottom = 8.0;
    final h = size.height - padTop - padBottom;

    Offset pointAt(int i) => Offset(
          i / (values.length - 1) * size.width,
          padTop + h - (values[i] - minV) / span * h,
        );

    final grid = Paint()
      ..color = gridColor
      ..strokeWidth = 1;
    for (var i = 0; i <= 2; i++) {
      final y = padTop + h * i / 2;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }

    final line = Path()..moveTo(pointAt(0).dx, pointAt(0).dy);
    for (var i = 1; i < values.length; i++) {
      final p = pointAt(i);
      line.lineTo(p.dx, p.dy);
    }
    final area = Path.from(line)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();

    canvas.drawPath(
      area,
      Paint()
        ..color = lineColor.withAlpha(28)
        ..style = PaintingStyle.fill,
    );
    canvas.drawPath(
      line,
      Paint()
        ..color = lineColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeJoin = StrokeJoin.round,
    );

    final p = pointAt(selected);
    canvas.drawLine(
      Offset(p.dx, 0),
      Offset(p.dx, size.height),
      Paint()
        ..color = lineColor.withAlpha(120)
        ..strokeWidth = 1,
    );
    canvas.drawCircle(p, 5, Paint()..color = lineColor);
    canvas.drawCircle(p, 2.5, Paint()..color = Colors.white);
  }

  @override
  bool shouldRepaint(covariant _LineChartPainter old) =>
      old.selected != selected ||
      old.lineColor != lineColor ||
      old.values.length != values.length ||
      !_sameValues(old.values, values);

  static bool _sameValues(List<int> a, List<int> b) {
    for (var i = 0; i < a.length && i < b.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
