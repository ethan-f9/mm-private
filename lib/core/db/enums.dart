// Enum yang disimpan sebagai text (nama enum) lewat `textEnum<T>()`.
// Jangan rename nilai enum setelah ada data; tambah nilai baru saja.
// TradeSide ada di features/investments/domain/trade_side.dart.

enum AccountType { cash, bank, ewallet, foreign }

enum CategoryKind { expense, income }

enum TxKind { expense, income }

enum TxSource { manual, ai }

enum AssetType { stock, crypto, fund, gold }

enum PriceSource { auto, manual }
