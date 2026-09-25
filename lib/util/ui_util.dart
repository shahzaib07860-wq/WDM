import 'package:flutter/cupertino.dart';

void safePop(BuildContext context) {
  if (Navigator.of(context).canPop()) {
    Navigator.of(context).pop();
  }
}

const double legacyMenuBarHeight = 35;
const double topMenuHeight = 64;
const double legacyStatusBarHeight = 31;
const double minimizedSideMenuWidth = 174;

double resolveWindowWidth(Size size) {
  return size.width - minimizedSideMenuWidth;
}

bool minimizedSideMenu(Size size) => false;
