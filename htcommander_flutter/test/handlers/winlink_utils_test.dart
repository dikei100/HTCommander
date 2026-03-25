import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:htcommander_flutter/handlers/winlink_utils.dart';

void main() {
  group('WinlinkSecurity', () {
    test('secureLoginResponse produces correct 8-digit response', () {
      expect(
        WinlinkSecurity.secureLoginResponse('23753528', 'FOOBAR'),
        equals('72768415'),
      );
    });

    test('secureLoginResponse is case-sensitive on password', () {
      expect(
        WinlinkSecurity.secureLoginResponse('23753528', 'FooBar'),
        equals('95074758'),
      );
    });

    test('generateChallenge returns 8-digit string', () {
      final challenge = WinlinkSecurity.generateChallenge();
      expect(challenge.length, equals(8));
      expect(int.tryParse(challenge), isNotNull);
    });
  });

  group('WinlinkChecksum', () {
    test('computeChecksum and checkChecksum on test vector 1', () {
      final m1 = hexStringToByteArray(
        '8A34C7000000ECF57A1C6D66F79F7F89E6E9F47BBD7E9736D6672D87ED00F8E1'
        '60EFB7961C1DDD7D2A3AD354A1BFA14D52D6D3C00BFCA805FB9FEFA81500825C'
        'CB99EFDFE6955BA77C3F15F51C50E4BB8E517FECE77F565F46BF86D198D8F322D'
        'CB49688BC56EBDF096CD99DF01F77D993EC16DB62F23CE6914315EA40BF0E3BF26'
        'E7B06282D35CE8E6D9E0574026E297E2321BB5B86B0155CB49B091E10E90F18769'
        '7B0D25C047355ECDFE06D4E379C8A6126C0C4E3503CEE1122',
      );
      expect(WinlinkChecksum.computeChecksum(m1), equals(0x53));
      expect(WinlinkChecksum.checkChecksum(m1, 0x53), isTrue);
    });

    test('computeChecksum and checkChecksum on test vector 2', () {
      final m2 = hexStringToByteArray(
        'F05B9A010000ECF57A1C6D676FB1DEEB79B7BC2E96FFAFD4E9E672D87ED00F8E1'
        '60EFB795FC1DDD753ACAB3D3BBE2D2A3336967E005FE4605FB9FEFA814F882549'
        'B99DFDFE69D4B781C3F15E51440E4B3AE50FFECA73F563F46BF86D15B5873231E'
        '339388BC2EEBDF056CD99DF01F77D98BF4069A56EE38FE01A6E2BCC817E1477E4'
        'DCDF98A0C4D73635A69CEB5FEE0D95E21361DADC346D34CA49325D7414878C1B4B'
        '5868FC0041AAF467EFDB534CE7229450038FE8445165D954D200F01160F273EA006'
        '213D0FF86E9F662B3C86BB61AF60D350340',
      );
      expect(WinlinkChecksum.computeChecksum(m2), equals(0x2A));
      expect(WinlinkChecksum.checkChecksum(m2, 0x2A), isTrue);
    });
  });

  group('WinlinkCrc16', () {
    test('compute CRC16 on test vector 1', () {
      final m1 = hexStringToByteArray(
        'C7000000ECF57A1C6D66F79F7F89E6E9F47BBD7E9736D6672D87ED00F8E160EFB'
        '7961C1DDD7D2A3AD354A1BFA14D52D6D3C00BFCA805FB9FEFA81500825CCB99EF'
        'DFE6955BA77C3F15F51C50E4BB8E517FECE77F565F46BF86D198D8F322DCB49688'
        'BC56EBDF096CD99DF01F77D993EC16DB62F23CE6914315EA40BF0E3BF26E7B06282'
        'D35CE8E6D9E0574026E297E2321BB5B86B0155CB49B091E10E90F187697B0D25C04'
        '7355ECDFE06D4E379C8A6126C0C4E3503CEE1122',
      );
      expect(WinlinkCrc16.compute(m1), equals(0x348A));
    });

    test('compute CRC16 on test vector 2', () {
      final m2 = hexStringToByteArray(
        '9A010000ECF57A1C6D676FB1DEEB79B7BC2E96FFAFD4E9E672D87ED00F8E160EFB'
        '795FC1DDD753ACAB3D3BBE2D2A3336967E005FE4605FB9FEFA814F882549B99DFD'
        'FE69D4B781C3F15E51440E4B3AE50FFECA73F563F46BF86D15B5873231E339388B'
        'C2EEBDF056CD99DF01F77D98BF4069A56EE38FE01A6E2BCC817E1477E4DCDF98A0'
        'C4D73635A69CEB5FEE0D95E21361DADC346D34CA49325D7414878C1B4B5868FC004'
        '1AAF467EFDB534CE7229450038FE8445165D954D200F01160F273EA006213D0FF86E'
        '9F662B3C86BB61AF60D350340',
      );
      expect(WinlinkCrc16.compute(m2), equals(0x5BF0));
    });
  });

  group('WinlinkCompression', () {
    test('decode and re-encode test vector 1 round-trips exactly', () {
      const xm1 =
          '8A34C7000000ECF57A1C6D66F79F7F89E6E9F47BBD7E9736D6672D87ED00F8E1'
          '60EFB7961C1DDD7D2A3AD354A1BFA14D52D6D3C00BFCA805FB9FEFA81500825C'
          'CB99EFDFE6955BA77C3F15F51C50E4BB8E517FECE77F565F46BF86D198D8F322D'
          'CB49688BC56EBDF096CD99DF01F77D993EC16DB62F23CE6914315EA40BF0E3BF26'
          'E7B06282D35CE8E6D9E0574026E297E2321BB5B86B0155CB49B091E10E90F18769'
          '7B0D25C047355ECDFE06D4E379C8A6126C0C4E3503CEE1122';
      final m1 = hexStringToByteArray(xm1);

      final decoded = WinlinkCompression.decode(m1, 199, checkCrc: true);
      expect(decoded.decompressed.length, equals(199));

      final reEncoded =
          WinlinkCompression.encode(decoded.decompressed, prependCrc: true);
      expect(bytesToHex(reEncoded.compressed), equals(xm1));
    });

    test('decode and re-encode test vector 2 round-trips exactly', () {
      const xm2 =
          'F05B9A010000ECF57A1C6D676FB1DEEB79B7BC2E96FFAFD4E9E672D87ED00F8E1'
          '60EFB795FC1DDD753ACAB3D3BBE2D2A3336967E005FE4605FB9FEFA814F882549'
          'B99DFDFE69D4B781C3F15E51440E4B3AE50FFECA73F563F46BF86D15B5873231E'
          '339388BC2EEBDF056CD99DF01F77D98BF4069A56EE38FE01A6E2BCC817E1477E4'
          'DCDF98A0C4D73635A69CEB5FEE0D95E21361DADC346D34CA49325D7414878C1B4B'
          '5868FC0041AAF467EFDB534CE7229450038FE8445165D954D200F01160F273EA006'
          '213D0FF86E9F662B3C86BB61AF60D350340';
      final m2 = hexStringToByteArray(xm2);

      final decoded = WinlinkCompression.decode(m2, 410, checkCrc: true);
      expect(decoded.decompressed.length, equals(410));

      final reEncoded =
          WinlinkCompression.encode(decoded.decompressed, prependCrc: true);
      expect(bytesToHex(reEncoded.compressed), equals(xm2));
    });

    test('encode empty input returns empty', () {
      final result =
          WinlinkCompression.encode(Uint8List(0), prependCrc: false);
      expect(result.compressed.length, equals(0));
      expect(result.crc, equals(0));
    });
  });
}
