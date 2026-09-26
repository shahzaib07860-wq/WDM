import 'dart:convert';
import 'dart:typed_data';

import 'package:brisk_download_engine/brisk_download_engine.dart';
import 'package:brisk_download_engine/src/download_engine/client/custom_base_client.dart';
import 'package:http/http.dart' as http;
import 'package:wdm/model/download_item.dart';
import 'package:wdm/setting/settings_cache.dart';
import 'package:wdm/util/file_extensions.dart';
import 'package:wdm/util/http_util.dart';

class SiteGrabResult {
  final List<String> urls;
  final int pagesVisited;

  const SiteGrabResult(this.urls, this.pagesVisited);
}

class SiteGrabber {
  static final RegExp _hrefPattern = RegExp(
    r'''href\s*=\s*["']([^"'#]+)["']''',
    caseSensitive: false,
  );

  static final Set<String> _downloadExtensions = {
    ...FileExtensions.video,
    ...FileExtensions.music,
    ...FileExtensions.document,
    ...FileExtensions.program,
    ...FileExtensions.compressed,
    ...FileExtensions.image,
  }.map((e) => e.toLowerCase().replaceFirst('.', '')).toSet();

  static List<Uri> extractLinks(String html, Uri base) {
    final links = <Uri>[];
    for (final match in _hrefPattern.allMatches(html)) {
      final raw = match.group(1)?.trim();
      if (raw == null || raw.isEmpty) continue;
      try {
        final uri = base.resolve(raw);
        if (!['http', 'https'].contains(uri.scheme)) continue;
        links.add(uri.removeFragment());
      } catch (_) {}
    }
    return links;
  }

  static bool isDownloadCandidate(Uri uri) {
    final path = uri.path.toLowerCase();
    final last = path.split('/').last;
    final dot = last.lastIndexOf('.');
    if (dot >= 0 && dot < last.length - 1) {
      final ext = last.substring(dot + 1);
      if (_downloadExtensions.contains(ext)) return true;
      if (last.endsWith('.tar.gz')) return true;
    }
    final q = uri.query.toLowerCase();
    return q.contains('download=') ||
        q.contains('attachment=') ||
        path.contains('/download/');
  }

  static bool _sameSite(Uri a, Uri b) =>
      a.scheme == b.scheme && a.host == b.host && a.port == b.port;

  static Future<SiteGrabResult> crawl(
    String startUrl, {
    int maxPages = 25,
    int maxDownloads = 300,
  }) async {
    final start = Uri.tryParse(startUrl.trim());
    if (start == null || !['http', 'https'].contains(start.scheme)) {
      throw const FormatException('Enter a valid http or https website URL.');
    }

    final client = await HttpClientBuilder.buildClient(SettingsCache.clientSettings);
    final pending = <Uri>[start.removeFragment()];
    final seenPages = <String>{};
    final downloads = <String>{};

    try {
      while (pending.isNotEmpty &&
          seenPages.length < maxPages &&
          downloads.length < maxDownloads) {
        final page = pending.removeAt(0);
        if (!seenPages.add(page.toString())) continue;

        final request = http.Request('GET', page)
          ..followRedirects = true
          ..headers.addAll(userAgentHeader)
          ..headers['accept'] = 'text/html,application/xhtml+xml;q=0.9,*/*;q=0.5';

        http.StreamedResponse response;
        try {
          response = await client.send(request).timeout(const Duration(seconds: 15));
        } catch (_) {
          continue;
        }

        if (response.statusCode < 200 || response.statusCode >= 400) {
          await response.stream.drain<void>();
          continue;
        }
        final contentType = response.headers['content-type']?.toLowerCase() ?? '';
        if (!contentType.contains('text/html') &&
            !contentType.contains('application/xhtml')) {
          await response.stream.drain<void>();
          continue;
        }

        final declared = int.tryParse(response.headers['content-length'] ?? '');
        if (declared != null && declared > 2 * 1024 * 1024) {
          await client.cancelRequest();
          continue;
        }

        final bytes = <int>[];
        var tooLarge = false;
        await for (final chunk in response.stream) {
          if (bytes.length + chunk.length > 2 * 1024 * 1024) {
            tooLarge = true;
            await client.cancelRequest();
            break;
          }
          bytes.addAll(chunk);
        }
        if (tooLarge) continue;

        final html = utf8.decode(bytes, allowMalformed: true);
        for (final link in extractLinks(html, page)) {
          if (!_sameSite(start, link)) continue;
          if (isDownloadCandidate(link)) {
            downloads.add(link.toString());
            if (downloads.length >= maxDownloads) break;
            continue;
          }
          final path = link.path.toLowerCase();
          final looksLikePage = path.isEmpty ||
              path.endsWith('/') ||
              !path.split('/').last.contains('.') ||
              path.endsWith('.html') ||
              path.endsWith('.htm') ||
              path.endsWith('.php') ||
              path.endsWith('.asp') ||
              path.endsWith('.aspx');
          if (looksLikePage &&
              !seenPages.contains(link.toString()) &&
              pending.length < maxPages * 3) {
            pending.add(link);
          }
        }
      }
    } finally {
      client.close();
    }
    return SiteGrabResult(downloads.toList(), seenPages.length);
  }
}

class RemoteZipEntry {
  final String name;
  final int compressedSize;
  final int uncompressedSize;
  final bool isDirectory;

  const RemoteZipEntry({
    required this.name,
    required this.compressedSize,
    required this.uncompressedSize,
    required this.isDirectory,
  });
}

class RemoteZipInspector {
  static const int _tailBytes = 256 * 1024;
  static const int _maxCentralDirectoryBytes = 8 * 1024 * 1024;
  static const int _maxEntries = 10000;

  static Future<List<RemoteZipEntry>> inspect(DownloadItem item) async {
    var totalSize = item.contentLength;
    if (totalSize <= 0) {
      final info = await requestFileInfo(item, SettingsCache.clientSettings);
      totalSize = info?.contentLength ?? 0;
    }
    if (totalSize <= 0) {
      throw const FormatException('Could not determine ZIP file size.');
    }

    final client = await HttpClientBuilder.buildClient(SettingsCache.clientSettings);
    try {
      final tailStart = totalSize > _tailBytes ? totalSize - _tailBytes : 0;
      final tail = await _fetchRange(
        client,
        item,
        tailStart,
        totalSize - 1,
        maxBytes: _tailBytes + 1,
        totalFileSize: totalSize,
      );
      final eocd = _findEocd(tail);
      if (eocd < 0) {
        throw const FormatException(
          'ZIP central directory was not found. ZIP64 or a damaged archive may be involved.',
        );
      }

      final disk = _u16(tail, eocd + 4);
      final centralDisk = _u16(tail, eocd + 6);
      final entries = _u16(tail, eocd + 10);
      final centralSize = _u32(tail, eocd + 12);
      final centralOffset = _u32(tail, eocd + 16);

      if (disk != 0 || centralDisk != 0) {
        throw const FormatException('Multi-disk ZIP archives are not supported.');
      }
      if (entries == 0xffff ||
          centralSize == 0xffffffff ||
          centralOffset == 0xffffffff) {
        throw const FormatException('ZIP64 preview is not supported yet.');
      }
      if (entries > _maxEntries) {
        throw FormatException('ZIP contains too many entries to preview (\$entries).');
      }
      if (centralSize > _maxCentralDirectoryBytes) {
        throw const FormatException('ZIP directory is too large to preview safely.');
      }
      if (centralOffset + centralSize > totalSize) {
        throw const FormatException('ZIP central directory is outside the file.');
      }

      final centralStartInTail = centralOffset - tailStart;
      Uint8List central;
      if (centralStartInTail >= 0 &&
          centralStartInTail + centralSize <= tail.length) {
        central = Uint8List.fromList(
          tail.sublist(centralStartInTail, centralStartInTail + centralSize),
        );
      } else {
        central = await _fetchRange(
          client,
          item,
          centralOffset,
          centralOffset + centralSize - 1,
          maxBytes: centralSize + 1,
          totalFileSize: totalSize,
        );
      }
      return parseCentralDirectory(central, entries);
    } finally {
      client.close();
    }
  }

  static List<RemoteZipEntry> parseCentralDirectory(
    Uint8List data,
    int expectedEntries,
  ) {
    final result = <RemoteZipEntry>[];
    var offset = 0;
    while (offset + 46 <= data.length && result.length < expectedEntries) {
      if (_u32(data, offset) != 0x02014b50) {
        throw const FormatException('Invalid ZIP central-directory record.');
      }
      final flags = _u16(data, offset + 8);
      final compressedSize = _u32(data, offset + 20);
      final uncompressedSize = _u32(data, offset + 24);
      final nameLength = _u16(data, offset + 28);
      final extraLength = _u16(data, offset + 30);
      final commentLength = _u16(data, offset + 32);
      final end = offset + 46 + nameLength + extraLength + commentLength;
      if (end > data.length) {
        throw const FormatException('Truncated ZIP central directory.');
      }
      if (compressedSize == 0xffffffff || uncompressedSize == 0xffffffff) {
        throw const FormatException('ZIP64 entries are not supported yet.');
      }

      final nameBytes = data.sublist(offset + 46, offset + 46 + nameLength);
      final name = (flags & 0x0800) != 0
          ? utf8.decode(nameBytes, allowMalformed: true)
          : latin1.decode(nameBytes);
      result.add(
        RemoteZipEntry(
          name: name,
          compressedSize: compressedSize,
          uncompressedSize: uncompressedSize,
          isDirectory: name.endsWith('/'),
        ),
      );
      offset = end;
    }
    if (result.length != expectedEntries) {
      throw FormatException(
        'ZIP preview expected \$expectedEntries entries but found ${result.length}.',
      );
    }
    return result;
  }

  static Future<Uint8List> _fetchRange(
    CustomBaseClient client,
    DownloadItem item,
    int start,
    int end, {
    required int maxBytes,
    required int totalFileSize,
  }) async {
    final request = http.Request('GET', Uri.parse(item.downloadUrl))
      ..followRedirects = true
      ..headers['range'] = 'bytes=\$start-\$end';
    if (!item.requestHeaders.keys.any((k) => k.toLowerCase() == 'user-agent')) {
      request.headers.addAll(userAgentHeader);
    }
    request.headers.addAll(item.requestHeaders);
    if (item.referer != null &&
        !request.headers.keys.any((k) => k.toLowerCase() == 'referer')) {
      request.headers['referer'] = item.referer!;
    }

    final response = await client.send(request).timeout(const Duration(seconds: 20));
    if (response.statusCode != 206 && response.statusCode != 200) {
      await response.stream.drain<void>();
      throw FormatException('ZIP server returned HTTP ${response.statusCode}.');
    }
    if (response.statusCode == 200 && totalFileSize > maxBytes) {
      await client.cancelRequest();
      throw const FormatException(
        'This server does not support byte ranges, so a safe remote ZIP preview is unavailable.',
      );
    }

    final bytes = <int>[];
    await for (final chunk in response.stream) {
      if (bytes.length + chunk.length > maxBytes) {
        await client.cancelRequest();
        throw const FormatException('ZIP preview response exceeded the safe limit.');
      }
      bytes.addAll(chunk);
    }
    return Uint8List.fromList(bytes);
  }

  static int _findEocd(Uint8List data) {
    for (var i = data.length - 22; i >= 0; i--) {
      if (_u32(data, i) == 0x06054b50) return i;
    }
    return -1;
  }

  static int _u16(List<int> data, int offset) =>
      data[offset] | (data[offset + 1] << 8);

  static int _u32(List<int> data, int offset) =>
      data[offset] |
      (data[offset + 1] << 8) |
      (data[offset + 2] << 16) |
      (data[offset + 3] << 24);
}
