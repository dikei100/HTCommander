import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import '../core/data_broker_client.dart';
import 'winlink_utils.dart';

/// Binary attachment for Winlink mail.
class WinlinkMailAttachment {
  String name;
  Uint8List data;

  WinlinkMailAttachment({required this.name, required this.data});

  Map<String, dynamic> toJson() => {
        'name': name,
        'data': base64Encode(data),
      };

  factory WinlinkMailAttachment.fromJson(Map<String, dynamic> json) =>
      WinlinkMailAttachment(
        name: json['name'] as String? ?? '',
        data: json['data'] != null
            ? base64Decode(json['data'] as String)
            : Uint8List(0),
      );
}

/// Mail flags matching C# WinLinkMail.MailFlags enum.
class MailFlags {
  static const int unread = 1;
  static const int private_ = 2;
  static const int p2p = 4;
}

/// A Winlink mail message.
class WinlinkMail {
  String mid;
  String from;
  String to;
  String? cc;
  String subject;
  String body;
  DateTime date;
  String folder;
  bool read;
  String? mbo;
  String? location;
  int flags;
  List<String> attachments;
  List<WinlinkMailAttachment> binaryAttachments;

  WinlinkMail({
    required this.mid,
    required this.from,
    required this.to,
    required this.subject,
    this.cc,
    this.body = '',
    DateTime? date,
    this.folder = 'Inbox',
    this.read = false,
    this.mbo,
    this.location,
    this.flags = 0,
    List<String>? attachments,
    List<WinlinkMailAttachment>? binaryAttachments,
  })  : date = date ?? DateTime.now(),
        attachments = attachments ?? [],
        binaryAttachments = binaryAttachments ?? [];

  Map<String, dynamic> toJson() => {
        'mid': mid,
        'from': from,
        'to': to,
        if (cc != null && cc!.isNotEmpty) 'cc': cc,
        'subject': subject,
        'body': body,
        'date': date.toIso8601String(),
        'folder': folder,
        'read': read,
        if (mbo != null) 'mbo': mbo,
        if (location != null) 'location': location,
        if (flags != 0) 'flags': flags,
        'attachments': attachments,
        if (binaryAttachments.isNotEmpty)
          'binaryAttachments':
              binaryAttachments.map((a) => a.toJson()).toList(),
      };

  factory WinlinkMail.fromJson(Map<String, dynamic> json) => WinlinkMail(
        mid: json['mid'] as String? ?? '',
        from: json['from'] as String? ?? '',
        to: json['to'] as String? ?? '',
        cc: json['cc'] as String?,
        subject: json['subject'] as String? ?? '',
        body: json['body'] as String? ?? '',
        date: DateTime.tryParse(json['date'] ?? ''),
        folder: json['folder'] as String? ?? 'Inbox',
        read: json['read'] as bool? ?? false,
        mbo: json['mbo'] as String?,
        location: json['location'] as String?,
        flags: json['flags'] as int? ?? 0,
        attachments: (json['attachments'] as List?)
                ?.map((a) => a.toString())
                .toList() ??
            [],
        binaryAttachments: (json['binaryAttachments'] as List?)
                ?.map((a) =>
                    WinlinkMailAttachment.fromJson(a as Map<String, dynamic>))
                .toList() ??
            [],
      );

  /// Generate a random 12-character message ID (digits + uppercase letters).
  static String generateMid() {
    final rng = Random.secure();
    const chars = '0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ';
    return String.fromCharCodes(
      List.generate(12, (_) => chars.codeUnitAt(rng.nextInt(36))),
    );
  }

  /// Serialize a mail to the Winlink binary wire format.
  static Uint8List serializeMail(WinlinkMail mail) {
    final bodyData = utf8.encode(mail.body);
    final sb = StringBuffer();

    sb.writeln('MID: ${mail.mid}');
    final dateStr =
        '${mail.date.year.toString().padLeft(4, '0')}/${mail.date.month.toString().padLeft(2, '0')}/${mail.date.day.toString().padLeft(2, '0')} ${mail.date.hour.toString().padLeft(2, '0')}:${mail.date.minute.toString().padLeft(2, '0')}';
    sb.writeln('Date: $dateStr');
    if ((mail.flags & MailFlags.private_) != 0) sb.writeln('Type: Private');
    if (mail.from.isNotEmpty) sb.writeln('From: ${mail.from}');
    if (mail.to.isNotEmpty) sb.writeln('To: ${mail.to}');
    if (mail.cc != null && mail.cc!.isNotEmpty) sb.writeln('Cc: ${mail.cc}');
    if (mail.subject.isNotEmpty) sb.writeln('Subject: ${mail.subject}');
    if (mail.mbo != null && mail.mbo!.isNotEmpty) sb.writeln('Mbo: ${mail.mbo}');
    if ((mail.flags & MailFlags.p2p) != 0) sb.writeln('X-P2P: True');
    if (mail.location != null && mail.location!.isNotEmpty) {
      sb.writeln('X-Location: ${mail.location}');
    }
    if (mail.body.isNotEmpty) sb.writeln('Body: ${bodyData.length}');
    for (final att in mail.binaryAttachments) {
      sb.writeln('File: ${att.data.length} ${att.name}');
    }
    sb.writeln(); // Empty line before body

    final headerData = utf8.encode(sb.toString());
    final buf = BytesBuilder();
    buf.add(headerData);
    buf.add(bodyData);
    buf.add([0x0D, 0x0A]); // \r\n
    for (final att in mail.binaryAttachments) {
      buf.add(att.data);
      buf.add([0x0D, 0x0A]);
    }
    buf.addByte(0x00); // Null terminator
    return buf.toBytes();
  }

  /// Deserialize a mail from the Winlink binary wire format.
  static WinlinkMail? deserializeMail(Uint8List databuf) {
    final headerLimit = _findFirstDoubleNewline(databuf);
    if (headerLimit < 0) return null;

    final header = utf8.decode(databuf.sublist(0, headerLimit));
    final mail = WinlinkMail(
      mid: '',
      from: '',
      to: '',
      subject: '',
    );

    int bodyLength = -1;
    int ptr = headerLimit + 4; // Skip \r\n\r\n
    final lines = header.replaceAll('\r\n', '\n').split(RegExp(r'[\n\r]'));

    for (final line in lines) {
      final i = line.indexOf(':');
      if (i <= 0) continue;
      final key = line.substring(0, i).toLowerCase().trim();
      final value = line.substring(i + 1).trim();

      switch (key) {
        case 'mid':
          mail.mid = value;
          break;
        case 'date':
          try {
            final parts = value.split(RegExp(r'[/ :]'));
            if (parts.length >= 5) {
              mail.date = DateTime(
                int.parse(parts[0]),
                int.parse(parts[1]),
                int.parse(parts[2]),
                int.parse(parts[3]),
                int.parse(parts[4]),
              );
            }
          } catch (_) {}
          break;
        case 'type':
          if (value.toLowerCase() == 'private') {
            mail.flags |= MailFlags.private_;
          }
          break;
        case 'to':
          mail.to = value;
          break;
        case 'cc':
          mail.cc = value;
          break;
        case 'from':
          mail.from = value;
          break;
        case 'subject':
          mail.subject = value;
          break;
        case 'mbo':
          mail.mbo = value;
          break;
        case 'body':
          bodyLength = int.tryParse(value) ?? -1;
          break;
        case 'file':
          final j = value.indexOf(' ');
          if (j > 0) {
            final dataLen = int.tryParse(value.substring(0, j).trim()) ?? 0;
            final name = value.substring(j + 1).trim();
            mail.binaryAttachments.add(WinlinkMailAttachment(
              name: name,
              data: Uint8List(dataLen), // Placeholder, filled below
            ));
          }
          break;
        case 'x-location':
          mail.location = value;
          break;
        case 'x-p2p':
          if (value.toLowerCase() == 'true') {
            mail.flags |= MailFlags.p2p;
          }
          break;
      }
    }

    // Extract body
    if (bodyLength > 0 && ptr + bodyLength <= databuf.length) {
      mail.body = utf8.decode(databuf.sublist(ptr, ptr + bodyLength));
      ptr += bodyLength + 2; // Skip body + \r\n
    }

    // Extract binary attachments
    for (final att in mail.binaryAttachments) {
      if (ptr + att.data.length <= databuf.length) {
        att.data = Uint8List.fromList(
            databuf.sublist(ptr, ptr + att.data.length));
        ptr += att.data.length + 2; // Skip data + \r\n
      }
    }

    return mail;
  }

  /// Encode a mail into compressed B2F binary blocks.
  /// Returns null on compression failure.
  static ({List<Uint8List> blocks, int uncompressedSize, int compressedSize})?
      encodeMailToBlocks(WinlinkMail mail) {
    final uncompressedMail = serializeMail(mail);
    final uncompressedSize = uncompressedMail.length;

    final encoded =
        WinlinkCompression.encode(uncompressedMail, prependCrc: true);
    final payloadBuf = encoded.compressed;
    if (payloadBuf.isEmpty) return null;

    final subjectBuf = utf8.encode(mail.subject);
    final buf = BytesBuilder();

    // Header block: type 0x01 = subject
    buf.addByte(0x01);
    buf.addByte(subjectBuf.length + 3);
    buf.add(subjectBuf);
    buf.addByte(0x00);
    buf.addByte(0x30); // ASCII '0'
    buf.addByte(0x00);

    // Data blocks: type 0x02, max 250 bytes each
    int payloadPtr = 0;
    while (payloadPtr < payloadBuf.length) {
      final blockSize =
          payloadBuf.length - payloadPtr < 250 ? payloadBuf.length - payloadPtr : 250;
      buf.addByte(0x02);
      buf.addByte(blockSize);
      buf.add(payloadBuf.sublist(payloadPtr, payloadPtr + blockSize));
      payloadPtr += blockSize;
    }

    // Checksum block: type 0x04
    buf.addByte(0x04);
    buf.addByte(WinlinkChecksum.computeChecksum(payloadBuf));

    final output = buf.toBytes();
    final compressedSize = output.length;

    // Break into 128-byte transmission blocks
    final blocks = <Uint8List>[];
    int outputPtr = 0;
    while (outputPtr < output.length) {
      final blockSize =
          output.length - outputPtr < 128 ? output.length - outputPtr : 128;
      blocks.add(Uint8List.fromList(
          output.sublist(outputPtr, outputPtr + blockSize)));
      outputPtr += blockSize;
    }

    return (
      blocks: blocks,
      uncompressedSize: uncompressedSize,
      compressedSize: compressedSize,
    );
  }

  /// Decode compressed B2F binary blocks back into a mail.
  /// Returns null on failure.
  static ({WinlinkMail? mail, bool fail, int dataConsumed})
      decodeBlocksToEmail(Uint8List block) {
    if (block.isEmpty) return (mail: null, fail: false, dataConsumed: 0);

    // First pass: validate structure and compute payload size
    int payloadLen = 0, ptr = 0;
    bool completeMail = false;
    while (!completeMail && (ptr + 1) < block.length) {
      final cmd = block[ptr];
      switch (cmd) {
        case 1: // Subject header
          final cmdlen = block[ptr + 1];
          ptr += 2 + cmdlen;
          break;
        case 2: // Data block
          final cmdlen = block[ptr + 1];
          payloadLen += cmdlen;
          ptr += 2 + cmdlen;
          break;
        case 4: // Checksum
          ptr += 2;
          completeMail = true;
          break;
        default:
          return (mail: null, fail: false, dataConsumed: 0);
      }
    }
    if (!completeMail) return (mail: null, fail: false, dataConsumed: 0);

    // Second pass: extract payload and validate checksum
    ptr = 0;
    final payload = Uint8List(payloadLen);
    int payloadPtr = 0;
    completeMail = false;
    while (!completeMail && (ptr + 1) < block.length) {
      final cmd = block[ptr];
      switch (cmd) {
        case 1:
          final cmdlen = block[ptr + 1];
          ptr += 2 + cmdlen;
          break;
        case 2:
          final cmdlen = block[ptr + 1];
          payload.setRange(
              payloadPtr, payloadPtr + cmdlen, block, ptr + 2);
          payloadPtr += cmdlen;
          ptr += 2 + cmdlen;
          break;
        case 4:
          final cmdlen = block[ptr + 1];
          if (WinlinkChecksum.computeChecksum(payload) != cmdlen) {
            return (mail: null, fail: true, dataConsumed: 0);
          }
          ptr += 2;
          break;
      }
    }

    // Decompress
    final expectedLength = payload[2] +
        (payload[3] << 8) +
        (payload[4] << 16) +
        (payload[5] << 24);
    try {
      final decoded = WinlinkCompression.decode(payload, expectedLength,
          checkCrc: true);
      if (decoded.decompressed.length != expectedLength) {
        return (mail: null, fail: true, dataConsumed: 0);
      }
      final mail = deserializeMail(decoded.decompressed);
      if (mail == null) return (mail: null, fail: true, dataConsumed: 0);
      return (mail: mail, fail: false, dataConsumed: ptr);
    } catch (_) {
      return (mail: null, fail: true, dataConsumed: 0);
    }
  }

  /// Check if a mail is addressed to the given callsign.
  static bool isMailForStation(String callsign, String? to, String? cc) {
    return _isMailForStationEx(callsign, to) ||
        _isMailForStationEx(callsign, cc);
  }

  static bool _isMailForStationEx(String callsign, String? t) {
    if (callsign.isEmpty || t == null || t.isEmpty) return false;
    final recipients = t.split(';');
    for (final s2 in recipients) {
      final s3 = s2.trim();
      if (s3.isEmpty) continue;
      final atIdx = s3.indexOf('@');
      if (atIdx == -1) {
        if (s3.toUpperCase() == callsign.toUpperCase()) return true;
        if (s3.toUpperCase().startsWith('${callsign.toUpperCase()}-')) {
          return true;
        }
      } else {
        final key = s3.substring(0, atIdx).toUpperCase();
        final domain = s3.substring(atIdx + 1).toUpperCase();
        if (domain == 'WINLINK.ORG' &&
            (key == callsign.toUpperCase() ||
                key.startsWith('${callsign.toUpperCase()}-'))) {
          return true;
        }
      }
    }
    return false;
  }

  static int _findFirstDoubleNewline(Uint8List data) {
    if (data.length < 4) return -1;
    for (int i = 0; i <= data.length - 4; i++) {
      if (data[i] == 0x0D &&
          data[i + 1] == 0x0A &&
          data[i + 2] == 0x0D &&
          data[i + 3] == 0x0A) {
        return i;
      }
    }
    return -1;
  }

}

/// In-memory mail store for Winlink mail.
///
/// Simplified port of HTCommander.Core/MailStore.cs
/// SQLite persistence will be added in a later phase.
class MailStore {
  final DataBrokerClient _broker = DataBrokerClient();
  final List<WinlinkMail> _mails = [];

  MailStore() {
    _broker.subscribe(1, 'MailAdd', _onMailAdd);
    _broker.subscribe(1, 'MailDelete', _onMailDelete);
    _broker.subscribe(1, 'MailMove', _onMailMove);

    // Signal readiness
    _broker.dispatch(1, 'MailStoreReady', true, store: false);
  }

  void _onMailAdd(int deviceId, String name, Object? data) {
    if (data is! WinlinkMail) return;
    _mails.add(data);
    _dispatchMails();
  }

  void _onMailDelete(int deviceId, String name, Object? data) {
    if (data is! String) return;
    _mails.removeWhere((m) => m.mid == data);
    _dispatchMails();
  }

  void _onMailMove(int deviceId, String name, Object? data) {
    if (data is! Map) return;
    final mid = data['mid'];
    final newFolder = data['folder'];
    if (mid is! String || newFolder is! String) return;
    for (final mail in _mails) {
      if (mail.mid == mid) {
        mail.folder = newFolder;
        break;
      }
    }
    _dispatchMails();
  }

  /// Whether a mail with the given message ID exists.
  bool mailExists(String mid) => _mails.any((m) => m.mid == mid);

  /// Gets a mail by message ID, or null if not found.
  WinlinkMail? getMail(String mid) {
    for (final mail in _mails) {
      if (mail.mid == mid) return mail;
    }
    return null;
  }

  /// Returns all mails.
  List<WinlinkMail> getAllMails() => List.unmodifiable(_mails);

  /// Returns mails filtered by folder name.
  List<WinlinkMail> getMailsByFolder(String folder) =>
      _mails.where((m) => m.folder == folder).toList();

  /// Adds a mail to the store.
  void addMail(WinlinkMail mail) {
    _mails.add(mail);
    _dispatchMails();
  }

  /// Deletes a mail by message ID.
  void deleteMail(String mid) {
    _mails.removeWhere((m) => m.mid == mid);
    _dispatchMails();
  }

  /// Moves a mail to a new folder.
  void moveMail(String mid, String newFolder) {
    for (final mail in _mails) {
      if (mail.mid == mid) {
        mail.folder = newFolder;
        break;
      }
    }
    _dispatchMails();
  }

  void _dispatchMails() {
    _broker.dispatch(1, 'Mails', List<WinlinkMail>.from(_mails),
        store: false);
  }

  void dispose() {
    _broker.dispose();
  }
}
