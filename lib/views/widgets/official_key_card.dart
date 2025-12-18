import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'dart:math' as math;
import 'dart:ui' as ui;

/// 官方配置卡片组件（保持与 KeyCard 一致的视觉风格）
class OfficialKeyCard extends StatefulWidget {
  final bool isCurrent;
  final Widget icon;
  final String title;
  final String subtitle;
  final String description;
  final List<Widget> actions;
  final VoidCallback? onTap;

  const OfficialKeyCard({
    super.key,
    required this.isCurrent,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.description,
    required this.actions,
    this.onTap,
  });

  @override
  State<OfficialKeyCard> createState() => _OfficialKeyCardState();
}

class _OfficialKeyCardState extends State<OfficialKeyCard> {
  bool _isHovering = false;

  @override
  Widget build(BuildContext context) {
    final shadTheme = ShadTheme.of(context);
    
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovering = true),
      onExit: (_) => setState(() => _isHovering = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          // 基础背景色
          color: widget.isCurrent
              ? Color.alphaBlend(
                  shadTheme.colorScheme.primary.withOpacity(0.04),
                  shadTheme.colorScheme.card,
                )
              : shadTheme.colorScheme.card,
          border: Border.all(
            color: widget.isCurrent
                ? shadTheme.colorScheme.primary
                : shadTheme.colorScheme.border.withOpacity(0.8),
            width: widget.isCurrent ? 2 : 1.5,
          ),
          boxShadow: [
            if (_isHovering)
              BoxShadow(
                color: Colors.black.withOpacity(0.25),
                blurRadius: 24,
                offset: const Offset(0, 12),
                spreadRadius: 0,
              )
            else
              BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 4,
                offset: const Offset(0, 2),
                spreadRadius: 0,
              ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Stack(
            children: [
              // 1. 柔和的流光渐变（模拟环境光）
              // 左上角的高光
              Positioned(
                top: -100,
                left: -100,
                child: Container(
                  width: 300,
                  height: 300,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        shadTheme.colorScheme.primary.withOpacity(0.05),
                        Colors.transparent,
                      ],
                      stops: const [0.0, 1.0],
                    ),
                  ),
                ),
              ),
              // 右下角的反光
              Positioned(
                bottom: -100,
                right: -100,
                child: Container(
                  width: 300,
                  height: 300,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        shadTheme.colorScheme.secondary.withOpacity(0.05),
                        Colors.transparent,
                      ],
                      stops: const [0.0, 1.0],
                    ),
                  ),
                ),
              ),

              // 2. 噪点纹理（提供磨砂质感）
              Positioned.fill(
                child: Opacity(
                  opacity: 0.04, 
                  child: CustomPaint(
                    painter: _OfficialNoisePainter(
                      color: shadTheme.colorScheme.foreground,
                    ),
                  ),
                ),
              ),
              
              // 3. 内容层
              InkWell(
                onTap: widget.onTap,
                borderRadius: BorderRadius.circular(12),
                hoverColor: Colors.transparent,
                splashColor: Colors.transparent,
                highlightColor: Colors.transparent,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // 顶部：Logo + 标题区域
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Logo
                          Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(8),
                              color: shadTheme.colorScheme.muted,
                            ),
                            child: Center(
                              child: widget.icon,
                            ),
                          ),
                          const SizedBox(width: 10),
                          // 标题和副标题
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  widget.title,
                                  style: shadTheme.textTheme.p.copyWith(
                                    fontWeight: FontWeight.bold,
                                    color: shadTheme.colorScheme.foreground,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  widget.subtitle,
                                  style: shadTheme.textTheme.small.copyWith(
                                    color: shadTheme.colorScheme.mutedForeground,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8), // 与 KeyCard 一致的间距
                      // 中间：描述信息
                      SizedBox(
                        height: 24, // 固定高度
                        width: double.infinity,
                        child: Text(
                          widget.description,
                          style: shadTheme.textTheme.small.copyWith(
                            fontSize: 11,
                            color: shadTheme.colorScheme.mutedForeground,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const Spacer(),
                      // 底部：操作按钮组
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: widget.actions,
                      ),
                    ],
                  ),
                ),
              ),
              
              // 4. 悬浮在右上角的"当前"标签
              if (widget.isCurrent)
                Positioned(
                  top: 12,
                  right: 12,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: shadTheme.colorScheme.primary,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.1),
                          blurRadius: 4,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Text(
                      '当前',
                      style: shadTheme.textTheme.small.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 噪点纹理绘制器 (复制自 KeyCard)
class _OfficialNoisePainter extends CustomPainter {
  final Color color;
  final double density; 

  _OfficialNoisePainter({
    required this.color,
    this.density = 0.8,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.0;

    final random = math.Random(42); 

    for (int i = 0; i < size.width * size.height * 0.05 * density; i++) {
      final x = random.nextDouble() * size.width;
      final y = random.nextDouble() * size.height;
      
      paint.color = color.withOpacity(random.nextDouble() * 0.5);
      canvas.drawPoints(ui.PointMode.points, [Offset(x, y)], paint);
    }
  }

  @override
  bool shouldRepaint(covariant _OfficialNoisePainter oldDelegate) {
    return false; 
  }
}


