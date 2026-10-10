import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 防止代码或配置里引用了不存在的供应商图标文件（例如硅基流动曾误写成 siliconcloud-color.svg）。
void main() {
  test('all referenced platform svg icons exist', () {
    final dir = Directory('assets/icons/platforms');
    final existing = dir
        .listSync()
        .whereType<File>()
        .map((f) => f.uri.pathSegments.last)
        .toSet();
    final pattern = RegExp(r'''['"]([A-Za-z0-9_.\-]+\.svg)['"]''');
    final sources = <File>[
      ...Directory('lib')
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart')),
      File('assets/config/app_config.json'),
    ];
    final missing = <String>{};
    for (final f in sources) {
      for (final m in pattern.allMatches(f.readAsStringSync())) {
        final name = m.group(1)!;
        if (!existing.contains(name)) missing.add('$name (${f.path})');
      }
    }
    expect(missing, isEmpty);
  });

  test('every referenced assets/... path exists', () {
    final pattern = RegExp(r'''['"](assets/[A-Za-z0-9_./\-]+\.(?:svg|png|jpg|jpeg|json|ico|webp))['"]''');
    final sources = <File>[
      ...Directory('lib').listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('.dart')),
      ...Directory('assets').listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('.json')),
    ];
    final missing = <String>{};
    for (final f in sources) {
      for (final m in pattern.allMatches(f.readAsStringSync())) {
        final path = m.group(1)!;
        if (path.contains(r'$')) continue;
        if (!File(path).existsSync()) missing.add('$path (${f.path})');
      }
    }
    expect(missing, isEmpty);
  });
}
