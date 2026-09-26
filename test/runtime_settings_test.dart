import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:wdm/util/download_engine_util.dart';
import 'package:wdm/setting/settings_cache.dart';

void main() {
  test('download settings propagate runtime speed limit', () {
    SettingsCache.connectionRetryTimeout = 10;
    SettingsCache.connectionRetryCount = -1;
    SettingsCache.connectionsNumber = 8;
    SettingsCache.m3u8ConnectionNumber = 8;
    SettingsCache.loggerEnabled = false;
    SettingsCache.proxyEnabled = false;
    SettingsCache.proxyAddress = '';
    SettingsCache.proxyPort = '';
    SettingsCache.proxyUsername = '';
    SettingsCache.proxyPassword = '';

    // Temporary/save directories are only stored in the settings object here;
    // this test does not perform filesystem I/O.
    SettingsCache.temporaryDir = Directory.systemTemp;
    SettingsCache.saveDir = Directory.systemTemp;

    final settings = downloadSettingsFromCache(maxBytesPerSecond: 123456);
    expect(settings.maxBytesPerSecond, 123456);
  });
}
