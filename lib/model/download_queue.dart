import 'package:hive/hive.dart';

part 'download_queue.g.dart';

@HiveType(typeId: 1)
class DownloadQueue extends HiveObject {
  @HiveField(0)
  String name;

  @HiveField(1)
  List<int>? downloadItemsIds;

  @HiveField(2)
  DateTime? scheduledStart;

  @HiveField(3)
  DateTime? scheduledEnd;

  @HiveField(4, defaultValue: false)
  bool shutdownAfterCompletion;

  @HiveField(5, defaultValue: 1)
  int simultaneousDownloads;

  @HiveField(6, defaultValue: false)
  bool scheduleEnabled;

  DownloadQueue({
    required this.name,
    this.downloadItemsIds,
    this.shutdownAfterCompletion = false,
    this.simultaneousDownloads = 1,
    this.scheduleEnabled = false,
  });
}
