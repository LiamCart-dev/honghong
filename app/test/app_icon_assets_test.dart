import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:honghong/core/widgets/app_icon.dart';

/// 每个 AppIcon 都必须有 1x/2x/3x 三档 PNG 和 SVG 源文件（含妈咪日记新增图标）。
void main() {
  test('所有 AppIcon 资源齐全', () {
    for (final icon in AppIcon.values) {
      for (final p in [
        'assets/icons/${icon.file}.png',
        'assets/icons/2.0x/${icon.file}.png',
        'assets/icons/3.0x/${icon.file}.png',
      ]) {
        expect(File(p).existsSync(), isTrue, reason: '缺少 $p');
      }
    }
  });

  test('妈咪日记图标已登记', () {
    expect(AppIcon.diary.asset, 'assets/icons/diary.png');
    expect(AppIcon.keyboard.asset, 'assets/icons/keyboard.png');
    expect(AppIcon.edit.asset, 'assets/icons/edit.png');
    for (final n in ['diary', 'keyboard', 'edit']) {
      expect(File('assets/icons/svg/$n.svg').existsSync(), isTrue);
    }
  });

  test('健康记录图标已登记', () {
    expect(AppIcon.healthTemp.asset, 'assets/icons/health_temp.png');
    expect(AppIcon.healthMed.asset, 'assets/icons/health_med.png');
    expect(AppIcon.healthSymptom.asset, 'assets/icons/health_symptom.png');
    for (final n in ['health_temp', 'health_med', 'health_symptom']) {
      expect(File('assets/icons/svg/$n.svg').existsSync(), isTrue);
      expect(File('assets/icons/2.0x/$n.png').existsSync(), isTrue);
      expect(File('assets/icons/3.0x/$n.png').existsSync(), isTrue);
    }
  });
}
