import '../../../core/l10n/app_strings.dart';
import '../domain/campus_card.dart';
import '../domain/campus_card_repository.dart';

class MockCampusCardRepository implements CampusCardRepository {
  @override
  Future<CampusCardSnapshot> load() async {
    return CampusCardSnapshot(
      card: const CampusCardInfo(
        balanceCents: 4250,
        pendingCents: 0,
        lost: false,
        frozen: false,
        expireDate: '2027-08-31',
        cardType: '学生卡（演示）',
      ),
      transactions: const [
        CampusCardTransaction(
          timeLabel: '2026-09-14 12:18:03',
          amountCents: -1250,
          merchant: '梧桐苑一楼食堂（演示）',
          balanceCents: 4250,
          typeName: '消费',
          description: '梧桐苑一楼食堂-消费',
        ),
        CampusCardTransaction(
          timeLabel: '2026-09-13 08:02:41',
          amountCents: -800,
          merchant: '康桥苑超市（演示）',
          balanceCents: 5500,
          typeName: '消费',
          description: '康桥苑超市-消费',
        ),
        CampusCardTransaction(
          timeLabel: '2026-09-12 18:40:11',
          amountCents: 10000,
          merchant: '圈存（演示）',
          balanceCents: 6300,
          typeName: '圈存',
          description: '圈存转入',
        ),
      ],
      live: false,
      banner: AppStrings.mockBanner,
      totalCount: 3,
    );
  }
}
