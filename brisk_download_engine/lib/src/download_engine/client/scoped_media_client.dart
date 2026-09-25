import 'package:http/http.dart' as http;

import 'custom_base_client.dart';

Map<String, String> mediaRequestHeaders(
  Map<String, String> headers,
  String source,
  String target,
) {
  final a = Uri.parse(source), b = Uri.parse(target);
  if (!['http', 'https'].contains(b.scheme))
    throw FormatException('Unsupported media URL');
  final sameOrigin =
      a.scheme == b.scheme && a.host == b.host && a.port == b.port;
  return {
    for (final entry in headers.entries)
      if (sameOrigin ||
          ![
            'authorization',
            'cookie',
            'proxy-authorization',
          ].contains(entry.key.toLowerCase()))
        entry.key.toLowerCase(): entry.value,
  };
}

/// Uses a Dart HTTP client, whose followRedirects flag is honored. Credentials
/// are stripped permanently when a redirect crosses an origin boundary.
class ScopedMediaClient with CustomBaseClient {
  final CustomBaseClient inner;
  ScopedMediaClient(this.inner);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    var uri = request.url;
    var headers = Map<String, String>.from(request.headers);
    for (var hop = 0; hop <= 5; hop++) {
      final next = http.Request(request.method, uri)
        ..followRedirects = false
        ..headers.addAll(headers);
      final response = await inner.send(next);
      final location = response.headers['location'];
      if (![301, 302, 303, 307, 308].contains(response.statusCode) ||
          location == null) {
        return response;
      }
      await response.stream.drain<void>();
      if (hop == 5) throw http.ClientException('Too many media redirects', uri);
      final target = uri.resolve(location);
      headers = mediaRequestHeaders(headers, uri.toString(), target.toString());
      uri = target;
    }
    throw StateError('Unreachable');
  }

  @override
  Future<void> cancelRequest() => inner.cancelRequest();
  @override
  void close() => inner.close();
}
