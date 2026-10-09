import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:key_core/services/config_file_service.dart';
import 'package:path/path.dart' as path;

void main() {
  group('ConfigFileService', () {
    late ConfigFileService service;
    late Directory tempDir;

    setUp(() async {
      service = ConfigFileService.instance;
      tempDir = await Directory.systemTemp.createTemp('config_test_');
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('should write and read JSON config', () async {
      final configPath = path.join(tempDir.path, 'test_config.json');
      final config = {
        'apiKey': 'test-key-123',
        'model': 'gpt-5-pro',
        'temperature': 0.7,
      };

      // 写入配置
      await service.writeJsonConfig(configPath, config, createBackup: false);

      // 读取配置
      final readConfig = await service.readJsonConfig(configPath);

      expect(readConfig, equals(config));
    });

    test('should preserve existing fields when updating', () async {
      final configPath = path.join(tempDir.path, 'test_config.json');
      
      // 初始配置
      final initialConfig = {
        'apiKey': 'old-key',
        'model': 'old-model',
        'temperature': 0.7,
        'maxTokens': 1000,
      };
      await service.writeJsonConfig(configPath, initialConfig, createBackup: false);

      // 更新部分字段
      await service.updateJsonFields(
        configPath,
        {'apiKey': 'new-key', 'model': 'new-model'},
        createBackup: false,
      );

      // 验证
      final updated = await service.readJsonConfig(configPath);
      expect(updated['apiKey'], 'new-key');
      expect(updated['model'], 'new-model');
      expect(updated['temperature'], 0.7); // 应该保留
      expect(updated['maxTokens'], 1000); // 应该保留
    });

    test('should remove field when value is null', () async {
      final configPath = path.join(tempDir.path, 'test_config.json');
      
      final initialConfig = {
        'apiKey': 'test-key',
        'model': 'test-model',
        'optional': 'should-be-removed',
      };
      await service.writeJsonConfig(configPath, initialConfig, createBackup: false);

      // 移除字段
      await service.updateJsonFields(
        configPath,
        {'optional': null},
        createBackup: false,
      );

      final updated = await service.readJsonConfig(configPath);
      expect(updated.containsKey('optional'), isFalse);
      expect(updated.containsKey('apiKey'), isTrue);
    });

    test('should create backup when enabled', () async {
      final configPath = path.join(tempDir.path, 'test_config.json');
      
      // 创建初始配置
      final initialConfig = {'apiKey': 'old-key'};
      await service.writeJsonConfig(configPath, initialConfig, createBackup: false);

      // 更新配置（创建备份）
      final newConfig = {'apiKey': 'new-key'};
      await service.writeJsonConfig(configPath, newConfig, createBackup: true);

      // 检查备份是否存在
      final backups = await service.listBackups(configPath);
      expect(backups, isNotEmpty);
    });

    test('should list backups in reverse chronological order', () async {
      final configPath = path.join(tempDir.path, 'test_config.json');
      
      // 创建初始配置
      await service.writeJsonConfig(
        configPath,
        {'version': 1},
        createBackup: false,
      );

      // 创建多个备份
      for (int i = 2; i <= 4; i++) {
        await Future.delayed(Duration(milliseconds: 10)); // 确保时间戳不同
        await service.writeJsonConfig(
          configPath,
          {'version': i},
          createBackup: true,
        );
      }

      final backups = await service.listBackups(configPath);
      expect(backups.length, greaterThanOrEqualTo(3));
      
      // 验证排序（新的在前）
      for (int i = 0; i < backups.length - 1; i++) {
        final current = path.basename(backups[i]);
        final next = path.basename(backups[i + 1]);
        expect(
          current.compareTo(next) > 0,
          isTrue,
          reason: 'Backups should be sorted in reverse chronological order',
        );
      }
    });

    test('should cleanup old backups keeping recent ones', () async {
      final configPath = path.join(tempDir.path, 'test_config.json');
      
      // 创建初始配置
      await service.writeJsonConfig(
        configPath,
        {'version': 1},
        createBackup: false,
      );

      // 创建 10 个备份
      for (int i = 2; i <= 11; i++) {
        await Future.delayed(Duration(milliseconds: 10));
        await service.writeJsonConfig(
          configPath,
          {'version': i},
          createBackup: true,
        );
      }

      // 清理，只保留 3 个
      await service.cleanupOldBackups(configPath, keep: 3);

      final remaining = await service.listBackups(configPath);
      expect(remaining.length, 3);
    });

    test('should restore backup correctly', () async {
      final configPath = path.join(tempDir.path, 'test_config.json');
      
      // 创建初始配置
      final originalConfig = {'apiKey': 'original-key', 'model': 'original-model'};
      await service.writeJsonConfig(configPath, originalConfig, createBackup: false);

      // 更新配置（创建备份）
      await service.writeJsonConfig(
        configPath,
        {'apiKey': 'modified-key', 'model': 'modified-model'},
        createBackup: true,
      );

      // 获取备份
      final backups = await service.listBackups(configPath);
      expect(backups, isNotEmpty);

      // 恢复备份
      await service.restoreBackup(backups.first, configPath);

      // 验证恢复
      final restored = await service.readJsonConfig(configPath);
      expect(restored['apiKey'], 'original-key');
      expect(restored['model'], 'original-model');
    });

    test('should throw error when reading non-existent file', () async {
      final configPath = path.join(tempDir.path, 'non_existent.json');
      
      expect(
        () => service.readJsonConfig(configPath),
        throwsException,
      );
    });

    test('should create directory if not exists when writing', () async {
      final subDir = path.join(tempDir.path, 'nested', 'deep');
      final configPath = path.join(subDir, 'config.json');
      
      await service.writeJsonConfig(
        configPath,
        {'test': 'value'},
        createBackup: false,
      );

      expect(await File(configPath).exists(), isTrue);
    });

    test('exists should return correct status', () async {
      final existingPath = path.join(tempDir.path, 'existing.json');
      final nonExistingPath = path.join(tempDir.path, 'non_existing.json');
      
      await service.writeJsonConfig(
        existingPath,
        {'test': 'value'},
        createBackup: false,
      );

      expect(await service.exists(existingPath), isTrue);
      expect(await service.exists(nonExistingPath), isFalse);
    });
  });
}
