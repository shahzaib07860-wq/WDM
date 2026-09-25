import 'dart:async';

import 'package:wdm/db/hive_util.dart';
import 'package:wdm/model/download_queue.dart';
import 'package:wdm/model/download_item.dart';
import 'package:wdm/provider/download_request_provider.dart';
import 'package:wdm/util/app_logger.dart';
import 'package:wdm/util/download_engine_util.dart';
import 'package:wdm/util/queue_window_policy.dart';
import 'package:wdm/util/shutdown_manager.dart';
import 'package:brisk_download_engine/brisk_download_engine.dart';
import 'package:flutter/material.dart';
import 'package:pluto_grid/pluto_grid.dart';
import 'package:provider/provider.dart';

class QueueScheduleHandler {
  static Timer? downloadCheckerTimer;
  static Timer? schedulerTimer;
  static Map<DownloadQueue, List<int>> runningDownloads = {};
  static List<int> stoppedDownloads = [];
  static List<DownloadQueue> stoppedQueues = [];
  static Map<DownloadQueue, List<PlutoRow>> queueRows = {};
  static Map<DownloadQueue, bool> queues = {};
  static bool _busy = false;
  static bool _restored = false;

  static Future<void> restore(BuildContext context) async {
    if (_restored) return;
    _restored = true;
    final provider = Provider.of<DownloadRequestProvider>(
      context,
      listen: false,
    );
    for (final queue in HiveUtil.instance.downloadQueueBox.values) {
      if (queue.scheduleEnabled) _register(queue, provider);
    }
    if (queues.isNotEmpty) _startTimer(provider);
  }

  static Future<void> schedule(
    DownloadQueue queue,
    BuildContext context, {
    required bool shutdownAfterCompletion,
    required int simultaneousDownloads,
    required DateTime? scheduledStart,
    required DateTime? scheduledEnd,
  }) async {
    if (scheduledStart != null &&
        scheduledEnd != null &&
        !scheduledEnd.isAfter(scheduledStart)) {
      throw ArgumentError('The schedule end must be later than its start.');
    }
    queue
      ..shutdownAfterCompletion = shutdownAfterCompletion
      ..simultaneousDownloads = simultaneousDownloads < 1
          ? 1
          : simultaneousDownloads
      ..scheduledStart = scheduledStart
      ..scheduledEnd = scheduledEnd
      ..scheduleEnabled = true;
    await queue.save();
    stoppedQueues.remove(queue);
    stoppedDownloads.removeWhere(
      (id) => queue.downloadItemsIds?.contains(id) ?? false,
    );
    final provider = Provider.of<DownloadRequestProvider>(
      context,
      listen: false,
    );
    _register(queue, provider);
    _startTimer(provider);
  }

  static void _register(DownloadQueue queue, DownloadRequestProvider provider) {
    queues[queue] = false;
    runningDownloads.putIfAbsent(queue, () => []);
    final items = (queue.downloadItemsIds ?? <int>[])
        .map((id) => HiveUtil.instance.downloadItemsBox.get(id))
        .whereType<DownloadItem>();
    queueRows[queue] = provider.buildRows(
      items
          .map(
            (item) => DownloadProgressMessage(
              downloadItem: buildFromDownloadItem(item),
            ),
          )
          .toList(),
    );
  }

  static void _startTimer(DownloadRequestProvider provider) {
    downloadCheckerTimer ??= Timer.periodic(
      const Duration(seconds: 1),
      (_) => _tick(provider),
    );
    _tick(provider);
  }

  static Future<void> _finish(
    DownloadQueue queue,
    DownloadRequestProvider provider, {
    bool expired = false,
  }) async {
    stoppedQueues.add(queue);
    queues[queue] = false;
    queue.scheduleEnabled = false;
    await queue.save();
    if (expired) {
      for (final id in List<int>.from(runningDownloads[queue] ?? [])) {
        if (HiveUtil.instance.downloadItemsBox.containsKey(id))
          await provider.pauseDownload(id);
      }
    }
    runningDownloads[queue] = [];
    // End of a time window pauses work; shutdown applies only to completion.
    if (!expired && queue.shutdownAfterCompletion)
      ShutdownManager.scheduleShutdown();
  }

  static Future<void> _tick(DownloadRequestProvider provider) async {
    if (_busy) return;
    _busy = true;
    try {
      for (final queue in List<DownloadQueue>.from(queues.keys)) {
        if (!queue.scheduleEnabled || stoppedQueues.contains(queue)) continue;
        final now = DateTime.now();
        if (queue.scheduledEnd != null && !now.isBefore(queue.scheduledEnd!)) {
          await _finish(queue, provider, expired: true);
          continue;
        }
        if (!queueWindowOpen(now, queue.scheduledStart, queue.scheduledEnd))
          continue;
        final running = runningDownloads.putIfAbsent(queue, () => []);
        running.removeWhere((id) {
          final item = HiveUtil.instance.downloadItemsBox.get(id);
          final status = provider.downloads[id]?.status ?? item?.status;
          final failed = [
            DownloadStatus.failed,
            DownloadStatus.assembleFailed,
            DownloadStatus.canceled,
          ].contains(status);
          if (failed && !stoppedDownloads.contains(id))
            stoppedDownloads.add(id);
          return item == null ||
              status == DownloadStatus.assembleComplete ||
              failed;
        });
        final ids = queue.downloadItemsIds ?? <int>[];
        var slots = queueAvailableSlots(
          queue.simultaneousDownloads,
          running.length,
        );
        for (final id in ids) {
          if (slots == 0) break;
          if (!queueWindowOpen(
            DateTime.now(),
            queue.scheduledStart,
            queue.scheduledEnd,
          ))
            break;
          final item = HiveUtil.instance.downloadItemsBox.get(id);
          if (item == null || stoppedDownloads.contains(id)) continue;
          final status = provider.downloads[id]?.status ?? item.status;
          if (status == DownloadStatus.assembleComplete ||
              runningDownloads.values.any((active) => active.contains(id)))
            continue;
          // Do not acquire a job that was independently started by the user.
          if ([
            DownloadStatus.downloading,
            DownloadStatus.connecting,
            DownloadStatus.assembling,
            DownloadStatus.resetting,
            DownloadStatus.validatingFiles,
          ].contains(provider.downloads[id]?.status))
            continue;
          running.add(id);
          queues[queue] = true;
          slots--;
          provider.startDownload(id);
        }
        final complete = ids.every((id) {
          final item = HiveUtil.instance.downloadItemsBox.get(id);
          return item == null ||
              (provider.downloads[id]?.status ?? item.status) ==
                  DownloadStatus.assembleComplete;
        });
        if (complete && running.isEmpty) await _finish(queue, provider);
      }
    } catch (e, stack) {
      Logger.log('Queue scheduler error: $e\n$stack');
    } finally {
      _busy = false;
    }
  }

  static Future<void> stopAll() async {
    downloadCheckerTimer?.cancel();
    downloadCheckerTimer = null;
    schedulerTimer?.cancel();
    schedulerTimer = null;
    // Disable all queues before the first await so an in-flight tick cannot
    // start another job while Stop All is being persisted.
    for (final queue in queues.keys) {
      queue.scheduleEnabled = false;
      stoppedQueues.add(queue);
    }
    for (final queue in queues.keys) {
      await queue.save();
    }
  }
}
