import '../domain/campus_card.dart';

/// Maps ncard berserker JSON → domain.
///
/// Field names follow public XJTUToolBox `card/campus_card.py`
/// (`elec_accamt`, `tranamt`, `jndatetimeStr`, …). Never log payloads.
abstract final class CampusCardMapper {
  static const _incomeMarkers = [
    '充值',
    '圈存',
    '退款',
    '补助',
    'recharge',
    'transfer-in',
    'refund',
    'subsidy',
  ];
  static const _expenseMarkers = [
    '消费',
    '支出',
    '扣款',
    'consume',
    'expense',
    'transfer-out',
  ];

  static CampusCardInfo? cardFromQuery(Object? root) {
    final data = _dataOf(root);
    if (data == null) return null;
    final cards = data['card'];
    if (cards is! List || cards.isEmpty) return null;
    final first = cards.first;
    if (first is! Map) return null;
    final map = first.map((k, v) => MapEntry(k.toString(), v));
    var expire = (map['expdate']?.toString() ?? '').trim();
    if (expire.length == 8 && int.tryParse(expire) != null) {
      expire =
          '${expire.substring(0, 4)}-${expire.substring(4, 6)}-${expire.substring(6)}';
    }
    return CampusCardInfo(
      balanceCents: _cents(map['elec_accamt']),
      pendingCents: _cents(map['unsettle_amount']),
      lost: _flag(map['barflag']),
      frozen: _flag(map['freezeflag']),
      expireDate: expire,
      cardType: (map['cardname']?.toString() ?? '').trim(),
    );
  }

  static List<CampusCardTransaction> transactionsFromTurnover(Object? root) {
    final data = _dataOf(root);
    if (data == null) return const [];
    final records = data['records'];
    if (records is! List) return const [];
    final out = <CampusCardTransaction>[];
    for (final item in records) {
      if (item is! Map) continue;
      final map = item.map((k, v) => MapEntry(k.toString(), v));
      final rawAmt = _cents(map['tranamt']);
      final typeName = (map['turnoverType']?.toString() ?? '').trim();
      final icon = (map['icon']?.toString() ?? '').trim();
      final resume = (map['resume']?.toString() ?? '').trim();
      final merchantRaw = (map['toMerchant']?.toString() ?? '').trim();
      final merchant = merchantRaw.isNotEmpty
          ? merchantRaw
          : (resume.contains('-') ? resume.split('-').first : resume);
      out.add(
        CampusCardTransaction(
          timeLabel: (map['jndatetimeStr']?.toString() ?? '').trim(),
          amountCents: signedAmountCents(rawAmt, typeName, icon),
          merchant: merchant,
          balanceCents: _cents(map['cardBalance']),
          typeName: typeName,
          description: resume,
        ),
      );
    }
    return out;
  }

  static int? totalFromTurnover(Object? root) {
    final data = _dataOf(root);
    if (data == null) return null;
    final total = data['total'];
    if (total is num) return total.toInt();
    return int.tryParse(total?.toString() ?? '');
  }

  /// Public for tests: income first so e.g. 「消费退款」 stays positive.
  static int signedAmountCents(int rawAmount, String typeName, String icon) {
    if (rawAmount < 0) return rawAmount;
    final normalized = '$typeName $icon'.toLowerCase();
    for (final marker in _incomeMarkers) {
      if (normalized.contains(marker.toLowerCase())) return rawAmount.abs();
    }
    for (final marker in _expenseMarkers) {
      if (normalized.contains(marker.toLowerCase())) return -rawAmount.abs();
    }
    return rawAmount;
  }

  static bool looksOk(Map<String, dynamic> json) {
    final code = json['code']?.toString();
    if (code == null) return false;
    if (code == '401' || code == '403') return false;
    return code == '200' || code == '0';
  }

  static Map<String, dynamic>? _dataOf(Object? root) {
    if (root is! Map) return null;
    final data = root['data'];
    if (data is Map) return data.map((k, v) => MapEntry(k.toString(), v));
    return null;
  }

  static bool _flag(Object? value) {
    if (value == true || value == 1) return true;
    return value?.toString() == '1';
  }

  /// Integers are cents; fractional numbers are treated as yuan.
  static int _cents(Object? value) {
    if (value == null) return 0;
    if (value is int) return value;
    if (value is num) {
      if (value == value.roundToDouble()) return value.toInt();
      return (value * 100).round();
    }
    final text = value.toString().trim();
    if (text.isEmpty) return 0;
    if (text.contains('.')) {
      final yuan = double.tryParse(text);
      if (yuan != null) return (yuan * 100).round();
    }
    return int.tryParse(text) ?? 0;
  }
}
