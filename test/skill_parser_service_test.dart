import 'package:key_core/services/skill_parser_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SkillParserService', () {
    final parser = SkillParserService();

    test('parses YAML frontmatter and body', () {
      const content = '''---
name: my-skill
description: Does something useful
---
# Instructions

Run this command.
''';

      final result = parser.parseSkillMd(content);
      expect(result.name, 'my-skill');
      expect(result.description, 'Does something useful');
      expect(result.body, contains('Run this command'));
    });

    test('generates valid SKILL.md', () {
      final content = parser.generateSkillMd(
        name: 'deploy-web',
        description: 'Deploy web app',
        body: 'Step 1',
      );

      expect(content, contains('name: deploy-web'));
      expect(content, contains('description: Deploy web app'));
      expect(content, contains('Step 1'));
    });
  });
}
