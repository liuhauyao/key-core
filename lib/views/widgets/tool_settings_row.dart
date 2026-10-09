// 设置 › 工具配置：系统设置风格的工具行（替代旧 ToolConfigCard 网格卡片）
// logo 28 · 名称 · 配置文件路径（等宽）· 状态徽标 · 浏览 / 恢复默认 · 紧凑开关
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../models/mcp_server.dart';
import '../../services/ai_tool_config_service.dart';
import '../../theme/kc_tokens.dart';
import '../../utils/app_localizations.dart';
import '../../viewmodels/settings_viewmodel.dart';
import 'kc_controls.dart';
import 'kc_logo.dart';
import 'kc_settings.dart';
import 'kc_toast.dart';

/// 开关逻辑（可测）：
/// - 关闭：**总是允许**，不依赖配置是否有效（旧实现在「配置缺失 / 尚未校验」时把开关整个禁用，导致无法关闭）；
/// - 开启：先校验配置文件，无效则拒绝并返回 false。
Future<bool> applyToolToggle(SettingsViewModel vm, AiToolType tool, bool enabled) async {
  if (!enabled) return vm.setToolEnabled(tool, false);
  await vm.refreshToolConfigValidation(tool);
  if (!vm.isToolConfigValid(tool)) return false;
  return vm.setToolEnabled(tool, true);
}

String _tildify(String p) {
  final home = Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'];
  return home != null && home.isNotEmpty && p.startsWith(home) ? '~${p.substring(home.length)}' : p;
}

class ToolSettingsRow extends StatefulWidget {
  const ToolSettingsRow({super.key, required this.tool, required this.viewModel});
  final AiToolType tool;
  final SettingsViewModel viewModel;

  @override
  State<ToolSettingsRow> createState() => _ToolSettingsRowState();
}

class _ToolSettingsRowState extends State<ToolSettingsRow> {
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && widget.viewModel.isToolEnabled(widget.tool)) widget.viewModel.refreshToolConfigValidation(widget.tool);
    });
  }

  String _t(String k, String f) => AppLocalizations.of(context)?.tr(k, f) ?? f;

  Future<void> _toggle(bool v) async {
    setState(() => _busy = true);
    final ok = await applyToolToggle(widget.viewModel, widget.tool, v);
    if (!mounted) return;
    setState(() => _busy = false);
    if (!ok && v) {
      showKcToast(context, _t('tool_enable_missing', '无法启用：未找到 {tool} 配置文件').replaceAll('{tool}', widget.tool.displayName),
          kind: KcToastKind.error);
    }
  }

  Future<void> _browse() async {
    final dir = await FilePicker.platform.getDirectoryPath(
      dialogTitle: _t('tool_pick_dir', '选择 {tool} 配置目录').replaceAll('{tool}', widget.tool.displayName),
    );
    if (dir == null || dir.isEmpty) return;
    await widget.viewModel.setToolConfigDir(widget.tool, dir);
    if (widget.viewModel.isToolEnabled(widget.tool)) await widget.viewModel.refreshToolConfigValidation(widget.tool);
  }

  @override
  Widget build(BuildContext context) {
    final vm = widget.viewModel;
    final tool = widget.tool;
    final kc = context.kc;
    final enabled = vm.isToolEnabled(tool);
    final valid = vm.isToolConfigValid(tool);
    final dir = vm.getToolConfigDir(tool) ?? vm.getDefaultToolConfigDir(tool);
    final custom = dir != vm.getDefaultToolConfigDir(tool);
    String file;
    try {
      file = _tildify(AiToolConfigService.expandPath(AiToolConfigService.getConfigFilePath(tool, customConfigDir: dir)));
    } catch (_) {
      file = _tildify(dir);
    }
    final chip = !enabled
        ? KcStatusChip(_t('tool_status_off', '未启用'))
        : valid
            ? KcStatusChip(_t('tool_status_ok', '已检测'), kind: KcChipKind.ok)
            : KcStatusChip(_t('tool_status_missing', '配置缺失'), kind: KcChipKind.warn);
    Widget iconBtn(Key key, IconData icon, String tip, VoidCallback onTap) => Tooltip(
          message: tip,
          child: InkWell(
            key: key,
            borderRadius: BorderRadius.circular(6),
            onTap: onTap,
            child: SizedBox(width: 26, height: 26, child: Icon(icon, size: 15, color: kc.text2)),
          ),
        );
    return KcSettingsRow(
      key: ValueKey('toolRow.${tool.value}'),
      leading: KcLogoBox(size: 28, radius: 7, child: KcToolLogo(tool: tool, size: 20)),
      title: tool.displayName,
      subtitle: file + (custom ? '  ·  ${_t('custom_path', '自定义')}' : ''),
      mono: true,
      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
        chip,
        const SizedBox(width: 6),
        if (custom)
          iconBtn(ValueKey('toolRow.reset.${tool.value}'), Icons.restart_alt, _t('reset_default_dir', '恢复默认目录'), () async {
            await vm.resetToolConfigDir(tool);
            if (vm.isToolEnabled(tool)) await vm.refreshToolConfigValidation(tool);
          }),
        iconBtn(ValueKey('toolRow.browse.${tool.value}'), Icons.folder_outlined, _t('browse_dir', '选择配置目录'), _browse),
        const SizedBox(width: 6),
        SizedBox(
          width: 32,
          child: _busy
              ? const Center(child: SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 1.5)))
              : KcSwitch(key: ValueKey('toolRow.switch.${tool.value}'), value: enabled, onChanged: _toggle),
        ),
      ]),
    );
  }
}
