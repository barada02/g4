import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:flutter/foundation.dart';

// Direct model URL (no authentication needed)
const String modelUrl = 'https://huggingface.co/litert-community/gemma-4-E2B-it-litert-lm/resolve/main/gemma-4-E2B-it.litertlm';

/// Core AI model service using Gemma with streaming support
class GemmaService {
  GemmaService._internal();
  static final GemmaService instance = GemmaService._internal();

  final _gemma = FlutterGemmaPlugin.instance;
  dynamic _model;
  bool _initialised = false;
  final List<Map<String, String>> _chatHistory = [];

  bool get isInitialised => _initialised;

  /// Initialize Gemma model from direct download URL
  Future<void> init() async {
    if (_initialised) return;

    try {
      debugPrint('📥 Initializing Gemma 4 E2B model...');
      
      // Create model using flutter_gemma API
      _model = await _gemma.createModel(
        modelType: ModelType.gemmaIt,
        maxTokens: 2048,
      );

      _initialised = true;
      _chatHistory.clear();
      debugPrint('✅ GemmaService initialized successfully');
    } catch (e) {
      debugPrint('❌ GemmaService initialization error: $e');
      rethrow;
    }
  }

  /// Send message and stream response token by token
  Future<void> sendWithStreaming({
    required String text,
    required Function(String) onToken,
    required Function(MessageStats) onComplete,
  }) async {
    if (!_initialised || _model == null) {
      throw Exception('GemmaService not initialized');
    }

    try {
      final startTime = DateTime.now();
      DateTime? firstTokenTime;
      int tokenCount = 0;
      final buffer = StringBuffer();

      // Add user message to history
      _chatHistory.add({'role': 'user', 'content': text});

      // Build chat context from history
      final prompt = _buildChatPrompt();

      // Generate response with streaming
      await _model.generateResponse(
        prompt: prompt,
        streaming: true,
        onToken: (token) {
          firstTokenTime ??= DateTime.now();
          tokenCount++;
          buffer.write(token);
          onToken(token);
        },
      );

      final response = buffer.toString();
      
      // Add assistant response to history
      _chatHistory.add({'role': 'assistant', 'content': response});

      final stats = MessageStats(
        totalTokens: tokenCount,
        timeToFirstToken: firstTokenTime?.difference(startTime).inMilliseconds,
        totalTime: DateTime.now().difference(startTime).inMilliseconds,
      );
      onComplete(stats);
    } catch (e) {
      debugPrint('❌ Stream error: $e');
      rethrow;
    }
  }

  /// Build chat prompt from history
  String _buildChatPrompt() {
    final buffer = StringBuffer();
    
    for (final msg in _chatHistory) {
      final role = msg['role'] == 'user' ? 'user' : 'model';
      buffer.writeln('$role: ${msg['content']}');
    }
    
    buffer.write('model: ');
    return buffer.toString();
  }

  /// Clear chat session
  void clearChat() {
    _chatHistory.clear();
    debugPrint('🗑️ Chat history cleared');
  }

  /// Cleanup resources
  Future<void> dispose() async {
    _model = null;
    _chatHistory.clear();
    _initialised = false;
    debugPrint('🛑 GemmaService disposed');
  }
}

/// Statistics from streaming response
class MessageStats {
  final int totalTokens;
  final int? timeToFirstToken; // ms to first token
  final int totalTime; // Total response time

  MessageStats({
    required this.totalTokens,
    this.timeToFirstToken,
    required this.totalTime,
  });

  String get formattedStats {
    final ttft = timeToFirstToken ?? 0;
    return 'Tokens: $totalTokens | TTFT: ${ttft}ms | Total: ${totalTime}ms';
  }
}
