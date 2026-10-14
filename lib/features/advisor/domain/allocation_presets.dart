/// Kelas aset untuk target alokasi. Kunci selain `cash` sama dengan nama
/// `AssetType`.
const assetClassKeys = ['cash', 'stock', 'fund', 'gold', 'crypto'];

String assetClassLabel(String key) {
  switch (key) {
    case 'cash':
      return 'Kas';
    case 'stock':
      return 'Saham';
    case 'fund':
      return 'Reksadana';
    case 'gold':
      return 'Emas';
    case 'crypto':
      return 'Crypto';
  }
  return key;
}

class AllocationPreset {
  const AllocationPreset(this.name, this.bps);

  final String name;

  /// Basis points per kelas (10000 = 100%). Total harus 10000.
  final Map<String, int> bps;
}

/// Titik awal yang bisa diedit. Ini bukan rekomendasi personal: risk profile
/// hanya memilih preset, angkanya tetap keputusanmu.
const allocationPresets = [
  AllocationPreset('Konservatif', {
    'cash': 3000,
    'stock': 1000,
    'fund': 4000,
    'gold': 2000,
    'crypto': 0,
  }),
  AllocationPreset('Moderat', {
    'cash': 1500,
    'stock': 3500,
    'fund': 3000,
    'gold': 1500,
    'crypto': 500,
  }),
  AllocationPreset('Agresif', {
    'cash': 1000,
    'stock': 5000,
    'fund': 1500,
    'gold': 1000,
    'crypto': 1500,
  }),
];
