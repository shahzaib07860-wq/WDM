import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:brisk_download_engine/src/download_engine/client/scoped_media_client.dart';
import 'package:brisk_download_engine/brisk_download_engine.dart';
import 'package:brisk_download_engine/src/download_engine/client/http_client_builder.dart';
import 'package:brisk_download_engine/src/download_engine/util/constants.dart';
import 'package:path/path.dart';

import 'package:encrypt/encrypt.dart';
import 'package:rhttp/rhttp.dart';

/// Decrypts an AES-128 encrypted file.
/// If chunked mode is enabled, it decrypts the file in chunks to reduce memory usage.
Future<void> decryptAes128File(
  File file,
  Uint8List key,
  IV iv, {
  bool chunked = false,
}) async {
  final aesKey = Key(key);
  final encrypter = Encrypter(AES(aesKey, mode: AESMode.cbc));
  if (chunked) {
    const chunkSize = 5 * 1024 * 1024;
    final outputFile = File(join(file.parent.path, "Decrypted.ts"));
    final outputFileOpen = outputFile.openWrite();
    final inputStream = file.openSync();
    try {
      final buffer = Uint8List(chunkSize);
      int bytesRead;
      while ((bytesRead = inputStream.readIntoSync(buffer)) > 0) {
        final chunk = Uint8List.sublistView(buffer, 0, bytesRead);
        final decryptedBytes = encrypter.decryptBytes(Encrypted(chunk), iv: iv);
        outputFileOpen.add(decryptedBytes);
      }
    } finally {
      await outputFileOpen.close();
      inputStream.closeSync();
    }
    final filePath = file.path;
    file.deleteSync();
    outputFile.renameSync(filePath);
    return;
  }
  final decryptedBytes = encrypter.decryptBytes(
    Encrypted(file.readAsBytesSync()),
    iv: iv,
  );
  file.writeAsBytesSync(decryptedBytes, mode: FileMode.write);
}

/// Set decryption initialization vector based on the sequence number of the segment as a big-endian
/// This is only used when the m3u8 requires a decryption process and does not provide an IV itself.
/// Thus, based on the m3u8 specification, the IV should be derived from the sequence number.
IV deriveImplicitIV(int sequenceNumber) {
  final iv = Uint8List(16);
  iv.buffer.asByteData().setUint64(8, sequenceNumber);
  return IV(iv);
}

/// Set decryption initialization vector based on the IV value defined in the m3u8 file
IV deriveExplicitIV(String ivString) {
  if (ivString.startsWith("0x")) {
    ivString = ivString.substring(2);
  }
  final ivBytes = List.generate(
    ivString.length ~/ 2,
    (i) => int.parse(ivString.substring(i * 2, i * 2 + 2), radix: 16),
  );
  return IV(Uint8List.fromList(ivBytes));
}

Future<http.Response> fetchMediaResponse(
  String url, {
  HttpClientSettings? clientSettings,
  Map<String, String> headers = const {},
}) async {
  final client = ScopedMediaClient(
    await HttpClientBuilder.buildClient(
      HttpClientSettings(
        clientType: ClientType.dartHttp,
        proxySetting: clientSettings?.proxySetting,
      ),
    ),
  );
  try {
    final response = await client.get(
      Uri.parse(url),
      headers: {...userAgentHeader, ...headers},
    );
    if (response.statusCode != 200)
      throw http.ClientException(
        'Media HTTP ${response.statusCode}',
        Uri.parse(url),
      );
    return response;
  } finally {
    client.close();
  }
}

Future<String> fetchBodyString(
  String url, {
  HttpClientSettings? clientSettings,
  Map<String, String> headers = const {},
}) async => (await fetchMediaResponse(
  url,
  clientSettings: clientSettings,
  headers: headers,
)).body;

Future<Uint8List> fetchDecryptionKey(
  String keyUrl, {
  HttpClientSettings? clientSettings,
  Map<String, String> headers = const {},
}) async {
  final response = await fetchMediaResponse(
    keyUrl,
    clientSettings: clientSettings,
    headers: headers,
  );
  if (response.bodyBytes.length != 16)
    throw FormatException('Invalid AES-128 key length');
  return response.bodyBytes;
}
