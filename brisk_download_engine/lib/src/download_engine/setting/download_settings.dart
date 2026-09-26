import 'dart:io';

import 'package:brisk_download_engine/src/download_engine/client/http_client_settings.dart';
import 'package:brisk_download_engine/src/download_engine/setting/proxy_setting.dart';
import 'package:rhttp/rhttp.dart';

class DownloadSettings extends ConnectionSettings {
  final Directory baseSaveDir;
  int totalConnections;
  int totalM3u8Connections;

  DownloadSettings({
    required this.baseSaveDir,
    required this.totalConnections,
    required this.totalM3u8Connections,
    required super.loggerEnabled,
    required super.baseTempDir,
    required super.connectionRetryTimeoutMillis,
    required super.maxConnectionRetryCount,
    super.clientSettings,
    super.maxBytesPerSecond = 0,
  });
}

class ConnectionSettings {
  final Directory baseTempDir;
  final int connectionRetryTimeoutMillis;
  final int maxConnectionRetryCount;
  final bool loggerEnabled;
  final HttpClientSettings? clientSettings;
  final int maxBytesPerSecond;

  ConnectionSettings({
    required this.baseTempDir,
    required this.connectionRetryTimeoutMillis,
    required this.maxConnectionRetryCount,
    required this.loggerEnabled,
    this.clientSettings,
    this.maxBytesPerSecond = 0,
  });
}
