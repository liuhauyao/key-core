import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import '../../models/skill.dart';
import '../../services/skill_parser_service.dart';
import '../../services/skills_path_service.dart';
import '../../utils/app_localizations.dart';
import '../widgets/kc_toast.dart';
import '../../viewmodels/skills_viewmodel.dart';

/// 技能模板
class _SkillTemplate {
  final String name;
  final String description;
  final String body;
  final List<String> tags;
  final IconData icon;

  const _SkillTemplate({
    required this.name,
    required this.description,
    required this.body,
    this.tags = const [],
    required this.icon,
  });
}

/// 内置创建模板
const _kSkillTemplates = <_SkillTemplate>[
  _SkillTemplate(
    name: 'Code Review',
    description: 'Automated code review checklist and best practices',
    body: '''You are a code review assistant. When reviewing code, check for:
- Correctness: Does the code do what it intends?
- Performance: Are there obvious performance issues?
- Security: Are there any security vulnerabilities?
- Maintainability: Is the code easy to understand and modify?
- Style: Does the code follow project conventions?

Provide actionable feedback, not just criticism.''',
    tags: ['review', 'best-practices'],
    icon: Icons.rate_review_outlined,
  ),
  _SkillTemplate(
    name: 'Documentation Generator',
    description: 'Generate comprehensive documentation from code',
    body: '''You are a documentation assistant. For any code provided:
1. Write a clear summary of what the code does
2. Document all public APIs with parameters and return types
3. Include usage examples where applicable
4. Note any side effects or edge cases

Use clear, concise language suitable for developers of all levels.''',
    tags: ['docs', 'writing'],
    icon: Icons.description_outlined,
  ),
  _SkillTemplate(
    name: 'Test Writer',
    description: 'Generate comprehensive unit and integration tests',
    body: '''You are a testing assistant. Write tests following these guidelines:
- Name test cases clearly describing the scenario
- Follow the Arrange-Act-Assert pattern
- Cover edge cases (empty, null, error states)
- Test both success and failure paths
- Mock external dependencies appropriately
- Include meaningful assertions, not just "doesn't throw"

Output the test file contents ready to save.''',
    tags: ['testing', 'quality'],
    icon: Icons.science_outlined,
  ),
  _SkillTemplate(
    name: 'Custom (Empty)',
    description: 'Start from a blank skill',
    body: '',
    tags: [],
    icon: Icons.add_circle_outline,
  ),
];

class SkillFormPage extends StatefulWidget {
  final Skill? skill;

  const SkillFormPage({super.key, this.skill});

  @override
  State<SkillFormPage> createState() => _SkillFormPageState();
}

class _SkillFormPageState extends State<SkillFormPage> {
  final _formKey = GlobalKey<FormState>();
  final _skillIdController = TextEditingController();
  final _nameController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _notesController = TextEditingController();
  final _bodyController = TextEditingController();
  final _categoryController = TextEditingController();
  final _tagController = TextEditingController();
  final _tagFocusNode = FocusNode();

  final _parserService = SkillParserService();
  bool _isSaving = false;
  bool _isLoading = false;
  final Set<SkillTargetTool> _enabledTools = {};
  final List<String> _tags = [];
  bool _showTemplatePicker = true; // 在创建模式下初始显示模板选择

  bool get _isEditing => widget.skill != null;

  @override
  void initState() {
    super.initState();
    if (_isEditing) {
      _showTemplatePicker = false;
      _loadExistingSkill();
    } else {
      _enabledTools.addAll(SkillsPathService.defaultEnabledTools);
    }
  }

  Future<void> _loadExistingSkill() async {
    final skill = widget.skill!;
    setState(() => _isLoading = true);

    _skillIdController.text = skill.skillId;
    _nameController.text = skill.name;
    _descriptionController.text = skill.description ?? '';
    _notesController.text = skill.notes ?? '';
    _enabledTools.addAll(skill.enabledTools);
    if (skill.tags != null) _tags.addAll(skill.tags!);

    try {
      final content = await context.read<SkillsViewModel>().readSkillContent(skill);
      final parsed = _parserService.parseSkillMd(content);
      _bodyController.text = parsed.body;
    } catch (_) {}

    if (mounted) setState(() => _isLoading = false);
  }

  @override
  void dispose() {
    _skillIdController.dispose();
    _nameController.dispose();
    _descriptionController.dispose();
    _notesController.dispose();
    _bodyController.dispose();
    _categoryController.dispose();
    _tagController.dispose();
    _tagFocusNode.dispose();
    super.dispose();
  }

  void _applyTemplate(_SkillTemplate template) {
    setState(() {
      _showTemplatePicker = false;
      if (_skillIdController.text.isEmpty) {
        // Generate an id from the template name
        _skillIdController.text = template.name
            .toLowerCase()
            .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
            .replaceAll(RegExp(r'-+'), '-')
            .replaceAll(RegExp(r'^-|-$'), '');
      }
      // Custom template has an empty name — user fills it in
      if (template.name != 'Custom (Empty)') {
        _nameController.text = template.name;
      }
      _descriptionController.text = template.description;
      _bodyController.text = template.body;
      _tags.clear();
      _tags.addAll(template.tags);
    });
  }

  void _addTag(String tag) {
    final trimmed = tag.trim();
    if (trimmed.isEmpty) return;
    if (_tags.contains(trimmed)) return;
    setState(() => _tags.add(trimmed));
    _tagController.clear();
  }

  void _removeTag(String tag) {
    setState(() => _tags.remove(tag));
  }

  @override
  Widget build(BuildContext context) {
    final shadTheme = ShadTheme.of(context);
    final localizations = AppLocalizations.of(context);

    return Scaffold(
      backgroundColor: shadTheme.colorScheme.background,
      appBar: AppBar(
        backgroundColor: shadTheme.colorScheme.background,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(false),
        ),
        title: Text(
          _isEditing
              ? (localizations?.skillsEdit ?? 'Edit Skill')
              : (localizations?.skillsCreate ?? 'Create Skill'),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: ShadButton(
              onPressed: _isSaving || _isLoading ? null : _save,
              child: Text(localizations?.save ?? 'Save'),
            ),
          ),
        ],
      ),
      body: _isLoading
          ? Center(child: CircularProgressIndicator(color: shadTheme.colorScheme.primary))
          : Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.all(24),
                children: [
                  // ── Template picker (new skill only) ──
                  if (!_isEditing && _showTemplatePicker) ...[
                    _sectionTitle(localizations?.skillsStartFromTemplate ?? 'Start from template', shadTheme),
                    const SizedBox(height: 12),
                    _buildTemplateGrid(shadTheme),
                    const SizedBox(height: 24),
                  ],

                  // ── Basic Info ──
                  _sectionTitle(localizations?.skillsBasicInfo ?? 'Basic Info', shadTheme),
                  const SizedBox(height: 12),
                  _buildField(
                    label: localizations?.skillsId ?? 'Skill ID',
                    child: ShadInput(
                      controller: _skillIdController,
                      enabled: !_isEditing,
                      placeholder: Text(localizations?.skillsIdHint ?? 'my-skill'),
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (!_isEditing)
                    _buildField(
                      label: localizations?.skillsCategory ?? 'Category (optional)',
                      child: ShadInput(
                        controller: _categoryController,
                        placeholder: Text(localizations?.skillsCategoryHint ?? 'shipping'),
                      ),
                    ),
                  if (!_isEditing) const SizedBox(height: 12),
                  _buildField(
                    label: localizations?.skillsName ?? 'Name',
                    child: ShadInput(
                      controller: _nameController,
                      placeholder: Text(localizations?.skillsNameHint ?? 'My Skill'),
                    ),
                  ),
                  const SizedBox(height: 12),
                  _buildField(
                    label: localizations?.skillsDescription ?? 'Description',
                    child: ShadInput(
                      controller: _descriptionController,
                      placeholder: Text(localizations?.skillsDescriptionHint ?? 'What this skill does'),
                    ),
                  ),
                  const SizedBox(height: 12),
                  _buildField(
                    label: localizations?.notes ?? 'Notes',
                    child: ShadInput(controller: _notesController),
                  ),

                  // ── Tags ──
                  const SizedBox(height: 20),
                  _sectionTitle('Tags', shadTheme),
                  const SizedBox(height: 8),
                  _buildTagsArea(shadTheme),
                  const SizedBox(height: 20),

                  // ── Target Tools ──
                  _sectionTitle(localizations?.skillsTargetTools ?? 'Target Tools', shadTheme),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 12,
                    runSpacing: 8,
                    children: SkillsPathService.supportedTools.map((tool) {
                      return FilterChip(
                        label: Text(tool.displayName),
                        selected: _enabledTools.contains(tool),
                        onSelected: (selected) {
                          setState(() {
                            if (selected) {
                              _enabledTools.add(tool);
                            } else {
                              _enabledTools.remove(tool);
                            }
                          });
                        },
                      );
                    }).toList(),
                  ),

                  // ── SKILL.md Content ──
                  const SizedBox(height: 24),
                  _sectionTitle(localizations?.skillsContent ?? 'SKILL.md Content', shadTheme),
                  const SizedBox(height: 12),
                  Container(
                    decoration: BoxDecoration(
                      color: shadTheme.colorScheme.muted,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: shadTheme.colorScheme.border),
                    ),
                    padding: const EdgeInsets.all(12),
                    child: TextField(
                      controller: _bodyController,
                      maxLines: 16,
                      style: shadTheme.textTheme.p,
                      decoration: InputDecoration(
                        border: InputBorder.none,
                        hintText: localizations?.skillsContentHint ?? 'Skill instructions...',
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildTemplateGrid(ShadThemeData shadTheme) {
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: _kSkillTemplates.map((template) {
        final isCustom = template.name == 'Custom (Empty)';
        return GestureDetector(
          onTap: () => _applyTemplate(template),
          child: Container(
            width: 160,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              color: isCustom
                  ? shadTheme.colorScheme.muted.withOpacity(0.3)
                  : shadTheme.colorScheme.primary.withOpacity(0.04),
              border: Border.all(
                color: isCustom
                    ? shadTheme.colorScheme.border
                    : shadTheme.colorScheme.primary.withOpacity(0.2),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(template.icon, size: 24, color: shadTheme.colorScheme.primary),
                const SizedBox(height: 10),
                Text(template.name,
                    style: shadTheme.textTheme.p.copyWith(fontWeight: FontWeight.w600)),
                const SizedBox(height: 4),
                Text(
                  template.description,
                  style: shadTheme.textTheme.small.copyWith(
                    color: shadTheme.colorScheme.mutedForeground,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildTagsArea(ShadThemeData shadTheme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Tag chips
        if (_tags.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Wrap(
              spacing: 6,
              runSpacing: 4,
              children: _tags.map((tag) {
                return Chip(
                  label: Text(tag, style: const TextStyle(fontSize: 12)),
                  deleteIcon: const Icon(Icons.close, size: 16),
                  onDeleted: () => _removeTag(tag),
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  visualDensity: VisualDensity.compact,
                );
              }).toList(),
            ),
          ),

        // Tag input row
        Row(
          children: [
            Expanded(
              child: SizedBox(
                height: 38,
                child: ShadInput(
                  controller: _tagController,
                  focusNode: _tagFocusNode,
                  placeholder: const Text('Add tag...'),
                  onSubmitted: (value) {
                    _addTag(value);
                    _tagFocusNode.requestFocus();
                  },
                ),
              ),
            ),
            const SizedBox(width: 8),
            ShadButton(
              width: 38,
              height: 38,
              padding: EdgeInsets.zero,
              onPressed: () {
                _addTag(_tagController.text);
                _tagFocusNode.requestFocus();
              },
              child: const Icon(Icons.add, size: 18),
            ),
          ],
        ),
      ],
    );
  }

  Widget _sectionTitle(String title, ShadThemeData shadTheme) {
    return Text(title, style: shadTheme.textTheme.h4);
  }

  Widget _buildField({required String label, required Widget child}) {
    final shadTheme = ShadTheme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: shadTheme.textTheme.small.copyWith(fontWeight: FontWeight.w600)),
        const SizedBox(height: 6),
        child,
      ],
    );
  }

  Future<void> _save() async {
    final localizations = AppLocalizations.of(context);
    final viewModel = context.read<SkillsViewModel>();

    final skillId = _skillIdController.text.trim();
    final name = _nameController.text.trim();
    final description = _descriptionController.text.trim();

    if (skillId.isEmpty || name.isEmpty || description.isEmpty) {
      showKcToast(context, localizations?.skillsValidationRequired ?? 'Please fill required fields', kind: KcToastKind.success);
      return;
    }

    setState(() => _isSaving = true);

    final content = _parserService.generateSkillMd(
      name: name,
      description: description,
      body: _bodyController.text,
    );

    bool success;
    if (_isEditing) {
      success = await viewModel.updateSkill(
        widget.skill!.copyWith(
          name: name,
          description: description,
          notes: _notesController.text.trim().isEmpty ? null : _notesController.text.trim(),
          enabledTools: _enabledTools.toList(),
          tags: _tags.isEmpty ? null : List.from(_tags),
        ),
        skillMdContent: content,
      );
    } else {
      success = await viewModel.addSkill(
        skillId: skillId,
        name: name,
        description: description,
        body: _bodyController.text,
        enabledTools: _enabledTools.toList(),
        tags: _tags.isEmpty ? null : List.from(_tags),
        notes: _notesController.text.trim().isEmpty ? null : _notesController.text.trim(),
        categoryPath: _categoryController.text.trim().isEmpty ? null : _categoryController.text.trim(),
      );
    }

    if (!mounted) return;
    setState(() => _isSaving = false);

    if (success) {
      Navigator.of(context).pop(true);
    } else {
      showKcToast(context, viewModel.errorMessage ?? localizations?.skillsSaveFailed ?? 'Save failed', kind: KcToastKind.success);
    }
  }
}
