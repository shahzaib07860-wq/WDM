import 'package:brisk_download_engine/brisk_download_engine.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:wdm/constants/file_type.dart';
import 'package:wdm/provider/pluto_grid_util.dart';
import 'package:wdm/provider/queue_provider.dart';
import 'package:wdm/provider/theme_provider.dart';
import 'package:wdm/util/ui_util.dart';
import 'package:wdm/widget/legacy/legacy_palette.dart';

class SideMenu extends StatefulWidget {
  const SideMenu({super.key});

  @override
  State<SideMenu> createState() => _SideMenuState();
}

class _SideMenuState extends State<SideMenu> {
  String selected = 'All downloads';

  @override
  Widget build(BuildContext context) {
    final light = Provider.of<ThemeProvider>(context).activeTheme.isLight;
    final queueProvider = Provider.of<QueueProvider>(context);
    return Container(
      width: minimizedSideMenuWidth,
      color: LegacyPalette.bg0(light),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 7),
          _item('All downloads', Icons.download_rounded, light,
              () => _all(queueProvider)),
          _item('Unfinished', Icons.downloading_outlined, light,
              () => _status(queueProvider, DownloadStatus.assembleComplete, negate: true)),
          _item('Finished', Icons.download_done_rounded, light,
              () => _status(queueProvider, DownloadStatus.assembleComplete)),
          _item('Failed', Icons.error_outline_rounded, light,
              () => _status(queueProvider, DownloadStatus.failed)),
          _item('Paused', Icons.pause_circle_outline_rounded, light,
              () => _status(queueProvider, DownloadStatus.paused)),
          _heading('Categories', light),
          _item('Compressed', Icons.archive_outlined, light,
              () => _category(queueProvider, DLFileType.compressed)),
          _item('Documents', Icons.description_outlined, light,
              () => _category(queueProvider, DLFileType.documents)),
          _item('Music', Icons.music_note_outlined, light,
              () => _category(queueProvider, DLFileType.music)),
          _item('Programs', Icons.apps_outlined, light,
              () => _category(queueProvider, DLFileType.program)),
          _item('Video', Icons.movie_outlined, light,
              () => _category(queueProvider, DLFileType.video)),
          _item('Images', Icons.image_outlined, light,
              () => _category(queueProvider, DLFileType.images)),
          _item('Other', Icons.insert_drive_file_outlined, light,
              () => _category(queueProvider, DLFileType.other)),
          _heading('Queues', light),
          _item('Main queue', Icons.queue_outlined, light,
              () => _queues(queueProvider, 'Main queue')),
          _item('Browser extension', Icons.extension_outlined, light,
              () => _queues(queueProvider, 'Browser extension')),
          const Spacer(),
          _bandwidth(light),
        ],
      ),
    );
  }

  Widget _heading(String text, bool light) => Padding(
        padding: const EdgeInsets.fromLTRB(12, 11, 10, 4),
        child: Text(
          text.toUpperCase(),
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            letterSpacing: .4,
            color: LegacyPalette.text3(light),
          ),
        ),
      );

  Widget _item(
    String title,
    IconData icon,
    bool light,
    VoidCallback onTap,
  ) {
    final active = selected == title;
    return InkWell(
      onTap: onTap,
      hoverColor: LegacyPalette.hover(light),
      child: Container(
        height: 34,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: active ? LegacyPalette.selected(light) : Colors.transparent,
          border: Border(
            left: BorderSide(
              width: 2,
              color: active ? LegacyPalette.accent(light) : Colors.transparent,
            ),
          ),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              size: 16,
              color: active
                  ? LegacyPalette.accent(light)
                  : LegacyPalette.text2(light),
            ),
            const SizedBox(width: 9),
            Expanded(
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13.5,
                  color: active
                      ? LegacyPalette.text(light)
                      : LegacyPalette.text2(light),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _bandwidth(bool light) => Container(
        margin: const EdgeInsets.all(9),
        padding: const EdgeInsets.fromLTRB(9, 7, 9, 8),
        decoration: BoxDecoration(
          color: LegacyPalette.bg1(light),
          border: Border.all(color: LegacyPalette.border(light)),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Bandwidth',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: LegacyPalette.text3(light),
              ),
            ),
            const SizedBox(height: 5),
            SizedBox(
              height: 38,
              child: CustomPaint(
                painter: _BandwidthPainter(
                  line: LegacyPalette.accent(light),
                  grid: LegacyPalette.rowBorder(light),
                ),
                child: const SizedBox.expand(),
              ),
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Text('0 KB/s',
                    style: TextStyle(
                        fontSize: 11, color: LegacyPalette.text2(light))),
                const Spacer(),
                Text('Peak 0',
                    style: TextStyle(
                        fontSize: 10, color: LegacyPalette.text3(light))),
              ],
            ),
          ],
        ),
      );

  void _activate(String title, QueueProvider queueProvider) {
    queueProvider.setQueueTopMenu(false);
    queueProvider.setDownloadQueueTopMenu(false);
    setState(() => selected = title);
  }

  void _all(QueueProvider queueProvider) {
    PlutoGridUtil.removeFilters();
    queueProvider.setSelectedQueue(null);
    queueProvider.setQueueTabSelected(false);
    _activate('All downloads', queueProvider);
  }

  void _status(
    QueueProvider queueProvider,
    String status, {
    bool negate = false,
  }) {
    PlutoGridUtil.removeFilters();
    PlutoGridUtil.addFilter('status', status, negate: negate);
    queueProvider.setSelectedQueue(null);
    queueProvider.setQueueTabSelected(false);
    final label = status == DownloadStatus.assembleComplete
        ? (negate ? 'Unfinished' : 'Finished')
        : status == DownloadStatus.failed
            ? 'Failed'
            : 'Paused';
    _activate(label, queueProvider);
  }

  void _category(QueueProvider queueProvider, DLFileType type) {
    PlutoGridUtil.removeFilters();
    PlutoGridUtil.addFilter('file_type', type.name);
    queueProvider.setSelectedQueue(null);
    queueProvider.setQueueTabSelected(false);
    final labels = {
      DLFileType.compressed: 'Compressed',
      DLFileType.documents: 'Documents',
      DLFileType.music: 'Music',
      DLFileType.program: 'Programs',
      DLFileType.video: 'Video',
      DLFileType.images: 'Images',
      DLFileType.other: 'Other',
    };
    _activate(labels[type] ?? 'Other', queueProvider);
  }

  void _queues(QueueProvider queueProvider, String title) {
    PlutoGridUtil.removeFilters();
    queueProvider.setSelectedQueue(null);
    queueProvider.setQueueTabSelected(true);
    _activate(title, queueProvider);
  }
}

class _BandwidthPainter extends CustomPainter {
  final Color line;
  final Color grid;

  _BandwidthPainter({required this.line, required this.grid});

  @override
  void paint(Canvas canvas, Size size) {
    final gridPaint = Paint()
      ..color = grid
      ..strokeWidth = 1;
    for (var i = 1; i < 4; i++) {
      final y = size.height * i / 4;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }
    final linePaint = Paint()
      ..color = line
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;
    final path = Path()
      ..moveTo(0, size.height - 4)
      ..lineTo(size.width * .25, size.height - 4)
      ..lineTo(size.width * .38, size.height - 7)
      ..lineTo(size.width * .50, size.height - 5)
      ..lineTo(size.width * .72, size.height - 8)
      ..lineTo(size.width, size.height - 5);
    canvas.drawPath(path, linePaint);
  }

  @override
  bool shouldRepaint(covariant _BandwidthPainter oldDelegate) =>
      oldDelegate.line != line || oldDelegate.grid != grid;
}
