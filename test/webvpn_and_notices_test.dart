import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:xjtu_campus/core/network/campus_session.dart';
import 'package:xjtu_campus/core/network/imported_campus_cookie.dart';
import 'package:xjtu_campus/features/notifications/data/dean_notices_parser.dart';
import 'package:xjtu_campus/core/network/webvpn_url.dart';
import 'package:xjtu_campus/core/storage/memory_credential_store.dart';
import 'package:xjtu_campus/features/notifications/data/dean_public_challenge.dart';

void main() {
  test('WebVPN encrypts jwxt host with default key', () {
    final url = WebVpnUrl.convert(
      'https://jwxt.xjtu.edu.cn/jwapp/sys/homeapp/index.do',
    );
    expect(
      url,
      'https://webvpn.xjtu.edu.cn/https/'
      '77726476706e69737468656265737421fae05988692862446b468ca88d1b203b'
      '/jwapp/sys/homeapp/index.do',
    );
  });

  test('WebVPN leaves CAS untouched when converting helper used', () {
    final cas = WebVpnUrl.maybeConvert(
      'https://login.xjtu.edu.cn/cas/login',
      enabled: true,
    );
    expect(cas, 'https://login.xjtu.edu.cn/cas/login');
  });

  group('DeanPublicChallenge hash (JS 32-bit signed parity)', () {
    // Vectors from known-working Python mimicking JS simpleHash.
    const cases = <(String, int)>[
      ('cid_test123456', 1745049706),
      ('abc123Mozilla/5.', 1102458168),
      ('challenge42Mozilla/5.', 887655143),
      ('abc5Mozilla/5.', 1713949835),
      ('xyz-12342Mozilla/5.', 1753221068),
      ('challengeId_long_value100Mozilla/5.', 1894637222),
    ];

    for (final (input, expected) in cases) {
      test('simpleHash($input) == $expected', () {
        expect(DeanPublicChallenge.simpleHash(input), expected);
      });
    }

    test('hashFor uses UA prefix of 10 chars', () {
      const ua =
          'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
          '(KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36';
      expect(
        DeanPublicChallenge.hashFor(
          challengeId: 'abc',
          answer: 5,
          userAgent: ua,
        ),
        1713949835,
      );
    });
  });

  test('clientIdFromResponse parses success JSON', () {
    expect(
      DeanPublicChallenge.clientIdFromResponse(
        '{"message":"Verification successful","client_id":"cid_abc","success":true}',
      ),
      'cid_abc',
    );
    expect(
      DeanPublicChallenge.clientIdFromResponse('{"success":false}'),
      isNull,
    );
    expect(DeanPublicChallenge.clientIdFromResponse('<html>'), isNull);
  });

  test('parseChallenge extracts fields from interstitial HTML', () {
    const html = '''
      var challengeId = 't9FtihQX4UEQaj7WJyRWa1Kg3or06JgB';
      var a = 6;
      var b = 10;
      var operator = '*';
    ''';
    final parsed = DeanPublicChallenge.parseChallenge(html);
    expect(parsed, isNotNull);
    expect(parsed!.challengeId, 't9FtihQX4UEQaj7WJyRWa1Kg3or06JgB');
    expect(parsed.a, 6);
    expect(parsed.b, 10);
    expect(parsed.op, '*');
    expect(DeanPublicChallenge.computeAnswer(6, 10, '*'), 60);
  });

  test('importCookies persists dean client_id into jar', () async {
    final session = CampusSession(MemoryCredentialStore());
    await session.restore();
    await session.importCookies([
      const ImportedCampusCookie(
        name: 'client_id',
        value: 'cid_unit_test_value',
        domain: 'dean.xjtu.edu.cn',
        path: '/',
        scheme: 'https',
        secure: true,
      ),
    ]);
    final cookies = await session.jar.loadForRequest(
      Uri.parse('https://dean.xjtu.edu.cn/jxxx/jxtz2.htm'),
    );
    expect(
      cookies.any((c) => c.name == 'client_id' && c.value == 'cid_unit_test_value'),
      isTrue,
    );
  });

  test('importCookies serves rg.lib cleartext:8086 (not https-only)', () async {
    final session = CampusSession(MemoryCredentialStore());
    await session.restore();
    await session.importCookies([
      const ImportedCampusCookie(
        name: 'sessionid',
        value: 'lib_seat_cookie_value',
        domain: 'rg.lib.xjtu.edu.cn',
        path: '/',
        scheme: 'http',
        port: 8086,
        secure: false,
      ),
    ]);

    final http8086 = await session.jar.loadForRequest(
      Uri.parse('http://rg.lib.xjtu.edu.cn:8086/qseat'),
    );
    expect(
      http8086.any(
        (c) => c.name == 'sessionid' && c.value == 'lib_seat_cookie_value',
      ),
      isTrue,
      reason: 'http://rg.lib:8086/qseat must receive imported cookies',
    );
    expect(
      http8086.any((c) => c.name == 'sessionid' && c.secure == true),
      isFalse,
      reason: 'cleartext jar entry must not be Secure-only',
    );

    final http8010 = await session.jar.loadForRequest(
      Uri.parse('http://rg.lib.xjtu.edu.cn:8010/qseat'),
    );
    expect(
      http8010.any(
        (c) => c.name == 'sessionid' && c.value == 'lib_seat_cookie_value',
      ),
      isTrue,
      reason: 'lib host should also mirror :8010',
    );
  });

  test('DeanNoticeParser parses docs/dean-notices-live.html (≥5)', () {
    final html = File('docs/dean-notices-live.html').readAsStringSync();
    expect(DeanPublicChallenge.looksLikeNoticeList(html), isTrue);
    expect(DeanNoticeParser.looksLikeNoticeList(html), isTrue);
    final notices = DeanNoticeParser.parse(
      html,
      base: 'https://dean.xjtu.edu.cn/jxxx/jxtz2.htm',
    );
    expect(notices.length, greaterThanOrEqualTo(5));
    expect(notices.every((n) => n.url != null && n.title.isNotEmpty), isTrue);
  });
}
