import 'package:hive_ce/hive.dart';

part 'larm_timer.g.dart';

/// Timer status encoding stored in [LarmTimer.status].
abstract final class TimerStatus {
  static const int idle = 0;
  static const int running = 1;
  static const int paused = 2;
  static const int done = 3;
}

@HiveType(typeId: 1)
class LarmTimer extends HiveObject {
  LarmTimer({
    required this.id,
    required this.title,
    required this.durationSec,
    required this.remainingSec,
    required this.status,
    this.targetUtc,
    required this.enabled,
  });

  @HiveField(0)
  String id;

  @HiveField(1)
  String title;

  @HiveField(2)
  int durationSec;

  @HiveField(3)
  int remainingSec;

  @HiveField(4)
  int status;

  /// Exact completion instant while running; null otherwise.
  @HiveField(5)
  DateTime? targetUtc;

  @HiveField(6)
  bool enabled;
}
