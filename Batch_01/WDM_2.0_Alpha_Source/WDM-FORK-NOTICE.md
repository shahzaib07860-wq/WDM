# WDM 2 source fork notice

WDM 2 is an independent fork of [Brisk](https://github.com/BrisklyDev/brisk), based on upstream desktop commit `517c669953f2e7f261aec45a96b0611d541313fe` (retrieved 2026-09-24). The Brisk desktop code is distributed under GPL-3.0; its license is included as `LICENSE`. The fork keeps the separately licensed dependencies and their license files intact. WDM is not affiliated with or endorsed by Brisk or IDM.

Fork modifications: WDM name and artwork, smaller default desktop window, always-visible light/dark toggle, separate Windows program/installer identity, optional installer autostart, WDM browser-extension protocol and local port, and an independently authored MV3 extension under `extension/`. The extension is the prior WDM extension carried forward; no code from the separate Brisk browser extension repository is included.

The inherited `brisk_download_engine` package retains its original package name and copyright. Any references to Brisk in that package, credits, historical platform packaging, or upstream source URLs identify upstream code. WDM's fork has no update feed yet. Do not use an upstream Brisk auto-updater with WDM.
