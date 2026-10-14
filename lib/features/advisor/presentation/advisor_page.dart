import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:personal_finance_manager/core/db/app_database.dart';
import 'package:personal_finance_manager/core/money/currency_meta.dart';
import 'package:personal_finance_manager/core/utils/ui_helpers.dart';
import 'package:personal_finance_manager/core/widgets/amount_text.dart';
import 'package:personal_finance_manager/features/advisor/data/advisor_providers.dart';
import 'package:personal_finance_manager/features/advisor/data/advisor_service.dart';
import 'package:personal_finance_manager/features/advisor/domain/advisor_input.dart';
import 'package:personal_finance_manager/features/advisor/domain/advisor_metrics.dart';
import 'package:personal_finance_manager/features/advisor/domain/advisor_validator.dart';
import 'package:personal_finance_manager/features/advisor/domain/allocation_presets.dart';
import 'package:personal_finance_manager/features/settings/data/ai_providers.dart';

class AdvisorPage extends ConsumerStatefulWidget {
  const AdvisorPage({super.key});

  @override
  ConsumerState<AdvisorPage> createState() => _AdvisorPageState();
}

class _AdvisorPageState extends ConsumerState<AdvisorPage> {
  bool _busy = false;

  Future<void> _generate(AdvisorMetrics metrics) async {
    final key = await ref.read(secureStoreProvider).readAiKey();
    if (!mounted) return;
    if (key == null || key.isEmpty) {
      showSnack(context, 'Atur API key AI di Pengaturan dulu');
      return;
    }

    setState(() => _busy = true);
    try {
      await ref.read(advisorServiceProvider).generate(metrics);
    } on AdvisorException catch (e) {
      if (mounted) showSnack(context, e.message);
    } catch (e) {
      if (mounted) showSnack(context, 'AI gagal: ${errorMessage(e)}');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final metricsAsync = ref.watch(advisorMetricsProvider);
    final latest = ref.watch(latestAdvisorProvider).valueOrNull;
    final stealth = ref.watch(stealthModeProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Advisor'),
        actions: [
          IconButton(
            icon: const Icon(Icons.tune),
            tooltip: 'Target alokasi',
            onPressed: () => context.push('/allocation'),
          ),
        ],
      ),
      body: metricsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text(errorMessage(e))),
        data: (m) => ListView(
          padding: const EdgeInsets.all(24),
          children: [
            _MetricsSection(metrics: m),
            const SizedBox(height: 32),
            _InsightSection(
              metrics: m,
              latest: latest,
              stealth: stealth,
              busy: _busy,
              onGenerate: () => _generate(m),
            ),
            const SizedBox(height: 24),
            Text(
              'Angka dihitung aplikasi; AI hanya menarasikannya. Insight yang '
              'memuat angka di luar data, atau saran beli/jual dan prediksi '
              'harga, dibuang otomatis. Ini alat bantu, bukan nasihat keuangan '
              'profesional.',
              style: text.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

class _MetricsSection extends StatelessWidget {
  const _MetricsSection({required this.metrics});

  final AdvisorMetrics metrics;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final m = metrics;
    final base = CurrencyMeta.baseCurrency;

    Widget row(String label, Widget value) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            children: [
              Expanded(child: Text(label, style: text.bodyMedium)),
              value,
            ],
          ),
        );

    Widget money(int? minor) => minor == null
        ? Text('-', style: text.bodyMedium)
        : AmountText(minor: minor, currency: base, style: text.bodyMedium);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Ringkasan angka', style: text.titleMedium),
        const SizedBox(height: 8),
        if (!m.hasEnoughData)
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              border: Border.all(color: Colors.orange.shade700),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              'Data belum cukup untuk proyeksi. Dibutuhkan minimal '
              '$advisorMinDataDays hari pencatatan dan satu bulan penuh '
              '(sekarang ${m.dataSpanDays} hari). Angka di bawah belum bisa '
              'dijadikan patokan.',
              style: text.bodySmall,
            ),
          ),
        const SizedBox(height: 8),
        row('Rata-rata pemasukan / bulan', money(m.avgMonthlyIncomeMinor)),
        row('Rata-rata pengeluaran / bulan', money(m.avgMonthlyExpenseMinor)),
        row(
          'Rasio tabungan',
          Text(
            m.savingsRatePct == null ? '-' : pctText(m.savingsRatePct!),
            style: text.bodyMedium,
          ),
        ),
        row('Kas dan akun', money(m.cashMinor)),
        row(
          'Runway (kas / pengeluaran bulanan)',
          Text(
            m.runwayMonths == null
                ? '-'
                : '${m.runwayMonths!.toStringAsFixed(1).replaceAll('.', ',')} bulan',
            style: text.bodyMedium,
          ),
        ),
        if (m.missingFx.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              'Kurs ${m.missingFx.join(', ')} belum tersedia; sebagian data '
              'belum terhitung.',
              style: text.bodySmall?.copyWith(color: Colors.red),
            ),
          ),
        if (m.categoryTrends.isNotEmpty) ...[
          const SizedBox(height: 24),
          Text('Pengeluaran 30 hari terakhir', style: text.titleMedium),
          const SizedBox(height: 8),
          for (final c in m.categoryTrends)
            row(
              c.name,
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  money(c.last30Minor),
                  if (c.changePct != null)
                    Padding(
                      padding: const EdgeInsets.only(left: 8),
                      child: Text(
                        pctText(c.changePct!, signed: true),
                        style: text.bodySmall?.copyWith(
                          color: c.changePct! > 0 ? Colors.red : Colors.green.shade600,
                        ),
                      ),
                    ),
                ],
              ),
            ),
        ],
        const SizedBox(height: 24),
        Text('Alokasi aset', style: text.titleMedium),
        const SizedBox(height: 8),
        if (!m.hasTargets)
          Text(
            'Target alokasi belum diatur. Ketuk ikon di kanan atas untuk memilih '
            'preset atau mengatur sendiri.',
            style: text.bodySmall,
          ),
        for (final a in m.allocation)
          row(
            assetClassLabel(a.classKey),
            Text(
              [
                a.actualPct == null ? '-' : pctText(a.actualPct!),
                if (a.targetPct != null) 'target ${pctText(a.targetPct!)}',
                if (a.driftPts != null)
                  '(${pctText(a.driftPts!, signed: true).replaceAll('%', '')} poin)',
              ].join('  '),
              style: text.bodyMedium?.copyWith(
                color: a.driftPts != null && a.driftPts!.abs() >= 10
                    ? Colors.orange.shade700
                    : null,
              ),
            ),
          ),
      ],
    );
  }
}

class _InsightSection extends StatelessWidget {
  const _InsightSection({
    required this.metrics,
    required this.latest,
    required this.stealth,
    required this.busy,
    required this.onGenerate,
  });

  final AdvisorMetrics metrics;
  final AdvisorInsight? latest;
  final bool stealth;
  final bool busy;
  final VoidCallback onGenerate;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final row = latest;

    AdvisorPayload? payload;
    if (row != null) {
      try {
        payload = AdvisorPayload.fromJson(
          jsonDecode(row.payloadJson) as Map<String, dynamic>,
        );
      } catch (_) {
        payload = null;
      }
    }

    final currentHash = AdvisorService.hashFor(metrics);
    final isStale = row != null && row.inputHash != currentHash;
    final when = row == null
        ? null
        : DateFormat('d MMM y, HH:mm', 'id_ID').format(row.generatedAt);

    final buttonLabel = payload == null
        ? 'Buat insight'
        : (isStale ? 'Perbarui insight' : 'Buat ulang');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Insight AI', style: text.titleMedium),
        const SizedBox(height: 4),
        Text(
          'Mengirim ringkasan angka (total per bulan, per kategori, alokasi) ke '
          'provider AI-mu, bukan transaksi satu per satu.',
          style: text.bodySmall,
        ),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: (busy || !metrics.hasEnoughData) ? null : onGenerate,
          icon: busy
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.auto_awesome),
          label: Text(buttonLabel),
        ),
        if (!metrics.hasEnoughData)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text('Menunggu data cukup.', style: text.bodySmall),
          ),
        if (payload != null) ...[
          const SizedBox(height: 16),
          Text(
            'Dibuat $when \u2022 ${payload.model}'
            '${payload.dropped > 0 ? ' \u2022 ${payload.dropped} insight dibuang validator' : ''}',
            style: text.bodySmall,
          ),
          if (isStale)
            Text(
              'Data sudah berubah sejak insight ini dibuat.',
              style: text.bodySmall?.copyWith(color: Colors.orange.shade700),
            ),
          const SizedBox(height: 8),
          if (stealth)
            Text(
              'Disembunyikan: Stealth Mode aktif.',
              style: text.bodyMedium,
            )
          else
            for (final item in payload.items) _InsightCard(item: item),
        ],
      ],
    );
  }
}

class _InsightCard extends StatelessWidget {
  const _InsightCard({required this.item});

  final AdvisorItem item;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final color = switch (item.severity) {
      InsightSeverity.critical => Colors.red,
      InsightSeverity.warning => Colors.orange.shade700,
      InsightSeverity.info => Theme.of(context).colorScheme.outline,
    };
    final icon = switch (item.severity) {
      InsightSeverity.critical => Icons.error_outline,
      InsightSeverity.warning => Icons.warning_amber_outlined,
      InsightSeverity.info => Icons.info_outline,
    };

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        border: Border.all(color: color),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 20),
              const SizedBox(width: 8),
              Expanded(child: Text(item.title, style: text.titleSmall)),
            ],
          ),
          const SizedBox(height: 8),
          Text(item.detail, style: text.bodyMedium),
          const SizedBox(height: 8),
          for (final e in item.evidence)
            Text('\u2022 $e', style: text.bodySmall),
        ],
      ),
    );
  }
}
