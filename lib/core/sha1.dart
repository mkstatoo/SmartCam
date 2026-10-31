import 'dart:typed_data';

/// پیاده‌سازی کوچک SHA-1 (فقط برای رمز دیجست ONVIF/WS-Security لازم است؛
/// کاربرد امنیتی دیگری ندارد). خروجی ۲۰ بایت است.
Uint8List sha1(List<int> message) {
  int rotl(int x, int n) => ((x << n) | (x >> (32 - n))) & 0xFFFFFFFF;

  var h0 = 0x67452301;
  var h1 = 0xEFCDAB89;
  var h2 = 0x98BADCFE;
  var h3 = 0x10325476;
  var h4 = 0xC3D2E1F0;

  final bitLen = message.length * 8;
  final padLen = ((message.length + 9 + 63) ~/ 64) * 64;
  final data = Uint8List(padLen);
  data.setRange(0, message.length, message);
  data[message.length] = 0x80;
  // طول پیام (۶۴ بیت، big-endian) در انتها
  for (var i = 0; i < 8; i++) {
    data[padLen - 1 - i] = (bitLen >> (8 * i)) & 0xFF;
  }

  final w = List<int>.filled(80, 0);
  for (var chunk = 0; chunk < padLen; chunk += 64) {
    for (var i = 0; i < 16; i++) {
      final j = chunk + i * 4;
      w[i] =
          (data[j] << 24) |
          (data[j + 1] << 16) |
          (data[j + 2] << 8) |
          data[j + 3];
    }
    for (var i = 16; i < 80; i++) {
      w[i] = rotl(w[i - 3] ^ w[i - 8] ^ w[i - 14] ^ w[i - 16], 1);
    }
    var a = h0, b = h1, c = h2, d = h3, e = h4;
    for (var i = 0; i < 80; i++) {
      int f, k;
      if (i < 20) {
        f = (b & c) | ((~b & 0xFFFFFFFF) & d);
        k = 0x5A827999;
      } else if (i < 40) {
        f = b ^ c ^ d;
        k = 0x6ED9EBA1;
      } else if (i < 60) {
        f = (b & c) | (b & d) | (c & d);
        k = 0x8F1BBCDC;
      } else {
        f = b ^ c ^ d;
        k = 0xCA62C1D6;
      }
      final temp = (rotl(a, 5) + f + e + k + w[i]) & 0xFFFFFFFF;
      e = d;
      d = c;
      c = rotl(b, 30);
      b = a;
      a = temp;
    }
    h0 = (h0 + a) & 0xFFFFFFFF;
    h1 = (h1 + b) & 0xFFFFFFFF;
    h2 = (h2 + c) & 0xFFFFFFFF;
    h3 = (h3 + d) & 0xFFFFFFFF;
    h4 = (h4 + e) & 0xFFFFFFFF;
  }

  final out = Uint8List(20);
  final hs = [h0, h1, h2, h3, h4];
  for (var i = 0; i < 5; i++) {
    out[i * 4] = (hs[i] >> 24) & 0xFF;
    out[i * 4 + 1] = (hs[i] >> 16) & 0xFF;
    out[i * 4 + 2] = (hs[i] >> 8) & 0xFF;
    out[i * 4 + 3] = hs[i] & 0xFF;
  }
  return out;
}

String hexOf(List<int> bytes) =>
    bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
