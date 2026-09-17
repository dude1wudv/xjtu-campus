import 'dart:convert';
import 'dart:typed_data';

import 'package:pointycastle/export.dart';

/// 将校园直连 URL 转为 WebVPN 代理地址（AES-128-CFB，默认 wrdvpn 密钥）。
/// 仅用于学生本人经 WebVPN 登录后访问校内服务。
abstract final class WebVpnUrl {
  static const String base = 'https://webvpn.xjtu.edu.cn';
  static const String _key = 'wrdvpnisthebest!';
  static const String _iv = 'wrdvpnisthebest!';

  static bool isWebVpn(String url) {
    final host = Uri.tryParse(url)?.host;
    return host == 'webvpn.xjtu.edu.cn';
  }

  static bool isCampusUrl(String url) {
    final uri = Uri.tryParse(url);
    return uri != null &&
        (uri.scheme == 'http' || uri.scheme == 'https') &&
        (uri.host == 'xjtu.edu.cn' || uri.host.endsWith('.xjtu.edu.cn'));
  }

  /// Match a proxied origin without decrypting or guessing its hostname.
  static bool matchesHost(Uri uri, String host) {
    if (uri.host == host) return true;
    if (!isWebVpn(uri.toString())) return false;
    for (final scheme in const ['https', 'http']) {
      final prefix = Uri.parse(convert('$scheme://$host/')).path;
      if (uri.path.startsWith(prefix)) return true;
    }
    return false;
  }

  static bool isLoginPage(Uri uri) =>
      uri.host == 'login.xjtu.edu.cn' ||
      (isWebVpn(uri.toString()) &&
          (uri.path == '/login' || uri.path.startsWith('/login/')));

  static String maybeConvert(String url, {required bool enabled}) {
    if (!enabled || isWebVpn(url)) return url;
    final uri = Uri.tryParse(url);
    if (uri == null || !isCampusUrl(url)) return url;
    if (uri.host == 'login.xjtu.edu.cn' || uri.host == 'webvpn.xjtu.edu.cn') {
      return url;
    }
    return convert(url);
  }

  static String convert(String rawUrl) {
    final uri = Uri.parse(rawUrl);
    final hostname = uri.host;
    if (hostname.isEmpty) return rawUrl;

    final keyBytes = Uint8List.fromList(utf8.encode(_key));
    final ivBytes = Uint8List.fromList(utf8.encode(_iv));
    final encrypted = _aesCfb128Encrypt(
      key: keyBytes,
      iv: ivBytes,
      plaintext: Uint8List.fromList(utf8.encode(hostname)),
    );

    final encHex = _hex(ivBytes) + _hex(encrypted);
    var scheme = uri.scheme.isEmpty ? 'https' : uri.scheme;
    if (uri.hasPort) {
      scheme = '$scheme-${uri.port}';
    }
    final path = uri.path.isEmpty ? '/' : uri.path;
    final query = uri.hasQuery ? '?${uri.query}' : '';
    final fragment = uri.hasFragment ? '#${uri.fragment}' : '';
    return '$base/$scheme/$encHex$path$query$fragment';
  }

  /// AES-128-CFB，反馈段 128 bit（与 PyCryptodome segment_size=128 一致）。
  static Uint8List _aesCfb128Encrypt({
    required Uint8List key,
    required Uint8List iv,
    required Uint8List plaintext,
  }) {
    final aes = AESEngine()..init(true, KeyParameter(key));
    final out = Uint8List(plaintext.length);
    final shift = Uint8List.fromList(iv);
    final keystream = Uint8List(16);

    var offset = 0;
    while (offset < plaintext.length) {
      aes.processBlock(shift, 0, keystream, 0);
      final n = (plaintext.length - offset).clamp(0, 16);
      for (var i = 0; i < n; i++) {
        out[offset + i] = plaintext[offset + i] ^ keystream[i];
      }
      // CFB-128：密文反馈进移位寄存器
      if (n == 16) {
        shift.setAll(0, out.sublist(offset, offset + 16));
      } else {
        // 尾块不足 16：与常见实现一致，用生成的密文字节更新末尾
        for (var i = 0; i < n; i++) {
          shift[16 - n + i] = out[offset + i];
        }
      }
      offset += n;
    }
    return out;
  }

  static String _hex(List<int> bytes) {
    final buffer = StringBuffer();
    for (final b in bytes) {
      buffer.write(b.toRadixString(16).padLeft(2, '0'));
    }
    return buffer.toString();
  }
}
