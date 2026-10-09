import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:key_core/models/mcp_server.dart';
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

String _skillMd(String name, {String body = 'Body'}) =>
    '---\nname: $name\ndescription: $name skill\n---\n$body\n';

/// 构造一个 GitHub codeload 风格的 zip：顶层是 `<repo>-<branch>/`
List<int> _repoZip(String top, Map<String, String> files) {
  final archive = Archive();
  for (final e in files.entries) {
    final bytes = utf8.encode(e.value);
    archive.addFile(ArchiveFile('$top/${e.key}', bytes.length, bytes));
  }
  return ZipEncoder().encode(archive)!;
}

Future<Skill> _addLocalSkill(String home, String rel, {List<SkillTargetTool> tools = const []}) async {
  final dir = Directory(p.join(home, '.keycore', 'skills', rel));
  await dir.create(recursive: true);
  await File(p.join(dir.path, 'SKILL.md')).writeAsString(_skillMd(p.basename(rel)));
  final now = DateTime(2026);
  final skill = Skill(
    skillId: p.basename(rel),
    relativePath: rel,
    name: p.basename(rel),
    enabledTools: tools,
    createdAt: now,
    updatedAt: now,
  );
  final id = await SkillsDatabaseService().addSkill(skill);
  return skill.copyWith(id: id);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  late Directory tmp;
  late String home;

  setUp(() async {
    tmp = Directory.systemTemp.createTempSync('skills_parity_test_');
    home = p.join(tmp.path, 'home');
    Directory(home).createSync(recursive: true);
    SharedPreferences.setMockInitialValues({});
    SkillsPathService.debugHomeDirOverride = home;
    SkillsPathService.debugEnvironmentOverride = null;
    SkillsPathService.debugStorageLocationOverride = null;
    SkillsSyncService.debugSyncMethodOverride = SkillSyncMethod.auto;
    SkillsSyncService.debugFailSymlinks = false;
    DatabaseService.debugDatabasePathOverride = inMemoryDatabasePath;
    await DatabaseService.instance.close();
  });

  tearDown(() async {
    await DatabaseService.instance.close();
    SkillsPathService.debugHomeDirOverride = null;
    SkillsPathService.debugEnvironmentOverride = null;
    SkillsPathService.debugStorageLocationOverride = null;
    SkillsSyncService.debugSyncMethodOverride = null;
    SkillsSyncService.debugFailSymlinks = false;
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  group('目标工具与路径', () {
    test('覆盖 CC Switch 的全部 Skills 应用目录（含环境变量覆盖）', () async {
      final ps = SkillsPathService();
      final expected = {
        SkillTargetTool.claudecode: '.claude/skills',
        SkillTargetTool.codex: '.codex/skills',
        SkillTargetTool.gemini: '.gemini/skills',
        SkillTargetTool.opencode: '.config/opencode/skills',
        SkillTargetTool.grokBuild: '.grok/skills',
        SkillTargetTool.openclaw: '.openclaw/skills',
        SkillTargetTool.hermes: '.hermes/skills',
        SkillTargetTool.pi: '.pi/agent/skills',
        SkillTargetTool.mcode: '.minimax/skills',
        SkillTargetTool.cursor: '.cursor/skills',
      };
      for (final e in expected.entries) {
        expect(await ps.getToolSkillsDir(e.key), p.join(home, e.value), reason: e.key.name);
      }
      SkillsPathService.debugEnvironmentOverride = {'HERMES_HOME': '/opt/hermes'};
      expect(await ps.getToolSkillsDir(SkillTargetTool.hermes), '/opt/hermes/skills');
    });

    test('SkillTargetTool 与 AiToolType 双向映射且 value 稳定', () {
      expect(SkillTargetTool.claudecode.value, 'claudecode');
      expect(SkillTargetTool.grokBuild.value, AiToolType.grokBuild.value);
      for (final t in SkillTargetTool.values) {
        expect(SkillTargetTool.fromAiToolType(t.toAiToolType()), t);
        expect(SkillTargetTool.fromString(t.value), t);
      }
      expect(SkillTargetTool.fromAiToolType(AiToolType.windsurf), isNull);
    });

    test('detectInstalledTools 只返回已存在配置目录的工具', () async {
      Directory(p.join(home, '.claude')).createSync();
      Directory(p.join(home, '.hermes')).createSync();
      expect(await SkillsPathService().detectInstalledTools(),
          [SkillTargetTool.claudecode, SkillTargetTool.hermes]);
    });
  });

  group('内容哈希', () {
    test('与 CC Switch 规则一致：忽略隐藏文件，内容或路径变化即变化', () async {
      final dir = p.join(tmp.path, 'h');
      Directory(p.join(dir, 'sub')).createSync(recursive: true);
      File(p.join(dir, 'SKILL.md')).writeAsStringSync('a');
      File(p.join(dir, 'sub', 'x.txt')).writeAsStringSync('b');
      final h1 = await SkillsFs.computeDirHash(dir);
      File(p.join(dir, '.keycore-managed')).writeAsStringSync('x');
      File(p.join(dir, '.DS_Store')).writeAsStringSync('x');
      expect(await SkillsFs.computeDirHash(dir), h1);
      File(p.join(dir, 'sub', 'x.txt')).writeAsStringSync('c');
      expect(await SkillsFs.computeDirHash(dir), isNot(h1));
      // 手算：sha256("SKILL.md\0a\0sub/x.txt\0c\0")
      File(p.join(dir, '.keycore-managed')).deleteSync();
      File(p.join(dir, '.DS_Store')).deleteSync();
      expect(await SkillsFs.computeDirHash(dir),
          await _sha256Hex(utf8.encode('SKILL.md\u0000a\u0000sub/x.txt\u0000c\u0000')));
    });
  });

  group('同步方式', () {
    test('symlink 模式不再把标记文件写进源目录，并清理旧版本遗留标记', () async {
      final skill = await _addLocalSkill(home, 'alpha', tools: [SkillTargetTool.claudecode]);
      final source = p.join(home, '.keycore', 'skills', 'alpha');
      File(p.join(source, '.keycore-managed')).writeAsStringSync('managed-by=keycore\n');
      SkillsSyncService.debugSyncMethodOverride = SkillSyncMethod.symlink;

      final summary = await SkillsSyncService().syncToTool(SkillTargetTool.claudecode);
      expect(summary.synced, 1);
      final toolPath = p.join(home, '.claude', 'skills', 'alpha');
      expect(FileSystemEntity.isLinkSync(toolPath), isTrue);
      expect(File(p.join(source, '.keycore-managed')).existsSync(), isFalse);
      expect(await SkillsSyncService().computeSyncState(skill, SkillTargetTool.claudecode),
          SkillSyncState.synced);
    });

    test('copy 模式复制目录 + 写入受管标记；源变更后状态为 outdated，再同步刷新', () async {
      final skill = await _addLocalSkill(home, 'beta', tools: [SkillTargetTool.gemini]);
      SkillsSyncService.debugSyncMethodOverride = SkillSyncMethod.copy;
      final sync = SkillsSyncService();
      await sync.syncToTool(SkillTargetTool.gemini);

      final toolPath = p.join(home, '.gemini', 'skills', 'beta');
      expect(FileSystemEntity.isLinkSync(toolPath), isFalse);
      expect(File(p.join(toolPath, 'SKILL.md')).existsSync(), isTrue);
      final marker = await SkillsFs.readCopyMarker(toolPath);
      expect(marker?.relativePath, 'beta');
      expect(await sync.computeSyncState(skill, SkillTargetTool.gemini), SkillSyncState.synced);

      File(p.join(home, '.keycore', 'skills', 'beta', 'SKILL.md'))
          .writeAsStringSync(_skillMd('beta', body: 'changed'));
      expect(await sync.computeSyncState(skill, SkillTargetTool.gemini), SkillSyncState.outdated);

      await sync.syncToTool(SkillTargetTool.gemini);
      expect(File(p.join(toolPath, 'SKILL.md')).readAsStringSync(), contains('changed'));
      expect(await sync.computeSyncState(skill, SkillTargetTool.gemini), SkillSyncState.synced);
    });

    test('auto 模式在符号链接失败时回退为复制', () async {
      await _addLocalSkill(home, 'gamma', tools: [SkillTargetTool.pi]);
      SkillsSyncService.debugFailSymlinks = true;
      final summary = await SkillsSyncService().syncToTool(SkillTargetTool.pi);
      expect(summary.synced, 1);
      final toolPath = p.join(home, '.pi', 'agent', 'skills', 'gamma');
      expect(FileSystemEntity.isLinkSync(toolPath), isFalse);
      expect(await SkillsFs.readCopyMarker(toolPath), isNotNull);
    });

    test('symlink 模式在符号链接失败时报告失败而不是复制', () async {
      await _addLocalSkill(home, 'delta', tools: [SkillTargetTool.pi]);
      SkillsSyncService.debugSyncMethodOverride = SkillSyncMethod.symlink;
      SkillsSyncService.debugFailSymlinks = true;
      final summary = await SkillsSyncService().syncToTool(SkillTargetTool.pi);
      expect(summary.synced, 0);
      expect(Directory(p.join(home, '.pi', 'agent', 'skills', 'delta')).existsSync(), isFalse);
    });

    test('取消启用后清理受管副本，但不动用户自己的目录', () async {
      final skill = await _addLocalSkill(home, 'eps', tools: [SkillTargetTool.codex]);
      SkillsSyncService.debugSyncMethodOverride = SkillSyncMethod.copy;
      final sync = SkillsSyncService();
      await sync.syncToTool(SkillTargetTool.codex);
      final userDir = Directory(p.join(home, '.codex', 'skills', 'mine'))..createSync(recursive: true);
      File(p.join(userDir.path, 'SKILL.md')).writeAsStringSync(_skillMd('mine'));

      await SkillsDatabaseService().updateSkill(skill.copyWith(enabledTools: const []));
      await sync.syncToTool(SkillTargetTool.codex);
      expect(Directory(p.join(home, '.codex', 'skills', 'eps')).existsSync(), isFalse);
      expect(userDir.existsSync(), isTrue);
    });

    test('替换同名的用户目录时先移到 skill-backups/_replaced，而不是直接删除', () async {
      await _addLocalSkill(home, 'zeta', tools: [SkillTargetTool.claudecode]);
      final userDir = Directory(p.join(home, '.claude', 'skills', 'zeta'))..createSync(recursive: true);
      File(p.join(userDir.path, 'SKILL.md')).writeAsStringSync('user version');

      final sync = SkillsSyncService();
      final first = await sync.syncToTool(SkillTargetTool.claudecode);
      expect(first.conflicts, 1);
      await sync.syncToTool(SkillTargetTool.claudecode, replaceExisting: true);
      expect(FileSystemEntity.isLinkSync(userDir.path), isTrue);
      final replacedRoot = Directory(p.join(home, '.keycore', 'skill-backups', '_replaced', 'claudecode'));
      final moved = replacedRoot.listSync().single;
      expect(File(p.join(moved.path, 'SKILL.md')).readAsStringSync(), 'user version');
    });

    test('扫描时把受管副本识别为 Key Core 管理，导入全部工具只导入未管理的', () async {
      await _addLocalSkill(home, 'eta', tools: [SkillTargetTool.hermes]);
      SkillsSyncService.debugSyncMethodOverride = SkillSyncMethod.copy;
      final sync = SkillsSyncService();
      await sync.syncToTool(SkillTargetTool.hermes);
      final foreign = Directory(p.join(home, '.grok', 'skills', 'foreign'))..createSync(recursive: true);
      File(p.join(foreign.path, 'SKILL.md')).writeAsStringSync(_skillMd('foreign'));

      final unmanaged = await sync.scanUnmanaged();
      expect(unmanaged.keys, [SkillTargetTool.grokBuild]);
      final result = await sync.importFromAllTools();
      expect(result[SkillTargetTool.grokBuild]?.imported, 1);
      expect(result[SkillTargetTool.hermes]?.imported, 0);
      final imported = await SkillsDatabaseService().getSkillByRelativePath('foreign');
      expect(imported?.enabledTools, [SkillTargetTool.grokBuild]);
    });
  });

  group('卸载备份与恢复', () {
    test('卸载移除链接并把源目录移入备份；恢复后重新写入数据库', () async {
      final skill = await _addLocalSkill(home, 'theta', tools: [SkillTargetTool.claudecode]);
      final sync = SkillsSyncService();
      await sync.syncToTool(SkillTargetTool.claudecode);
      final link = p.join(home, '.claude', 'skills', 'theta');
      expect(FileSystemEntity.isLinkSync(link), isTrue);

      final backups = SkillsBackupService();
      final backupDir = await backups.uninstall(skill);
      expect(FileSystemEntity.typeSync(link, followLinks: false), FileSystemEntityType.notFound);
      expect(Directory(p.join(home, '.keycore', 'skills', 'theta')).existsSync(), isFalse);
      expect(File(p.join(backupDir, 'skill', 'SKILL.md')).existsSync(), isTrue);
      expect(await SkillsDatabaseService().getAllSkills(), isEmpty);

      final list = await backups.listBackups();
      expect(list.single.skillName, 'theta');
      final restored = await backups.restore(list.single);
      expect(restored.relativePath, 'theta');
      expect(restored.enabledTools, [SkillTargetTool.claudecode]);
      expect(File(p.join(home, '.keycore', 'skills', 'theta', 'SKILL.md')).existsSync(), isTrue);
      expect(await backups.listBackups(), isEmpty);
    });

    test('恢复时如已存在同名 Skill 则自动改名', () async {
      final skill = await _addLocalSkill(home, 'iota');
      final backups = SkillsBackupService();
      await backups.uninstall(skill);
      await _addLocalSkill(home, 'iota');
      final restored = await backups.restore((await backups.listBackups()).single);
      expect(restored.relativePath, 'iota-2');
    });
  });

  group('仓库 / skills.sh / ZIP / 更新', () {
    MockClient repoClient(Map<String, List<int>> zips, {List<Uri>? requested}) {
      return MockClient((req) async {
        requested?.add(req.url);
        if (req.url.host == 'skills.sh') {
          return http.Response(
            jsonEncode({
              'query': req.url.queryParameters['q'],
              'skills': [
                {'id': 'acme/tools/pdf', 'source': 'acme/tools', 'skillId': 'pdf', 'name': 'pdf', 'installs': 10},
                {'id': 'bad', 'source': 'nope', 'skillId': '', 'name': 'x', 'installs': 1},
              ],
              'count': 2,
            }),
            200,
          );
        }
        final bytes = zips[req.url.toString()];
        return bytes == null ? http.Response('nf', 404) : http.Response.bytes(bytes, 200);
      });
    }

    test('默认仓库与 CC Switch 一致，可增删并持久化', () async {
      final market = SkillsMarketService(client: MockClient((_) async => http.Response('', 404)));
      final repos = await market.getRepos();
      expect(repos.map((r) => '${r.fullName}@${r.branch}'), [
        'anthropics/skills@main',
        'ComposioHQ/awesome-claude-skills@master',
        'cexll/myclaude@master',
        'JimLiu/baoyu-skills@main',
      ]);
      await market.addRepo(SkillRepo.parse('https://github.com/acme/tools/tree/dev')!);
      await market.removeRepo('cexll', 'myclaude');
      final again = await SkillsMarketService().getRepos();
      expect(again.map((r) => r.fullName), contains('acme/tools'));
      expect(again.firstWhere((r) => r.name == 'tools').branch, 'dev');
      expect(again.map((r) => r.fullName), isNot(contains('cexll/myclaude')));
    });

    test('SkillRepo.parse 支持多种写法并拒绝非法输入', () {
      expect(SkillRepo.parse('a/b')!.zipUrl.toString(), 'https://codeload.github.com/a/b/zip/HEAD');
      expect(SkillRepo.parse('a/b@main')!.zipUrl.toString(),
          'https://codeload.github.com/a/b/zip/refs/heads/main');
      expect(SkillRepo.parse('https://github.com/a/b.git')!.fullName, 'a/b');
      expect(SkillRepo.parse('a'), isNull);
      expect(SkillRepo.parse('a/b/c'), isNull);
      expect(SkillRepo.parse('a b/c'), isNull);
    });

    test('从仓库 zip 发现并安装 Skill，记录来源与哈希；重复安装被拒绝', () async {
      final zip = _repoZip('tools-main', {
        'README.md': 'x',
        'skills/pdf/SKILL.md': _skillMd('pdf'),
        'skills/pdf/scripts/run.py': 'print(1)',
        'skills/docx/SKILL.md': _skillMd('docx'),
      });
      final market = SkillsMarketService(client: repoClient({
        'https://codeload.github.com/acme/tools/zip/refs/heads/main': zip,
      }));
      const repo = SkillRepo(owner: 'acme', name: 'tools', branch: 'main');
      final skills = await market.listRepoSkills(repo);
      expect(skills.map((s) => s.subdir), ['skills/docx', 'skills/pdf']);

      final installed = await market.installRemote(skills[1], enabledTools: [SkillTargetTool.claudecode]);
      expect(installed.relativePath, 'pdf');
      expect(installed.sourceRepo, 'acme/tools');
      expect(installed.sourceRef, 'main');
      expect(installed.sourceSubdir, 'skills/pdf');
      expect(installed.contentHash, skills[1].contentHash);
      expect(File(p.join(home, '.keycore', 'skills', 'pdf', 'scripts', 'run.py')).existsSync(), isTrue);

      expect((await market.listRepoSkills(repo))[1].installed, isTrue);
      expect(() => market.installRemote(skills[1]), throwsStateError);
    });

    test('skills.sh 搜索解析结果，安装时按 skillId 在来源仓库中定位', () async {
      final requested = <Uri>[];
      final zip = _repoZip('tools-HEAD', {'nested/deep/pdf/SKILL.md': _skillMd('pdf')});
      final market = SkillsMarketService(
        client: repoClient({'https://codeload.github.com/acme/tools/zip/HEAD': zip}, requested: requested),
      );
      final results = await market.searchSkillsSh('pdf');
      expect(results.single.source, 'acme/tools');
      expect(requested.first.queryParameters, {'q': 'pdf', 'limit': '20', 'offset': '0'});

      final skill = await market.installFromSkillsSh(results.single);
      expect(skill.sourceRepo, 'acme/tools');
      expect(skill.sourceSubdir, 'nested/deep/pdf');
      expect(skill.sourceRef, isNull);
    });

    test('resolveRemoteSkill：目录名优先，metadata 名需唯一，最后回退仓库根', () {
      const repo = SkillRepo(owner: 'a', name: 'b');
      RemoteSkill r(String subdir, String name) =>
          RemoteSkill(repo: repo, subdir: subdir, directoryName: p.basename(subdir), name: name, contentHash: '');
      expect(SkillsMarketService.resolveRemoteSkill([r('x/foo', 'bar'), r('y/z', 'foo')], 'foo')!.subdir, 'x/foo');
      expect(SkillsMarketService.resolveRemoteSkill([r('x/a', 'foo')], 'foo')!.subdir, 'x/a');
      expect(SkillsMarketService.resolveRemoteSkill([r('x/a', 'foo'), r('x/b', 'foo')], 'foo'), isNull);
      expect(SkillsMarketService.resolveRemoteSkill([r('', 'root')], 'other')!.subdir, '');
    });

    test('从 ZIP 安装：单个根 Skill 与多 Skill 包；拒绝 zip-slip', () async {
      final market = SkillsMarketService(client: MockClient((_) async => http.Response('', 404)));
      final single = File(p.join(tmp.path, 'my-tool.zip'));
      final a = Archive();
      final md = utf8.encode(_skillMd('My Tool'));
      a.addFile(ArchiveFile('SKILL.md', md.length, md));
      single.writeAsBytesSync(ZipEncoder().encode(a)!);
      final s1 = await market.installFromZip(single.path);
      expect(s1.single.relativePath, 'My-Tool');

      final multi = File(p.join(tmp.path, 'multi.zip'))
        ..writeAsBytesSync(_repoZip('pack', {'one/SKILL.md': _skillMd('one'), 'two/SKILL.md': _skillMd('two')}));
      final s2 = await market.installFromZip(multi.path);
      expect(s2.map((s) => s.relativePath), ['one', 'two']);

      final evil = Archive();
      final bytes = utf8.encode('x');
      evil.addFile(ArchiveFile('../evil.txt', bytes.length, bytes));
      expect(
        () => SkillsMarketService.extractZipBytes(ZipEncoder().encode(evil)!, p.join(tmp.path, 'out')),
        throwsStateError,
      );
      expect(File(p.join(tmp.path, 'evil.txt')).existsSync(), isFalse);
    });

    test('检查更新：远端内容变化即有更新；更新前自动备份本地内容', () async {
      var version = 'v1';
      final market = SkillsMarketService(client: MockClient((req) async {
        return http.Response.bytes(_repoZip('tools-main', {'pdf/SKILL.md': _skillMd('pdf', body: version)}), 200);
      }));
      const repo = SkillRepo(owner: 'acme', name: 'tools', branch: 'main');
      final installed = await market.installRemote((await market.listRepoSkills(repo)).single);

      var infos = await market.checkUpdates();
      expect(infos.single.hasUpdate, isFalse);

      version = 'v2';
      final fresh = SkillsMarketService(client: MockClient((req) async {
        return http.Response.bytes(_repoZip('tools-main', {'pdf/SKILL.md': _skillMd('pdf', body: version)}), 200);
      }));
      // 本地也改过
      File(p.join(home, '.keycore', 'skills', 'pdf', 'SKILL.md')).writeAsStringSync(_skillMd('pdf', body: 'local'));
      infos = await fresh.checkUpdates();
      expect(infos.single.hasUpdate, isTrue);
      expect(infos.single.locallyModified, isTrue);

      final updated = await fresh.updateSkill(installed);
      expect(File(p.join(home, '.keycore', 'skills', 'pdf', 'SKILL.md')).readAsStringSync(), contains('v2'));
      expect(updated.contentHash, infos.single.remoteHash);
      final backups = await SkillsBackupService().listBackups();
      expect(backups.single.reason, 'update');
      expect(File(p.join(backups.single.backupPath, 'skill', 'SKILL.md')).readAsStringSync(), contains('local'));
      expect((await SkillsDatabaseService().getAllSkills()).length, 1);
    });

    test('下载失败时抛出 HttpException，discoverAll 只记录该仓库错误', () async {
      final market = SkillsMarketService(client: MockClient((_) async => http.Response('nf', 404)));
      expect(() => market.downloadRepo(const SkillRepo(owner: 'a', name: 'b')), throwsA(isA<HttpException>()));
      final result = await market.discoverAll();
      expect(result.skills, isEmpty);
      expect(result.errors.length, SkillsMarketService.defaultRepos.length);
    });
  });

  group('存储迁移', () {
    test('迁移到 ~/.agents/skills 后链接指向新位置；目标冲突时不做任何修改', () async {
      await _addLocalSkill(home, 'kappa', tools: [SkillTargetTool.claudecode]);
      final sync = SkillsSyncService();
      await sync.syncToTool(SkillTargetTool.claudecode);

      final result = await sync.migrateStorage('agents');
      expect(result.moved, 1);
      final newPath = p.join(home, '.agents', 'skills', 'kappa');
      expect(Directory(newPath).existsSync(), isTrue);
      expect(Directory(p.join(home, '.keycore', 'skills', 'kappa')).existsSync(), isFalse);
      final link = p.join(home, '.claude', 'skills', 'kappa');
      expect(Link(link).targetSync(), newPath);

      // 冲突：keycore 目录下已有同名
      Directory(p.join(home, '.keycore', 'skills', 'kappa')).createSync(recursive: true);
      expect(() => sync.migrateStorage('keycore'), throwsStateError);
      expect(Directory(newPath).existsSync(), isTrue);
    });
  });

  group('数据库 v20', () {
    test('skills 表包含来源与哈希字段并可读写', () async {
      final db = await DatabaseService.instance.database;
      final cols = (await db.rawQuery('PRAGMA table_info(skills)')).map((r) => r['name']).toSet();
      expect(cols, containsAll(['source_repo', 'source_ref', 'source_subdir', 'content_hash']));
      expect(DatabaseService.schemaVersion, greaterThanOrEqualTo(20));
    });
  });
}

Future<String> _sha256Hex(List<int> bytes) async => sha256.convert(bytes).toString();
