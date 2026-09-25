
## Windows build request follow-up

The available execution host is Linux. Flutter's `build_windows.dart` explicitly rejects non-Windows hosts, and no Windows build runner is connected. Therefore this request did not produce an executable. The earlier rejected Flutter bootstrap was not retried.

Added `Build-WDM.cmd` and `scripts/build-windows.ps1` so a configured Windows development PC can check prerequisites, run the supplied analysis/tests, compile the desktop release, and invoke Inno Setup in one sequence. Failed commands stop the sequence; a timestamped transcript is written to `build-logs/`. The installer builder now accepts the located Inno compiler path. These scripts were inspected, but have not been executed on Windows. The source archive remains version 2.0.1 alpha.
