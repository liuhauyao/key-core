// skills_viewmodel getSyncSummary：按技能计数（修复原先按 技能×工具 组合计数，导致「已同步 6 / 共 3」这类数字）
import 'package:flutter_test/flutter_test.dart';
import 'package:key_core/models/skill.dart';
import 'package:key_core/viewmodels/skills_viewmodel.dart';

final _t = DateTime(2026, 1, 1);
Skill sk(String id, Map<SkillTargetTool, SkillSyncState> st, {bool active = true, List<SkillTargetTool>? tools}) => Skill(
      skillId: id,
      relativePath: id,
      name: id,
      description: '',
      enabledTools: tools ?? st.keys.toList(),
      syncStatus: st,
      isActive: active,
      createdAt: _t,
      updatedAt: _t,
    );

void main() {
  const c = SkillTargetTool.claudecode, x = SkillTargetTool.codex;
  test('每个技能只计一次：冲突 > 待同步 > 已同步', () {
    final s = SkillsViewModel.summarizeSkills([
      sk('a', {c: SkillSyncState.synced, x: SkillSyncState.synced}),
      sk('b', {c: SkillSyncState.synced, x: SkillSyncState.outdated}),
      sk('c', {c: SkillSyncState.conflict, x: SkillSyncState.notSynced}),
    ]);
    expect(s.total, 3);
    expect(s.synced, 1);
    expect(s.pending, 1);
    expect(s.conflicts, 1);
    expect(s.synced + s.pending + s.conflicts, lessThanOrEqualTo(s.total));
  });

  test('停用的技能不计入状态；启用了工具但无状态视为待同步', () {
    final s = SkillsViewModel.summarizeSkills([
      sk('a', {c: SkillSyncState.synced}, active: false),
      sk('b', {}, tools: [c]),
      sk('d', {}, tools: []),
    ]);
    expect(s.total, 3);
    expect(s.synced, 0);
    expect(s.pending, 1);
    expect(s.conflicts, 0);
  });
}
