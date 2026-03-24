import 'dart:io';
import 'dart:convert';

/// 检查所有语言文件的分组翻译是否完整
void main() {
  final scriptDir = Directory.current.path;
  final localesDir = Directory('$scriptDir/assets/locales');

  if (!localesDir.existsSync()) {
    print('错误: 语言文件目录不存在: ${localesDir.path}');
    exit(1);
  }

  final requiredKeys = [
    'category_popular',
    'category_claude_code',
    'category_codex',
    'category_llm',
    'category_cloud',
    'category_tools',
    'category_vector',
  ];

  print('检查语言文件的分组翻译...');
  print('=' * 50);

  final files = localesDir
      .listSync()
      .where((entity) => entity is File && entity.path.endsWith('.json'))
      .cast<File>();

  bool allComplete = true;

  for (final file in files) {
    final fileName = file.path.split(Platform.pathSeparator).last;
    print('\n检查文件: $fileName');

    try {
      final content = file.readAsStringSync();
      final data = json.decode(content) as Map<String, dynamic>;

      bool fileComplete = true;
      for (final key in requiredKeys) {
        if (data.containsKey(key)) {
          print('  ✅ $key: "${data[key]}"');
        } else {
          print('  ❌ 缺失: $key');
          fileComplete = false;
        }
      }

      if (fileComplete) {
        print('  🎉 $fileName 翻译完整');
      } else {
        print('  ⚠️  $fileName 翻译不完整');
        allComplete = false;
      }
    } catch (e) {
      print('  ❌ 解析失败: $e');
      allComplete = false;
    }
  }

  print('\n' + '=' * 50);
  if (allComplete) {
    print('🎉 所有语言文件的分组翻译都完整！');
  } else {
    print('⚠️  某些语言文件的分组翻译不完整，请检查上述输出。');
  }
}






