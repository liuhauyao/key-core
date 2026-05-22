import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:key_core/models/skill.dart';
import 'package:key_core/services/skills_path_service.dart';
import 'package:key_core/services/skills_store_service.dart';
import 'package:key_core/services/skills_sync_service.dart';
import 'package:path/path.dart' as path;

void main() {
  group('SkillsStoreService', () {
    late Directory tempHome;

    setUp(() async {
      tempHome = await Directory.systemTemp.createTemp('keycore_skills_test_');
      SkillsPathService.debugHomeDirOverride = tempHome.path;
    });

    tearDown(() async {
      SkillsPathService.debugHomeDirOverride = null;
      if (await tempHome.exists()) {
        await tempHome.delete(recursive: true);
      }
    });

    test('scanSkills finds nested skill directories', () async {
      final sourceRoot = Directory(path.join(tempHome.path, '.keycore', 'skills'));
      final skillDir = Directory(path.join(sourceRoot.path, 'shipping', 'deploy-web'));
      await skillDir.create(recursive: true);
      await File(path.join(skillDir.path, 'SKILL.md')).writeAsString('''---
name: deploy-web
description: Deploy staging
---
Body
''');

      final store = SkillsStoreService();
      final scanned = await store.scanSkills();

      expect(scanned.length, 1);
      expect(scanned.first.relativePath, 'shipping/deploy-web');
      expect(scanned.first.parsed.name, 'deploy-web');
    });

    test('importSkillFromFolder copies skill into keycore source', () async {
      final externalDir = Directory(path.join(tempHome.path, 'external', 'demo-skill'));
      await externalDir.create(recursive: true);
      await File(path.join(externalDir.path, 'SKILL.md')).writeAsString('''---
name: demo-skill
description: External skill
---
Hello
''');

      final store = SkillsStoreService();
      await store.importSkillFromFolder(externalDir.path);

      final importedFile = File(path.join(tempHome.path, '.keycore', 'skills', 'demo-skill', 'SKILL.md'));
      expect(await importedFile.exists(), isTrue);
      expect(await importedFile.readAsString(), contains('External skill'));
    });
  });

  group('SkillsSyncService', () {
    late Directory tempHome;

    setUp(() async {
      tempHome = await Directory.systemTemp.createTemp('keycore_sync_test_');
      SkillsPathService.debugHomeDirOverride = tempHome.path;
    });

    tearDown(() async {
      SkillsPathService.debugHomeDirOverride = null;
      if (await tempHome.exists()) {
        await tempHome.delete(recursive: true);
      }
    });

    test('computeSyncState returns synced for valid symlink', () async {
      final sourceRoot = Directory(path.join(tempHome.path, '.keycore', 'skills', 'my-skill'));
      await sourceRoot.create(recursive: true);
      await File(path.join(sourceRoot.path, 'SKILL.md')).writeAsString('''---
name: my-skill
description: Test skill
---
Body
''');

      final toolRoot = Directory(path.join(tempHome.path, '.cursor', 'skills'));
      await toolRoot.create(recursive: true);
      final toolPath = path.join(toolRoot.path, 'my-skill');
      await Link(toolPath).create(sourceRoot.path);

      final syncService = SkillsSyncService();
      final skill = Skill(
        skillId: 'my-skill',
        relativePath: 'my-skill',
        name: 'my-skill',
        description: 'Test skill',
        enabledTools: const [SkillTargetTool.cursor],
        isActive: true,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      final state = await syncService.computeSyncState(skill, SkillTargetTool.cursor);
      expect(state, SkillSyncState.synced);
    });

    test('computeSyncState returns conflict for real directory at tool path', () async {
      final sourceRoot = Directory(path.join(tempHome.path, '.keycore', 'skills', 'my-skill'));
      await sourceRoot.create(recursive: true);
      await File(path.join(sourceRoot.path, 'SKILL.md')).writeAsString('''---
name: my-skill
description: Test skill
---
Body
''');

      final toolSkillDir = Directory(path.join(tempHome.path, '.cursor', 'skills', 'my-skill'));
      await toolSkillDir.create(recursive: true);
      await File(path.join(toolSkillDir.path, 'SKILL.md')).writeAsString('local copy');

      final syncService = SkillsSyncService();
      final skill = Skill(
        skillId: 'my-skill',
        relativePath: 'my-skill',
        name: 'my-skill',
        description: 'Test skill',
        enabledTools: const [SkillTargetTool.cursor],
        isActive: true,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      final state = await syncService.computeSyncState(skill, SkillTargetTool.cursor);
      expect(state, SkillSyncState.conflict);
    });
  });
}
