// 应用更新（form_v3.md §10）——按发行版本分流：
//   · App Store 版：只能通过 App Store 更新（在 App Store 中打开），不访问 GitHub；
//   · 开源版：从 GitHub Releases 检查 → 下载 → SHA-256 校验 → 打开安装包。
// 与「配置模板更新」（CloudConfigService）无关，两种版本都保留模板远程更新。
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../config/edition.dart';
import '../config/oss_links.dart';

class ReleaseAsset {
  final String name;
  final String url;
  final int size;
  const ReleaseAsset(this.name, this.url, this.size);
}

class ReleaseInfo {
  final String version; // 去掉前缀 v
  final String tag;
  final String notes;
  final String pageUrl;
  final List<ReleaseAsset> assets;
  const ReleaseInfo({required this.version, required this.tag, required this.notes, required this.pageUrl, required this.assets});

  factory ReleaseInfo.fromJson(Map<String, dynamic> j) {
    final tag = (j['tag_name'] ?? '').toString();
    return ReleaseInfo(
      version: tag.startsWith('v') ? tag.substring(1) : tag,
      tag: tag,
      notes: (j['body'] ?? '').toString(),
      pageUrl: (j['html_url'] ?? '').toString(),
      assets: [
        for (final a in (j['assets'] as List? ?? const []))
          ReleaseAsset((a['name'] ?? '').toString(), (a['browser_download_url'] ?? '').toString(), (a['size'] as num?)?.toInt() ?? 0),
      ],
    );
  }
}

enum UpdateCheckStatus { upToDate, available, failed }

class UpdateCheckResult {
  final UpdateCheckStatus status;
  final ReleaseInfo? release;
  final String? error;
  const UpdateCheckResult(this.status, {this.release, this.error});
}

class AppUpdateService {
  AppUpdateService({http.Client? client}) : _client = client ?? http.Client();
  final http.Client _client;

  /// 语义化版本比较：a > b 返回正数。忽略 +build 部分，缺位按 0。
  @visibleForTesting
  static int compareVersions(String a, String b) {
    List<int> p(String v) => v.split('+').first.split('-').first.split('.').map((e) => int.tryParse(e) ?? 0).toList();
    final x = p(a), y = p(b);
    for (var i = 0; i < 3; i++) {
      final d = (i < x.length ? x[i] : 0) - (i < y.length ? y[i] : 0);
      if (d != 0) return d;
    }
    return 0;
  }

  /// 为当前平台挑选安装包
  @visibleForTesting
  static ReleaseAsset? pickAsset(List<ReleaseAsset> assets, {String? os}) {
    final platform = os ?? Platform.operatingSystem;
    final exts = switch (platform) {
      'macos' => ['.dmg', '.zip'],
      'windows' => ['.exe', '.msix', '.zip'],
      _ => ['.appimage', '.deb', '.tar.gz'],
    };
    final hint = switch (platform) { 'macos' => 'mac', 'windows' => 'win', _ => 'linux' };
    for (final ext in exts) {
      final hits = assets.where((a) => a.name.toLowerCase().endsWith(ext)).toList();
      if (hits.isEmpty) continue;
      return hits.firstWhere((a) => a.name.toLowerCase().contains(hint), orElse: () => hits.first);
    }
    return null;
  }

  /// 从 `<asset>.sha256` 或 `SHA256SUMS` 文本里取出目标文件的摘要
  @visibleForTesting
  static String? parseSha256(String text, String fileName) {
    final re = RegExp(r'\b([a-fA-F0-9]{64})\b');
    final lines = text.split(RegExp(r'\r?\n')).where((l) => l.trim().isNotEmpty).toList();
    for (final l in lines) {
      if (l.contains(fileName)) {
        final m = re.firstMatch(l);
        if (m != null) return m.group(1)!.toLowerCase();
      }
    }
    if (lines.length == 1) return re.firstMatch(lines.first)?.group(1)?.toLowerCase();
    return null;
  }

  static ReleaseAsset? _checksumAssetFor(List<ReleaseAsset> assets, ReleaseAsset target) {
    for (final a in assets) {
      if (a.name == '${target.name}.sha256') return a;
    }
    for (final a in assets) {
      final n = a.name.toLowerCase();
      if (n == 'sha256sums' || n == 'sha256sums.txt' || n == 'checksums.txt') return a;
    }
    return null;
  }

  Future<UpdateCheckResult> check(String currentVersion) async {
    assert(Edition.isOss, 'App Store 版不应调用 GitHub 更新检查');
    if (Edition.isAppStore) return const UpdateCheckResult(UpdateCheckStatus.failed, error: 'appstore');
    try {
      final r = await _client
          .get(Uri.parse(OssLinks.latestReleaseApi), headers: {'Accept': 'application/vnd.github+json'})
          .timeout(const Duration(seconds: 15));
      if (r.statusCode != 200) return UpdateCheckResult(UpdateCheckStatus.failed, error: 'HTTP ${r.statusCode}');
      final rel = ReleaseInfo.fromJson(jsonDecode(r.body) as Map<String, dynamic>);
      if (compareVersions(rel.version, currentVersion) > 0) {
        return UpdateCheckResult(UpdateCheckStatus.available, release: rel);
      }
      return UpdateCheckResult(UpdateCheckStatus.upToDate, release: rel);
    } catch (e) {
      return UpdateCheckResult(UpdateCheckStatus.failed, error: '$e');
    }
  }

  /// 下载安装包并做 SHA-256 校验；没有可用的校验文件则拒绝（不安装未校验的包）。
  /// 成功返回本地文件路径。
  Future<File> downloadAndVerify(ReleaseInfo rel, {void Function(double progress)? onProgress}) async {
    final asset = pickAsset(rel.assets);
    if (asset == null) throw const UpdateException('no_asset');
    final sumAsset = _checksumAssetFor(rel.assets, asset);
    if (sumAsset == null) throw const UpdateException('no_checksum');
    final sumText = (await _client.get(Uri.parse(sumAsset.url))).body;
    final expected = parseSha256(sumText, asset.name);
    if (expected == null) throw const UpdateException('no_checksum');

    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/kc-update-${rel.version}-${asset.name}');
    final req = await _client.send(http.Request('GET', Uri.parse(asset.url)));
    if (req.statusCode != 200) throw UpdateException('HTTP ${req.statusCode}');
    final total = req.contentLength ?? asset.size;
    final sink = file.openWrite();
    var got = 0;
    final hashSink = _DigestSink();
    final hasher = sha256.startChunkedConversion(hashSink);
    await for (final chunk in req.stream) {
      sink.add(chunk);
      hasher.add(chunk);
      got += chunk.length;
      if (total > 0) onProgress?.call(got / total);
    }
    await sink.close();
    hasher.close();
    final actual = hashSink.value.toString();
    if (actual != expected) {
      await file.delete().catchError((_) => file);
      throw const UpdateException('checksum_mismatch');
    }
    return file;
  }

  /// 打开安装包（macOS 挂载 dmg / Windows 运行安装程序 / Linux 在文件管理器中显示）
  Future<void> openInstaller(File f) async {
    if (Platform.isMacOS) {
      await Process.run('open', [f.path]);
    } else if (Platform.isWindows) {
      await Process.start(f.path, const [], mode: ProcessStartMode.detached);
    } else {
      await Process.run('xdg-open', [f.parent.path]);
    }
  }
}

class UpdateException implements Exception {
  final String code;
  const UpdateException(this.code);
  @override
  String toString() => 'UpdateException($code)';
}

class _DigestSink implements Sink<Digest> {
  late Digest value;
  @override
  void add(Digest data) => value = data;
  @override
  void close() {}
}
