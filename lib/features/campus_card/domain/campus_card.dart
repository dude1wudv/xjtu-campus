import 'package:equatable/equatable.dart';

/// One campus card (ncard) profile. Amounts stored in cents.
class CampusCardInfo extends Equatable {
  const CampusCardInfo({
    required this.balanceCents,
    required this.pendingCents,
    required this.lost,
    required this.frozen,
    required this.expireDate,
    required this.cardType,
  });

  final int balanceCents;
  final int pendingCents;
  final bool lost;
  final bool frozen;
  final String expireDate;
  final String cardType;

  double get balanceYuan => balanceCents / 100.0;
  double get pendingYuan => pendingCents / 100.0;

  String get balanceLabel => _yuan(balanceCents);
  String get pendingLabel => _yuan(pendingCents);

  bool get isRestricted => lost || frozen;

  Map<String, dynamic> toJson() => {
        'balanceCents': balanceCents,
        'pendingCents': pendingCents,
        'lost': lost,
        'frozen': frozen,
        'expireDate': expireDate,
        'cardType': cardType,
      };

  factory CampusCardInfo.fromJson(Map<String, dynamic> json) {
    return CampusCardInfo(
      balanceCents: (json['balanceCents'] as num?)?.toInt() ?? 0,
      pendingCents: (json['pendingCents'] as num?)?.toInt() ?? 0,
      lost: json['lost'] as bool? ?? false,
      frozen: json['frozen'] as bool? ?? false,
      expireDate: json['expireDate'] as String? ?? '',
      cardType: json['cardType'] as String? ?? '',
    );
  }

  @override
  List<Object?> get props => [
        balanceCents,
        pendingCents,
        lost,
        frozen,
        expireDate,
        cardType,
      ];
}

/// One turnover row. [amountCents] is signed (expense negative).
class CampusCardTransaction extends Equatable {
  const CampusCardTransaction({
    required this.timeLabel,
    required this.amountCents,
    required this.merchant,
    required this.balanceCents,
    required this.typeName,
    required this.description,
  });

  final String timeLabel;
  final int amountCents;
  final String merchant;
  final int balanceCents;
  final String typeName;
  final String description;

  bool get isExpense => amountCents < 0;
  bool get isIncome => amountCents > 0;

  String get amountLabel {
    final abs = _yuan(amountCents.abs());
    if (amountCents > 0) return '+$abs';
    if (amountCents < 0) return '-$abs';
    return abs;
  }

  String get balanceLabel => _yuan(balanceCents);

  Map<String, dynamic> toJson() => {
        'timeLabel': timeLabel,
        'amountCents': amountCents,
        'merchant': merchant,
        'balanceCents': balanceCents,
        'typeName': typeName,
        'description': description,
      };

  factory CampusCardTransaction.fromJson(Map<String, dynamic> json) {
    return CampusCardTransaction(
      timeLabel: json['timeLabel'] as String? ?? '',
      amountCents: (json['amountCents'] as num?)?.toInt() ?? 0,
      merchant: json['merchant'] as String? ?? '',
      balanceCents: (json['balanceCents'] as num?)?.toInt() ?? 0,
      typeName: json['typeName'] as String? ?? '',
      description: json['description'] as String? ?? '',
    );
  }

  @override
  List<Object?> get props => [
        timeLabel,
        amountCents,
        merchant,
        balanceCents,
        typeName,
        description,
      ];
}

class CampusCardSnapshot {
  const CampusCardSnapshot({
    required this.card,
    required this.transactions,
    required this.live,
    required this.banner,
    this.failed = false,
    this.fromCache = false,
    this.cachedAt,
    this.fetchedAt,
    this.totalCount,
  });

  final CampusCardInfo? card;
  final List<CampusCardTransaction> transactions;
  final bool live;
  final bool failed;
  final String banner;
  final bool fromCache;
  final DateTime? cachedAt;
  final DateTime? fetchedAt;
  final int? totalCount;

  CampusCardSnapshot copyWith({
    CampusCardInfo? card,
    List<CampusCardTransaction>? transactions,
    bool? live,
    bool? failed,
    String? banner,
    bool? fromCache,
    DateTime? cachedAt,
    DateTime? fetchedAt,
    int? totalCount,
    bool clearCard = false,
    bool clearCachedAt = false,
    bool clearFetchedAt = false,
  }) {
    return CampusCardSnapshot(
      card: clearCard ? null : (card ?? this.card),
      transactions: transactions ?? this.transactions,
      live: live ?? this.live,
      failed: failed ?? this.failed,
      banner: banner ?? this.banner,
      fromCache: fromCache ?? this.fromCache,
      cachedAt: clearCachedAt ? null : (cachedAt ?? this.cachedAt),
      fetchedAt: clearFetchedAt ? null : (fetchedAt ?? this.fetchedAt),
      totalCount: totalCount ?? this.totalCount,
    );
  }

  CampusCardSnapshot asCached(DateTime savedAt, {required String banner}) =>
      copyWith(
        fromCache: true,
        cachedAt: savedAt,
        banner: banner,
        failed: false,
        clearFetchedAt: true,
      );

  CampusCardSnapshot asFresh({String? banner}) => copyWith(
        fromCache: false,
        fetchedAt: DateTime.now(),
        banner: banner ?? this.banner,
        clearCachedAt: true,
      );

  Map<String, dynamic> toJson() => {
        'card': card?.toJson(),
        'transactions': transactions.map((t) => t.toJson()).toList(),
        'live': live,
        'banner': banner,
        'totalCount': totalCount,
      };

  factory CampusCardSnapshot.fromJson(Map<String, dynamic> json) {
    CampusCardInfo? card;
    final cardRaw = json['card'];
    if (cardRaw is Map) {
      card = CampusCardInfo.fromJson(Map<String, dynamic>.from(cardRaw));
    }
    final txRaw = json['transactions'];
    final transactions = <CampusCardTransaction>[];
    if (txRaw is List) {
      for (final item in txRaw) {
        if (item is Map) {
          transactions.add(
            CampusCardTransaction.fromJson(Map<String, dynamic>.from(item)),
          );
        }
      }
    }
    return CampusCardSnapshot(
      card: card,
      transactions: transactions,
      live: json['live'] as bool? ?? true,
      banner: json['banner'] as String? ?? '',
      totalCount: (json['totalCount'] as num?)?.toInt(),
    );
  }
}

String _yuan(int cents) => (cents / 100.0).toStringAsFixed(2);
