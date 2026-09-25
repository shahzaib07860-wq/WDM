import 'package:wdm/browser_extension/browser_extension_server.dart';
import 'package:wdm/constants/file_type.dart';
import 'package:wdm/l10n/app_localizations.dart';
import 'package:wdm/provider/download_request_provider.dart';
import 'package:wdm/provider/pluto_grid_check_row_provider.dart';
import 'package:wdm/provider/pluto_grid_util.dart';
import 'package:wdm/provider/queue_provider.dart';
import 'package:wdm/provider/search_bar_notifier_provider.dart';
import 'package:wdm/provider/theme_provider.dart';
import 'package:wdm/theme/application_theme.dart';
import 'package:wdm/util/file_util.dart';
import 'package:wdm/util/ui_util.dart';
import 'package:wdm/widget/download/add_url_dialog.dart';
import 'package:wdm/widget/download/download_info_dialog.dart';
import 'package:wdm/widget/download/download_progress_dialog.dart';
import 'package:wdm/widget/legacy/legacy_palette.dart';
import 'package:wdm/widget/other/automatic_url_update_dialog.dart';
import 'package:brisk_download_engine/brisk_download_engine.dart';
import 'package:flutter/material.dart';
import 'package:pluto_grid/pluto_grid.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher_string.dart';
import 'package:wdm/db/hive_util.dart';

class DownloadGrid extends StatefulWidget {
  @override
  State<DownloadGrid> createState() => _DownloadGridState();
}

class _DownloadGridState extends State<DownloadGrid> {
  bool selectionMode = false;
  late List<PlutoColumn> columns;
  DownloadRequestProvider? provider;
  QueueProvider? queueProvider;
  late PlutoGridCheckRowProvider plutoProvider;
  late SearchBarNotifierProvider searchBarNotifier;
  late AppLocalizations loc;
  late ApplicationTheme theme;

  @override
  void didChangeDependencies() {
    loc = AppLocalizations.of(context)!;
    initColumns(context);
    searchBarNotifier = Provider.of<SearchBarNotifierProvider>(context);
    theme = Provider.of<ThemeProvider>(context).activeTheme;
    if (searchBarNotifier.showSearchBar) {
      Future.delayed(Duration(milliseconds: 50), () {
        _searchFocusNode.requestFocus();
      });
    }
    super.didChangeDependencies();
  }

  void initColumns(BuildContext context) {
    final fullWidth = MediaQuery.of(context).size.width;
    final showTime = fullWidth >= 1080;
    final showDate = fullWidth >= 1240;
    columns = [
      PlutoColumn(
        readOnly: true,
        hide: true,
        width: 70,
        title: 'Id',
        field: 'id',
        type: PlutoColumnType.number(),
      ),
      PlutoColumn(
        readOnly: true,
        hide: true,
        width: 70,
        title: 'Uid',
        field: 'uid',
        type: PlutoColumnType.text(),
      ),
      PlutoColumn(
        enableRowChecked: selectionMode,
        width: fullWidth < 1080 ? 390 : 430,
        title: 'File name',
        field: 'file_name',
        type: PlutoColumnType.text(),
        renderer: (ctx) => PlutoGridUtil.fileNameColumnRenderer(ctx, theme),
      ),
      PlutoColumn(
        readOnly: true,
        width: 80,
        title: 'Size',
        field: 'size',
        type: PlutoColumnType.text(),
        renderer: rowText,
      ),
      PlutoColumn(
        readOnly: true,
        hide: true,
        width: 90,
        title: 'Progress',
        field: 'progress',
        type: PlutoColumnType.text(),
        renderer: rowText,
      ),
      PlutoColumn(
        readOnly: true,
        width: 146,
        title: 'Status',
        field: 'status',
        type: PlutoColumnType.text(),
        renderer: (ctx) => _statusBadge(
          ctx.row.cells[ctx.column.field]!.value.toString(),
        ),
      ),
      PlutoColumn(
        readOnly: true,
        enableSorting: false,
        width: 94,
        title: 'Speed',
        field: 'transfer_rate',
        type: PlutoColumnType.text(),
        renderer: rowText,
      ),
      PlutoColumn(
        readOnly: true,
        hide: !showTime,
        width: 94,
        title: 'Time left',
        field: 'time_left',
        type: PlutoColumnType.text(),
        renderer: rowText,
      ),
      PlutoColumn(
        readOnly: true,
        hide: !showDate,
        width: 105,
        title: 'Last try',
        field: 'start_date',
        type: PlutoColumnType.date(),
        renderer: rowText,
      ),
      PlutoColumn(
        readOnly: true,
        hide: true,
        width: 115,
        title: 'Finish date',
        field: 'finish_date',
        type: PlutoColumnType.date(),
        renderer: rowText,
      ),
      PlutoColumn(
        readOnly: true,
        hide: true,
        width: 120,
        title: 'File Type',
        field: 'file_type',
        type: PlutoColumnType.text(),
        renderer: rowText,
      ),
    ];
  }

  Text rowText(rendererContext) {
    return Text(
      rendererContext.row.cells[rendererContext.column.field]!.value.toString(),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        color: theme.downloadGridTheme.rowTextColor,
        fontWeight: theme.fontWeight,
      ),
    );
  }

  double resolveIconSize(DLFileType fileType) {
    if (fileType == DLFileType.documents || fileType == DLFileType.program)
      return 25;
    else if (fileType == DLFileType.music)
      return 28;
    else
      return 30;
  }

  final _searchController = TextEditingController();
  final _searchFocusNode = FocusNode();

  @override
  Widget build(BuildContext context) {
    provider = Provider.of<DownloadRequestProvider>(context, listen: false);
    plutoProvider = Provider.of<PlutoGridCheckRowProvider>(
      context,
      listen: false,
    );
    queueProvider = Provider.of<QueueProvider>(context);
    theme = Provider.of<ThemeProvider>(context).activeTheme;
    searchBarNotifier = Provider.of<SearchBarNotifierProvider>(context);
    final light = theme.isLight;
    final legacyGridTheme = DownloadGridTheme(
      backgroundColor: LegacyPalette.bg1(light),
      activeRowColor: LegacyPalette.hover(light),
      checkedRowColor: LegacyPalette.selected(light),
      borderColor: LegacyPalette.rowBorder(light),
      rowColor: LegacyPalette.bg1(light),
      rowTextColor: LegacyPalette.text(light),
      titleColumnTextColor: LegacyPalette.text2(light),
    );

    return Material(
      type: MaterialType.transparency,
      child: SizedBox.expand(
        child: Container(
          color: LegacyPalette.bg1(light),
          child: Column(
            children: [
              _legacyToolsBar(light),
              _queueBar(light),
              Expanded(
                child: Stack(
                  children: [
                    PlutoGrid(
                      key: ValueKey(
                        '${queueProvider?.selectedQueueId ?? 'download-grid'}-$selectionMode',
                      ),
                      mode: PlutoGridMode.selectWithOneTap,
                      configuration: PlutoGridUtil.config(legacyGridTheme),
                      columns: columns,
                      rows: [],
                      onSelected: (event) => PlutoGridUtil.handleRowSelection(
                        event,
                        PlutoGridUtil.plutoStateManager!,
                        plutoProvider,
                      ),
                      onRowChecked: (row) => plutoProvider.notifyListeners(),
                      onRowDoubleTap: onRowDoubleTap,
                      onLoaded: (event) =>
                          onLoaded(event, provider!, queueProvider!),
                      onRowSecondaryTap: (event) =>
                          showSecondaryTapMenu(context, event),
                    ),
                    if (HiveUtil.instance.downloadItemsBox.values.isEmpty)
                      IgnorePointer(
                        child: Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                'No downloads yet',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                  color: LegacyPalette.text(light),
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                'Click "Add URL" or use the browser extension',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: LegacyPalette.text3(light),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              _detailsBar(light),
            ],
          ),
        ),
      ),
    );
  }

  Widget _legacyToolsBar(bool light) {
    return Container(
      height: 45,
      padding: const EdgeInsets.symmetric(horizontal: 9),
      decoration: BoxDecoration(
        color: LegacyPalette.bg1(light),
        border: Border(
          bottom: BorderSide(color: LegacyPalette.border(light)),
        ),
      ),
      child: Row(
        children: [
          _smallTool('Batch URLs', Icons.playlist_add_rounded, light, () {
            _notPorted('Batch URL entry');
          }),
          _smallTool('Grab site', Icons.travel_explore_rounded, light, () {
            _notPorted('Site grabber');
          }),
          _smallTool('ZIP preview', Icons.folder_zip_outlined, light, () {
            _notPorted('ZIP preview');
          }),
          _smallTool('Clipboard', Icons.content_paste_rounded, light, () {
            _notPorted('Clipboard monitor');
          }),
          _smallTool(
            selectionMode ? 'Done' : 'Select files',
            selectionMode
                ? Icons.check_box_rounded
                : Icons.check_box_outline_blank_rounded,
            light,
            () => setState(() {
              selectionMode = !selectionMode;
              initColumns(context);
            }),
          ),
          const Spacer(),
          SizedBox(
            width: 140,
            height: 30,
            child: TextField(
              controller: _searchController,
              style: TextStyle(
                fontSize: 13,
                color: LegacyPalette.text(light),
              ),
              decoration: InputDecoration(
                hintText: 'Search downloads',
                hintStyle: TextStyle(
                  fontSize: 13,
                  color: LegacyPalette.text3(light),
                ),
                prefixIcon: Icon(
                  Icons.search_rounded,
                  size: 17,
                  color: LegacyPalette.text3(light),
                ),
                prefixIconConstraints:
                    const BoxConstraints(minWidth: 30, minHeight: 30),
                filled: true,
                fillColor: LegacyPalette.bg0(light),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(3),
                  borderSide: BorderSide(color: LegacyPalette.border(light)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(3),
                  borderSide: BorderSide(color: LegacyPalette.accent(light)),
                ),
              ),
              onChanged: PlutoGridUtil.addSearchFilter,
            ),
          ),
        ],
      ),
    );
  }

  Widget _smallTool(
    String label,
    IconData icon,
    bool light,
    VoidCallback onTap,
  ) {
    return Padding(
      padding: const EdgeInsets.only(right: 4),
      child: TextButton.icon(
        onPressed: onTap,
        icon: Icon(icon, size: 16),
        label: Text(label, style: const TextStyle(fontSize: 13)),
        style: TextButton.styleFrom(
          foregroundColor: LegacyPalette.text2(light),
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 5),
          minimumSize: const Size(0, 30),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(3),
          ),
        ),
      ),
    );
  }

  Widget _queueBar(bool light) {
    return Container(
      height: 33,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: LegacyPalette.bg2(light),
        border: Border(
          bottom: BorderSide(color: LegacyPalette.border(light)),
        ),
      ),
      child: Row(
        children: [
          Icon(
            Icons.check_circle_outline_rounded,
            size: 15,
            color: LegacyPalette.accent(light),
          ),
          const SizedBox(width: 6),
          Text(
            'Queue ready',
            style: TextStyle(
              fontSize: 13,
              color: LegacyPalette.text2(light),
            ),
          ),
          const Spacer(),
          Text(
            '↑ Move up',
            style: TextStyle(fontSize: 12, color: LegacyPalette.text3(light)),
          ),
          const SizedBox(width: 14),
          Text(
            '↓ Move down',
            style: TextStyle(fontSize: 12, color: LegacyPalette.text3(light)),
          ),
        ],
      ),
    );
  }

  Widget _detailsBar(bool light) {
    final selectedCount = PlutoGridUtil.selectedRowIds.length;
    return Container(
      constraints: const BoxConstraints(minHeight: 36, maxHeight: 115),
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: LegacyPalette.bg0(light),
        border: Border(
          top: BorderSide(color: LegacyPalette.border(light)),
        ),
      ),
      child: Text(
        selectedCount == 0
            ? 'Select a download for its location and scan result.'
            : '$selectedCount download${selectedCount == 1 ? '' : 's'} selected.',
        style: TextStyle(
          fontSize: 13,
          height: 1.5,
          color: LegacyPalette.text2(light),
        ),
      ),
    );
  }

  Widget _statusBadge(String status) {
    final light = theme.isLight;
    final lower = status.toLowerCase();
    final isError = lower.contains('fail') || lower.contains('error');
    final isDone =
        status == DownloadStatus.assembleComplete || lower.contains('complete');
    final isActive = lower.contains('download') ||
        lower.contains('connect') ||
        lower.contains('validat') ||
        lower.contains('assembl');
    final color = isError
        ? LegacyPalette.error(light)
        : isActive
            ? LegacyPalette.accent(light)
            : LegacyPalette.text2(light);
    final background = isError
        ? LegacyPalette.error(light).withOpacity(.10)
        : isActive
            ? LegacyPalette.accentBg(light)
            : LegacyPalette.bg3(light);
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 3),
        decoration: BoxDecoration(
          color: isDone ? LegacyPalette.bg3(light) : background,
          borderRadius: BorderRadius.circular(3),
        ),
        child: Text(
          status.isEmpty ? 'Ready' : status,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 12,
            color: color,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    );
  }

  void _notPorted(String feature) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text('$feature is visible in the 1.4.1 layout; its 2.0 engine port is not connected yet.'),
          duration: const Duration(seconds: 2),
        ),
      );
  }

  Widget showSearchbar() {
    return Positioned(
      top: 16,
      left: 16,
      width: 400,
      height: 35,
      child: Material(
        elevation: 10,
        color: theme.alertDialogTheme.backgroundColor,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: theme.alertDialogTheme.borderColor,
              width: 1,
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    focusNode: _searchFocusNode,
                    style: TextStyle(color: theme.textColor),
                    decoration: InputDecoration(
                      isDense: true,
                      hintStyle: TextStyle(color: theme.textColor),
                      hintText: 'Search downloads...',
                      contentPadding: EdgeInsets.zero,
                      border: InputBorder.none,
                    ),
                    onChanged: PlutoGridUtil.addSearchFilter,
                  ),
                ),
                IconButton(
                  icon: Icon(
                    Icons.close,
                    size: 20,
                    color: theme.widgetTheme.iconColor,
                  ),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  onPressed: searchBarNotifier.toggleShow,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void showSecondaryTapMenu(
    BuildContext context,
    PlutoGridOnRowSecondaryTapEvent event,
  ) {
    final provider =
        Provider.of<DownloadRequestProvider>(context, listen: false);
    final size = MediaQuery.of(context).size;
    final loc = AppLocalizations.of(context)!;
    final theme =
        Provider.of<ThemeProvider>(context, listen: false).activeTheme;
    final id = event.row.cells["id"]!.value;
    final status = event.row.cells["status"]!.value;
    final downloadProgress = provider.downloads[id];
    final downloadExists = downloadProgress != null;
    final downloadComplete = status == DownloadStatus.assembleComplete;
    final updateUrlEnabled = downloadExists
        ? (downloadProgress.status != DownloadStatus.assembleComplete ||
            downloadProgress.status != DownloadStatus.downloading)
        : (!downloadComplete || status == DownloadStatus.paused);
    final automaticUrlUpdateEnabled = updateUrlEnabled &&
        HiveUtil.instance.downloadItemsBox.get(id)?.referer != null;
    showMenu(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(
          color: theme.contextMenuTheme.borderColor,
          width: 1,
        ),
      ),
      color: theme.contextMenuTheme.backgroundColor,
      popUpAnimationStyle: AnimationStyle(
        curve: Easing.emphasizedAccelerate,
        duration: Durations.short2,
      ),
      context: context,
      position: Directionality.of(context) == TextDirection.rtl
          ? RelativeRect.fromDirectional(
              textDirection: TextDirection.rtl,
              bottom: event.offset.dy,
              top: event.offset.dy,
              end: size.width - event.offset.dx,
              start: size.width - event.offset.dx,
            )
          : RelativeRect.fromLTRB(
              event.offset.dx,
              event.offset.dy,
              event.offset.dx,
              event.offset.dy,
            ),
      items: [
        PopupMenuItem(
          value: "Show Progress",
          child: Text(
            loc.popupMenu_showProgress,
            style: contextMenuItemTextStyle(downloadExists),
          ),
          enabled: downloadExists,
        ),
        PopupMenuItem(
          value: "Open File",
          child: Text(
            loc.btn_openFile,
            style: contextMenuItemTextStyle(downloadComplete),
          ),
          enabled: downloadComplete,
        ),
        PopupMenuItem(
          value: "Open File Location",
          child: Text(
            loc.btn_openFileLocation,
            style: contextMenuItemTextStyle(downloadComplete),
          ),
          enabled: downloadComplete,
        ),
        PopupMenuItem(
          value: "Update URL",
          child: Text(
            loc.btn_updateUrl,
            style: contextMenuItemTextStyle(updateUrlEnabled),
          ),
          enabled: updateUrlEnabled,
        ),
        PopupMenuItem(
          value: "Automatic URL Update",
          child: Text(
            loc.automaticUrlUpdate,
            style: contextMenuItemTextStyle(automaticUrlUpdateEnabled),
          ),
          enabled: automaticUrlUpdateEnabled,
        ),
        PopupMenuItem(
          value: "Properties",
          child: Text(
            loc.popupMenu_properties,
            style: contextMenuItemTextStyle(true),
          ),
        ),
      ],
    ).then((value) => onMenuItemClicked(value, event));
  }

  TextStyle contextMenuItemTextStyle(bool enabled) {
    return TextStyle(
      color: enabled
          ? theme.contextMenuTheme.itemTextColor
          : theme.contextMenuTheme.itemDisabledTextColor,
    );
  }

  void onMenuItemClicked(String? value, PlutoGridOnRowSecondaryTapEvent event) {
    if (value == null) {
      return;
    }
    final downloadId = event.row.cells["id"]!.value;
    final downloadItem = HiveUtil.instance.downloadItemsBox.get(downloadId);
    if (downloadItem == null) {
      return;
    }
    switch (value) {
      case "Show Progress":
        showDialog(
          context: context,
          builder: (_) => DownloadProgressDialog(downloadItem.key),
          barrierDismissible: false,
        );
        break;
      case "Open File":
        launchUrlString("file:${downloadItem.filePath}");
        break;
      case "Open File Location":
        openFileLocation(downloadItem);
        break;
      case "Update URL":
        showDialog(
          context: context,
          builder: (context) =>
              AddUrlDialog(downloadId: downloadItem.key, updateDialog: true),
        );
        break;
      case "Automatic URL Update":
        launchUrlString(downloadItem.referer!);
        BrowserExtensionServer.awaitingUpdateUrlItem = downloadItem;
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) => AutomaticUrlUpdateDialog(),
        );
        break;
      case "Properties":
        showDialog(
          context: context,
          builder: (context) => DownloadInfoDialog(
            downloadItem,
            showActionButtons: false,
            showFileActionButtons:
                downloadItem.status == DownloadStatus.assembleComplete,
          ),
        );
        break;
      default:
        break;
    }
  }

  void onLoaded(
    event,
    DownloadRequestProvider provider,
    QueueProvider queueProvider,
  ) async {
    PlutoGridUtil.setStateManager(event.stateManager);
    PlutoGridUtil.plutoStateManager
        ?.setSelectingMode(PlutoGridSelectingMode.row);
    PlutoGridUtil.registerKeyListeners(
      PlutoGridUtil.plutoStateManager!,
      onDeletePressed: () => PlutoGridUtil.onRemovePressed(context),
    );
    if (queueProvider.selectedQueueId == null) {
      provider.fetchRows(HiveUtil.instance.downloadItemsBox.values.toList());
    } else {
      final queueId = queueProvider.selectedQueueId!;
      final queue = await HiveUtil.instance.downloadQueueBox.get(queueId);
      if (queue?.downloadItemsIds == null) return;
      final downloads = queue!.downloadItemsIds!
          .map((e) => HiveUtil.instance.downloadItemsBox.get(e)!)
          .toList();
      provider.fetchRows(downloads);
    }
    PlutoGridUtil.setSavedFilters();
  }

  void onRowDoubleTap(event) {
    final status = event.row.cells["status"]?.value;
    final id = event.row.cells["id"]?.value;
    final downloadItem = HiveUtil.instance.downloadItemsBox.get(id);
    final downloadProgress = provider!.downloads[id];
    if (status == null || downloadItem == null) {
      return;
    }
    if (downloadProgress != null &&
        downloadProgress.status != DownloadStatus.assembleComplete) {
      showDialog(
        context: context,
        builder: (_) => DownloadProgressDialog(id),
        barrierDismissible: false,
      );
      return;
    }
    showDialog(
      context: context,
      builder: (context) => DownloadInfoDialog(
        downloadItem,
        showActionButtons: false,
        newDownload: false,
        showFileActionButtons:
            downloadItem.status == DownloadStatus.assembleComplete,
      ),
    );
  }
}
