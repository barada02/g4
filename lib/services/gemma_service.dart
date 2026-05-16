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
  String _downloadStatus = '';

  bool get isInitialised => _initialised;
  String? get initError => _initError;
  bool get initializationAttempted => _initializationAttempted;
  bool get isDownloading => _isDownloading;
  int get downloadProgress => _downloadProgress;
  String get downloadStatus => _downloadStatus;

  /// Update download progress for UI
  void _updateProgress(int progress, String status) {
    _downloadProgress = progress;
    _downloadStatus = status;
    debugPrint('📊 $status ($_downloadProgress%)');
  }

  /// Download model from HuggingFace if not already present
  Future<String?> _downloadModelIfNeeded() async {
    try {
      final appDir = await getApplicationDocumentsDirectory();
      final modelPath = '${appDir.path}/$modelFileName';
      final modelFile = File(modelPath);

      // If model already exists locally, use it
      if (await modelFile.exists()) {
        _updateProgress(100, 'Model found locally');
        debugPrint('✅ Model already downloaded at: $modelPath');
        return modelPath;
      }

      _updateProgress(0, 'Starting model download...');
      _isDownloading = true;

      debugPrint('📥 Downloading Gemma 4 E2B model...');
      debugPrint('📍 URL: $modelUrl');
      debugPrint('💾 Destination: $modelPath');

      // Download model file
      final request = http.Request('GET', Uri.parse(modelUrl));
      final streamedResponse = await request.send();

      if (streamedResponse.statusCode != 200) {
        throw Exception(
          'HTTP Error ${streamedResponse.statusCode}: Failed to download model',
        );
      }

      final totalSize = streamedResponse.contentLength ?? 0;
      if (totalSize <= 0) {
        throw Exception('Unknown model size - cannot download');
      }

      _updateProgress(1, 'Downloading (${(totalSize / 1024 / 1024).toStringAsFixed(1)} MB)');
      debugPrint('📦 Total model size: ${(totalSize / 1024 / 1024).toStringAsFixed(2)} MB');

      // Stream directly to file without buffering to avoid OOM
      final sink = modelFile.openWrite();
      int downloadedBytes = 0;
      int lastProgressUpdate = 0;

      try {
        // Stream the download directly to file
        await streamedResponse.stream.forEach((chunk) {
          sink.add(chunk);
          downloadedBytes += chunk.length;

          // Update progress every 1% or at least every 5MB
          int currentProgress = ((downloadedBytes / totalSize) * 100).toInt();
          if (currentProgress - lastProgressUpdate >= 1 || 
              (downloadedBytes - lastProgressUpdate * (totalSize ~/ 100)) >= 5 * 1024 * 1024) {
            _updateProgress(
              currentProgress,
              'Downloading ${(downloadedBytes / 1024 / 1024).toStringAsFixed(1)}/'
              '${(totalSize / 1024 / 1024).toStringAsFixed(1)} MB',
            );
            lastProgressUpdate = currentProgress;
          }
        });
        
        // Close the sink and wait for all data to be written
        await sink.close();
      } catch (e) {
        await sink.close();
        rethrow;
      }

      _updateProgress(100, 'Model downloaded successfully!');
      _isDownloading = false;
      
      debugPrint('✅ Model saved successfully: $downloadedBytes bytes');
      debugPrint('📍 Model path: $modelPath');

      return modelPath;
    } catch (e) {
      _isDownloading = false;
      _downloadProgress = 0;
      _downloadStatus = 'Download failed: $e';
      debugPrint('❌ Download error: $e');
      rethrow;
    }
  }

  /// Initialize Gemma model - downloads if needed
  Future<void> init({Function(int, String)? onProgress}) async {
    if (_initializationAttempted) return;
    _initializationAttempted = true;

    try {
      // PHASE 1: Download model if needed (with UI updates)
      _updateProgress(5, 'Checking for model...');
      final modelPath = await _downloadModelIfNeeded();

      if (modelPath == null) {
        throw Exception('Failed to obtain model path');
      }

      // Ensure download is fully complete
      if (GemmaService.instance.isDownloading) {
        throw Exception('Download still in progress - initialization delayed');
      }

      // PHASE 2: Initialize model only AFTER download is 100% complete
      _updateProgress(70, 'Setting up model...');
      debugPrint('⚙️ Creating model instance...');

      // Create model - flutter_gemma plugin will use the downloaded model
      try {
        _model = await _gemma.createModel(
          modelType: ModelType.gemmaIt,
          maxTokens: 2048,
        );
      } catch (e) {
        // If createModel fails, try alternative initialization
        debugPrint('⚠️ Primary initialization failed: $e');
        debugPrint('🔄 Retrying with alternative method...');
        
        // Try to set the model path explicitly
        try {
          await _gemma.modelManager.setModelPath(modelPath);
          _model = await _gemma.createModel(
            modelType: ModelType.gemmaIt,
            maxTokens: 2048,
          );
        } catch (e2) {
          throw Exception('Failed to initialize model: $e2');
        }
      }

      _updateProgress(85, 'Creating chat session...');
      debugPrint('💬 Setting up chat...');

      // Create chat session
      _chat = await _model.createChat(
        randomSeed: 42,
        temperature: 0.7,
        topK: 40,
        topP: 0.95,
      );

      _updateProgress(100, 'Ready!');
      _initialised = true;
      _initError = null;
      
      debugPrint('✅ GemmaService initialized successfully!');
      debugPrint('🎉 Model is ready for chat');
    } catch (e) {
      _initError = e.toString();
      _initialised = false;
      _updateProgress(0, 'Initialization failed');
      
      debugPrint('❌ Initialization error: $e');

      // Provide helpful diagnostics
      if (e.toString().contains('No active inference model')) {
        debugPrint('💡 The model needs to be properly registered with flutter_gemma');
      } else if (e.toString().contains('Out of memory')) {
        debugPrint('⚠️ Device ran out of memory during model loading');
        debugPrint('💡 Try freeing up memory and restarting the app');
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

      debugPrint('🚀 Sending: $text');

      // Use the correct flutter_gemma API for streaming response
      // The respond method returns a Stream<String> for token-by-token output
      final tokenStream = _chat.respond(text);
      
      await for (final token in tokenStream) {
        firstTokenTime ??= DateTime.now();
        tokenCount++;
        buffer.write(token);
        onToken(token);
      }

      final response = buffer.toString();
      debugPrint('✅ Response complete: ${response.length} characters, $tokenCount tokens');

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
