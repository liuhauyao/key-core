import '../models/mcp_server.dart';
import '../models/prompt.dart';
import '../services/prompts/prompt_service.dart';
import 'base_viewmodel.dart';

/// 系统提示词 ViewModel
class PromptsViewModel extends BaseViewModel {
  PromptsViewModel({PromptService? service}) : _service = service ?? PromptService();

  final PromptService _service;

  AiToolType _tool = PromptService.supportedTools.first;
  List<Prompt> _prompts = const [];
  String? _filePath;
  bool _liveFileExists = false;

  AiToolType get tool => _tool;
  List<Prompt> get prompts => _prompts;
  String? get filePath => _filePath;
  bool get liveFileExists => _liveFileExists;
  List<AiToolType> get tools => PromptService.supportedTools;

  Future<void> init() async {
    await executeAsync(() async {
      await _service.importOnFirstLaunch();
      await _load();
    });
  }

  Future<void> selectTool(AiToolType tool) async {
    _tool = tool;
    await executeAsync(_load);
  }

  Future<void> _load() async {
    _filePath = await _service.promptFilePath(_tool);
    _liveFileExists = await _service.currentFileContent(_tool) != null;
    _prompts = await _service.getPrompts(_tool);
    notifyListeners();
  }

  Future<bool> save({int? id, required String name, required String content, String? description}) async {
    final result = await executeAsync(() async {
      final now = DateTime.now();
      final existing = id == null ? null : _prompts.where((p) => p.id == id).firstOrNull;
      await _service.upsert(existing != null
          ? existing.copyWith(name: name, content: content, description: description, updatedAt: now)
          : Prompt(
              tool: _tool,
              name: name,
              content: content,
              description: description,
              createdAt: now,
              updatedAt: now,
            ));
      await _load();
      return true;
    });
    return result ?? false;
  }

  Future<bool> setEnabled(Prompt prompt, bool enabled) async {
    final result = await executeAsync(() async {
      if (enabled) {
        await _service.enable(_tool, prompt.id!);
      } else {
        await _service.disable(_tool, prompt.id!);
      }
      await _load();
      return true;
    });
    return result ?? false;
  }

  Future<bool> delete(Prompt prompt) async {
    final result = await executeAsync(() async {
      await _service.delete(_tool, prompt.id!);
      await _load();
      return true;
    });
    return result ?? false;
  }

  Future<bool> importFromFile() async {
    final result = await executeAsync(() async {
      await _service.importFromFile(_tool);
      await _load();
      return true;
    });
    return result ?? false;
  }
}
