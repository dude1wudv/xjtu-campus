import 'package:flutter_test/flutter_test.dart';
import 'package:xjtu_campus/features/campus_card/data/ncard_sso.dart';
import 'package:xjtu_campus/features/campus_card/data/ncard_mobile_stealth.dart';
import 'package:xjtu_campus/core/constants/campus_urls.dart';

void main() {
  test('NcardSso.ticketFromUri extracts ticket on ncard host', () {
    final uri = Uri.parse(
      'https://ncard.xjtu.edu.cn/plat/?ticket=ST-abc123-demo',
    );
    expect(NcardSso.ticketFromUri(uri), 'ST-abc123-demo');
  });

  test('NcardSso.ticketFromUri rejects non-ncard host', () {
    final uri = Uri.parse(
      'https://login.xjtu.edu.cn/cas/login?ticket=ST-should-ignore',
    );
    expect(NcardSso.ticketFromUri(uri), isNull);
  });

  test('NcardSso.ticketFromUri returns null without ticket', () {
    final uri = Uri.parse('https://ncard.xjtu.edu.cn/plat/');
    expect(NcardSso.ticketFromUri(uri), isNull);
  });

  test('iPhone UA is used for ncard mobile', () {
    expect(CampusUrls.ncardMobileUserAgent, contains('iPhone'));
    expect(CampusUrls.ncardMobileUserAgent, contains('Mobile/15E148'));
    expect(NcardMobileStealth.userAgent, CampusUrls.ncardMobileUserAgent);
  });

  test('accessTokenFromJson reads top-level token', () {
    expect(
      NcardSso.accessTokenFromJson({'access_token': 'tok-top'}),
      'tok-top',
    );
  });

  test('accessTokenFromJson reads nested data.access_token', () {
    expect(
      NcardSso.accessTokenFromJson({
        'code': 200,
        'data': {'access_token': 'tok-nested'},
      }),
      'tok-nested',
    );
  });

  test('accessTokenFromJson returns null when missing', () {
    expect(NcardSso.accessTokenFromJson({'code': 401}), isNull);
    expect(NcardSso.accessTokenFromJson(null), isNull);
  });
}
