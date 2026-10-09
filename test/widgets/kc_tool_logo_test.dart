// 数据栈新增的 AiToolType（OpenCode / Grok Build / Hermes / Pi / MiniMax Code）也要有可用的 logo 与短名。
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:key_core/models/mcp_server.dart';
import 'package:key_core/views/widgets/kc_logo.dart';

void main() {
  test('每个 AiToolType 的 logo 资源都存在、短名非空', () {
    for (final t in AiToolType.values) {
      final asset = kcToolLogoAsset(t);
      expect(File(asset).existsSync(), isTrue, reason: '$t → $asset');
      expect(kcToolShortName(t), isNotEmpty, reason: '$t');
    }
  });
}
