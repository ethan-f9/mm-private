import 'advisor_input.dart';

enum InsightSeverity { info, warning, critical }

class AdvisorItem {
  const AdvisorItem({
    required this.severity,
    required this.title,
    required this.detail,
    required this.evidence,
  });

  final InsightSeverity severity;
  final String title;
  final String detail;
  final List<String> evidence;

  Map<String, dynamic> toJson() => {
        'severity': severity.name,
        'title': title,
        'detail': detail,
        'evidence': evidence,
      };

  factory AdvisorItem.fromJson(Map<String, dynamic> json) => AdvisorItem(
        severity: InsightSeverity.values.firstWhere(
          (s) => s.name == json['severity'],
          orElse: () => InsightSeverity.info,
        ),
        title: json['title'] as String,
        detail: json['detail'] as String,
        evidence: [for (final e in json['evidence'] as List) e as String],
      );
}

/// Isi yang disimpan di tabel `advisor_insights`.
class AdvisorPayload {
  const AdvisorPayload({
    required this.items,
    required this.dropped,
    required this.model,
  });

  final List<AdvisorItem> items;

  /// Jumlah insight yang dibuang validator.
  final int dropped;
  final String model;

  Map<String, dynamic> toJson() => {
        'items': [for (final i in items) i.toJson()],
        'dropped': dropped,
        'model': model,
      };

  factory AdvisorPayload.fromJson(Map<String, dynamic> json) => AdvisorPayload(
        items: [
          for (final i in json['items'] as List)
            AdvisorItem.fromJson(i as Map<String, dynamic>),
        ],
        dropped: json['dropped'] as int,
        model: json['model'] as String,
      );
}

class ValidationResult {
  const ValidationResult(this.accepted, this.rejections);

  final List<AdvisorItem> accepted;

  /// Alasan tiap insight yang dibuang (untuk ditampilkan/di-debug).
  final List<String> rejections;
}

/// Kata yang menandakan rekomendasi transaksi atau prediksi pasar.
final _forbidden = RegExp(
  r'\b(beli|jual|buy|sell|prediksi|diprediksi)\b|target harga|akan (naik|turun)',
  caseSensitive: false,
);

/// Terima hanya insight yang:
/// - berbentuk benar dan punya evidence berisi angka,
/// - hanya memuat angka yang ada di data input ([allowedTokens]),
/// - tidak memuat rekomendasi beli/jual atau prediksi.
ValidationResult validateInsights(
  Object? rawInsights,
  Set<String> allowedTokens, {
  int maxItems = 5,
}) {
  final accepted = <AdvisorItem>[];
  final rejections = <String>[];

  if (rawInsights is! List) {
    return const ValidationResult([], ['Jawaban AI tidak memuat daftar insight']);
  }

  for (var i = 0; i < rawInsights.length; i++) {
    final label = 'Insight ${i + 1}';
    final raw = rawInsights[i];
    if (raw is! Map) {
      rejections.add('$label: bentuk tidak valid');
      continue;
    }

    final title = raw['title'];
    final detail = raw['detail'];
    final evidence = raw['evidence'];
    if (title is! String ||
        title.trim().isEmpty ||
        detail is! String ||
        detail.trim().isEmpty) {
      rejections.add('$label: judul atau detail kosong');
      continue;
    }
    if (evidence is! List ||
        evidence.isEmpty ||
        evidence.any((e) => e is! String)) {
      rejections.add('$label: tidak ada evidence');
      continue;
    }
    final evidenceTexts = [for (final e in evidence) (e as String).trim()];

    final evidenceTokens = numberTokens(evidenceTexts.join(' '));
    if (evidenceTokens.isEmpty) {
      rejections.add('$label: evidence tanpa angka');
      continue;
    }

    final fullText = '$title $detail ${evidenceTexts.join(' ')}';
    if (_forbidden.hasMatch(fullText)) {
      rejections.add('$label: memuat rekomendasi beli/jual atau prediksi');
      continue;
    }

    final unknown = numberTokens(fullText).difference(allowedTokens);
    if (unknown.isNotEmpty) {
      rejections.add('$label: angka tidak ada di data (${unknown.join(', ')})');
      continue;
    }

    final severityName = raw['severity'];
    accepted.add(
      AdvisorItem(
        severity: InsightSeverity.values.firstWhere(
          (s) => s.name == severityName,
          orElse: () => InsightSeverity.info,
        ),
        title: title.trim(),
        detail: detail.trim(),
        evidence: evidenceTexts,
      ),
    );
    if (accepted.length == maxItems) break;
  }

  return ValidationResult(accepted, rejections);
}
