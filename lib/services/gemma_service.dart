import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import 'package:http/http.dart' as http;

// Direct model URL (no authentication needed)
const String modelUrl = 'https://huggingface.co/litert-community/gemma-4-E2B-it-litert-lm/resolve/main/gemma-4-E2B-it.litertlm';
const String modelFileName = 'gemma-4-E2B-it.litertlm';

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
  bool _isDownloading = false;
  int _downloadProgress = 0; // 0-100

  bool get isInitialised => _initialised;
  String? get initError => _initError;
  bool get initializationAttempted => _initializationAttempted;
  bool get isDownloading => _isDownloading;
  int get downloadProgress => _downloadProgress;

  /// Download model from HuggingFace if not already present
  Future<String?> _downloadModelIfNeeded() async {
    try {
      final appDir = await getApplicationDocumentsDirectory();
      final modelPath = '${appDir.path}/$modelFileName';
      final modelFile = File(modelPath);

      // If model already exists locally, use it
      if (await modelFile.exists()) {
        debugPrint('✅ Model already downloaded at: $modelPath');
        return modelPath;
      }

      debugPrint('📥 Starting model download from HuggingFace...');
      _isDownloading = true;
      _downloadProgress = 0;

      // Download model file
      final request = http.Request('GET', Uri.parse(modelUrl));
      final streamedResponse = await request.send();

      if (streamedResponse.statusCode != 200) {
        throw Exception(
          'Failed to download model: ${streamedResponse.statusCode}',
        );
      }

      final totalSize = streamedResponse.contentLength ?? 0;
      debugPrint('📦 Model size: ${(totalSize / 1024 / 1024).toStringAsFixed(2)} MB');

      final bytes = <int>[];
      int downloadedBytes = 0;

      // Stream the download with progress updates
      await streamedResponse.stream.forEach((chunk) {
        bytes.addAll(chunk);
        downloadedBytes += chunk.length;
        if (totalSize > 0) {
          _downloadProgress = ((downloadedBytes / totalSize) * 100).toInt();
          debugPrint(
            '⬇️ Download progress: $_downloadProgress% '
            '(${(downloadedBytes / 1024 / 1024).toStringAsFixed(2)} MB / '
            '${(totalSize / 1024 / 1024).toStringAsFixed(2)} MB)',
          );
        }
      });

      // Save to file
      await modelFile.writeAsBytes(bytes);
      debugPrint('✅ Model downloaded successfully: ${bytes.length} bytes');
      debugPrint('💾 Model saved at: $modelPath');

      _downloadProgress = 100;
      _isDownloading = false;
      return modelPath;
    } catch (e) {
      _isDownloading = false;
      _downloadProgress = 0;
      debugPrint('❌ Download error: $e');
      rethrow;
    }
  }

  /// Initialize Gemma model - downloads if needed and configures flutter_gemma
  Future<void> init({Function(int)? onDownloadProgress}) async {
    if (_initializationAttempted) return;
    _initializationAttempted = true;

    try {
      debugPrint('🚀 Initializing Gemma 4 E2B model...');

      // Download model if not already present
      debugPrint('📋 Checking for local model...');
      final modelPath = await _downloadModelIfNeeded();

      if (modelPath == null) {
        throw Exception('Failed to get model path');
      }

      debugPrint('⚙️ Configuring flutter_gemma with model at: $modelPath');

      // Create model instance with the local model
      _model = await _gemma.createModel(
        modelType: ModelType.gemmaIt,
        maxTokens: 2048,
      );

      debugPrint('💬 Creating chat session...');

      // Create chat session from the model
      _chat = await _model.createChat(
        randomSeed: 42,
        temperature: 0.7,
        topK: 40,
        topP: 0.95,
      );

      _initialised = true;
      _initError = null;
      debugPrint('✅ GemmaService initialized successfully!');
    } catch (e) {
      _initError = e.toString();
      _initialised = false;
      debugPrint('❌ GemmaService initialization error: $e');

      // Show helpful message about what went wrong
      if (e.toString().contains('No active inference model')) {
        debugPrint(
          '⚠️ Model not activated. Make sure the flutter_gemma plugin '
          'is properly installed.',
        );
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
