import 'package:flutter_test/flutter_test.dart';
import 'package:xjtu_campus/core/network/webvpn_url.dart';

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
}
