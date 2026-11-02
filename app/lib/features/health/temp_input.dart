/// 体温输入过滤与校验（纯 Dart，无 Flutter）。
library;

import 'package:honghong/domain/health/health_config.dart';
import 'package:honghong/domain/health/health_models.dart';
import 'package:honghong/domain/health/medical_alert.dart';

/// 只保留数字和一个小数点，最多 1 位小数。
String filterTempInput(String raw) {
  final buf = StringBuffer();
  var seenDot = false;
  var decimals = 0;
  for (final r in raw.runes) {
    final ch = String.fromCharCode(r);
    if (ch.compareTo('0') >= 0 && ch.compareTo('9') <= 0) {
      if (seenDot) {
        if (decimals >= 1) continue;
        decimals++;
      }
      buf.write(ch);
    } else if (ch == '.' && !seenDot) {
      seenDot = true;
      buf.write(ch);
    }
  }
  return buf.toString();
}

enum TempInputIssueKind {
  empty,
  missingDecimal,
  fahrenheit,
  outOfRange,
}

class TempInputIssue {
  const TempInputIssue({
    required this.kind,
    this.suggestionC,
    this.message,
  });
  final TempInputIssueKind kind;
  final double? suggestionC;
  final String? message;
}

class TempInputResult {
  const TempInputResult.ok(this.celsius) : issue = null;
  const TempInputResult.bad(this.issue) : celsius = null;
  final double? celsius;
  final TempInputIssue? issue;
  bool get canSave => issue == null && celsius != null;
}

TempInputResult parseTempInput(String text, {HealthConfig config = kHealthConfig}) {
  final t = text.trim();
  if (t.isEmpty || t == '.' || t == '--.-') {
    return const TempInputResult.bad(TempInputIssue(kind: TempInputIssueKind.empty));
  }

  final hasDot = t.contains('.');
  final v = double.tryParse(t);
  if (v == null) {
    return const TempInputResult.bad(TempInputIssue(kind: TempInputIssueKind.empty));
  }

  final range = config.recordableC;
  final fRange = config.fahrenheitGuess;

  // 漏小数点：三位整数 340–425 → 34.0–42.5
  if (!hasDot && v == v.roundToDouble() && v >= 340 && v <= 425) {
    final suggested = double.parse((v / 10).toStringAsFixed(1));
    return TempInputResult.bad(TempInputIssue(
      kind: TempInputIssueKind.missingDecimal,
      suggestionC: suggested,
      message: '是不是 ${suggested.toStringAsFixed(1)}℃？',
    ));
  }

  // 华氏识别
  if (fRange != null && v >= fRange.lo && v <= fRange.hi) {
    final c = double.parse((((v - 32) * 5 / 9)).toStringAsFixed(1));
    return TempInputResult.bad(TempInputIssue(
      kind: TempInputIssueKind.fahrenheit,
      suggestionC: c,
      message: config.copy.fahrenheitGuessHint.replaceFirst('37.0', c.toStringAsFixed(1)),
    ));
  }

  if (range != null && (v < range.lo || v > range.hi)) {
    return TempInputResult.bad(TempInputIssue(
      kind: TempInputIssueKind.outOfRange,
      message: config.copy.recordableOutOfRange,
    ));
  }

  final c = double.parse(v.toStringAsFixed(1));
  return TempInputResult.ok(c);
}

/// 面板 AlertBox 文案：优先 MedicalAlert；非急症偏低用 [panelLowTempHint]。
/// 返回 (text, showEmergencyLine)。
({String? text, bool emergency}) panelAlertForReading({
  required double celsius,
  required TempSite site,
  required int ageDays,
  required DateTime at,
  HealthConfig config = kHealthConfig,
}) {
  final snap = HealthSnapshot(
    at: at,
    temps: [TempReading(at: at, celsius: celsius, site: site)],
  );
  final alert = MedicalAlert.evaluate(snapshot: snap, ageDays: ageDays, config: config);
  if (alert.level != MedicalAlertLevel.none && alert.reasons.isNotEmpty) {
    final u4 = alert.reasons.any((r) => r.code == 'U4');
    return (text: alert.reasons.first.label, emergency: u4);
  }
  if (celsius < 36.0) {
    return (text: config.copy.panelLowTempHint, emergency: false);
  }
  return (text: null, emergency: false);
}

String tempSiteLabel(TempSite s) => switch (s) {
      TempSite.armpit => '腋温',
      TempSite.rectal => '肛温',
    };
