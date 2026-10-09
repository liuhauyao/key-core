import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import '../../models/skill.dart';
import '../../services/skill_parser_service.dart';
import '../../services/skills_path_service.dart';
import '../../utils/app_localizations.dart';
import '../../viewmodels/skills_viewmodel.dart';
import '../widgets/ime_safe_text_field.dart';

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

  final _parserService = SkillParserService();
  bool _isSaving = false;
  bool _isLoading = false;
  final Set<SkillTargetTool> _enabledTools = {};

  bool get _isEditing => widget.skill != null;

  @override
  void initState() {
    super.initState();
    if (_isEditing) {
      _loadExistingSkill();
    } else {
      _enabledTools.addAll(SkillsPathService.supportedTools);
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
    super.dispose();
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
                  const SizedBox(height: 24),
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
                    child: ImeSafeTextField(
                      controller: _bodyController,
                      maxLines: 16,
                      hintText: localizations?.skillsContentHint ?? 'Skill instructions...',
                      isDark: Theme.of(context).brightness == Brightness.dark,
                    ),
                  ),
                ],
              ),
            ),
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(localizations?.skillsValidationRequired ?? 'Please fill required fields')),
      );
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
        notes: _notesController.text.trim().isEmpty ? null : _notesController.text.trim(),
        categoryPath: _categoryController.text.trim().isEmpty ? null : _categoryController.text.trim(),
      );
    }

    if (!mounted) return;
    setState(() => _isSaving = false);

    if (success) {
      Navigator.of(context).pop(true);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(viewModel.errorMessage ?? localizations?.skillsSaveFailed ?? 'Save failed')),
      );
    }
  }
}
