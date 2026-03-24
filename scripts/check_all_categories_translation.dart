import 'dart:io';
import 'dart:convert';

/// 检查所有语言文件是否都有 all_categories 翻译
void main() {
  final scriptDir = Directory.current.path;
  final localesDir = Directory('$scriptDir/assets/locales');

  if (!localesDir.existsSync()) {
    print('错误: 语言文件目录不存在: ${localesDir.path}');
    exit(1);
  }

  print('检查语言文件的 all_categories 翻译...');
  print('=' * 50);

  final files = localesDir
      .listSync()
      .where((entity) => entity is File && entity.path.endsWith('.json'))
      .cast<File>()
      .toList();

  // 按文件名排序，便于查看
  files.sort((a, b) => a.path.compareTo(b.path));

  bool allComplete = true;

  for (final file in files) {
    final fileName = file.path.split(Platform.pathSeparator).last;
    print('\n检查文件: $fileName');

    try {
      final content = file.readAsStringSync();
      final data = json.decode(content) as Map<String, dynamic>;

      if (data.containsKey('all_categories')) {
        print('  ✅ all_categories: "${data['all_categories']}"');
      } else {
        print('  ❌ 缺失: all_categories');
        allComplete = false;
      }
    } catch (e) {
      print('  ❌ 解析失败: $e');
      allComplete = false;
    }
  }

  print('\n' + '=' * 50);
  if (allComplete) {
    print('🎉 所有语言文件都有 all_categories 翻译！');
  } else {
    print('⚠️  某些语言文件缺少 all_categories 翻译，请检查上述输出。');
  }
}






