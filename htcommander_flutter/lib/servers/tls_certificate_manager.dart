/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0
*/

import 'dart:io';

/// Manages self-signed TLS certificates for HTTPS servers.
/// Uses PEM format with openssl for generation.
/// Port of HTCommander.Core/Utils/TlsCertificateManager.cs
class TlsCertificateManager {
  static SecurityContext? _cachedContext;

  /// Returns a SecurityContext with a valid self-signed certificate.
  /// Creates a new certificate if none exists or the existing one is invalid.
  static Future<SecurityContext?> getOrCreateContext(String configDir) async {
    if (_cachedContext != null) return _cachedContext;

    final certPath = '$configDir/htcommander-tls.pem';
    final keyPath = '$configDir/htcommander-tls-key.pem';

    if (File(certPath).existsSync() && File(keyPath).existsSync()) {
      try {
        final context = SecurityContext()
          ..useCertificateChain(certPath)
          ..usePrivateKey(keyPath);
        _cachedContext = context;
        return _cachedContext;
      } catch (_) {
        // Certificate invalid or expired, regenerate below
      }
    }

    return _generateCert(configDir);
  }

  /// Invalidates the cached context, forcing regeneration on next call.
  static void invalidateCache() {
    _cachedContext = null;
  }

  static Future<SecurityContext?> _generateCert(String configDir) async {
    try {
      Directory(configDir).createSync(recursive: true);

      // Build Subject Alternative Names
      final sanParts = <String>['DNS:localhost', 'IP:127.0.0.1', 'IP:::1'];
      try {
        final interfaces = await NetworkInterface.list();
        for (final iface in interfaces) {
          for (final addr in iface.addresses) {
            sanParts.add('IP:${addr.address}');
          }
        }
      } catch (_) {
        // NetworkInterface.list() might fail on some platforms
      }
      final sanString = sanParts.join(',');

      final certPath = '$configDir/htcommander-tls.pem';
      final keyPath = '$configDir/htcommander-tls-key.pem';

      // Generate self-signed certificate using openssl
      final result = await Process.run('openssl', [
        'req', '-x509', '-newkey', 'rsa:3072',
        '-keyout', keyPath, '-out', certPath,
        '-days', '3650', '-nodes',
        '-subj', '/CN=HTCommander',
        '-addext', 'subjectAltName=$sanString',
      ]);

      if (result.exitCode != 0) {
        stderr.writeln(
            'TlsCertificateManager: openssl failed (exit ${result.exitCode}): '
            '${result.stderr}');
        return null;
      }

      // Set restrictive file permissions on Linux/macOS
      if (!Platform.isWindows) {
        try {
          await Process.run('chmod', ['600', certPath]);
        } catch (_) {}
        try {
          await Process.run('chmod', ['600', keyPath]);
        } catch (_) {}
      }

      final context = SecurityContext()
        ..useCertificateChain(certPath)
        ..usePrivateKey(keyPath);
      _cachedContext = context;
      return context;
    } catch (e) {
      stderr.writeln('TlsCertificateManager: certificate generation failed: $e');
      return null;
    }
  }
}
