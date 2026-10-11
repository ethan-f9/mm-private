import 'package:personal_finance_manager/core/db/app_database.dart';

/// Satu baris di daftar riwayat: transaksi biasa atau transfer.
sealed class LedgerItem {
  const LedgerItem();

  DateTime get occurredAt;
}

class TransactionItem extends LedgerItem {
  const TransactionItem(this.row);

  final TransactionRow row;

  @override
  DateTime get occurredAt => row.occurredAt;
}

class TransferItem extends LedgerItem {
  const TransferItem(this.transfer);

  final Transfer transfer;

  @override
  DateTime get occurredAt => transfer.occurredAt;
}
