import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:wdm/setting/settings_cache.dart';
import 'package:wdm/util/app_logger.dart';

class DownloadSecurityUtil {
  static Future<void> onDownloadCompleted(String filePath) async {
    if (SettingsCache.playCompletionSound) {
      try {
        await SystemSound.play(SystemSoundType.alert);
      } catch (e) {
        Logger.log('Completion sound failed: $e');
      }
    }
    if (SettingsCache.scanCompletedDownloads && Platform.isWindows) {
      unawaited(_scanWithWindowsDefender(filePath));
    }
  }

  static Future<void> _scanWithWindowsDefender(String filePath) async {
    final file = File(filePath);
    if (!file.existsSync()) return;
    try {
      final escaped = file.absolute.path.replaceAll("'", "''");
      final result = await Process.run(
        'powershell.exe',
        [
          '-NoProfile',
          '-NonInteractive',
          '-ExecutionPolicy',
          'Bypass',
          '-Command',
          "Start-MpScan -ScanType CustomScan -ScanPath '$escaped'",
        ],
        runInShell: false,
      ).timeout(const Duration(minutes: 15));
      if (result.exitCode != 0) {
        Logger.log(
          'Windows Defender scan returned ${result.exitCode}: ${result.stderr}',
        );
      }
    } on TimeoutException {
      Logger.log('Windows Defender scan timed out for $filePath');
    } catch (e) {
      Logger.log('Windows Defender scan failed: $e');
    }
  }
}
