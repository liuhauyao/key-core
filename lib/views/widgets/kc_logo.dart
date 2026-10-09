// 统一的 logo 容器（ui_redesign_plan §4.6）：白底 + 1px 描边，暗色下仍保持白底，
// 保证 `fill="currentColor"` 的单色品牌 SVG 可见；不对 logo 做反色或 colorFilter。
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../models/mcp_server.dart' show AiToolType;
import '../../theme/kc_tokens.dart';

/// 侧栏和卡片用到的 5 个工具（顺序即展示顺序）
const List<AiToolType> kcKeyTools = [
  AiToolType.claudecode,
  AiToolType.claudeDesktop,
  AiToolType.codex,
  AiToolType.gemini,
  AiToolType.openclaw,
];

/// 工具 logo 资源（与 AppType.logoPath 一致）
String kcToolLogoAsset(AiToolType tool) {
  switch (tool) {
    case AiToolType.claudecode:
    case AiToolType.claudeDesktop:
      return 'assets/icons/platforms/claude-color.svg';
    case AiToolType.codex:
      return 'assets/icons/platforms/openai.svg';
    case AiToolType.gemini:
      return 'assets/icons/platforms/gemini-color.svg';
    case AiToolType.openclaw:
      return 'assets/icons/platforms/openclaw-color.svg';
    case AiToolType.cursor:
      return 'assets/icons/platforms/cursor.svg';
    case AiToolType.windsurf:
      return 'assets/icons/platforms/windsurf.svg';
  }
}

/// 工具短名（chip 用）
String kcToolShortName(AiToolType tool) {
  switch (tool) {
    case AiToolType.claudecode:
      return 'Claude';
    case AiToolType.claudeDesktop:
      return 'Desktop';
    case AiToolType.codex:
      return 'Codex';
    case AiToolType.gemini:
      return 'Gemini';
    case AiToolType.openclaw:
      return 'OpenClaw';
    case AiToolType.cursor:
      return 'Cursor';
    case AiToolType.windsurf:
      return 'Windsurf';
  }
}

/// 工具全名
String kcToolName(AiToolType tool) {
  switch (tool) {
    case AiToolType.claudecode:
      return 'Claude Code';
    case AiToolType.claudeDesktop:
      return 'Claude Desktop';
    default:
      return kcToolShortName(tool);
  }
}

/// 白底 logo 容器
class KcLogoBox extends StatelessWidget {
  const KcLogoBox({
    super.key,
    required this.child,
    this.size = 36,
    this.radius = KcRadius.logo,
    this.circle = false,
    this.background,
    this.bordered = true,
  });

  final Widget child;
  final double size;
  final double radius;
  final bool circle;

  /// 默认白底；首字回退时传 bg-subtle
  final Color? background;
  final bool bordered;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: background ?? KcLogo.containerBg,
        shape: circle ? BoxShape.circle : BoxShape.rectangle,
        borderRadius: circle ? null : BorderRadius.circular(radius),
        border: bordered ? Border.all(color: KcLogo.containerBorder, width: 1) : null,
      ),
      child: child,
    );
  }
}

/// 工具 logo（圆形白底）。Claude Desktop 在右下角叠一个小屏幕角标，与 Claude Code 区分。
class KcToolLogo extends StatelessWidget {
  const KcToolLogo({super.key, required this.tool, this.size = 18, this.logoSize});

  final AiToolType tool;
  final double size;
  final double? logoSize;

  @override
  Widget build(BuildContext context) {
    final inner = logoSize ?? (size * 0.7).roundToDouble();
    final box = KcLogoBox(
      size: size,
      circle: true,
      child: SvgPicture.asset(
        kcToolLogoAsset(tool),
        width: inner,
        height: inner,
        allowDrawingOutsideViewBox: true,
      ),
    );
    if (tool != AiToolType.claudeDesktop) return box;
    final badgeW = (size * 0.5).clamp(7.0, 12.0);
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          box,
          Positioned(
            right: -1,
            bottom: -1,
            child: Container(
              width: badgeW,
              height: badgeW * 0.75,
              decoration: BoxDecoration(
                color: KcToolColors.claudeDesktop,
                borderRadius: BorderRadius.circular(1.5),
                border: Border.all(color: KcLogo.containerBg, width: 1),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
