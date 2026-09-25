import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:wdm/constants/file_type.dart';
import 'package:path/path.dart' as path;
import 'package:provider/provider.dart';
import 'package:wdm/provider/download_request_provider.dart';

import 'package:wdm/constants/setting_options.dart';
import 'package:wdm/constants/setting_type.dart';
import 'package:wdm/db/hive_util.dart';
import 'package:wdm/l10n/app_localizations.dart';
import 'package:wdm/model/download_item.dart';
import 'package:wdm/model/setting.dart';
import 'package:wdm/util/app_logger.dart';
import 'package:wdm/util/auto_updater_util.dart';
import 'package:wdm/util/download_addition_ui_util.dart';
import 'package:wdm/util/file_util.dart';
import 'package:wdm/util/http_util.dart';
import 'package:wdm/util/parse_util.dart';
import 'package:wdm/setting/settings_cache.dart';
import 'package:wdm/util/ui_util.dart';
import 'package:wdm/widget/base/error_dialog.dart';
import 'package:wdm/widget/download/m3u8_master_playlist_dialog.dart';
import 'package:wdm/widget/download/update_available_dialog.dart';
import 'package:wdm/widget/loader/file_info_loader.dart';
import 'package:brisk_download_engine/brisk_download_engine.dart';
import 'package:brisk_download_engine/src/download_engine/client/custom_base_client.dart';
import 'package:dartx/dartx.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher_string.dart';
import 'package:window_to_front/window_to_front.dart';
import 'package:window_manager/window_manager.dart';
import 'package:wdm/widget/download/multi_download_addition_dialog.dart';

class BrowserExtensionServer {
  static bool _cancelClicked = false;
  static Future<void> _persistTail = Future<void>.value();
  static const String extensionVersion = "2.0.1";
  static DownloadItem? awaitingUpdateUrlItem;
  static HttpServer? _server;

  /// A map of prefetch vtt and m3u8 data by tabId coming form the extension
  static Map<int, List<M3U8>> _m3u8PrefetchCache = {};
  static Map<int, Map<String, String>> vttPrefetchCache = {};
  static Map<int, List<Pair<String, String>>> _fetchedVtts = {};
  static Timer? _m3u8PrefetchCacheClearTimer;

  /// To be able to reuse the http client, cached vtts will try be fetched every
  /// 3 seconds and the first pair argument determines how many times the timer
  /// should run in total.
  static Map<int, Pair<int, Timer?>> _vttFetcherTimers = {};

  static Future<void> setup(BuildContext context) async {
    if (_server != null) return;
    _m3u8PrefetchCacheClearTimer = Timer.periodic(
      Duration(minutes: 5),
      (_) => _m3u8PrefetchCache.clear(),
    );

    final port = _extensionPort;
    try {
      _server = await HttpServer.bind(InternetAddress.loopbackIPv4, port);
      handleExtensionRequests(context);
    } catch (e) {
      if (e.toString().contains("Invalid port")) {
        _showInvalidPortError(context, port.toString());
        return;
      }
      if (e.toString().contains("Only one usage of each socket address")) {
        _showPortInUseError(context, port.toString());
        return;
      }
      _showUnexpectedError(context, port.toString(), e);
    }
  }

  static Future<void> restart(BuildContext context) async {
    _vttFetcherTimers.clear();
    vttPrefetchCache.clear();
    _m3u8PrefetchCache.clear();
    _m3u8PrefetchCacheClearTimer?.cancel();
    _m3u8PrefetchCacheClearTimer = null;
    _vttFetcherTimers.forEach((_, value) => value.second?.cancel());
    await _server?.close(force: true);
    _server = null;
    await Future.delayed(Duration(milliseconds: 300));
    await setup(context);
  }

  static Future<void> handleExtensionRequests(BuildContext context) async {
    await for (HttpRequest request in _server!) {
      runZonedGuarded(
        () async {
          bool responseClosed = false;
          try {
            addCORSHeaders(request);
            final origin = request.headers.value(HttpHeaders.originHeader);
            if (origin != null &&
                !origin.startsWith('chrome-extension://') &&
                !origin.startsWith('moz-extension://')) {
              request.response.statusCode = HttpStatus.forbidden;
              await request.response.close();
              return;
            }
            if (request.method == 'OPTIONS') {
              request.response.statusCode = HttpStatus.noContent;
              await request.response.close();
              return;
            }
            if (request.method == 'GET' && request.uri.path == '/wdm-health') {
              await sendResponse(request, {'ok': true, 'app': 'WDM 2'});
              return;
            }
            if (request.method == 'POST' && request.uri.path == '/wdm-open') {
              await windowManager.show();
              await WindowToFront.activate();
              await sendResponse(request, {'ok': true});
              return;
            }
            if (request.method != 'POST' ||
                request.headers.contentType?.mimeType != 'application/json') {
              request.response.statusCode = HttpStatus.methodNotAllowed;
              await request.response.close();
              return;
            }
            final jsonBody = await _jsonifyBody(request);
            if (jsonBody is! Map<String, dynamic>) {
              await flushAndCloseResponse(request, false);
              return;
            }
            final targetVersion = jsonBody["extensionVersion"];
            if (targetVersion == null ||
                targetVersion.toString().isNullOrBlank) {
              await request.response.close();
              responseClosed = true;
              return;
            }
            // This fork ships its own extension; never offer upstream updates.
            if (request.uri.path == '/fetch-m3u8') {
              _fetchAndCacheM3u8(request, jsonBody);
              return;
            }
            if (request.uri.path == '/fetch-vtt') {
              _fetchAndCacheVtt(request, jsonBody);
              return;
            }
            final success = await _handleDownloadAddition(
              jsonBody,
              context,
              request,
            );
            await flushAndCloseResponse(request, success);
            responseClosed = true;
          } catch (e, stack) {
            Logger.log("Request handling error: $e\n$stack");
            try {
              Logger.log("responseClosed? $responseClosed");
              if (!responseClosed) {
                Logger.log("Closing response...");
                await flushAndCloseResponse(request, false);
              }
            } catch (_) {}
          }
        },
        (error, stack) {
          if (error == "Failed to get file information") {
            DownloadAdditionUiUtil.showFileInfoErrorDialog(context);
            flushAndCloseResponse(request, false);
            return;
          }
          Logger.log("Unhandled error in request zone: $error\n$stack");
        },
      );
    }
  }

  static dynamic _jsonifyBody(HttpRequest request) async {
    if (request.contentLength > 1024 * 1024) return null;
    final bodyBytes = await request.fold<List<int>>([], (previous, element) {
      if (previous.length + element.length > 1024 * 1024) {
        throw const FormatException('Extension request exceeds 1 MiB');
      }
      return previous..addAll(element);
    });
    final body = utf8.decode(bodyBytes);
    if (body.isEmpty) {
      return null;
    }
    return jsonDecode(body);
  }

  static void _fetchAndCacheVtt(HttpRequest request, jsonBody) async {
    final tabId = jsonBody['tabId'];
    vttPrefetchCache[tabId] ??= {};
    _fetchedVtts[tabId] ??= [];
    vttPrefetchCache[tabId]!.addAll({jsonBody['url']: jsonBody['referer']});
    if (_vttFetcherTimers[tabId] == null) {
      final client = await HttpClientBuilder.buildClient(
        SettingsCache.clientSettings,
      );
      _vttFetcherTimers[tabId] ??= Pair(
        1,
        Timer.periodic(
          Duration(seconds: 3),
          (timer) => _fetchAndCacheVttSubtitles(tabId, timer, client),
        ),
      );
    }
    await flushAndCloseResponse(request, true);
  }

  static void _fetchAndCacheVttSubtitles(
    tabId,
    Timer timer,
    CustomBaseClient client,
  ) {
    if (_vttFetcherTimers[tabId]!.first > 2) {
      timer.cancel();
    }
    vttPrefetchCache.forEach((tabId, vtts) {
      vtts.forEach((url, referer) {
        final alreadyFetched = _fetchedVtts[tabId]!.any(
          (pair) => pair.first == url,
        );
        if (alreadyFetched) {
          return;
        }
        final uri = Uri.parse(url);
        final headers = {
          'referer': referer ?? '',
          'User-Agent': userAgentHeader.values.first,
        };
        client.get(uri, headers: headers).then((response) {
          if (response.statusCode == 200) {
            _fetchedVtts[tabId]!.add(Pair(url, response.body));
          }
        });
      });
    });
    _vttFetcherTimers[tabId] = Pair(_vttFetcherTimers[tabId]!.first + 1, timer);
  }

  static void _fetchAndCacheM3u8(request, jsonBody) async {
    final url = jsonBody['url'];
    final referer = jsonBody['referer'];
    final suggestedName = jsonBody['suggestedName'];
    final tabId = jsonBody['tabId'];
    M3U8 m3u8;
    try {
      m3u8 = await _downloadAndParseM3u8Meta(
        url,
        refererHeader: referer,
        suggestedName: suggestedName,
        requestHeaders: _requestHeaders(jsonBody['headers'], referer),
      );
    } catch (e) {
      flushAndCloseResponse(request, false);
      return;
    }
    final responseBody = {};
    _m3u8PrefetchCache[tabId] = [];
    _m3u8PrefetchCache[tabId]!.add(m3u8);
    if (m3u8.isMasterPlaylist) {
      m3u8.setStreamInfsResolutionFileName();
      for (final streamInf in m3u8.streamInfos) {
        if (streamInf.m3u8 != null) {
          _m3u8PrefetchCache[tabId]!.add(streamInf.m3u8!);
        }
      }
      final streamInfs = m3u8.streamInfos
          .map(
            (s) => {
              'url': s.m3u8!.url,
              'resolution': s.resolution,
              'fileName': s.m3u8!.fileName,
            },
          )
          .toList();
      responseBody['streamInfs'] = streamInfs;
    }
    responseBody['referer'] = referer;
    responseBody['isMasterPlaylist'] = m3u8.isMasterPlaylist;
    responseBody['fileName'] = m3u8.fileName;
    responseBody['url'] = m3u8.url;
    responseBody['captured'] = true;
    await sendResponse(request, responseBody);
  }

  static void showNewBrowserExtensionVersion(BuildContext context) async {
    var lastNotify = HiveUtil.getSetting(
      SettingOptions.lastBrowserExtensionUpdateNotification,
    );
    if (lastNotify == null) {
      lastNotify = Setting(
        name: "lastBrowserExtensionUpdateNotification",
        value: "0",
        settingType: SettingType.system.name,
      );
      await HiveUtil.instance.settingBox.add(lastNotify);
    }
    if (int.parse(lastNotify.value) + 86400000 >
        DateTime.now().millisecondsSinceEpoch) {
      return;
    }
    final changeLog = await getLatestVersionChangeLog(
      browserExtension: true,
      removeChangeLogHeader: true,
    );
    showDialog(
      barrierDismissible: false,
      context: context,
      builder: (context) => UpdateAvailableDialog(
        isBrowserExtension: true,
        newVersion: extensionVersion,
        changeLog: changeLog,
        onUpdatePressed: () => launchUrlString(
          "https://github.com/AminBhst/brisk-browser-extension",
        ),
        onLaterPressed: () {
          lastNotify!.value = DateTime.now().millisecondsSinceEpoch.toString();
          lastNotify.save();
        },
      ),
    );
  }

  static Future<bool> _handleDownloadAddition(
    jsonBody,
    context,
    request,
  ) async {
    final type = jsonBody["type"] as String;
    switch (type.toLowerCase()) {
      case "single":
        return _handleSingleDownloadRequest(jsonBody, context, request);
      case "multi":
        // This protocol acknowledges only individually persisted jobs.
        return false;
      case "m3u8":
        return await _handleM3u8DownloadRequest(jsonBody, context, request);
      default:
        return false;
    }
  }

  static Future<bool> _handleM3u8DownloadRequest(
    jsonBody,
    context,
    request,
  ) async {
    final root = await _fetchM3u8(jsonBody, context);
    if (root == null) return false;
    final variants = root.isMasterPlaylist
        ? root.streamInfos.map((v) => v.m3u8).whereType<M3U8>().toList()
        : <M3U8>[root];
    // Browser capture chooses the first playable variant; it must be persisted
    // before the browser is told that it can relinquish its download.
    final playable = variants.where((v) => v.segments.isNotEmpty).toList();
    if (playable.isEmpty) return false;
    final media = playable.first;
    if (media.encryptionDetails.encryptionMethod ==
        M3U8EncryptionMethod.sampleAes) {
      return false;
    }
    final item = DownloadItem.fromUrl(media.url)
      ..fileName = '${path.basenameWithoutExtension(media.fileName)}.ts'
      ..downloadType = 'M3U8'
      ..fileType = DLFileType.video.name
      ..supportsPause = true
      ..contentLength = -1
      ..requestHeaders = Map<String, String>.from(media.requestHeaders)
      ..extraInfo = {
        'duration': media.totalDuration,
        'm3u8Content': media.stringContent,
        'refererHeader': media.refererHeader,
      };
    return _persistBrowserDownload(item, context);
  }

  static Future<M3U8?> _fetchM3u8(jsonBody, context) async {
    final url = jsonBody['m3u8Url'];
    if (url is! String ||
        !['http', 'https'].contains(Uri.tryParse(url)?.scheme))
      return null;
    final referer = jsonBody['refererHeader'] as String?;
    var name = jsonBody['suggestedName'] as String?;
    if (FileUtil.isFileNameInvalid(name) || name == '') name = null;
    return _downloadAndParseM3u8Meta(
      url,
      refererHeader: referer,
      suggestedName: name,
      requestHeaders: _requestHeaders(jsonBody['headers'], referer),
    );
  }

  /// Fetches the subtitles from the prefetched cache and if empty, downloads them
  static Future<List<Map<String, String>>> _fetchVttSubtitles(
    jsonBody,
    context,
  ) async {
    final tabId = jsonBody['tabId'];
    List<Pair<String, String>>? subtitles = _fetchedVtts[tabId];
    bool foundInCache = true;
    if (_fetchedVtts[tabId] == null || _fetchedVtts[tabId]!.isEmpty) {
      foundInCache = false;
      final List<Map<String, String>> vttUrls =
          (jsonBody['vttUrls'] as List?)
              ?.map(
                (item) => (item as Map).map<String, String>(
                  (key, value) =>
                      MapEntry(key.toString(), value?.toString() ?? ""),
                ),
              )
              .toList() ??
          [];
      try {
        _showLoadingDialog(
          context,
          customMessage: AppLocalizations.of(context)!.fetchingSubtitles,
        );
        subtitles = await fetchSubtitlesIsolate(
          vttUrls,
          SettingsCache.clientSettings,
        );
      } catch (e) {
        Logger.log("Failed to fetch subs ${e}");
      }
    }
    if (!foundInCache) {
      safePop(context);
    }
    return subtitles
            ?.map((p) => {'url': p.first, 'content': p.second})
            .toList() ??
        [];
  }

  static Future<M3U8> _downloadAndParseM3u8Meta(
    String url, {
    String? refererHeader,
    String? suggestedName,
    Map<String, String> requestHeaders = const {},
  }) async {
    return (await M3U8.fromUrl(
      url,
      clientSettings: SettingsCache.clientSettings,
      refererHeader: refererHeader,
      suggestedFileName: suggestedName,
      requestHeaders: requestHeaders,
    ))!;
  }

  static void _handleMasterPlaylist(
    M3U8 m3u8,
    BuildContext context,
    List<Map<String, String>> subtitles,
  ) {
    showDialog(
      context: context,
      builder: (context) =>
          M3u8MasterPlaylistDialog(m3u8: m3u8, subtitles: subtitles),
      barrierDismissible: false,
    );
  }

  static Future<void> sendResponse(HttpRequest request, body) async {
    try {
      final responseBody = jsonEncode(body);
      request.response.write(responseBody);
      await request.response.flush();
      await request.response.close();
    } catch (_) {
      try {
        await request.response.close();
      } catch (_) {}
    }
  }

  static Future<void> flushAndCloseResponse(
    HttpRequest request,
    bool success,
  ) async {
    return await sendResponse(request, {
      "captured": success,
      "accepted": success,
    });
  }

  static void addCORSHeaders(HttpRequest httpRequest) {
    final origin = httpRequest.headers.value(HttpHeaders.originHeader);
    if (origin != null &&
        (origin.startsWith('chrome-extension://') ||
            origin.startsWith('moz-extension://'))) {
      httpRequest.response.headers.set('Access-Control-Allow-Origin', origin);
    }
    httpRequest.response.headers.set(
      'Access-Control-Allow-Headers',
      'Content-Type',
    );
    httpRequest.response.headers.set(
      'Access-Control-Allow-Methods',
      'GET, POST, OPTIONS',
    );
  }

  static void _handleMultiDownloadRequest(jsonBody, context, request) {
    List downloadHrefs = jsonBody["data"]["downloadHrefs"];
    final referer = jsonBody['data']['referer'];
    if (downloadHrefs.isEmpty) return;
    downloadHrefs =
        downloadHrefs
            .toSet()
            .toList() // removes duplicates
          ..removeWhere((url) => !isUrlValid(url));
    final downloadItems = downloadHrefs
        .map((e) => DownloadItem.fromUrl(e))
        .toList();
    downloadItems.forEach((item) => item.referer = referer);
    _cancelClicked = false;
    _showLoadingDialog(context);
    requestFileInfoBatch(downloadItems.toList(), SettingsCache.clientSettings)
        .then((fileInfos) {
          if (_cancelClicked) {
            return;
          }
          fileInfos?.removeWhere(
            (fileInfo) => SettingsCache.extensionSkipCaptureRules.any(
              (rule) => rule.isSatisfiedByFileInfo(fileInfo),
            ),
          );
          handleWindowToFront();
          safePop(context);
          showDialog(
            context: context,
            barrierDismissible: false,
            builder: (_) => MultiDownloadAdditionDialog(fileInfos!),
          );
        })
        .onError(
          (error, stackTrace) =>
              DownloadAdditionUiUtil.onFileInfoRetrievalError(context),
        );
  }

  static void handleWindowToFront() {
    if (_windowToFrontEnabled) {
      windowManager.show().then((_) => WindowToFront.activate());
    }
  }

  static void _showLoadingDialog(context, {String? customMessage}) {
    showDialog(
      barrierDismissible: false,
      context: context,
      builder: (_) => FileInfoLoader(
        message: customMessage,
        onCancelPressed: () {
          _cancelClicked = true;
          safePop(context);
        },
      ),
    );
  }

  static Map<String, String> _requestHeaders(
    dynamic supplied,
    dynamic referer,
  ) {
    final headers = <String, String>{};
    if (supplied is Map) {
      for (final entry in supplied.entries) {
        final name = entry.key.toString().toLowerCase();
        if ([
              'authorization',
              'cookie',
              'user-agent',
              'accept',
              'accept-language',
              'referer',
            ].contains(name) &&
            entry.value is String &&
            !(entry.value as String).contains(RegExp(r'[\r\n]'))) {
          headers[name] = entry.value as String;
        }
      }
    }
    if (referer is String &&
        referer.startsWith(RegExp(r'https?://')) &&
        !referer.contains(RegExp(r'[\r\n]')))
      headers['referer'] = referer;
    return headers;
  }

  static Future<bool> _handleSingleDownloadRequest(
    jsonBody,
    context,
    request,
  ) async {
    final data = jsonBody['data'];
    final url = data['url'];
    if (url is! String ||
        !['http', 'https'].contains(Uri.tryParse(url)?.scheme)) {
      return false;
    }
    final headers = _requestHeaders(data['headers'], data['referer']);
    final cookie = data['cookie'];
    if (cookie is String && !cookie.contains(RegExp(r'[\r\n]')))
      headers['cookie'] = cookie;
    final fileInfo = await DownloadAdditionUiUtil.requestFileInfo(
      url,
      headers: headers,
    );
    if (SettingsCache.extensionSkipCaptureRules.any(
      (rule) => rule.isSatisfiedByFileInfo(fileInfo),
    )) {
      return false;
    }
    final item = DownloadItem.fromUrl(url)
      ..requestHeaders = headers
      ..referer = data['referer']
      ..supportsPause = fileInfo.supportsPause
      ..contentLength = fileInfo.contentLength
      ..fileName = path.basename(fileInfo.fileName)
      ..fileType = FileUtil.detectFileType(fileInfo.fileName).name;
    return _persistBrowserDownload(item, context);
  }

  static Future<bool> _persistBrowserDownload(
    DownloadItem item,
    BuildContext context,
  ) async {
    final previous = _persistTail;
    final done = Completer<void>();
    _persistTail = done.future;
    await previous;
    try {
      if (FileUtil.isFileNameInvalid(item.fileName)) return false;
      final rule = SettingsCache.fileSavePathRules.firstOrNullWhere(
        (rule) => rule.isSatisfiedByDownloadItem(item),
      );
      item.filePath = FileUtil.getFilePath(
        item.fileName,
        baseSaveDir: rule == null ? null : Directory(rule.savePath),
        useTypeBasedSubDirs:
            rule == null && SettingsCache.automaticFileSavePathCategorization,
      );
      item.fileName = path.basename(item.filePath);
      await HiveUtil.instance.addDownloadItem(item);
      await HiveUtil.instance.downloadItemsBox.flush();
      await HiveUtil.instance.downloadQueueBox.flush();
      // UI failures must not turn a durably accepted job into a rejection.
      try {
        Provider.of<DownloadRequestProvider>(
          context,
          listen: false,
        ).addRequest(item);
        handleWindowToFront();
      } catch (e) {
        Logger.log('Download queued; UI refresh failed: $e');
      }
      return true;
    } finally {
      done.complete();
    }
  }

  static int get _extensionPort => int.parse(
    HiveUtil.getSetting(SettingOptions.extensionPort)?.value ?? "3021",
  );

  static bool get _windowToFrontEnabled => parseBool(
    HiveUtil.getSetting(SettingOptions.enableWindowToFront)?.value ?? "true",
  );

  static void _showPortInUseError(BuildContext context, String port) {
    showDialog(
      context: context,
      builder: (context) => ErrorDialog(
        width: 580,
        height: 160,
        textHeight: 70,
        title: "Port ${port} is already in use by another process!",
        description:
            "\nFor optimal browser integration, please change the extension port in [Settings->Extension->Port] then restart the app."
            " Finally, set the same port number for the browser extension by clicking on its icon.",
      ),
    );
  }

  static void _showInvalidPortError(BuildContext context, String port) {
    showDialog(
      context: context,
      builder: (context) => ErrorDialog(
        width: 400,
        height: 120,
        textHeight: 20,
        textSpaceBetween: 18,
        title: "Port $port is invalid!",
        description: "Please set a valid port value in app settings, then set the same value for the browser extension",
      ),
    );
  }

  static void _showUnexpectedError(BuildContext context, String port, e) {
    showDialog(
      context: context,
      builder: (context) => ErrorDialog(
        width: 750,
        height: 200,
        textHeight: 40,
        textSpaceBetween: 10,
        title: "Failed to listen to port $port! ${e.runtimeType}",
        description: e.toString(),
      ),
    );
  }
}
