import 'dart:io';
import 'dart:convert';

/// 生成图标列表配置文件
/// 用法: dart scripts/generate_icon_list.dart
void main() {
  final scriptDir = Directory.current.path;
  final assetsDir = Directory('$scriptDir/assets');
  final iconsDir = Directory('${assetsDir.path}/icons/platforms');
  final configDir = Directory('${assetsDir.path}/config');

  // 检查目录是否存在
  if (!iconsDir.existsSync()) {
    print('错误: 图标目录不存在: ${iconsDir.path}');
    exit(1);
  }

  if (!configDir.existsSync()) {
    configDir.createSync(recursive: true);
  }

  // 获取所有 SVG 文件
  final svgFiles = iconsDir
      .listSync(recursive: false)
      .where((entity) =>
          entity is File &&
          entity.path.endsWith('.svg'))
      .map((file) => file.path.split(Platform.pathSeparator).last)
      .toList();

  // 排序
  svgFiles.sort();

  // 生成配置文件内容
  final configData = {
    'version': '1.0.0',
    'generatedAt': DateTime.now().toIso8601String(),
    'totalIcons': svgFiles.length,
    'icons': svgFiles,
  };

  // 写入配置文件
  final configFile = File('${configDir.path}/icon_list.json');
  configFile.writeAsStringSync(const JsonEncoder.withIndent('  ').convert(configData));

  print('图标配置已生成，共 ${svgFiles.length} 个图标');
}







