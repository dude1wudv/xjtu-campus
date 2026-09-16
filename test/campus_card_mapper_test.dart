import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:xjtu_campus/core/cache/snapshot_cache.dart';
import 'package:xjtu_campus/core/l10n/app_strings.dart';
import 'package:xjtu_campus/features/campus_card/data/campus_card_mapper.dart';
import 'package:xjtu_campus/features/campus_card/domain/campus_card.dart';

void main() {
  test('CampusCardMapper 解析 redact 样例：余额为分、流水符号', () {
    final file = File('docs/ncard-sample-redacted.json');
    expect(file.existsSync(), isTrue);
    final root = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
    final card = CampusCardMapper.cardFromQuery(root['card']);
    expect(card, isNotNull);
    expect(card!.balanceCents, 4250);
    expect(card.balanceLabel, '42.50');
    expect(card.expireDate, '2027-08-31');
    expect(card.cardType, '学生卡');
    expect(card.lost, isFalse);

    final txs = CampusCardMapper.transactionsFromTurnover(root['turnover']);
    expect(txs, hasLength(3));
    expect(txs[0].amountCents, -1250);
    expect(txs[0].merchant, '梧桐苑一楼食堂');
    expect(txs[2].amountCents, 10000);
    expect(txs[2].isIncome, isTrue);
    expect(CampusCardMapper.totalFromTurnover(root['turnover']), 3);
  });

  test('signedAmountCents 收入优先于消费（退款）', () {
    expect(
      CampusCardMapper.signedAmountCents(800, '消费退款', ''),
      800,
    );
    expect(
      CampusCardMapper.signedAmountCents(1200, '消费', 'consume'),
      -1200,
    );
    expect(
      CampusCardMapper.signedAmountCents(-300, '消费', ''),
      -300,
    );
  });

  test('CampusCardSnapshot cache roundtrip', () async {
    SharedPreferences.setMockInitialValues({});
    final cache = SnapshotCache(await SharedPreferences.getInstance());
    final snap = CampusCardSnapshot(
      card: const CampusCardInfo(
        balanceCents: 1000,
        pendingCents: 0,
        lost: false,
        frozen: false,
        expireDate: '2027-01-01',
        cardType: '学生卡',
      ),
      transactions: const [
        CampusCardTransaction(
          timeLabel: '2026-09-14 10:00:00',
          amountCents: -200,
          merchant: '食堂',
          balanceCents: 1000,
          typeName: '消费',
          description: '食堂-消费',
        ),
      ],
      live: true,
      banner: AppStrings.campusCardLiveBanner,
      totalCount: 1,
    );
    await cache.write(SnapshotCache.campusCard, snap.toJson());
    final restored = await cache.readMapped(
      SnapshotCache.campusCard,
      CampusCardSnapshot.fromJson,
    );
    expect(restored, isNotNull);
    expect(restored!.card?.balanceCents, 1000);
    expect(restored.transactions, hasLength(1));
    expect(restored.transactions.first.amountCents, -200);
    await cache.clearAll();
    expect(await cache.read(SnapshotCache.campusCard), isNull);
  });
}
