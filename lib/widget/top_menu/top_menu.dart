import 'dart:io';

import 'package:brisk_download_engine/brisk_download_engine.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:window_manager/window_manager.dart';
import 'package:wdm/db/hive_util.dart';
import 'package:wdm/provider/download_request_provider.dart';
import 'package:wdm/provider/pluto_grid_check_row_provider.dart';
import 'package:wdm/provider/pluto_grid_util.dart';
import 'package:wdm/provider/queue_provider.dart';
import 'package:wdm/provider/settings_provider.dart';
import 'package:wdm/provider/theme_provider.dart';
import 'package:wdm/setting/settings_cache.dart';
import 'package:wdm/util/ui_util.dart';
import 'package:wdm/widget/download/add_url_dialog.dart';
import 'package:wdm/widget/download/queue_schedule_handler.dart';
import 'package:wdm/widget/legacy/legacy_palette.dart';
import 'package:wdm/widget/queue/schedule_dialog.dart';
import 'package:wdm/widget/setting/setting_dialog.dart';
import 'package:wdm/widget/top_menu/top_menu_button.dart';

class TopMenu extends StatefulWidget {
  const TopMenu({super.key});

  @override
  State<TopMenu> createState() => _TopMenuState();
}

class _TopMenuState extends State<TopMenu> {
  late DownloadRequestProvider provider;

  @override
  Widget build(BuildContext context) {
    provider = Provider.of<DownloadRequestProvider>(context, listen: false);
    Provider.of<PlutoGridCheckRowProvider>(context);
    Provider.of<QueueProvider>(context);
    final light = Provider.of<ThemeProvider>(context).activeTheme.isLight;
    final canResume = isDownloadButtonEnabled(provider);
    final canPause = isPauseButtonEnabled(provider);
    final selected = PlutoGridUtil.selectedRowExists;

    return Container(
      height: topMenuHeight,
      decoration: BoxDecoration(
        color: LegacyPalette.bg2(light),
        border: Border(
          bottom: BorderSide(color: LegacyPalette.border(light)),
        ),
      ),
      child: Row(
        children: [
          const SizedBox(width: 4),
          _button(
            title: 'Add URL',
            icon: Icons.add_link_rounded,
            enabled: true,
            primary: true,
            onTap: _addUrl,
          ),
          _button(
            title: 'Resume',
            icon: Icons.play_arrow_rounded,
            enabled: canResume,
            onTap: _resumeSelected,
          ),
          _button(
            title: 'Stop',
            icon: Icons.stop_rounded,
            enabled: canPause,
            onTap: _pauseSelected,
          ),
          _button(
            title: 'Stop all',
            icon: Icons.stop_circle_outlined,
            enabled: provider.downloads.isNotEmpty,
            onTap: _stopAll,
          ),
          _separator(light),
          _button(
            title: 'Delete',
            icon: Icons.delete_outline_rounded,
            enabled: selected,
            onTap: () => PlutoGridUtil.onRemovePressed(context),
          ),
          _button(
            title: 'Delete done',
            icon: Icons.delete_sweep_outlined,
            enabled: true,
            onTap: _deleteCompleted,
          ),
          _separator(light),
          _button(
            title: 'Options',
            icon: Icons.settings_outlined,
            enabled: true,
            onTap: _openOptions,
          ),
          _button(
            title: 'Scheduler',
            icon: Icons.schedule_rounded,
            enabled: true,
            onTap: _openScheduler,
          ),
          _separator(light),
          _button(
            title: 'Start queue',
            icon: Icons.playlist_play_rounded,
            enabled: true,
            onTap: _startQueue,
          ),
          _button(
            title: 'Pause queue',
            icon: Icons.pause_circle_outline_rounded,
            enabled: true,
            onTap: _pauseQueue,
          ),
          _separator(light),
          _button(
            title: 'Folder',
            icon: Icons.folder_open_outlined,
            enabled: true,
            onTap: _openFolder,
          ),
          const Spacer(),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Row(
              children: [
                Icon(
                  Icons.arrow_downward_rounded,
                  size: 15,
                  color: LegacyPalette.accent(light),
                ),
                const SizedBox(width: 3),
                Text(
                  '—',
                  style: TextStyle(
                    fontSize: 13,
                    color: LegacyPalette.text2(light),
                  ),
                ),
              ],
            ),
          ),
          _separator(light),
          _button(
            title: 'Exit',
            icon: Icons.power_settings_new_rounded,
            enabled: true,
            onTap: () => windowManager.close(),
          ),
          const SizedBox(width: 4),
        ],
      ),
    );
  }

  Widget _button({
    required String title,
    required IconData icon,
    required bool enabled,
    required VoidCallback? onTap,
    bool primary = false,
  }) {
    final light =
        Provider.of<ThemeProvider>(context, listen: false).activeTheme.isLight;
    return TopMenuButton(
      title: title,
      isEnabled: enabled,
      onTap: onTap,
      icon: Icon(
        icon,
        color: primary && enabled
            ? LegacyPalette.accent(light)
            : enabled
                ? LegacyPalette.text2(light)
                : LegacyPalette.text3(light).withOpacity(.45),
      ),
      onHoverColor: LegacyPalette.hover(light),
    );
  }

  Widget _separator(bool light) => Container(
        width: 1,
        height: 35,
        margin: const EdgeInsets.symmetric(horizontal: 3),
        color: LegacyPalette.borderStrong(light),
      );

  void _addUrl() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const AddUrlDialog(),
    );
  }

  void _resumeSelected() {
    PlutoGridUtil.doOperationOnCheckedRows((id, _) {
      provider.startDownload(id);
    });
  }

  void _pauseSelected() {
    PlutoGridUtil.doOperationOnCheckedRows((id, _) {
      provider.pauseDownload(id);
    });
  }

  Future<void> _stopAll() async {
    for (final id in provider.downloads.keys.toList()) {
      await provider.pauseDownload(id);
    }
  }

  void _deleteCompleted() {
    final manager = PlutoGridUtil.plutoStateManager;
    if (manager == null) return;
    for (final row in manager.rows) {
      if (row.cells['status']?.value == DownloadStatus.assembleComplete) {
        manager.setRowChecked(row, true, checkedViaSelect: true);
      }
    }
    manager.notifyListeners();
    if (manager.checkedRows.isNotEmpty) {
      PlutoGridUtil.onRemovePressed(context);
    } else {
      _toast('No completed downloads to delete.');
    }
  }

  void _openOptions() {
    Provider.of<SettingsProvider>(context, listen: false).selectedTabId = 0;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const SettingsDialog(),
    );
  }

  void _openScheduler() {
    final queueProvider = Provider.of<QueueProvider>(context, listen: false);
    final id = queueProvider.selectedQueueId;
    if (id == null) {
      _toast('Select a queue first.');
      return;
    }
    final queue = HiveUtil.instance.downloadQueueBox.get(id);
    if (queue == null) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => ScheduleDialog(
        queue: queue,
        onAcceptClicked: ({
          required bool shutdownAfterCompletion,
          required int simultaneousDownloads,
          DateTime? scheduledStart,
          DateTime? scheduledEnd,
        }) {
          QueueScheduleHandler.schedule(
            queue,
            context,
            shutdownAfterCompletion: shutdownAfterCompletion,
            simultaneousDownloads: simultaneousDownloads,
            scheduledStart: scheduledStart,
            scheduledEnd: scheduledEnd,
          );
        },
      ),
    );
  }

  void _startQueue() {
    final queueProvider = Provider.of<QueueProvider>(context, listen: false);
    final id = queueProvider.selectedQueueId;
    if (id == null) {
      queueProvider.setQueueTabSelected(true);
      _toast('Select a queue to start.');
      return;
    }
    final queue = HiveUtil.instance.downloadQueueBox.get(id);
    for (final downloadId in queue?.downloadItemsIds ?? <int>[]) {
      provider.startDownload(downloadId);
    }
  }

  Future<void> _pauseQueue() async {
    final queueProvider = Provider.of<QueueProvider>(context, listen: false);
    final id = queueProvider.selectedQueueId;
    if (id == null) {
      _toast('Select a queue to pause.');
      return;
    }
    final queue = HiveUtil.instance.downloadQueueBox.get(id);
    for (final downloadId in queue?.downloadItemsIds ?? <int>[]) {
      await provider.pauseDownload(downloadId);
    }
  }

  Future<void> _openFolder() async {
    if (Platform.isWindows) {
      await Process.run('explorer.exe', [SettingsCache.saveDir.path]);
    }
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          duration: const Duration(seconds: 2),
        ),
      );
  }
}

bool isDownloadButtonEnabled(DownloadRequestProvider provider) {
  final selectedRowIds = PlutoGridUtil.selectedRowIds;
  final completedDownloadSelected = selectedRowIds
      .map((id) => HiveUtil.instance.downloadItemsBox.get(id))
      .whereType<dynamic>()
      .any((download) => download.status == DownloadStatus.assembleComplete);
  if (selectedRowIds.isEmpty || completedDownloadSelected) return false;
  return provider.downloads.values
          .where((item) => selectedRowIds.contains(item.downloadItem.id))
          .every((item) => item.buttonAvailability.startButtonEnabled) ||
      provider.downloads.values.isEmpty;
}

bool isPauseButtonEnabled(DownloadRequestProvider provider) {
  final selectedRowIds = PlutoGridUtil.selectedRowIds;
  if (selectedRowIds.isEmpty || provider.downloads.values.isEmpty) return false;
  return provider.downloads.values
      .where((item) => selectedRowIds.contains(item.downloadItem.id))
      .every((item) => item.buttonAvailability.pauseButtonEnabled);
}
