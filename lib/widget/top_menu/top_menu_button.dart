import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:wdm/provider/theme_provider.dart';
import 'package:wdm/widget/legacy/legacy_palette.dart';

class TopMenuButton extends StatefulWidget {
  final String title;
  final Widget icon;
  final Color onHoverColor;
  final VoidCallback? onTap;
  final double fontSize;
  final bool isEnabled;

  const TopMenuButton({
    super.key,
    required this.title,
    required this.icon,
    this.onHoverColor = Colors.transparent,
    required this.onTap,
    this.fontSize = 13,
    required this.isEnabled,
  });

  @override
  State<TopMenuButton> createState() => _TopMenuButtonState();
}

class _TopMenuButtonState extends State<TopMenuButton> {
  bool hovered = false;

  @override
  Widget build(BuildContext context) {
    final light = Provider.of<ThemeProvider>(context).activeTheme.isLight;
    final width = (widget.title.length * 6.4 + 20).clamp(56.0, 82.0);
    return MouseRegion(
      onEnter: (_) => setState(() => hovered = true),
      onExit: (_) => setState(() => hovered = false),
      child: InkWell(
        onTap: widget.isEnabled ? widget.onTap : null,
        hoverColor: Colors.transparent,
        child: Container(
          width: width,
          height: 64,
          decoration: BoxDecoration(
            color: hovered && widget.isEnabled
                ? LegacyPalette.hover(light)
                : Colors.transparent,
            border: Border(
              bottom: BorderSide(
                width: 2,
                color: hovered && widget.isEnabled
                    ? LegacyPalette.accent(light)
                    : Colors.transparent,
              ),
            ),
          ),
          padding: const EdgeInsets.fromLTRB(5, 8, 5, 5),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SizedBox(
                height: 23,
                child: IconTheme(
                  data: IconThemeData(
                    size: 21,
                    color: widget.isEnabled
                        ? LegacyPalette.text2(light)
                        : LegacyPalette.text3(light).withValues(alpha: .45),
                  ),
                  child: widget.icon,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                widget.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: widget.fontSize,
                  height: 1,
                  color: widget.isEnabled
                      ? LegacyPalette.text(light)
                      : LegacyPalette.text3(light).withValues(alpha: .45),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
