import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:key_core/models/skill.dart';
import 'package:key_core/services/database_service.dart';
import 'package:key_core/services/skills/skills_backup_service.dart';
import 'package:key_core/services/skills/skills_fs.dart';
import 'package:key_core/services/skills/skills_market_service.dart';
import 'package:key_core/services/skills_database_service.dart';
import 'package:key_core/services/skills_path_service.dart';
import 'package:key_core/services/skills_sync_service.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// 联网端到端（默认跳过；KEYCORE_NETWORK_TESTS=1 时运行）：
/// 从真实公开仓库（anthropics/skills）下载 zip → 安装 → 同步（复制模式）→ 制造“有更新”→ 更新（自动备份）→
/// 同步后的副本随之更新 → 卸载（备份）→ 恢复 → 临时目录清理。
final _skip = Platform.environment['KEYCORE_NETWORK_TESTS'] == '1'
    ? false
    : '联网测试：设置 KEYCORE_NETWORK_TESTS=1 运行';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  late Directory tmp;
  late String home;

  setUp(() async {
    // TestWidgetsFlutterBinding 会把所有 HTTP 请求替换为 400；联网测试需要真实网络
    HttpOverrides.global = null;
    tmp = Directory.systemTemp.createTempSync('skills_net_e2e_');
    home = p.join(tmp.path, 'home');
    Directory(home).createSync(recursive: true);
    SharedPreferences.setMockInitialValues({});
    SkillsPathService.debugHomeDirOverride = home;
    SkillsSyncService.debugSyncMethodOverride = SkillSyncMethod.copy;
    DatabaseService.debugDatabasePathOverride = inMemoryDatabasePath;
    await DatabaseService.instance.close();
  });

  tearDown(() async {
    await DatabaseService.instance.close();
    SkillsPathService.debugHomeDirOverride = null;
    SkillsSyncService.debugSyncMethodOverride = null;
    tmp.deleteSync(recursive: true);
  });

  test('真实仓库：安装 → 同步 → 更新 → 卸载 → 恢复', () async {
    final market = SkillsMarketService();
    const repo = SkillRepo(owner: 'anthropics', name: 'skills', branch: 'main');
    final remote = await market.listRepoSkills(repo);
    expect(remote, isNotEmpty);
    final target = remote.firstWhere((r) => r.directoryName == 'pdf', orElse: () => remote.first);
    expect(target.subdir, isNotEmpty);

    // 安装 + 同步到 Claude Code（复制模式）
    var skill = await market.installRemote(target, enabledTools: const [SkillTargetTool.claudecode]);
    final paths = SkillsPathService();
    final local = await paths.getSkillSourcePath(skill.relativePath);
    expect(File(p.join(local, 'SKILL.md')).existsSync(), isTrue);
    expect(skill.contentHash, await SkillsFs.computeDirHash(local));
    final sync = SkillsSyncService();
    final summary = await sync.syncToTool(SkillTargetTool.claudecode);
    expect(summary.failed, 0);
    final toolCopy = p.join(await paths.getToolSkillsDir(SkillTargetTool.claudecode), p.basename(local));
    expect(FileSystemEntity.isLinkSync(toolCopy), isFalse);
    expect(File(p.join(toolCopy, 'SKILL.md')).readAsStringSync(), File(p.join(local, 'SKILL.md')).readAsStringSync());

    // 没有变化时不报告更新
    var updates = await market.checkUpdates();
    expect(updates.single.hasUpdate, isFalse);

    // 制造“远端有更新 + 本地被改过”：本地改内容，记录的哈希改为旧值
    File(p.join(local, 'SKILL.md')).writeAsStringSync('locally modified\n', mode: FileMode.append);
    skill = skill.copyWith(contentHash: 'old-hash');
    await SkillsDatabaseService().updateSkill(skill);
    updates = await market.checkUpdates();
    expect(updates.single.hasUpdate, isTrue);
    expect(updates.single.locallyModified, isTrue);

    final updated = await market.updateSkill(skill);
    expect(File(p.join(local, 'SKILL.md')).readAsStringSync(), isNot(contains('locally modified')));
    expect(updated.contentHash, await SkillsFs.computeDirHash(local));
    final backups = await SkillsBackupService().listBackups();
    expect(backups.where((b) => b.reason == 'update'), hasLength(1), reason: '更新前自动备份本地修改');

    // 复制模式下，再次同步会刷新工具里的副本
    await sync.syncToTool(SkillTargetTool.claudecode, replaceExisting: true);
    expect(File(p.join(toolCopy, 'SKILL.md')).readAsStringSync(), File(p.join(local, 'SKILL.md')).readAsStringSync());

    // 卸载（先从工具移除，再备份删除）→ 恢复
    await sync.removeSkillFromTools(updated);
    expect(Directory(toolCopy).existsSync(), isFalse);
    await SkillsBackupService().uninstall(updated);
    expect(Directory(local).existsSync(), isFalse);
    expect(await SkillsDatabaseService().getAllSkills(), isEmpty);
    final entry = (await SkillsBackupService().listBackups()).firstWhere((b) => b.reason != 'update');
    final restored = await SkillsBackupService().restore(entry);
    expect(restored.sourceRepo, 'anthropics/skills');
    expect(File(p.join(await paths.getSkillSourcePath(restored.relativePath), 'SKILL.md')).existsSync(), isTrue);

    // 下载缓存清理
    final root = await market.downloadRepo(repo);
    expect(Directory(root).existsSync(), isTrue);
    await market.clearDownloadCache();
    expect(Directory(root).existsSync(), isFalse);
  }, skip: _skip, timeout: const Timeout(Duration(minutes: 3)));
}
