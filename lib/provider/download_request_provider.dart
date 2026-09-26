import 'dart:async';
import 'dart:io';

import 'package:wdm/db/hive_util.dart';
import 'package:wdm/util/tray_handler.dart';
import 'package:path/path.dart';
import 'package:wdm/model/download_item.dart';
import 'package:wdm/provider/pluto_grid_check_row_provider.dart';
import 'package:wdm/provider/pluto_grid_util.dart';
import 'package:wdm/util/ffmpeg.dart';
import 'package:wdm/util/notification_manager.dart';
import 'package:brisk_download_engine/brisk_download_engine.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:pluto_grid/pluto_grid.dart';
import 'package:wdm/util/download_engine_util.dart';
import 'package:wdm/util/donation_reminder.dart';
import 'package:wdm/util/download_security_util.dart';
import 'package:wdm/util/readability_util.dart';
import 'package:wdm/setting/settings_cache.dart';

class DownloadRequestProvider with ChangeNotifier {
  Map<int, DownloadProgressMessage> downloads = {};

  PlutoGridCheckRowProvider plutoProvider;

  DownloadRequestProvider(this.plutoProvider);

  static int get _nowMillis => DateTime.now().millisecondsSinceEpoch;

  void addRequest(DownloadItem item) {
    final progress = DownloadProgressMessage(
      downloadItem: buildFromDownloadItem(item),
    );
    downloads.addAll({item.key!: progress});
    insertRows([progress]);
    PlutoGridUtil.plutoStateManager?.notifyListeners();
    notifyListeners();
  }

  /// now in milliseconds in order to update every n seconds.
  /// Temp variable used to compare the last time the download item was updated to
  // TODO remove: Implement a custom update Queue
  int _previousUpdateTime = _nowMillis;

  Future<void> pauseDownload(int id) async {
    final item = HiveUtil.instance.downloadItemsBox.get(id);
    if (item == null) return;
    DownloadEngine.pause(item.uid);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    _rebalanceSpeedLimits();
  }

  Future<void> startDownload(int id) async {
    DownloadProgressMessage? downloadProgress = downloads[id];
    downloadProgress ??= await _addDownloadProgress(id);
    final downloadItem = downloadProgress.downloadItem;
    final totalConnections = _connectionCountFor(downloadItem);
    final activeCount = _activeDownloads().contains(downloadProgress)
        ? _activeDownloads().length
        : _activeDownloads().length + 1;
    final settings = downloadSettingsFromCache(
      maxBytesPerSecond: _perConnectionSpeedLimit(
        activeCount,
        totalConnections,
      ),
    )..totalConnections = totalConnections;

    await DownloadEngine.start(
      downloadItem,
      settings,
      downloadItem.downloadType,
      onButtonAvailability: _handleButtonAvailabilityMessage,
      onDownloadProgress: _handleDownloadProgressMessage,
    );
  }

  int _connectionCountFor(DownloadItemModel item) {
    if (item.m3u8Content != null && item.m3u8Content!.isNotEmpty) {
      return SettingsCache.m3u8ConnectionNumber;
    }
    return item.supportsPause ? SettingsCache.connectionsNumber : 1;
  }

  List<DownloadProgressMessage> _activeDownloads() {
    return downloads.values.where((progress) {
      return {
        DownloadStatus.connecting,
        DownloadStatus.downloading,
        DownloadStatus.validatingFiles,
        DownloadStatus.assembling,
      }.contains(progress.status);
    }).toList();
  }

  int _perConnectionSpeedLimit(int activeDownloads, int connections) {
    final totalBytesPerSecond = SettingsCache.globalSpeedLimitKbps * 1024;
    if (totalBytesPerSecond <= 0) return 0;
    final divisor = (activeDownloads < 1 ? 1 : activeDownloads) *
        (connections < 1 ? 1 : connections);
    return (totalBytesPerSecond ~/ divisor)
        .clamp(1, totalBytesPerSecond)
        .toInt();
  }

  void refreshRuntimeSettings() {
    _rebalanceSpeedLimits();
  }

  void _rebalanceSpeedLimits() {
    final active = _activeDownloads();
    if (active.isEmpty) return;
    for (final progress in active) {
      final uid = progress.downloadItem.uid;
      if (!DownloadEngine.engineChannels.containsKey(uid)) continue;
      final connections = _connectionCountFor(progress.downloadItem);
      final settings = downloadSettingsFromCache(
        maxBytesPerSecond: _perConnectionSpeedLimit(
          active.length,
          connections,
        ),
      )..totalConnections = connections;
      DownloadEngine.updateSettings(uid, settings);
    }
  }

  int? getExistingConnectionCount(DownloadItemModel downloadItem) {
    final tempPath = join(SettingsCache.temporaryDir.path, downloadItem.uid);
    final tempDir = Directory(tempPath);
    return tempDir.existsSync() ? tempDir.listSync().length : null;
  }

  void _handleButtonAvailabilityMessage(ButtonAvailabilityMessage message) {
    final download = downloads[message.downloadItem.id];
    download?.buttonAvailability = ButtonAvailability(
      message.pauseButtonEnabled,
      message.startButtonEnabled,
    );
    notifyListeners();
    plutoProvider.notifyListeners();
  }

  void _handleDownloadProgressMessage(DownloadProgressMessage progress) async {
    final id = progress.downloadItem.id!;
    final previousStatus = downloads[id]?.status;
    final isNewCompletion =
        progress.status == DownloadStatus.assembleComplete &&
            previousStatus != DownloadStatus.assembleComplete;
    final isNewFailure =
        (progress.status == DownloadStatus.failed ||
            progress.status == DownloadStatus.networkError) &&
        previousStatus != progress.status;
    downloads[id] = progress;
    final anyActive = _activeDownloads().isNotEmpty;
    if (anyActive) {
      TrayHandler.setTrayDownloading();
    } else {
      TrayHandler.setTrayInactive();
    }
    _handleNotification(
      progress,
      isNewCompletion: isNewCompletion,
      isNewFailure: isNewFailure,
    );
    if (previousStatus != progress.status) {
      _rebalanceSpeedLimits();
    }
    final downloadItem = progress.downloadItem;
    final dl = HiveUtil.instance.downloadItemsBox.get(downloadItem.id);
    if (dl == null) return;
    if (progress.status == DownloadStatus.assembling) {
      progress.downloadProgress = 1;
    }
    if (progress.assembleProgress == 1) {
      HiveUtil.instance.removeDownloadFromQueues(dl.key);
      PlutoGridUtil.removeCachedRow(id);
    }
    _updateDownloadRequest(progress, dl);
    if (isNewCompletion) {
      unawaited(DonationReminder.recordSuccessfulDownload());
    }
    if (progress.status == DownloadStatus.assembleComplete) {
      if (dl.subtitles.isNotEmpty && await FFmpeg.isInstalled()) {
        await FFmpeg.addSoftSubsToDownloadedFile(dl);
        _setNewMkvFilePath(dl, progress);
      }
      if (isNewCompletion) {
        await DownloadSecurityUtil.onDownloadCompleted(dl.filePath);
      }
    }
    notifyAllListeners(progress);
  }

  void _setNewMkvFilePath(DownloadItem dl, DownloadProgressMessage progress) {
    final downloadItem = progress.downloadItem;
    File(downloadItem.filePath).deleteSync();
    var newFileName = basenameWithoutExtension(downloadItem.filePath);
    newFileName += '.mkv';
    final newPath = join(File(downloadItem.filePath).parent.path, newFileName);
    downloadItem.filePath = newPath;
    downloadItem.fileName = newFileName;
    dl.filePath = newPath;
    dl.fileName = newFileName;
    _updateDownloadRequest(progress, dl);
    downloads[dl.key] = progress;
    notifyAllListeners(progress);
  }

  void _handleNotification(
    DownloadProgressMessage progress, {
    required bool isNewCompletion,
    required bool isNewFailure,
  }) {
    if (isNewCompletion && SettingsCache.notificationOnDownloadCompletion) {
      NotificationManager.showNotification(
        NotificationManager.downloadCompletionHeader,
        progress.downloadItem.fileName,
      );
    }
    if (isNewFailure && SettingsCache.notificationOnDownloadFailure) {
      NotificationManager.showNotification(
        NotificationManager.downloadFailureHeader,
        progress.downloadItem.fileName,
      );
    }
  }

  Future<DownloadProgressMessage> _addDownloadProgress(int id) async {
    final downloadItem = HiveUtil.instance.downloadItemsBox.get(id)!;
    downloads.addAll({
      id: DownloadProgressMessage(
        downloadItem: buildFromDownloadItem(downloadItem),
      )
    });
    // TODO handle download type properly
    return DownloadProgressMessage(
      downloadItem: buildFromDownloadItem(downloadItem),
    );
  }

  /// Updates the download request based on the incoming progress from handler isolate every 6 seconds
  void _updateDownloadRequest(
      DownloadProgressMessage progress, DownloadItem item) {
    final status = progress.status;
    if (isUpdateEligible(status)) {
      item.progress = progress.downloadProgress;
      item.status = status;
      if (status == DownloadStatus.assembleComplete) {
        item.finishDate = DateTime.now();
      }
      if (progress.assembledFileSize != null) {
        item.contentLength = progress.assembledFileSize!;
      }
      HiveUtil.instance.downloadItemsBox.put(item.key, item);
      _previousUpdateTime = _nowMillis;
    }
  }

  bool isUpdateEligible(String status) {
    return _previousUpdateTime + 2000 < _nowMillis ||
        status == DownloadStatus.assembleComplete ||
        status == DownloadStatus.paused ||
        status == DownloadStatus.networkError;
  }

  void insertRows(List<DownloadProgressMessage> progressData) {
    final stateManager = PlutoGridUtil.plutoStateManager;
    final rows = stateManager?.rows;
    final lastIndex = rows!.isNotEmpty ? rows.last.sortIdx : -1;
    stateManager?.insertRows(lastIndex + 1, buildRows(progressData));
  }

  /// TODO this shouldn't be in the provider. Move to [PlutoGridUtil]
  List<PlutoRow> buildRows(List<DownloadProgressMessage> progressData) {
    return progressData.map((e) {
      if (downloads[e.downloadItem.id] != null) {
        e = downloads[e.downloadItem.id]!;
      }
      return PlutoRow(
        cells: {
          "file_name": PlutoCell(value: e.downloadItem.fileName),
          "size": PlutoCell(
            value: e.downloadItem.fileSize < 0
                ? "Unknown"
                : convertByteToReadableStr(e.downloadItem.fileSize),
          ),
          "progress": PlutoCell(
            value:
                convertPercentageNumberToReadableStr(e.downloadProgress * 100),
          ),
          "status": PlutoCell(
            value: e.status == ""
                ? (e.downloadItem.status == DownloadStatus.assembleComplete ||
                        e.downloadItem.status == DownloadStatus.paused)
                    ? e.downloadItem.status
                    : ""
                : e.status,
          ),
          "transfer_rate": PlutoCell(value: e.transferRate),
          "time_left": PlutoCell(value: e.estimatedRemaining),
          "start_date": PlutoCell(value: e.downloadItem.startDate),
          "finish_date": PlutoCell(value: e.downloadItem.finishDate ?? ""),
          "file_type": PlutoCell(value: e.downloadItem.fileType),
          "id": PlutoCell(value: e.downloadItem.id),
          "uid": PlutoCell(value: e.downloadItem.uid),
        },
      );
    }).toList();
  }

  // int _tmpTime = _nowMillis;
  void notifyAllListeners(DownloadProgressMessage progress) {
    // if (_tmpTime + 90 > _nowMillis) return;
    // _tmpTime = _nowMillis;
    plutoProvider.notifyListeners();
    notifyListeners();
    PlutoGridUtil.updateRowCells(progress);
  }

  Future<void> fetchRows(List<DownloadItem> items) async {
    PlutoGridUtil.cachedRows.clear();
    final requests = items
        .map((e) => DownloadProgressMessage(
              downloadItem: buildFromDownloadItem(e),
              downloadProgress: e.progress,
            ))
        .toList();
    final stateManager = PlutoGridUtil.plutoStateManager;
    stateManager?.removeAllRows();
    stateManager?.insertRows(0, buildRows(requests));
    stateManager?.setShowLoading(false);
    stateManager?.notifyListeners();
  }
}
