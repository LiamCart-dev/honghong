import 'package:flutter_test/flutter_test.dart';
import 'package:honghong/domain/health/health_config.dart';
import 'package:honghong/domain/health/health_models.dart';
import 'package:honghong/features/health/temp_input.dart';

void main() {
  group('filterTempInput', () {
    test('只留数字和一个小数点，最多 1 位', () {
      expect(filterTempInput('37.89'), '37.8');
      expect(filterTempInput('37..5'), '37.5');
      expect(filterTempInput('a3b7.c2'), '37.2');
      expect(filterTempInput(''), '');
    });
  });

  group('parseTempInput', () {
    test('空值', () {
      expect(parseTempInput('').issue!.kind, TempInputIssueKind.empty);
      expect(parseTempInput('').canSave, isFalse);
    });

    test('漏小数点 372 → 37.2', () {
      final r = parseTempInput('372');
      expect(r.issue!.kind, TempInputIssueKind.missingDecimal);
      expect(r.issue!.suggestionC, 37.2);
      expect(r.canSave, isFalse);
    });

    test('华氏 98.6 → 37.0', () {
      final r = parseTempInput('98.6');
      expect(r.issue!.kind, TempInputIssueKind.fahrenheit);
      expect(r.issue!.suggestionC, 37.0);
    });

    test('超出范围', () {
      final r = parseTempInput('33.0');
      expect(r.issue!.kind, TempInputIssueKind.outOfRange);
      expect(r.issue!.message, contains('34.0'));
    });

    test('合法读数', () {
      final r = parseTempInput('37.5');
      expect(r.canSave, isTrue);
      expect(r.celsius, 37.5);
    });
  });

  group('panelAlertForReading', () {
    test('腋温发烧建议就医', () {
      final a = panelAlertForReading(
        celsius: 37.5,
        site: TempSite.armpit,
        ageDays: 128,
        at: DateTime(2026, 11, 2, 12),
      );
      expect(a.text, kHealthConfig.copy.panelFeverAxillary);
      expect(a.emergency, isFalse);
    });

    test('未满 3 月发烧请尽快就医', () {
      final a = panelAlertForReading(
        celsius: 37.5,
        site: TempSite.armpit,
        ageDays: 42,
        at: DateTime(2026, 11, 2, 12),
      );
      expect(a.text, kHealthConfig.copy.panelUrgentUnder3mo);
    });

    test('正常读数无提示', () {
      final a = panelAlertForReading(
        celsius: 36.6,
        site: TempSite.armpit,
        ageDays: 128,
        at: DateTime(2026, 11, 2, 12),
      );
      expect(a.text, isNull);
    });
  });
}
