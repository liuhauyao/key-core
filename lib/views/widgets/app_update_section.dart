// 「关于 › 应用更新」分组（form_v3.md §10）：
//   App Store 版：只有「通过 App Store 更新」（在 App Store 中打开），不出现仓库 / 许可证 / GitHub。
//   开源版：「检查更新（GitHub Releases）」→ 下载 → SHA-256 校验 → 打开安装包；另有 仓库 / 许可证 / 反馈 链接。
import 'package:flutter/material.dart';
import 'kc_settings.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../config/edition.dart';
import '../../config/oss_links.dart';
import '../../services/app_update_service.dart';
import '../../services/url_launcher_service.dart';
import '../../theme/kc_tokens.dart';
import '../../utils/app_localizations.dart';
import 'kc_toast.dart';

class AppUpdateSection extends StatefulWidget {
  const AppUpdateSection({super.key, required this.currentVersion, this.service, this.edition});

  final String? currentVersion;
  final AppUpdateService? service;

  /// 仅测试用：覆盖编译期 edition
  final KcEdition? edition;

  @override
  State<AppUpdateSection> createState() => _AppUpdateSectionState();
}

enum _Phase { idle, checking, upToDate, available, downloading, ready, failed }

class _AppUpdateSectionState extends State<AppUpdateSection> {
  late final AppUpdateService _svc = widget.service ?? AppUpdateService();
  _Phase _phase = _Phase.idle;
  ReleaseInfo? _rel;
  double _progress = 0;
  String? _error;
  dynamic _file;

  bool get _appStore => (widget.edition ?? Edition.current) == KcEdition.appstore;

  Future<void> _check() async {
    final v = widget.currentVersion;
    if (v == null) return;
    setState(() => _phase = _Phase.checking);
    final r = await _svc.check(v);
    if (!mounted) return;
    setState(() {
      _rel = r.release;
      _error = r.error;
      _phase = switch (r.status) {
        UpdateCheckStatus.available => _Phase.available,
        UpdateCheckStatus.upToDate => _Phase.upToDate,
        UpdateCheckStatus.failed => _Phase.failed,
      };
    });
  }

  Future<void> _download() async {
    final rel = _rel;
    if (rel == null) return;
    setState(() {
      _phase = _Phase.downloading;
      _progress = 0;
    });
    try {
      final f = await _svc.downloadAndVerify(rel, onProgress: (p) {
        if (mounted) setState(() => _progress = p);
      });
      if (!mounted) return;
      setState(() {
        _file = f;
        _phase = _Phase.ready;
      });
    } on UpdateException catch (e) {
      if (!mounted) return;
      final l = AppLocalizations.of(context);
      final msg = switch (e.code) {
        'no_checksum' => l?.tr('update_err_no_checksum', '该版本没有提供 SHA-256 校验文件，已停止安装；请到发布页手动下载') ??
            '该版本没有提供 SHA-256 校验文件，已停止安装；请到发布页手动下载',
        'checksum_mismatch' => l?.tr('update_err_mismatch', 'SHA-256 校验不一致，已删除下载文件') ?? 'SHA-256 校验不一致，已删除下载文件',
        'no_asset' => l?.tr('update_err_no_asset', '没有适用于当前系统的安装包') ?? '没有适用于当前系统的安装包',
        _ => e.code,
      };
      setState(() {
        _phase = _Phase.failed;
        _error = msg;
      });
      showKcToast(context, msg, kind: KcToastKind.error);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _phase = _Phase.failed;
        _error = '$e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = ShadTheme.of(context).colorScheme;
    final kc = context.kc;
    final l = AppLocalizations.of(context);
    String t(String k, String f) => l?.tr(k, f) ?? f;

    Widget row({required Key key, required String title, String? desc, Widget? trailing, Widget? leading}) =>
        KcSettingsRow(key: key, title: title, subtitle: desc, trailing: trailing, leading: leading);

    final rows = <Widget>[];
    final links = <Widget>[];
    // Edition.isAppStore 是编译期常量：App Store 构建中 else 分支（含 OssLinks 字符串）被整段 tree-shake
    if (Edition.isAppStore || _appStore) {
      rows.add(row(
        key: const ValueKey('update.appstore'),
        title: t('update_via_appstore', '应用更新'),
        desc: t('update_via_appstore_desc', '本版本通过 Mac App Store 更新；可在 App Store 中开启自动更新'),
        trailing: ShadButton.outline(
          key: const ValueKey('update.openAppStore'),
          height: KcSize.control,
          onPressed: () => UrlLauncherService().openUrl(Edition.appStoreUrl),
          child: Text(t('open_in_appstore', '在 App Store 中打开')),
        ),
      ));
    } else {
      final v = widget.currentVersion ?? '-';
      final desc = switch (_phase) {
        _Phase.idle => t('update_oss_desc', '从 GitHub Releases 检查新版本；下载后校验 SHA-256 再安装'),
        _Phase.checking => t('update_checking', '正在检查…'),
        _Phase.upToDate => t('update_uptodate', '已是最新版本（{v}）').replaceAll('{v}', v),
        _Phase.available => t('update_available', '发现新版本 {new}（当前 {v}）').replaceAll('{new}', _rel?.version ?? '').replaceAll('{v}', v),
        _Phase.downloading => t('update_downloading', '正在下载… {p}%').replaceAll('{p}', (_progress * 100).toStringAsFixed(0)),
        _Phase.ready => t('update_ready', '已下载并通过 SHA-256 校验'),
        _Phase.failed => '${t('update_failed', '检查更新失败')}${_error == null ? '' : '：$_error'}',
      };
      final Widget action = switch (_phase) {
        _Phase.checking || _Phase.downloading =>
          const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
        _Phase.available => ShadButton(
            key: const ValueKey('update.download'),
            height: KcSize.control,
            onPressed: _download,
            child: Text(t('update_download_install', '下载并安装')),
          ),
        _Phase.ready => ShadButton(
            key: const ValueKey('update.install'),
            height: KcSize.control,
            onPressed: () => _svc.openInstaller(_file),
            child: Text(t('update_open_installer', '打开安装包')),
          ),
        _ => ShadButton.outline(
            key: const ValueKey('update.check'),
            height: KcSize.control,
            onPressed: widget.currentVersion == null ? null : _check,
            child: Text(t('update_check', '检查更新')),
          ),
      };
      rows.add(row(key: const ValueKey('update.oss'), title: t('update_oss_title', '应用更新（GitHub Releases）'), desc: desc, trailing: action));
      Widget link(String k, IconData icon, Color tile, String title, String detail, String url) => KcSettingsRow(
            key: ValueKey('update.link.$k'),
            leading: KcIconTile(icon, color: tile),
            title: title,
            trailing: Row(mainAxisSize: MainAxisSize.min, children: [
              Text(detail, style: KcType.mono.copyWith(fontSize: 11.5, color: cs.mutedForeground)),
              const SizedBox(width: 8),
              Icon(Icons.open_in_new, size: 14, color: kc.text2),
            ]),
            onTap: () => UrlLauncherService().openUrl(url),
          );
      links.add(link('releases', Icons.article_outlined, KcIconTile.purple, t('about_changelog', '更新日志'), 'Releases', OssLinks.releasesUrl));
      links.add(link('repo', Icons.code, KcIconTile.graphite, t('about_repo', '源代码仓库'), OssLinks.repoSlug, OssLinks.repoUrl));
      links.add(link('issues', Icons.feedback_outlined, KcIconTile.green, t('about_issues', '反馈问题'), 'GitHub Issues', OssLinks.issuesUrl));
      links.add(link('license', Icons.description_outlined, KcIconTile.gray, t('about_license', '开源许可证'), 'MIT', OssLinks.licenseUrl));
    }

    return Column(key: const ValueKey('appUpdateSection'), crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      KcSettingsSection(rows: rows),
      if (links.isNotEmpty) ...[const SizedBox(height: 18), KcSettingsSection(rows: links)],
    ]);
  }
}
