// 基础冒烟测试：验证本地化在中英文下均可回退到内置翻译。
//
// 原文件是 `flutter create` 生成的计数器模板，引用了不存在的
// `package:ai_key_manager/main.dart` 和 `MyApp`，会导致整个测试套件
// 编译失败（并连带使同批次的其他测试文件加载失败）。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:key_core/utils/app_localizations.dart';

void main() {
  test('AppLocalizations falls back to built-in zh/en strings', () {
    final zh = AppLocalizations(const Locale('zh'));
    final en = AppLocalizations(const Locale('en'));
    expect(zh.settings, '设置');
    expect(en.settings, 'Settings');
  });
}
