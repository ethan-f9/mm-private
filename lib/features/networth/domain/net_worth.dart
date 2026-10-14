import 'package:personal_finance_manager/core/money/currency_meta.dart';
import 'package:personal_finance_manager/features/investments/domain/fx_table.dart';
import 'package:personal_finance_manager/features/investments/domain/portfolio.dart';

class NetWorth {
  const NetWorth({
    required this.cashMinor,
    required this.investmentsMinor,
    required this.unrealizedMinor,
    required this.unpricedCount,
    required this.missingFx,
  });

  /// Saldo semua akun dalam IDR.
  final int cashMinor;

  /// Nilai pasar portofolio dalam IDR.
  final int investmentsMinor;
  final int unrealizedMinor;
  final int unpricedCount;

  /// Currency yang kursnya belum ada. Nilainya BELUM masuk total.
  final Set<String> missingFx;

  int get totalMinor => cashMinor + investmentsMinor;
  bool get isComplete => missingFx.isEmpty;
}

/// Net worth dalam IDR = saldo akun (sudah memuat dampak kas dari trade)
/// + nilai pasar portofolio. Currency tanpa kurs tidak dijumlahkan dan
/// dilaporkan di [NetWorth.missingFx], bukan dianggap nol diam-diam.
NetWorth computeNetWorth({
  required Map<String, int> cashByCurrency,
  required List<Holding> holdings,
  required FxTable fx,
}) {
  var cash = 0;
  final missing = <String>{};
  cashByCurrency.forEach((currency, minor) {
    if (currency == CurrencyMeta.baseCurrency) {
      cash += minor;
      return;
    }
    final converted = fx.toBaseMinor(minor, currency);
    if (converted == null) {
      missing.add(currency);
    } else {
      cash += converted;
    }
  });

  final portfolio = summarizePortfolio(holdings, fx);
  return NetWorth(
    cashMinor: cash,
    investmentsMinor: portfolio.valueMinor,
    unrealizedMinor: portfolio.unrealizedMinor,
    unpricedCount: portfolio.unpricedCount,
    missingFx: {...missing, ...portfolio.missingFx},
  );
}
