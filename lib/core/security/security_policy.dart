import 'dart:io';

import 'package:flutter/foundation.dart';

/// Central security policy for LocalLink's local-only server endpoints.
///
/// LocalLink permits only private/link-local endpoint addresses (or explicitly
/// local hostnames) and permits plaintext HTTP only in debug builds.
class SecurityPolicy {
  const SecurityPolicy._();

  static bool get allowInsecureHttp => kDebugMode;

  static const int maxServerAddressLength = 255;

  static Uri normalizeServerUri(String value) {
    final raw = value.trim();
    if (raw.isEmpty || raw.length > maxServerAddressLength) {
      throw const FormatException('Server address is required');
    }

    final candidate = RegExp(r'^https?://', caseSensitive: false).hasMatch(raw)
        ? raw
        : 'http://$raw';
    final uri = Uri.tryParse(candidate);
    if (uri == null ||
        (uri.scheme != 'http' && uri.scheme != 'https') ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment ||
        (uri.path.isNotEmpty && uri.path != '/')) {
      throw const FormatException(
        'Server address must be a local HTTP/HTTPS host, for example 192.168.1.20:8080',
      );
    }
    if (uri.hasPort && (uri.port < 1 || uri.port > 65535)) {
      throw const FormatException('Server port must be between 1 and 65535');
    }
    if (!isLocalOnlyHost(uri.host)) {
      throw const FormatException(
        'LocalLink server must use a private, link-local, loopback, or explicitly local hostname',
      );
    }
    if (uri.scheme == 'http' && !allowInsecureHttp) {
      throw const FormatException(
        'Plain HTTP is disabled in release builds. Configure HTTPS for release builds.',
      );
    }
    final normalized = Uri(
      scheme: uri.scheme.toLowerCase(),
      host: uri.host,
      port: uri.hasPort ? uri.port : null,
    );
    return normalized;
  }

  static String normalizeServerAddress(String value) =>
      normalizeServerUri(value).toString();

  static Uri resolveLocalResource(String reference,
      {required String baseAddress}) {
    final base = normalizeServerUri(baseAddress);
    final raw = reference.trim();
    if (raw.isEmpty)
      throw const FormatException('Resource reference is required');
    final candidate = Uri.tryParse(raw);
    final resolved = candidate != null && candidate.hasScheme
        ? candidate
        : base.resolve(raw);
    if (resolved.scheme != base.scheme ||
        resolved.host.toLowerCase() != base.host.toLowerCase() ||
        resolved.port != base.port ||
        !isLocalOnlyHost(resolved.host)) {
      throw const FormatException(
          'Resource URL must remain on the configured LocalLink server');
    }
    return resolved;
  }

  static bool isLocalOnlyHost(String host) {
    final normalized = host.trim().toLowerCase();
    if (normalized == 'localhost' || normalized.endsWith('.local')) return true;
    final address = InternetAddress.tryParse(normalized);
    if (address == null) return false;
    final bytes = address.rawAddress;
    if (address.type == InternetAddressType.IPv4) {
      if (bytes.length != 4) return false;
      final a = bytes[0], b = bytes[1];
      return a == 10 ||
          a == 127 ||
          a == 169 && b == 254 ||
          a == 192 && b == 168 ||
          a == 172 && b >= 16 && b <= 31;
    }
    if (bytes.length != 16) return false;
    final isLoopback =
        bytes.sublist(0, 15).every((b) => b == 0) && bytes[15] == 1;
    final isLinkLocal = bytes[0] == 0xfe && (bytes[1] & 0xc0) == 0x80;
    final isUniqueLocal = (bytes[0] & 0xfe) == 0xfc;
    return isLoopback || isLinkLocal || isUniqueLocal;
  }

  static bool isSensitiveHeader(String name) {
    final lower = name.toLowerCase();
    return lower == 'authorization' ||
        lower == 'x-device-token' ||
        lower == 'x-admin-token' ||
        lower == 'x-recovery-secret';
  }
}
