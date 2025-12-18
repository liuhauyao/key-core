import 'dart:io';
import 'dart:convert';

/// 比较中英文本地化文件，找出缺失的配置项
void main() {
  final scriptDir = Directory.current.path;
  final zhFile = File('$scriptDir/assets/locales/zh.json');
  final enFile = File('$scriptDir/assets/locales/en.json');

  if (!zhFile.existsSync() || !enFile.existsSync()) {
    print('错误: 本地化文件不存在');
    exit(1);
  }

  // 读取文件内容
  final zhContent = zhFile.readAsStringSync();
  final enContent = enFile.readAsStringSync();

  final zhData = json.decode(zhContent) as Map<String, dynamic>;
  final enData = json.decode(enContent) as Map<String, dynamic>;

  // 获取所有键
  final zhKeys = zhData.keys.toSet();
  final enKeys = enData.keys.toSet();

  // 找出中文有但英文没有的键
  final missingInEn = zhKeys.difference(enKeys);
  // 找出英文有但中文没有的键
  final missingInZh = enKeys.difference(zhKeys);

  print('=== 本地化文件对比结果 ===');
  print('中文文件键数量: ${zhKeys.length}');
  print('英文文件键数量: ${enKeys.length}');
  print('缺失数量: ${missingInEn.length} (中文有，英文无)');
  print('');

  if (missingInEn.isNotEmpty) {
    print('❌ 英文文件中缺失的配置项:');
    for (final key in missingInEn.toList()..sort()) {
      final zhValue = zhData[key];
      print('  "$key": "$zhValue"');
    }
  }

  if (missingInZh.isNotEmpty) {
    print('');
    print('⚠️ 中文文件中缺失的配置项:');
    for (final key in missingInZh.toList()..sort()) {
      final enValue = enData[key];
      print('  "$key": "$enValue"');
    }
  }

  if (missingInEn.isEmpty && missingInZh.isEmpty) {
    print('✅ 所有配置项都匹配！');
  }
}
