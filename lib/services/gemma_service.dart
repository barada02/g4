import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:flutter/foundation.dart';

/// Core AI model service using Gemma with streaming support
class GemmaService {
  GemmaService._internal();
  static final GemmaService instance = GemmaService._internal();

  final _gemma = FlutterGemmaPlugin.instance;
  dynamic _model;
  dynamic _chat;
  bool _initialised = false;
  bool _initializationAttempted = false;
  String? _initError;

  bool get isInitialised => _initialised;
  String? get initError => _initError;
  bool get initializationAttempted => _initializationAttempted;

  /// Initialize Gemma model - requires model to be installed on device
  /// The flutter_gemma plugin handles model discovery automatically
  Future<void> init() async {
    if (_initializationAttempted) return;
    _initializationAttempted = true;

    try {
      debugPrint('📥 Initializing Gemma 4 E2B model...');
      
      // Try to create model - flutter_gemma plugin discovers installed models
      _model = await _gemma.createModel(
        modelType: ModelType.gemmaIt,
        maxTokens: 2048,
      );

      // Create chat session from the model
      _chat = await _model.createChat(
        randomSeed: 42,
        temperature: 0.7,
        topK: 40,
        topP: 0.95,
      );

      _initialised = true;
      _initError = null;
      debugPrint('✅ GemmaService initialized successfully');
    } catch (e) {
      _initError = e.toString();
      _initialised = false;
      debugPrint('❌ GemmaService initialization error: $e');
      
      // Show helpful message about model setup
      if (e.toString().contains('No active inference model')) {
        debugPrint('⚠️ Model not found. The Gemma model needs to be installed on your device.');
        debugPrint('ℹ️ Please install the model through the flutter_gemma setup process.');
      }
    }
  }

  /// Send message and stream response token by token
  Future<void> sendWithStreaming({
    required String text,
    required Function(String) onToken,
    required Function(MessageStats) onComplete,
  }) async {
    if (!_initialised || _chat == null) {
      throw Exception('GemmaService not initialized. Error: $_initError');
    }

    try {
      final startTime = DateTime.now();
      DateTime? firstTokenTime;
      int tokenCount = 0;
      final buffer = StringBuffer();

      // Add user message to chat
      await _chat.addMessage(text);

      // Stream response token by token
      await _chat.streamResponse(
        (token) {
          firstTokenTime ??= DateTime.now();
          tokenCount++;
          buffer.write(token);
          onToken(token);
        },
      );

      final response = buffer.toString();

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

  /// Clear chat session
  Future<void> clearChat() async {
    if (_chat != null) {
      await _chat.clear();
    }
    debugPrint('🗑️ Chat cleared');
  }

  /// Cleanup resources
  Future<void> dispose() async {
    _chat = null;
    _model = null;
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
