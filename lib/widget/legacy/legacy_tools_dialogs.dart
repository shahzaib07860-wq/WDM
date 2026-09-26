import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:wdm/model/download_item.dart';
import 'package:wdm/provider/theme_provider.dart';
import 'package:wdm/util/download_addition_ui_util.dart';
import 'package:wdm/util/legacy_tools.dart';
import 'package:wdm/util/readability_util.dart';

class BatchUrlDialog extends StatefulWidget {
  final BuildContext parentContext;

  const BatchUrlDialog({super.key, required this.parentContext});

  @override
  State<BatchUrlDialog> createState() => _BatchUrlDialogState();
}

class _BatchUrlDialogState extends State<BatchUrlDialog> {
  final controller = TextEditingController();

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Provider.of<ThemeProvider>(context).activeTheme;
    return AlertDialog(
      backgroundColor: theme.alertDialogTheme.backgroundColor,
      title: Text('Batch URLs', style: TextStyle(color: theme.textColor)),
      content: SizedBox(
        width: 560,
        child: TextField(
          controller: controller,
          autofocus: true,
          minLines: 9,
          maxLines: 14,
          style: TextStyle(color: theme.textColor, fontSize: 14),
          decoration: InputDecoration(
            hintText: 'Paste one or more http/https URLs, one per line',
            hintStyle: TextStyle(color: theme.textHintColor),
            border: const OutlineInputBorder(),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _submit,
          child: const Text('Continue'),
        ),
      ],
    );
  }

  void _submit() {
    final urls = DownloadAdditionUiUtil.extractUrls(controller.text)
        .where((u) => Uri.tryParse(u)?.hasScheme ?? false)
        .toSet()
        .toList();
    if (urls.isEmpty) {
      ScaffoldMessenger.of(widget.parentContext).showSnackBar(
        const SnackBar(content: Text('No valid URLs found.')),
      );
      return;
    }
    Navigator.pop(context);
    Future.microtask(
      () => DownloadAdditionUiUtil.handleDownloadAddition(
        widget.parentContext,
        urls.join('\n'),
      ),
    );
  }
}

class SiteGrabberDialog extends StatefulWidget {
  final BuildContext parentContext;

  const SiteGrabberDialog({super.key, required this.parentContext});

  @override
  State<SiteGrabberDialog> createState() => _SiteGrabberDialogState();
}

class _SiteGrabberDialogState extends State<SiteGrabberDialog> {
  final controller = TextEditingController();
  bool busy = false;
  String status =
      'Crawls up to 25 same-site pages and collects downloadable links.';

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Provider.of<ThemeProvider>(context).activeTheme;
    return AlertDialog(
      backgroundColor: theme.alertDialogTheme.backgroundColor,
      title: Text('Grab site', style: TextStyle(color: theme.textColor)),
      content: SizedBox(
        width: 560,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: controller,
              enabled: !busy,
              autofocus: true,
              style: TextStyle(color: theme.textColor),
              decoration: InputDecoration(
                hintText: 'https://example.com/downloads/',
                hintStyle: TextStyle(color: theme.textHintColor),
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            if (busy) const LinearProgressIndicator(),
            const SizedBox(height: 8),
            Text(
              status,
              style: TextStyle(color: theme.subtleTextColor, fontSize: 13),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: busy ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: busy ? null : _grab,
          child: const Text('Scan'),
        ),
      ],
    );
  }

  Future<void> _grab() async {
    setState(() {
      busy = true;
      status = 'Scanning site…';
    });
    try {
      final result = await SiteGrabber.crawl(controller.text);
      if (!mounted) return;
      if (result.urls.isEmpty) {
        setState(() {
          busy = false;
          status =
              'Scanned ${result.pagesVisited} pages; no downloadable links found.';
        });
        return;
      }
      Navigator.pop(context);
      ScaffoldMessenger.of(widget.parentContext).showSnackBar(
        SnackBar(
          content: Text(
            'Found ${result.urls.length} links across ${result.pagesVisited} pages.',
          ),
        ),
      );
      Future.microtask(
        () => DownloadAdditionUiUtil.handleDownloadAddition(
          widget.parentContext,
          result.urls.join('\n'),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        busy = false;
        status = e.toString().replaceFirst('FormatException: ', '');
      });
    }
  }
}

class ZipPreviewDialog extends StatefulWidget {
  final DownloadItem item;

  const ZipPreviewDialog({super.key, required this.item});

  @override
  State<ZipPreviewDialog> createState() => _ZipPreviewDialogState();
}

class _ZipPreviewDialogState extends State<ZipPreviewDialog> {
  late Future<List<RemoteZipEntry>> future;

  @override
  void initState() {
    super.initState();
    future = RemoteZipInspector.inspect(widget.item);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Provider.of<ThemeProvider>(context).activeTheme;
    return AlertDialog(
      backgroundColor: theme.alertDialogTheme.backgroundColor,
      title: Text(
        'ZIP preview — ${widget.item.fileName}',
        style: TextStyle(color: theme.textColor),
      ),
      content: SizedBox(
        width: 660,
        height: 430,
        child: FutureBuilder<List<RemoteZipEntry>>(
          future: future,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return Center(
                child: Text(
                  snapshot.error
                      .toString()
                      .replaceFirst('FormatException: ', ''),
                  textAlign: TextAlign.center,
                  style: TextStyle(color: theme.textColor),
                ),
              );
            }
            final entries = snapshot.data ?? const <RemoteZipEntry>[];
            if (entries.isEmpty) {
              return Center(
                child: Text(
                  'Archive is empty.',
                  style: TextStyle(color: theme.textColor),
                ),
              );
            }
            return ListView.separated(
              itemCount: entries.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (_, index) {
                final entry = entries[index];
                return ListTile(
                  dense: true,
                  leading: Icon(
                    entry.isDirectory
                        ? Icons.folder_outlined
                        : Icons.insert_drive_file_outlined,
                    color: theme.widgetTheme.iconColor,
                  ),
                  title: Text(
                    entry.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: theme.textColor, fontSize: 13),
                  ),
                  trailing: entry.isDirectory
                      ? null
                      : Text(
                          convertByteToReadableStr(entry.uncompressedSize),
                          style: TextStyle(
                            color: theme.subtleTextColor,
                            fontSize: 12,
                          ),
                        ),
                );
              },
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
      ],
    );
  }
}
