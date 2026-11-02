import '../health/health_models.dart';
import '../health/health_snapshot_codec.dart';

/// 一次哭声发生时的上下文快照。
class CryContext {
  const CryContext({
    required this.at,
    required this.babyAgeMonths,
    this.sinceLastFeed,
    this.sinceLastSleepEnd,
    this.sinceLastDiaper,
    this.sinceLastBurp,
    this.isSleeping = false,
    this.health,
  });

  final DateTime at;
  final double babyAgeMonths;
  final Duration? sinceLastFeed;
  final Duration? sinceLastSleepEnd; // 醒着多久了
  final Duration? sinceLastDiaper;
  final Duration? sinceLastBurp;
  final bool isSleeping;

  /// 哭声时刻的健康快照（#1 PR-F）；老记录为 null。
  final HealthSnapshot? health;

  int get hourOfDay => at.hour;

  CryContext withHealth(HealthSnapshot? health) => CryContext(
        at: at,
        babyAgeMonths: babyAgeMonths,
        sinceLastFeed: sinceLastFeed,
        sinceLastSleepEnd: sinceLastSleepEnd,
        sinceLastDiaper: sinceLastDiaper,
        sinceLastBurp: sinceLastBurp,
        isSleeping: isSleeping,
        health: health,
      );

  Map<String, Object?> toJson() => {
        'at': at.toIso8601String(),
        'baby_age_months': babyAgeMonths,
        'since_feed_min': sinceLastFeed?.inMinutes,
        'since_wake_min': sinceLastSleepEnd?.inMinutes,
        'since_diaper_min': sinceLastDiaper?.inMinutes,
        'since_burp_min': sinceLastBurp?.inMinutes,
        'is_sleeping': isSleeping,
        'hour': hourOfDay,
        if (health != null) 'health': healthSnapshotToJson(health!),
      };

  factory CryContext.fromJson(Map<String, dynamic> json) {
    Duration? mins(Object? v) => v is num ? Duration(minutes: v.toInt()) : null;
    final at = DateTime.tryParse('${json['at']}') ?? DateTime.fromMillisecondsSinceEpoch(0);
    final age = json['baby_age_months'];
    return CryContext(
      at: at,
      babyAgeMonths: age is num ? age.toDouble() : 0,
      sinceLastFeed: mins(json['since_feed_min']),
      sinceLastSleepEnd: mins(json['since_wake_min']),
      sinceLastDiaper: mins(json['since_diaper_min']),
      sinceLastBurp: mins(json['since_burp_min']),
      isSleeping: json['is_sleeping'] == true,
      health: healthSnapshotFromJson(json['health']),
    );
  }
}
