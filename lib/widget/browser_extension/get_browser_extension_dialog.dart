import 'package:wdm/provider/theme_provider.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class GetBrowserExtensionDialog extends StatelessWidget {
  const GetBrowserExtensionDialog({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Provider.of<ThemeProvider>(context).activeTheme;
    return AlertDialog(
      backgroundColor: theme.alertDialogTheme.backgroundColor,
      title: Text('WDM browser extension', style: TextStyle(color: theme.textColor)),
      content: SizedBox(
        width: 430,
        child: Text(
          'In Chrome, Edge, or Brave, open Extensions, enable Developer mode, '
          'then choose Load unpacked and select the extension folder beside '
          'the installed WDM application. Keep WDM open while downloading. '
          'The extension can detect media and send downloads to WDM.',
          style: TextStyle(color: theme.textColor, fontSize: 15, height: 1.4),
        ),
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Got it'))],
    );
  }
}
