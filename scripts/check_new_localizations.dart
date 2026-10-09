import 'dart:io';
import 'dart:convert';

/// 检查新增的本地化键是否在所有语言文件中都存在
void main() {
  final scriptDir = Directory.current.path;
  final localesDir = Directory('$scriptDir/assets/locales');

  if (!localesDir.existsSync()) {
    print('错误: 语言文件目录不存在: ${localesDir.path}');
    exit(1);
  }

  // 新增的本地化键
  final newKeys = [
    'all_categories',
    'enter_key_value_first',
    'validation_failed_with_error',
    'query_failed_with_error',
    'key_name_too_long',
    'tags_too_long',
  ];

  print('检查新增的本地化键...');
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

      bool fileComplete = true;
      for (final key in newKeys) {
        if (data.containsKey(key)) {
          // 检查翻译是否包含占位符
          final translation = data[key] as String;
          if (key.contains('error') && !translation.contains('{error}')) {
            print('  ⚠️  $key: "$translation" (缺少 {error} 占位符)');
            fileComplete = false;
          } else if (key == 'key_name_too_long' && !translation.contains('{maxLength}')) {
            print('  ⚠️  $key: "$translation" (缺少 {maxLength} 占位符)');
            fileComplete = false;
          } else {
            print('  ✅ $key: "$translation"');
          }
        } else {
          print('  ❌ 缺失: $key');
          fileComplete = false;
        }
      }

      if (fileComplete) {
        print('  🎉 $fileName 新增翻译完整');
      } else {
        print('  ⚠️  $fileName 新增翻译不完整');
        allComplete = false;
      }
    } catch (e) {
      print('  ❌ 解析失败: $e');
      allComplete = false;
    }
  }

  print('\n' + '=' * 50);
  if (allComplete) {
    print('🎉 所有语言文件的新增本地化翻译都完整！');
  } else {
    print('⚠️  某些语言文件缺少新增的本地化翻译，请检查上述输出。');
  }
}






