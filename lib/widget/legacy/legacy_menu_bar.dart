import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:window_manager/window_manager.dart';
import 'package:wdm/provider/download_request_provider.dart';
import 'package:wdm/provider/pluto_grid_util.dart';
import 'package:wdm/provider/settings_provider.dart';
import 'package:wdm/provider/theme_provider.dart';
import 'package:wdm/setting/settings_cache.dart';
import 'package:wdm/theme/application_theme_holder.dart';
import 'package:wdm/widget/browser_extension/get_browser_extension_dialog.dart';
import 'package:wdm/widget/download/add_url_dialog.dart';
import 'package:wdm/widget/legacy/legacy_palette.dart';
import 'package:wdm/widget/setting/setting_dialog.dart';

class LegacyMenuBar extends StatelessWidget {
  const LegacyMenuBar({super.key});

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final light = themeProvider.activeTheme.isLight;
    return Container(
      height: 35,
      decoration: BoxDecoration(
        color: LegacyPalette.bg0(light),
        border: Border(
          bottom: BorderSide(color: LegacyPalette.border(light)),
        ),
      ),
      child: Row(
        children: [
          const SizedBox(width: 5),
          _menu(context, 'Tasks', const ['Add URL', 'Exit'], light),
          _menu(context, 'File', const ['Open download folder', 'Options'], light),
          _menu(context, 'Downloads', const ['Resume', 'Pause', 'Stop all'], light),
          _menu(context, 'View', const ['Toggle theme'], light),
          _menu(context, 'Help', const ['Browser extension'], light),
          _menu(context, 'About', const ['About WDM'], light),
          const Spacer(),
          InkWell(
            onTap: () => _toggleTheme(context),
            hoverColor: LegacyPalette.hover(light),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
              child: Row(
                children: [
                  Icon(
                    light ? Icons.dark_mode_outlined : Icons.light_mode_outlined,
                    size: 17,
                    color: LegacyPalette.text2(light),
                  ),
                  const SizedBox(width: 5),
                  Text(
                    light ? 'Dark mode' : 'Light mode',
                    style: TextStyle(
                      fontSize: 13,
                      color: LegacyPalette.text(light),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(left: 8, right: 10),
            child: Text(
              'WDM ${SettingsCache.currentVersion}',
              style: TextStyle(
                fontSize: 12,
                color: LegacyPalette.text3(light),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _menu(
    BuildContext context,
    String label,
    List<String> items,
    bool light,
  ) {
    return PopupMenuButton<String>(
      tooltip: '',
      offset: const Offset(0, 31),
      color: LegacyPalette.bg2(light),
      onSelected: (value) => _onSelected(context, value),
      itemBuilder: (_) => items
          .map(
            (item) => PopupMenuItem<String>(
              value: item,
              height: 35,
              child: Text(
                item,
                style: TextStyle(
                  fontSize: 13,
                  color: LegacyPalette.text(light),
                ),
              ),
            ),
          )
          .toList(),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            color: LegacyPalette.text(light),
          ),
        ),
      ),
    );
  }

  Future<void> _onSelected(BuildContext context, String value) async {
    final downloadProvider =
        Provider.of<DownloadRequestProvider>(context, listen: false);
    switch (value) {
      case 'Add URL':
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (_) => const AddUrlDialog(),
        );
        break;
      case 'Exit':
        await windowManager.close();
        break;
      case 'Open download folder':
        if (Platform.isWindows) {
          await Process.run('explorer.exe', [SettingsCache.saveDir.path]);
        }
        break;
      case 'Options':
        Provider.of<SettingsProvider>(context, listen: false).selectedTabId = 0;
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (_) => const SettingsDialog(),
        );
        break;
      case 'Resume':
        PlutoGridUtil.doOperationOnCheckedRows((id, _) {
          downloadProvider.startDownload(id);
        });
        break;
      case 'Pause':
        PlutoGridUtil.doOperationOnCheckedRows((id, _) {
          downloadProvider.pauseDownload(id);
        });
        break;
      case 'Stop all':
        for (final id in downloadProvider.downloads.keys.toList()) {
          await downloadProvider.pauseDownload(id);
        }
        break;
      case 'Toggle theme':
        await _toggleTheme(context);
        break;
      case 'Browser extension':
        showDialog(
          context: context,
          builder: (_) => GetBrowserExtensionDialog(),
        );
        break;
      case 'About WDM':
        showAboutDialog(
          context: context,
          applicationName: 'WDM — Web Download Manager',
          applicationVersion: SettingsCache.currentVersion,
          children: const [
            Text('Fast desktop download manager with browser integration.'),
          ],
        );
        break;
      default:
        break;
    }
  }

  Future<void> _toggleTheme(BuildContext context) async {
    final current = Provider.of<ThemeProvider>(context, listen: false);
    SettingsCache.applicationThemeId =
        current.activeTheme.isLight ? 'Celestial Dark' : 'Light';
    ApplicationThemeHolder.setActiveTheme();
    current.updateActiveTheme();
    await SettingsCache.saveCachedSettingsToDB();
  }
}
