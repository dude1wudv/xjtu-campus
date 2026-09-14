import 'dart:convert';
import 'dart:typed_data';

import 'package:pointycastle/export.dart';

/// RSA PKCS#1 v1.5 加密，输出学校 CAS 所需的 `__RSA__` + Base64。
String rsaEncryptPassword(String password, String pemPublicKey) {
  final key = parseRsaPublicKeyPem(pemPublicKey);
  final engine = PKCS1Encoding(RSAEngine())
    ..init(true, PublicKeyParameter<RSAPublicKey>(key));
  final cipher = engine.process(Uint8List.fromList(utf8.encode(password)));
  return '__RSA__${base64.encode(cipher)}';
}

RSAPublicKey parseRsaPublicKeyPem(String pem) {
  final b64 = pem
      .replaceAll('-----BEGIN PUBLIC KEY-----', '')
      .replaceAll('-----END PUBLIC KEY-----', '')
      .replaceAll(RegExp(r'\s'), '');
  final bytes = base64.decode(b64);
  final parser = _Asn1Parser(Uint8List.fromList(bytes));
  final spki = parser.readSequence();
  final inner = _Asn1Parser(spki);
  inner.readSequence(); // algorithm
  final bitString = inner.readBitString();
  final keyParser = _Asn1Parser(bitString);
  final keySeq = _Asn1Parser(keyParser.readSequence());
  final modulus = keySeq.readInteger();
  final exponent = keySeq.readInteger();
  return RSAPublicKey(modulus, exponent);
}

class _Asn1Parser {
  _Asn1Parser(this.bytes);

  final Uint8List bytes;
  int offset = 0;

  Uint8List readSequence() => _read(0x30);

  Uint8List readBitString() {
    final raw = _read(0x03);
    if (raw.isEmpty) return raw;
    return Uint8List.fromList(raw.sublist(1));
  }

  BigInt readInteger() {
    final raw = _read(0x02);
    return _bytesToBigInt(raw);
  }

  Uint8List _read(int tag) {
    if (offset >= bytes.length || bytes[offset] != tag) {
      throw const FormatException('无法解析学校 RSA 公钥');
    }
    offset++;
    var length = bytes[offset++];
    if (length & 0x80 != 0) {
      final count = length & 0x7f;
      length = 0;
      for (var i = 0; i < count; i++) {
        length = (length << 8) | bytes[offset++];
      }
    }
    final end = offset + length;
    final slice = Uint8List.fromList(bytes.sublist(offset, end));
    offset = end;
    return slice;
  }

  BigInt _bytesToBigInt(Uint8List raw) {
    var value = BigInt.zero;
    for (final byte in raw) {
      value = (value << 8) | BigInt.from(byte);
    }
    return value;
  }
}
