import 'dart:io';

void main() {
  print('系统时区信息:');
  print('DateTime.now().timeZoneName: ${DateTime.now().timeZoneName}');
  print('Platform.localeName: ${Platform.localeName}');
  print('LANG环境变量: ${Platform.environment['LANG']}');
  
  final timezone = DateTime.now().timeZoneName.toLowerCase();
  print('时区小写: $timezone');
  print('包含cst: ${timezone.contains('cst')}');
  print('包含china: ${timezone.contains('china')}');
  
  final locale = Platform.localeName.toLowerCase();
  print('语言环境小写: $locale');
  print('以zh_cn开头: ${locale.startsWith('zh_cn')}');
  print('以zh-hans-cn开头: ${locale.startsWith('zh-hans-cn')}');
  
  final lang = Platform.environment['LANG']?.toLowerCase() ?? '';
  print('LANG环境变量小写: $lang');
  print('包含zh_cn: ${lang.contains('zh_cn')}');
  print('包含zh-hans: ${lang.contains('zh-hans')}');
}
