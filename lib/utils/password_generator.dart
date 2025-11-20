import 'dart:math';

/// 密码生成器
class PasswordGenerator {
  static const String _lowercase = 'abcdefghijklmnopqrstuvwxyz';
  static const String _uppercase = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ';
  static const String _numbers = '0123456789';
  static const String _symbols = '!@#\$%^&*()_+-=[]{}|;:,.<>?';

  /// 生成随机密码
  /// 
  /// [length] 密码长度，默认16
  /// [includeLowercase] 包含小写字母
  /// [includeUppercase] 包含大写字母
  /// [includeNumbers] 包含数字
  /// [includeSymbols] 包含特殊字符
  static String generate({
    int length = 16,
    bool includeLowercase = true,
    bool includeUppercase = true,
    bool includeNumbers = true,
    bool includeSymbols = true,
  }) {
    final random = Random.secure();
    String chars = '';
    
    if (includeLowercase) chars += _lowercase;
    if (includeUppercase) chars += _uppercase;
    if (includeNumbers) chars += _numbers;
    if (includeSymbols) chars += _symbols;

    if (chars.isEmpty) {
      throw ArgumentError('至少需要选择一种字符类型');
    }

    // 确保至少包含每种类型的字符
    final password = StringBuffer();
    if (includeLowercase && length > 0) {
      password.write(_lowercase[random.nextInt(_lowercase.length)]);
      length--;
    }
    if (includeUppercase && length > 0) {
      password.write(_uppercase[random.nextInt(_uppercase.length)]);
      length--;
    }
    if (includeNumbers && length > 0) {
      password.write(_numbers[random.nextInt(_numbers.length)]);
      length--;
    }
    if (includeSymbols && length > 0) {
      password.write(_symbols[random.nextInt(_symbols.length)]);
      length--;
    }

    // 填充剩余字符
    for (int i = 0; i < length; i++) {
      password.write(chars[random.nextInt(chars.length)]);
    }

    // 打乱字符顺序
    final passwordList = password.toString().split('')..shuffle(random);
    return passwordList.join();
  }

  /// 生成易记的密码（使用单词组合）
  static String generateMemorable({
    int wordCount = 4,
    String separator = '-',
  }) {
    final random = Random.secure();
    final words = [
      'apple', 'banana', 'cherry', 'dragon', 'eagle', 'forest', 'garden',
      'happy', 'island', 'joker', 'knight', 'light', 'magic', 'nature',
      'ocean', 'planet', 'queen', 'river', 'sunset', 'tiger', 'universe',
      'valley', 'wizard', 'xylophone', 'yellow', 'zebra',
      'alpha', 'beta', 'gamma', 'delta', 'echo', 'foxtrot', 'golf',
      'hotel', 'india', 'juliet', 'kilo', 'lima', 'mike', 'november',
      'oscar', 'papa', 'quebec', 'romeo', 'sierra', 'tango', 'uniform',
      'victor', 'whiskey', 'xray', 'yankee', 'zulu',
    ];

    final selectedWords = <String>[];
    for (int i = 0; i < wordCount; i++) {
      selectedWords.add(words[random.nextInt(words.length)]);
    }

    // 随机添加数字
    if (random.nextBool()) {
      selectedWords.add(random.nextInt(100).toString());
    }

    return selectedWords.join(separator);
  }
}

