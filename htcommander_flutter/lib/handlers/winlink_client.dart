/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0
*/

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../core/data_broker.dart';
import '../core/data_broker_client.dart';
import '../radio/ax25/ax25_address.dart';
import '../radio/ax25/ax25_session.dart';
import 'mail_store.dart';
import 'winlink_utils.dart';

/// Connection state for the Winlink client.
enum WinlinkConnectionState {
  disconnected,
  connecting,
  connected,
  syncing,
  disconnecting,
}

/// Transport type for Winlink session.
enum _TransportType { tcp, x25 }

/// Debug log entry for Winlink protocol debugging.
class WinlinkDebugEntry {
  final DateTime time;
  final String direction; // 'TX', 'RX', 'INFO', 'ERROR'
  final String message;

  const WinlinkDebugEntry({
    required this.time,
    required this.direction,
    required this.message,
  });
}

/// Winlink client for syncing email over TCP or AX.25 radio.
///
/// Port of HTCommander.Core/WinLink/WinlinkClient.cs
class WinlinkClient {
  final DataBrokerClient _broker = DataBrokerClient();
  WinlinkConnectionState _state = WinlinkConnectionState.disconnected;
  String? _appDataPath;

  final List<WinlinkMail> _inbox = [];
  final List<WinlinkMail> _outbox = [];
  final List<WinlinkMail> _sent = [];
  final List<WinlinkMail> _trash = [];
  final List<WinlinkDebugEntry> _debugLog = [];
  static const int _maxDebugEntries = 1000;
  static const String _mailFileName = 'winlink_mail.json';

  // Transport state
  _TransportType _transportType = _TransportType.tcp;
  int _lockedRadioId = -1;
  AX25Session? _ax25Session;
  bool _pendingDisconnect = false;
  final Map<String, Object> _sessionState = {};

  // TCP state
  Socket? _tcpSocket;
  bool _tcpRunning = false;

  WinlinkConnectionState get state => _state;
  List<WinlinkMail> get inbox => List.unmodifiable(_inbox);
  List<WinlinkMail> get outbox => List.unmodifiable(_outbox);
  List<WinlinkMail> get sent => List.unmodifiable(_sent);
  List<WinlinkMail> get trash => List.unmodifiable(_trash);
  List<WinlinkDebugEntry> get debugLog => List.unmodifiable(_debugLog);

  WinlinkClient() {
    _broker.subscribe(1, 'WinlinkSync', _onWinlinkSync);
    _broker.subscribe(1, 'WinlinkSyncTcp', _onWinlinkSyncTcp);
    _broker.subscribe(1, 'WinlinkDisconnect', _onWinlinkDisconnect);
    _broker.subscribe(1, 'WinlinkCompose', _onWinlinkCompose);
    _broker.subscribe(1, 'WinlinkDeleteMail', _onWinlinkDeleteMail);
    _broker.subscribe(1, 'WinlinkMoveMail', _onWinlinkMoveMail);
    _broker.subscribe(1, 'RequestWinlinkMail', _onRequestMail);
    _broker.subscribe(1, 'RequestWinlinkDebug', _onRequestDebug);
  }

  /// Initialize persistence. Call after app data path is known.
  void initialize(String appDataPath) {
    _appDataPath = appDataPath;
    _loadMail();
    _dispatchMailState();
  }

  // ---------------------------------------------------------------------------
  // Radio sync (AX.25 transport)
  // ---------------------------------------------------------------------------

  void _onWinlinkSync(int deviceId, String name, Object? data) {
    if (data is! Map) return;
    final radioId = data['RadioId'] as int?;
    final station = data['Station'] as Map?;
    if (radioId == null || radioId <= 0 || station == null) {
      _addDebug('ERROR', 'Invalid radio sync parameters');
      return;
    }
    _startRadioSync(radioId, station);
  }

  void _startRadioSync(int radioId, Map station) {
    final stationCallsign = station['Callsign'] as String?;
    final stationChannel = station['Channel'] as String?;
    if (stationCallsign == null || stationCallsign.isEmpty) {
      _addDebug('ERROR', 'Station callsign is required');
      return;
    }

    // Find the channel ID
    if (stationChannel != null && stationChannel.isNotEmpty) {
      final channels =
          DataBroker.getValue<List?>(radioId, 'Channels', null);
      if (channels != null) {
        bool found = false;
        for (int i = 0; i < channels.length; i++) {
          final ch = channels[i];
          if (ch is Map && ch['name'] == stationChannel) {
            found = true;
            break;
          }
        }
        if (!found) {
          _addDebug('ERROR', 'Channel "$stationChannel" not found');
          _stateMessage('Channel "$stationChannel" not found');
          return;
        }
      }
    }

    _lockedRadioId = radioId;
    _transportType = _TransportType.x25;

    // Lock the radio for Winlink
    final lockData = <String, String>{'Usage': 'Winlink'};
    if (stationChannel != null) lockData['Channel'] = stationChannel;
    _broker.dispatch(radioId, 'SetLock', lockData);

    // Clear debug history
    _broker.dispatch(1, 'WinlinkDebugClear', null, store: false);
    _debugLog.clear();

    _stateMessage('Connecting to $stationCallsign via radio...');
    _initializeAX25Session(radioId, stationCallsign);
  }

  void _initializeAX25Session(int radioId, String destCallsignFull) {
    _disposeAX25Session();

    // Parse own callsign
    final ownCallsign =
        DataBroker.getValue<String>(0, 'CallSign', 'NOCALL');
    final ownStationId = DataBroker.getValue<int>(0, 'StationId', 0);

    // Parse destination callsign (may include -SSID)
    String destCall = destCallsignFull;
    int destSsid = 0;
    final dashIdx = destCallsignFull.indexOf('-');
    if (dashIdx > 0) {
      destCall = destCallsignFull.substring(0, dashIdx);
      destSsid =
          int.tryParse(destCallsignFull.substring(dashIdx + 1)) ?? 0;
    }

    _ax25Session = AX25Session(radioId);
    _ax25Session!.callSignOverride = ownCallsign;
    _ax25Session!.stationIdOverride = ownStationId;
    _ax25Session!.onStateChanged = _onAX25SessionStateChanged;
    _ax25Session!.onDataReceived = _onAX25SessionDataReceived;
    _ax25Session!.onError = _onAX25SessionError;

    final destAddr = AX25Address.getAddress(destCall, destSsid);
    final srcAddr = AX25Address.getAddress(ownCallsign, ownStationId);
    if (destAddr == null || srcAddr == null) {
      _addDebug('ERROR', 'Invalid callsign format');
      _unlockRadio();
      return;
    }

    _setState(WinlinkConnectionState.connecting);
    _ax25Session!.connect([destAddr, srcAddr]);
  }

  void _onAX25SessionStateChanged(
      AX25Session sender, AX25ConnectionState state) {
    switch (state) {
      case AX25ConnectionState.connecting:
        _setState(WinlinkConnectionState.connecting);
        break;
      case AX25ConnectionState.connected:
        _setState(WinlinkConnectionState.connected);
        break;
      case AX25ConnectionState.disconnecting:
        _setState(WinlinkConnectionState.disconnecting);
        break;
      case AX25ConnectionState.disconnected:
        _pendingDisconnect = false;
        _sessionState.clear();
        _disposeAX25Session();
        _unlockRadio();
        _setState(WinlinkConnectionState.disconnected);
        _saveMail();
        _dispatchMailState();
        break;
    }
  }

  void _onAX25SessionDataReceived(AX25Session sender, Uint8List data) {
    if (data.isEmpty) return;
    _processStream(data);
  }

  void _onAX25SessionError(AX25Session sender, String error) {
    _addDebug('ERROR', 'AX.25: $error');
  }

  void _disposeAX25Session() {
    final session = _ax25Session;
    if (session != null) {
      session.onStateChanged = null;
      session.onDataReceived = null;
      session.onError = null;
      if (session.currentState == AX25ConnectionState.connected ||
          session.currentState == AX25ConnectionState.connecting) {
        session.disconnect();
      }
      session.dispose();
      _ax25Session = null;
    }
  }

  void _disconnectX25() {
    if (_ax25Session == null || _pendingDisconnect) return;
    final session = _ax25Session!;
    if (session.currentState == AX25ConnectionState.connected ||
        session.currentState == AX25ConnectionState.connecting) {
      _pendingDisconnect = true;
      session.disconnect();
    } else {
      _disposeAX25Session();
      _unlockRadio();
      _setState(WinlinkConnectionState.disconnected);
    }
  }

  void _unlockRadio() {
    if (_lockedRadioId > 0) {
      _broker.dispatch(
          _lockedRadioId, 'SetUnlock', {'Usage': 'Winlink'});
      _lockedRadioId = -1;
    }
  }

  // ---------------------------------------------------------------------------
  // TCP transport
  // ---------------------------------------------------------------------------

  void _onWinlinkSyncTcp(int deviceId, String name, Object? data) {
    if (data is! Map) return;
    final host = data['host'] as String?;
    final port = data['port'] as int? ?? 8772;
    final callsign = data['callsign'] as String?;
    final password = data['password'] as String?;

    if (host == null || callsign == null || password == null) {
      _addDebug('ERROR', 'Missing TCP sync parameters');
      return;
    }

    _connectTcp(host, port);
  }

  Future<void> _connectTcp(String host, int port) async {
    if (_state != WinlinkConnectionState.disconnected) return;

    _transportType = _TransportType.tcp;
    _setState(WinlinkConnectionState.connecting);

    // Clear debug history
    _broker.dispatch(1, 'WinlinkDebugClear', null, store: false);
    _debugLog.clear();

    _stateMessage('Connecting to $host:$port...');

    try {
      _tcpSocket = await Socket.connect(host, port,
          timeout: const Duration(seconds: 15));
      _tcpRunning = true;
      _setState(WinlinkConnectionState.connected);
      _addDebug('INFO', 'Connected to $host:$port');

      // Start receive loop
      _tcpReceiveLoop();
    } catch (e) {
      _addDebug('ERROR', 'Connection failed: $e');
      _setState(WinlinkConnectionState.disconnected);
    }
  }

  void _tcpReceiveLoop() {
    _tcpSocket?.listen(
      (data) {
        if (!_tcpRunning) return;
        _processStream(Uint8List.fromList(data));
      },
      onDone: () {
        if (_tcpRunning) _disconnectTcp();
      },
      onError: (e) {
        if (_tcpRunning) {
          _addDebug('ERROR', 'TCP: $e');
          _disconnectTcp();
        }
      },
    );
  }

  void _disconnectTcp() {
    _setState(WinlinkConnectionState.disconnecting);
    _tcpRunning = false;
    _tcpSocket?.destroy();
    _tcpSocket = null;
    _sessionState.clear();
    _setState(WinlinkConnectionState.disconnected);
    _saveMail();
    _dispatchMailState();
  }

  // ---------------------------------------------------------------------------
  // Transport abstraction
  // ---------------------------------------------------------------------------

  void _transportSendString(String output) {
    // Log each line
    for (final line in output.split(RegExp(r'[\r\n]+'))) {
      if (line.isNotEmpty) _addDebug('TX', line);
    }
    final bytes = utf8.encode(output);
    _transportSendBytes(Uint8List.fromList(bytes));
  }

  void _transportSendBytes(Uint8List data) {
    if (_transportType == _TransportType.x25) {
      _ax25Session?.sendData(data);
    } else {
      _tcpSocket?.add(data);
    }
  }

  void _transportDisconnect() {
    if (_transportType == _TransportType.x25) {
      _disconnectX25();
    } else {
      _disconnectTcp();
    }
  }

  // ---------------------------------------------------------------------------
  // B2F Protocol Engine
  // ---------------------------------------------------------------------------

  /// Binary mail reception accumulator.
  BytesBuilder? _binaryMailAccumulator;

  void _processStream(Uint8List data) {
    // Phase 0: Binary mail reception mode
    if (_binaryMailAccumulator != null) {
      _binaryMailAccumulator!.add(data);
      if (_binaryMailAccumulator!.length > 10 * 1024 * 1024) {
        _addDebug('ERROR', 'Binary data exceeded 10MB limit');
        _transportDisconnect();
        return;
      }
      if (_extractMail()) {
        // All proposals processed
        _binaryMailAccumulator = null;
        _sessionState.remove('wlMailProp');
        _transportSendString('FF\r');
        _transportDisconnect();
      }
      return;
    }

    // Phase 1: Line-by-line text processing
    final text = utf8.decode(data, allowMalformed: true);
    final lines = text.split(RegExp(r'\r\n|\r|\n'));

    for (final line in lines) {
      if (line.isEmpty) continue;
      _addDebug('RX', line);

      // TCP: Callsign prompt
      if (line.toLowerCase().contains('callsign') &&
          line.contains(':') &&
          _transportType == _TransportType.tcp) {
        final callsign =
            DataBroker.getValue<String>(0, 'CallSign', 'NOCALL');
        final stationId = DataBroker.getValue<int>(0, 'StationId', 0);
        final useStationId =
            DataBroker.getValue<int>(0, 'WinlinkUseStationId', 0) == 1;
        final callStr =
            useStationId && stationId > 0 ? '$callsign-$stationId' : callsign;
        _transportSendString('$callStr\r');
        continue;
      }

      // TCP: Password prompt
      if (line.toLowerCase().contains('password') &&
          line.contains(':') &&
          _transportType == _TransportType.tcp) {
        _transportSendString('CMSTelnet\r');
        continue;
      }

      // Session start: SID line ends with ">"
      if (line.endsWith('>') &&
          !_sessionState.containsKey('SessionStart')) {
        _sessionState['SessionStart'] = 1;
        _handleSessionStart();
        continue;
      }

      // Command parsing
      final spaceIdx = line.indexOf(' ');
      final key =
          (spaceIdx > 0 ? line.substring(0, spaceIdx) : line).toUpperCase();
      final value = spaceIdx > 0 ? line.substring(spaceIdx + 1) : '';

      switch (key) {
        case ';PQ:':
          // Authentication challenge
          _sessionState['WinlinkAuth'] = value.trim();
          break;

        case 'FS':
          _handleProposalResponse(value.trim());
          break;

        case 'FF':
          _updateEmails();
          _transportSendString('FQ\r');
          _transportDisconnect();
          break;

        case 'FC':
          // Incoming mail proposal
          final props = _sessionState['wlMailProp'];
          if (props is List<String>) {
            props.add(value);
          } else {
            _sessionState['wlMailProp'] = <String>[value];
          }
          break;

        case 'F>':
          _handleIncomingProposalsComplete(value.trim());
          break;

        case 'FQ':
          _updateEmails();
          _transportDisconnect();
          break;
      }
    }
  }

  void _handleSessionStart() {
    _setState(WinlinkConnectionState.syncing);
    final buf = StringBuffer();

    // 1. Client SID
    buf.write('[RMS Express-1.7.28.0-B2FHM\$]\r');

    // 2. Authentication response
    final challenge = _sessionState['WinlinkAuth'] as String?;
    if (challenge != null && challenge.isNotEmpty) {
      final password =
          DataBroker.getValue<String>(0, 'WinlinkPassword', '');
      if (password.isNotEmpty) {
        final authResponse =
            WinlinkSecurity.secureLoginResponse(challenge, password);
        buf.write(';PR: $authResponse\r');
      }
    }

    // 3. Mail proposals
    final proposedMails = <WinlinkMail>[];
    final proposedMailBlocks = <List<Uint8List>>[];
    int checksumAccum = 0;

    for (final mail in _outbox) {
      if (mail.mid.length != 12) continue;
      final encoded = WinlinkMail.encodeMailToBlocks(mail);
      if (encoded == null) continue;

      final proposalLine =
          'FC EM ${mail.mid} ${encoded.uncompressedSize} ${encoded.compressedSize} 0\r';
      buf.write(proposalLine);

      // Accumulate ASCII checksum of proposal line
      for (int i = 0; i < proposalLine.length; i++) {
        checksumAccum += proposalLine.codeUnitAt(i);
      }

      proposedMails.add(mail);
      proposedMailBlocks.add(encoded.blocks);
    }

    // 4. Checksum or no-mail
    if (proposedMails.isNotEmpty) {
      final checksum = ((-checksumAccum) & 0xFF);
      buf.write(
          'F> ${checksum.toRadixString(16).padLeft(2, '0').toUpperCase()}\r');
      _sessionState['OutMails'] = proposedMails;
      _sessionState['OutMailBlocks'] = proposedMailBlocks;
    } else {
      buf.write('FF\r');
    }

    _transportSendString(buf.toString());
  }

  void _handleProposalResponse(String value) {
    final outMails = _sessionState['OutMails'] as List<WinlinkMail>?;
    final outBlocks =
        _sessionState['OutMailBlocks'] as List<List<Uint8List>>?;

    if (outMails == null || outBlocks == null) {
      _transportSendString('FQ\r');
      return;
    }

    _sessionState['MailProposals'] = value;
    final responses = _parseProposalResponses(value);

    if (responses.length != outMails.length) {
      _addDebug(
          'ERROR', 'Proposal response count mismatch: ${responses.length} vs ${outMails.length}');
      _transportSendString('FQ\r');
      return;
    }

    bool anySent = false;
    for (int i = 0; i < responses.length; i++) {
      if (responses[i] == 'Y') {
        // Send all binary blocks for this mail
        for (final block in outBlocks[i]) {
          _transportSendBytes(block);
        }
        anySent = true;
      }
    }

    if (!anySent) {
      _updateEmails();
      _transportSendString('FF\r');
    }
  }

  void _handleIncomingProposalsComplete(String checksumHex) {
    final proposals = _sessionState['wlMailProp'] as List<String>?;
    if (proposals == null || proposals.isEmpty || _binaryMailAccumulator != null) {
      return;
    }

    // Validate checksum
    int checksumAccum = 0;
    for (final prop in proposals) {
      final fullLine = 'FC $prop\r';
      for (int i = 0; i < fullLine.length; i++) {
        checksumAccum += fullLine.codeUnitAt(i);
      }
    }
    final expectedChecksum = ((-checksumAccum) & 0xFF);
    final suppliedChecksum = int.tryParse(checksumHex, radix: 16) ?? -1;

    if (expectedChecksum != suppliedChecksum) {
      _addDebug('ERROR',
          'Proposal checksum mismatch: expected ${expectedChecksum.toRadixString(16)}, got $checksumHex');
      _transportDisconnect();
      return;
    }

    // Build response for each proposal
    final acceptedProposals = <String>[];
    final responseChars = StringBuffer();
    for (final prop in proposals) {
      final parts = prop.trim().split(RegExp(r'\s+'));
      if (parts.length < 4 || parts[0] != 'EM') {
        responseChars.write('H'); // Invalid proposal
        continue;
      }
      final mid = parts[1];
      // Check if we already have this mail
      final haveMail = _inbox.any((m) => m.mid == mid) ||
          _sent.any((m) => m.mid == mid) ||
          _trash.any((m) => m.mid == mid);
      if (haveMail) {
        responseChars.write('N');
      } else {
        responseChars.write('Y');
        acceptedProposals.add(prop);
      }
    }

    _transportSendString('FS $responseChars\r');

    if (acceptedProposals.isNotEmpty) {
      _sessionState['wlMailProp'] = acceptedProposals;
      _binaryMailAccumulator = BytesBuilder();
    }
  }

  /// Try to extract a complete mail from the binary accumulator.
  /// Returns true if all proposals have been processed.
  bool _extractMail() {
    final proposals = _sessionState['wlMailProp'] as List<String>?;
    if (proposals == null || proposals.isEmpty) return true;
    if (_binaryMailAccumulator == null ||
        _binaryMailAccumulator!.isEmpty) {
      return false;
    }

    final blockData = _binaryMailAccumulator!.toBytes();
    final result = WinlinkMail.decodeBlocksToEmail(blockData);

    if (result.fail) {
      _addDebug('ERROR', 'Failed to decode incoming mail');
      return true; // Stop receiving
    }

    if (result.mail == null) return false; // Need more data

    // Trim consumed data
    if (result.dataConsumed > 0 && result.dataConsumed < blockData.length) {
      _binaryMailAccumulator = BytesBuilder();
      _binaryMailAccumulator!.add(
          blockData.sublist(result.dataConsumed));
    } else {
      _binaryMailAccumulator = BytesBuilder();
    }

    // Remove the first proposal
    proposals.removeAt(0);

    // Add mail to inbox
    final mail = result.mail!;
    mail.folder = 'Inbox';
    _inbox.add(mail);
    _broker.dispatch(1, 'MailAdd', mail, store: false);
    _addDebug('INFO',
        'Received mail from ${mail.from}: ${mail.subject}');

    return proposals.isEmpty;
  }

  void _updateEmails() {
    final outMails = _sessionState['OutMails'] as List<WinlinkMail>?;
    final proposalsStr = _sessionState['MailProposals'] as String?;
    if (outMails == null || proposalsStr == null) return;

    final responses = _parseProposalResponses(proposalsStr);
    if (responses.length != outMails.length) return;

    for (int i = 0; i < responses.length; i++) {
      if (responses[i] == 'Y' || responses[i] == 'N') {
        final mail = outMails[i];
        // Move from outbox to sent
        _removeFromMailbox(_outbox, mail.mid);
        mail.folder = 'Sent';
        _sent.add(mail);
      }
    }

    _saveMail();
    _dispatchMailState();
  }

  /// Parse B2F proposal response string like "YN" → ["Y", "N"].
  List<String> _parseProposalResponses(String value) {
    // Normalize: + → Y, R → N, - → N, = → L, H → L, ! → A
    final normalized = value
        .replaceAll('+', 'Y')
        .replaceAll('R', 'N')
        .replaceAll('-', 'N')
        .replaceAll('=', 'L')
        .replaceAll('H', 'L')
        .replaceAll('!', 'A');

    final result = <String>[];
    final current = StringBuffer();
    for (int i = 0; i < normalized.length; i++) {
      final c = normalized[i];
      if (c.codeUnitAt(0) >= 0x30 && c.codeUnitAt(0) <= 0x39) {
        // Digit — append to current token
        current.write(c);
      } else if (c.codeUnitAt(0) >= 0x41 && c.codeUnitAt(0) <= 0x5A) {
        // Letter — start new token
        if (current.isNotEmpty) result.add(current.toString());
        current.clear();
        current.write(c);
      }
    }
    if (current.isNotEmpty) result.add(current.toString());
    return result;
  }

  // ---------------------------------------------------------------------------
  // Disconnect handler
  // ---------------------------------------------------------------------------

  void _onWinlinkDisconnect(int deviceId, String name, Object? data) {
    _transportDisconnect();
  }

  // ---------------------------------------------------------------------------
  // Mail management (unchanged from original)
  // ---------------------------------------------------------------------------

  void _onWinlinkCompose(int deviceId, String name, Object? data) {
    if (data is! WinlinkMail) return;
    data.folder = 'Outbox';
    // Generate MID if missing
    if (data.mid.isEmpty) data.mid = WinlinkMail.generateMid();
    _outbox.add(data);
    _saveMail();
    _dispatchMailState();
    _addDebug('INFO', 'Message queued to ${data.to}: ${data.subject}');
  }

  void _onWinlinkDeleteMail(int deviceId, String name, Object? data) {
    if (data is! String) return;
    final mid = data;
    WinlinkMail? mail;
    mail = _removeFromMailbox(_inbox, mid);
    mail ??= _removeFromMailbox(_outbox, mid);
    mail ??= _removeFromMailbox(_sent, mid);

    if (mail != null) {
      mail.folder = 'Trash';
      _trash.add(mail);
    } else {
      _trash.removeWhere((m) => m.mid == mid);
    }
    _saveMail();
    _dispatchMailState();
  }

  void _onWinlinkMoveMail(int deviceId, String name, Object? data) {
    if (data is! Map) return;
    final mid = data['messageId'] as String?;
    final mailbox = data['mailbox'] as String?;
    if (mid == null || mailbox == null) return;

    WinlinkMail? mail;
    mail = _removeFromMailbox(_inbox, mid);
    mail ??= _removeFromMailbox(_outbox, mid);
    mail ??= _removeFromMailbox(_sent, mid);
    mail ??= _removeFromMailbox(_trash, mid);

    if (mail != null) {
      mail.folder = mailbox;
      _getMailbox(mailbox).add(mail);
      _saveMail();
      _dispatchMailState();
    }
  }

  void _onRequestMail(int deviceId, String name, Object? data) {
    _dispatchMailState();
  }

  void _onRequestDebug(int deviceId, String name, Object? data) {
    _broker.dispatch(1, 'WinlinkDebugLog',
        List<WinlinkDebugEntry>.from(_debugLog), store: false);
  }

  WinlinkMail? _removeFromMailbox(List<WinlinkMail> mailbox, String mid) {
    final idx = mailbox.indexWhere((m) => m.mid == mid);
    if (idx >= 0) return mailbox.removeAt(idx);
    return null;
  }

  List<WinlinkMail> _getMailbox(String name) {
    switch (name) {
      case 'Inbox':
        return _inbox;
      case 'Outbox':
        return _outbox;
      case 'Sent':
        return _sent;
      case 'Trash':
        return _trash;
      default:
        return _inbox;
    }
  }

  // ---------------------------------------------------------------------------
  // State and debug helpers
  // ---------------------------------------------------------------------------

  void _setState(WinlinkConnectionState newState) {
    _state = newState;
    _broker.dispatch(1, 'WinlinkState', _state.name, store: false);
  }

  void _stateMessage(String message) {
    _addDebug('INFO', message);
  }

  void _addDebug(String direction, String message) {
    _debugLog.add(WinlinkDebugEntry(
      time: DateTime.now(),
      direction: direction,
      message: message,
    ));
    while (_debugLog.length > _maxDebugEntries) {
      _debugLog.removeAt(0);
    }
    _broker.dispatch(1, 'WinlinkStateMessage', message, store: false);
  }

  void _dispatchMailState() {
    _broker.dispatch(1, 'WinlinkMailState', {
      'inbox': _inbox.length,
      'outbox': _outbox.length,
      'sent': _sent.length,
      'trash': _trash.length,
    }, store: false);
  }

  // ---------------------------------------------------------------------------
  // Persistence
  // ---------------------------------------------------------------------------

  void _loadMail() {
    final path = _appDataPath;
    if (path == null) return;
    final file = File('$path/$_mailFileName');
    if (!file.existsSync()) return;
    try {
      final json = jsonDecode(file.readAsStringSync());
      if (json is Map) {
        _loadMailbox(_inbox, json['inbox']);
        _loadMailbox(_outbox, json['outbox']);
        _loadMailbox(_sent, json['sent']);
        _loadMailbox(_trash, json['trash']);
      }
    } catch (_) {}
  }

  void _loadMailbox(List<WinlinkMail> mailbox, dynamic jsonList) {
    if (jsonList is! List) return;
    for (final item in jsonList) {
      if (item is Map<String, dynamic>) {
        mailbox.add(WinlinkMail.fromJson(item));
      }
    }
  }

  void _saveMail() {
    final path = _appDataPath;
    if (path == null) return;
    try {
      final json = {
        'inbox': _inbox.map((m) => m.toJson()).toList(),
        'outbox': _outbox.map((m) => m.toJson()).toList(),
        'sent': _sent.map((m) => m.toJson()).toList(),
        'trash': _trash.map((m) => m.toJson()).toList(),
      };
      File('$path/$_mailFileName').writeAsStringSync(jsonEncode(json));
    } catch (_) {}
  }

  void dispose() {
    _disposeAX25Session();
    _unlockRadio();
    _tcpSocket?.destroy();
    _saveMail();
    _broker.dispose();
  }
}
