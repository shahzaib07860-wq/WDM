import 'package:wdm/browser_extension/browser_extension_server.dart';
import 'package:wdm/l10n/app_localizations.dart';
import 'package:wdm/provider/theme_provider.dart';
import 'package:wdm/widget/base/rounded_outlined_button.dart';
import 'package:wdm/widget/base/scrollable_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_spinkit/flutter_spinkit.dart';
import 'package:provider/provider.dart';

class AutomaticUrlUpdateDialog extends StatelessWidget {
  const AutomaticUrlUpdateDialog({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Provider.of<ThemeProvider>(context).activeTheme;
    final loc = AppLocalizations.of(context)!;
    return ScrollableDialog(
      scrollButtonVisible: false,
      scrollviewHeight: 200,
      height: 120,
      width: 430,
      backgroundColor: theme.alertDialogTheme.backgroundColor,
      title: Padding(
        padding: const EdgeInsets.all(15),
        child: Row(
          children: [
            SpinKitRing(color: Colors.blueAccent, size: 30),
            const SizedBox(width: 10),
            Text(
              loc.awaitingUrl,
              style: TextStyle(
                color: theme.textColor,
                fontWeight: FontWeight.bold,
                fontSize: 20,
              ),
            ),
          ],
        ),
      ),
      content: Padding(
        padding: EdgeInsets.all(15),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              loc.awaitingUrl_description,
              style: TextStyle(
                color: theme.textHintColor,
              ),
            ),
            const SizedBox(height: 5),
            Text(
              loc.awaitingUrl_descriptionHint,
              style: TextStyle(
                color: theme.textHintColor,
              ),
            )
          ],
        ),
      ),
      buttons: [
        RoundedOutlinedButton.fromButtonColor(
          theme.alertDialogTheme.deleteConfirmColor,
          text: loc.btn_cancel,
          onPressed: () {
            BrowserExtensionServer.awaitingUpdateUrlItem = null;
            Navigator.of(context).pop();
          },
        ),
      ],
    );
  }
}
