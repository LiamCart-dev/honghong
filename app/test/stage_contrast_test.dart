import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:honghong/core/theme/app_theme.dart';

import 'stage_tip_test.dart' as tip;

/// WCAG 2.1 相对亮度
double _lum(Color c) {
  double ch(double v) => v <= 0.04045 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
  return 0.2126 * ch(c.r) + 0.7152 * ch(c.g) + 0.0722 * ch(c.b);
}

/// WCAG 2.1 对比度（1–21）；前景/背景都按不透明处理
double contrastRatio(Color a, Color b) {
  final la = _lum(a), lb = _lum(b);
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
}

void main() {
  group('WCAG 对比度计算本身', () {
    test('黑白 21:1，同色 1:1', () {
      expect(contrastRatio(Colors.black, Colors.white), closeTo(21, 0.01));
      expect(contrastRatio(Colors.white, Colors.white), closeTo(1, 0.001));
    });
    test('#34 的旧配色（白字配 #FF9874）约 2.1:1，不达标', () {
      expect(contrastRatio(Colors.white, const Color(0xFFFF9874)), closeTo(2.1, 0.05));
    });
  });

  group('急症提示（alertInk / alertBg）对比度 ≥ 4.5:1（#34）', () {
    for (final (name, theme) in [('日间', AppTheme.day), ('夜间', AppTheme.night)]) {
      test('$name主题 token', () {
        final hh = theme.extension<Hh>()!;
        expect(hh.alertBg.a, 1.0, reason: '底色必须不透明，否则实际对比度取决于下层');
        expect(hh.alertInk.a, 1.0);
        expect(contrastRatio(hh.alertInk, hh.alertBg), greaterThanOrEqualTo(4.5));
      });
    }

    for (final night in [false, true]) {
      testWidgets('说明面板里实际渲染的急症提示 ≥ 4.5:1（${night ? '夜间' : '日间'}）', (tester) async {
        await tip.pumpEmergencyLine(tester, night: night);
        final box = tester.widget<Container>(find.byKey(const Key('stage-emergency')));
        final bg = (box.decoration! as BoxDecoration).color!;
        final text = tester.widget<Text>(
          find.descendant(of: find.byKey(const Key('stage-emergency')), matching: find.byType(Text)),
        );
        final fg = text.style!.color!;
        final hh = (night ? AppTheme.night : AppTheme.day).extension<Hh>()!;
        expect(bg, hh.alertBg);
        expect(fg, hh.alertInk);
        expect(contrastRatio(fg, bg), greaterThanOrEqualTo(4.5));
        expect(text.style!.fontWeight, FontWeight.w700); // 仍然醒目
        await tip.closeEmergencyLine(tester);
      });
    }
  });
}
