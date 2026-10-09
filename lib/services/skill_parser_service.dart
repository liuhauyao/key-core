import 'dart:io';
import 'package:path/path.dart' as path;
import 'package:yaml/yaml.dart';

/// SKILL.md 解析结果
class SkillParseResult {
  final String name;
  final String? description;
  final String body;
  final Map<String, dynamic> frontmatter;

  const SkillParseResult({
    required this.name,
    this.description,
    required this.body,
    this.frontmatter = const {},
  });
}

/// Skill 文件夹校验结果
class SkillValidationResult {
  final bool isValid;
  final List<String> errors;
  final SkillParseResult? parsed;

  const SkillValidationResult({
    required this.isValid,
    this.errors = const [],
    this.parsed,
  });
}

/// SKILL.md 解析服务
class SkillParserService {
  static const String skillFileName = 'SKILL.md';

  /// 解析 SKILL.md 内容
  SkillParseResult parseSkillMd(String content) {
    final trimmed = content.trimLeft();
    if (!trimmed.startsWith('---')) {
      const folderName = 'skill';
      return SkillParseResult(
        name: folderName,
        body: content,
        frontmatter: const {},
      );
    }

    final endIndex = trimmed.indexOf('\n---', 3);
    if (endIndex == -1) {
      return SkillParseResult(name: 'skill', body: content);
    }

    final frontmatterRaw = trimmed.substring(3, endIndex).trim();
    final body = trimmed.substring(endIndex + 4).trimLeft();

    Map<String, dynamic> frontmatter = {};
    try {
      final yaml = loadYaml(frontmatterRaw);
      if (yaml is Map) {
        frontmatter = yaml.map(
          (key, value) => MapEntry(key.toString(), value),
        );
      }
    } catch (_) {}

    final name = frontmatter['name']?.toString() ?? 'skill';
    final description = frontmatter['description']?.toString();

    return SkillParseResult(
      name: name,
      description: description,
      body: body,
      frontmatter: frontmatter,
    );
  }

  /// 生成 SKILL.md 内容
  String generateSkillMd({
    required String name,
    required String description,
    String body = '',
    Map<String, dynamic>? extraFrontmatter,
  }) {
    final buffer = StringBuffer()
      ..writeln('---')
      ..writeln('name: $name')
      ..writeln('description: $description');

    if (extraFrontmatter != null) {
      for (final entry in extraFrontmatter.entries) {
        if (entry.key == 'name' || entry.key == 'description') continue;
        buffer.writeln('${entry.key}: ${entry.value}');
      }
    }

    buffer
      ..writeln('---')
      ..writeln()
      ..write(body);

    return buffer.toString();
  }

  /// 校验 Skill 文件夹
  Future<SkillValidationResult> validateSkillFolder(Directory skillDir) async {
    final errors = <String>[];
    final skillFile = File(path.join(skillDir.path, skillFileName));

    if (!await skillFile.exists()) {
      return const SkillValidationResult(
        isValid: false,
        errors: ['Missing $skillFileName'],
      );
    }

    final content = await skillFile.readAsString();
    final parsed = parseSkillMd(content);

    if (parsed.description == null || parsed.description!.trim().isEmpty) {
      errors.add('description is required in frontmatter');
    }

    final folderName = path.basename(skillDir.path);
    if (parsed.name != folderName) {
      errors.add('name "$parsed.name" should match folder name "$folderName"');
    }

    return SkillValidationResult(
      isValid: errors.isEmpty,
      errors: errors,
      parsed: parsed,
    );
  }

  /// 从 Skill 目录读取解析结果
  Future<SkillParseResult?> readSkillFromDir(Directory skillDir) async {
    final skillFile = File(path.join(skillDir.path, skillFileName));
    if (!await skillFile.exists()) return null;
    final content = await skillFile.readAsString();
    return parseSkillMd(content);
  }
}
