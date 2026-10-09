import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:key_core/theme/kc_tokens.dart';

Future<KcTokens> _resolve(WidgetTester tester, {required Brightness material, required Brightness shad}) async {
  late KcTokens got;
  await tester.pumpWidget(MaterialApp(
    theme: KcTheme.material(material),
    home: ShadTheme(
      data: KcTheme.shad(shad),
      child: Builder(builder: (c) {
        got = c.kc;
        return const SizedBox();
      }),
    ),
  ));
  return got;
}

void main() {
  test('操作色为 #007AFF（浅）/ #0A84FF（深），生效中用绿色而非蓝色', () {
    expect(KcColorSchemes.light.primary, const Color(0xFF007AFF));
    expect(KcColorSchemes.dark.primary, const Color(0xFF0A84FF));
    expect(KcTokens.light.ok, isNot(KcColorSchemes.light.primary));
    expect(KcTokens.dark.ok, isNot(KcColorSchemes.dark.primary));
  });

  test('Material 主题挂上了 KcTokens 扩展', () {
    expect(KcTheme.material(Brightness.light).extension<KcTokens>(), KcTokens.light);
    expect(KcTheme.material(Brightness.dark).extension<KcTokens>(), KcTokens.dark);
  });

  testWidgets('context.kc 跟随 ShadTheme 亮度', (tester) async {
    expect(await _resolve(tester, material: Brightness.light, shad: Brightness.light), KcTokens.light);
    expect(await _resolve(tester, material: Brightness.dark, shad: Brightness.dark), KcTokens.dark);
    expect(await _resolve(tester, material: Brightness.light, shad: Brightness.dark), KcTokens.dark);
  });

  test('lerp 两端值正确', () {
    expect(KcTokens.light.lerp(KcTokens.dark, 0).sidebar, KcTokens.light.sidebar);
    expect(KcTokens.light.lerp(KcTokens.dark, 1).sidebar, KcTokens.dark.sidebar);
  });
}
