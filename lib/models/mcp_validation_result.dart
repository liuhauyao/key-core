import 'mcp_tool.dart';

/// MCP 校验结果
class McpValidationResult {
  final bool isValid;
  final String? error;
  final List<McpTool> tools;
  final DateTime timestamp;

  const McpValidationResult({
    required this.isValid,
    this.error,
    this.tools = const [],
    required this.timestamp,
  });

  factory McpValidationResult.success(List<McpTool> tools) {
    return McpValidationResult(
      isValid: true,
      tools: tools,
      timestamp: DateTime.now(),
    );
  }

  factory McpValidationResult.failure(String error) {
    return McpValidationResult(
      isValid: false,
      error: error,
      timestamp: DateTime.now(),
    );
  }
}

