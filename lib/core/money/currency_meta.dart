/// Skala minor unit per currency.
///
/// IDR sengaja dipakai tanpa sen (scale 0): semua nominal rupiah bulat.
/// JPY juga 0. USD/EUR 2. Tambah currency baru di sini, satu tempat.
class CurrencyMeta {
  const CurrencyMeta(this.code, this.scale, this.symbol);

  final String code;
  final int scale;
  final String symbol;

  static const idr = CurrencyMeta('IDR', 0, 'Rp');
  static const usd = CurrencyMeta('USD', 2, r'$');
  static const eur = CurrencyMeta('EUR', 2, '€');
  static const jpy = CurrencyMeta('JPY', 0, '¥');

  static const _all = <String, CurrencyMeta>{
    'IDR': idr,
    'USD': usd,
    'EUR': eur,
    'JPY': jpy,
  };

  static const baseCurrency = 'IDR';

  static CurrencyMeta of(String code) {
    final meta = _all[code];
    if (meta == null) {
      throw ArgumentError('Currency tidak didukung: $code');
    }
    return meta;
  }

  static Iterable<String> get supportedCodes => _all.keys;
}
