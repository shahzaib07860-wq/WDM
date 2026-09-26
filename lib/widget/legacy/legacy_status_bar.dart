import 'package:flutter/material.dart';
import 'package:brisk_download_engine/brisk_download_engine.dart';
import 'package:provider/provider.dart';
import 'package:wdm/provider/download_request_provider.dart';
import 'package:wdm/provider/pluto_grid_check_row_provider.dart';
import 'package:wdm/provider/pluto_grid_util.dart';
import 'package:wdm/provider/theme_provider.dart';
import 'package:wdm/widget/legacy/legacy_palette.dart';
import 'package:wdm/util/readability_util.dart';

class LegacyStatusBar extends StatelessWidget {
  const LegacyStatusBar({super.key});

  @override
  Widget build(BuildContext context) {
    final light = Provider.of<ThemeProvider>(context).activeTheme.isLight;
    final downloads = Provider.of<DownloadRequestProvider>(context);
    Provider.of<PlutoGridCheckRowProvider>(context);
    final selected = PlutoGridUtil.selectedRowIds.length;
    final active = downloads.downloads.values.where((p) {
      return p.status == DownloadStatus.downloading ||
          p.status == DownloadStatus.connecting ||
          p.status == DownloadStatus.validatingFiles ||
          p.status == DownloadStatus.assembling;
    }).length;
    final totalBytesPerSecond = downloads.downloads.values.fold<double>(
      0,
      (sum, p) => sum + p.bytesTransferRate,
    );
    return Container(
      height: 31,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: LegacyPalette.bg0(light),
        border: Border(
          top: BorderSide(color: LegacyPalette.border(light)),
        ),
      ),
      child: Row(
        children: [
          Text(
            active == 0 ? 'Ready' : '$active active',
            style: TextStyle(
              fontSize: 12,
              color: LegacyPalette.text2(light),
            ),
          ),
          const Spacer(),
          Icon(
            Icons.arrow_downward_rounded,
            size: 14,
            color: LegacyPalette.accent(light),
          ),
          const SizedBox(width: 3),
          Text(
            totalBytesPerSecond <= 0
                ? '0 B/s'
                : convertByteTransferRateToReadableStr(totalBytesPerSecond),
            style: TextStyle(fontSize: 12, color: LegacyPalette.text2(light)),
          ),
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 9),
            width: 1,
            height: 15,
            color: LegacyPalette.borderStrong(light),
          ),
          Text(
            selected == 0
                ? 'No selection'
                : '$selected selected',
            style: TextStyle(fontSize: 12, color: LegacyPalette.text2(light)),
          ),
        ],
      ),
    );
  }
}
