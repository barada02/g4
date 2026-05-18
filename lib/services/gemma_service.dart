import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:flutter_gemma/core/ffi/litert_lm_client.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'dart:async';
import 'dart:convert';
import '../models/chat_models.dart' as app_models;

// Direct model URL (no authentication needed)
const String modelUrl = 'https://huggingface.co/litert-community/gemma-4-E2B-it-litert-lm/resolve/main/gemma-4-E2B-it.litertlm';
const String modelFileName = 'gemma-4-E2B-it.litertlm';

/// Wrapper for FFI-based chat interface (compatible with platform API)
class _FFIChatWrapper {
  final LiteRtLmFfiClient _client;
  bool _conversationCreated = false;
  final List<app_models.AppMessage> _history = [];

  _FFIChatWrapper(this._client);

  /// Create a conversation session
  void createConversation() {
    if (!_conversationCreated) {
      _client.createConversation(
        systemMessage: 'You are a helpful AI assistant.',
        temperature: 0.7,
        topK: 40,
        topP: 0.95,
      );
      _conversationCreated = true;
    }
  }

  /// Add a message to the conversation
  Future<void> addQuery(app_models.AppMessage message) async {
    if (!_conversationCreated) {
      createConversation();
    }
    _history.add(message);
  }

  /// Stream responses token by token with smooth delay
  Stream<dynamic> generateChatResponseAsync() async* {
    if (_history.isEmpty) {
      throw Exception('No messages in conversation');
    }

    final lastMessage = _history.last;
    if (!lastMessage.isUser) {
      throw Exception('Last message must be from user');
    }

    // Ensure we have a non-null list for images
    final List<Uint8List> imageBytes = lastMessage.images ?? [];

    // Use the library's built-in method to properly encode message with base64 images
    // This handles: text content + base64-encoded images + proper JSON structure
    final messageJson = LiteRtLmFfiClient.buildMessageJson(
      lastMessage.content,
      imagesBytes: imageBytes.isNotEmpty ? imageBytes : null,
    );

    debugPrint('📤 Sending message with ${imageBytes.length} images');
    
    String assistantResponse = '';
    
    await for (final jsonChunk in _client.sendMessageStreamRaw(messageJson)) {
      // Each chunk is a raw SDK JSON response
      // Extract text from JSON chunk
      final textToken = LiteRtLmFfiClient.extractTextFromResponse(jsonChunk);
      if (textToken.isNotEmpty) {
        assistantResponse += textToken;
        yield app_models.AppTextResponse(token: textToken);
        
        // Add smooth delay for natural typing effect
        // This doesn't slow down the model, just the UI rendering
        await Future.delayed(const Duration(milliseconds: 30));
      }
    }
    
    debugPrint('✅ Assistant response received: ${assistantResponse.length} chars, ${assistantResponse.split(' ').length} tokens');
    
    // Add assistant response to history after streaming completes
    _history.add(app_models.AppMessage.text(
      text: assistantResponse,
      isUser: false,
    ));
  }

  /// Clear conversation history
  Future<void> clear() async {
    _history.clear();
    _conversationCreated = false;
    _client.createConversation(); // Reset for next conversation
  }

  /// Get conversation history
  Future<List<app_models.ChatMessage>> getHistory() async {
    return _history
        .map((msg) => app_models.ChatMessage(
              isUser: msg.isUser,
              content: msg.content,
              images: msg.images,
            ))
        .toList();
  }
}

/// Core AI model service using Gemma with streaming support
class GemmaService {
  GemmaService._internal();
  static final GemmaService instance = GemmaService._internal();

  final _gemma = FlutterGemmaPlugin.instance;
  LiteRtLmFfiClient? _ffiClient;
  _FFIChatWrapper? _ffiChat;
  dynamic _model;
  dynamic _chat;
  bool _usesFFI = false;
  bool _initialised = false;
  bool _initializationAttempted = false;
  String? _initError;
  bool _isDownloading = false;
  int _downloadProgress = 0; // 0-100
  String _downloadStatus = '';
  String _selectedBackend = 'gpu';  // Track selected backend
  int _conversationTurns = 0;  // Track conversation turns for KV cache management

  bool get isInitialised => _initialised;
  String? get initError => _initError;
  bool get initializationAttempted => _initializationAttempted;
  bool get isDownloading => _isDownloading;
  int get downloadProgress => _downloadProgress;
  String get downloadStatus => _downloadStatus;
  String get selectedBackend => _selectedBackend;

  /// Auto-detect best backend (GPU if available, fall back to CPU)
  Future<String> _detectOptimalBackend() async {
    debugPrint('🔍 Detecting optimal backend (GPU/CPU)...');
    
    try {
      // ========== ORIGINAL GPU LOGIC (COMMENTED FOR CPU TESTING) ==========
      // Try GPU first on Android (Qualcomm Adreno, ARM Mali)
      // if (Platform.isAndroid) {
      //   // GPU is typically available on modern Android devices
      //   debugPrint('✅ Android detected - attempting GPU backend');
      //   return 'gpu';
      // } else if (Platform.isIOS) {
      //   // iOS Metal support
      //   debugPrint('✅ iOS detected - attempting GPU backend (Metal)');
      //   return 'gpu';
      // } else {
      //   // Linux/Windows desktop
      //   debugPrint('⚠️ Desktop platform - using CPU backend');
      //   return 'cpu';
      // }
      // ======================================================================
      
      // 🧪 TESTING: Force CPU for performance comparison
      debugPrint('🧪 CPU TESTING MODE - forcing CPU backend for benchmarking');
      return 'cpu';
      
    } catch (e) {
      debugPrint('❌ Backend detection failed: $e - falling back to CPU');
      return 'cpu';
    }
  }

  /// Manage KV cache to prevent slowdown in long conversations
  Future<void> _manageKVCache() async {
    _conversationTurns++;
    
    // Clear cache every 20 turns to prevent OOM and maintain speed
    const maxTurnsBeforeClear = 20;
    
    if (_conversationTurns >= maxTurnsBeforeClear) {
      debugPrint('🧹 KV cache threshold reached ($_conversationTurns/$maxTurnsBeforeClear turns)');
      debugPrint('🔄 Clearing conversation history to manage KV cache...');
      
      try {
        // Clear old messages, keep system context
        await _chat?.clear();
        _conversationTurns = 0;
        debugPrint('✅ KV cache cleared, conversation reset');
      } catch (e) {
        debugPrint('⚠️ Cache clear failed: $e');
      }
    }
  }

  /// Update download progress for UI
  void _updateProgress(int progress, String status) {
    _downloadProgress = progress;
    _downloadStatus = status;
    debugPrint('📊 $status ($_downloadProgress%)');
  }

  /// Download model from HuggingFace if not already present
  Future<String?> _downloadModelIfNeeded() async {
    try {
      // Use app cache directory - flutter_gemma expects models here
      final cacheDir = await getApplicationCacheDirectory();
      final modelPath = '${cacheDir.path}/$modelFileName';
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

      // PHASE 2: Register and initialize model
      _updateProgress(60, 'Registering model...');
      debugPrint('📋 Setting model as active: $modelPath');

      // PHASE 3: Initialize model
      _updateProgress(70, 'Setting up model...');
      debugPrint('⚙️ Creating model instance...');

      try {
        debugPrint('📍 Creating inference model');

        // Check if model is LiteRT-LM format (.litertlm)
        if (modelPath.endsWith('.litertlm')) {
          debugPrint('🔧 Detected LiteRT-LM model - using Dart FFI backend');
          _usesFFI = true;

          // Initialize FFI client for LiteRT-LM models
          _ffiClient = LiteRtLmFfiClient();
          
          // Auto-detect optimal backend
          _selectedBackend = await _detectOptimalBackend();
          
          try {
            debugPrint('📍 Initializing FFI client with model: $modelPath');
            debugPrint('🖥️ Backend: $_selectedBackend');
            await _ffiClient!.initialize(
              modelPath: modelPath,
              backend: _selectedBackend,  // Use auto-detected backend
              maxTokens: 2048,
              enableVision: true,
              enableAudio: false,
            );
            debugPrint('✅ FFI client initialized successfully with $_selectedBackend backend');

            // Create FFI chat wrapper
            _ffiChat = _FFIChatWrapper(_ffiClient!);
            _ffiChat!.createConversation();
            _model = _ffiClient;
            _chat = _ffiChat;
          } catch (e) {
            debugPrint('❌ FFI initialization failed: $e');
            // If GPU fails, try with CPU backend explicitly
            if (e.toString().contains('GPU') || _selectedBackend == 'gpu') {
              debugPrint('🔄 GPU failed - retrying with CPU backend...');
              _selectedBackend = 'cpu';
              _ffiClient = LiteRtLmFfiClient();
              await _ffiClient!.initialize(
                modelPath: modelPath,
                backend: 'cpu',  // Fall back to CPU
                maxTokens: 2048,
                enableVision: true,
                enableAudio: false,
              );
              _ffiChat = _FFIChatWrapper(_ffiClient!);
              _ffiChat!.createConversation();
              _model = _ffiClient;
              _chat = _ffiChat;
              debugPrint('✅ FFI client initialized successfully with CPU backend');
            } else {
              throw Exception('Failed to initialize FFI client: $e');
            }
          }
        } else {
          // For non-LiteRT-LM models, use the platform channel API
          debugPrint('🔧 Using platform channel backend for regular model');
          _usesFFI = false;

          // Register the downloaded model as the active model via platform channel
          try {
            // Use new API: FlutterGemma.installModel().fromFile() instead of deprecated setModelPath()
            FlutterGemma.installModel(modelType: ModelType.gemmaIt).fromFile(modelPath);
            debugPrint('✅ Model registered and set as active');
          } catch (e) {
            debugPrint('❌ Failed to set active model: $e');
            throw Exception('Failed to register model: $e');
          }

          // Create model with platform API
          _model = await _gemma.createModel(
            modelType: ModelType.gemmaIt,
            maxTokens: 2048,
          );
          debugPrint('✅ Model initialized successfully');
        }
      } catch (e) {
        debugPrint('❌ Model initialization failed: $e');
        throw Exception('Failed to initialize model: $e');
      }

      _updateProgress(85, 'Creating chat session...');
      debugPrint('💬 Setting up chat...');

      // Chat session already created in FFI wrapper or by platform API
      if (!_usesFFI) {
        _chat = await _model.createChat(
          randomSeed: 42,
          temperature: 0.7,
          topK: 40,
          topP: 0.95,
        );
      }

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
      if (e.toString().contains('LiteRT-LM model')) {
        debugPrint('💡 FFI backend for LiteRT-LM models may not be available on this platform');
      } else if (e.toString().contains('No active inference model')) {
        debugPrint('💡 The model needs to be properly registered with flutter_gemma');
      } else if (e.toString().contains('Out of memory')) {
        debugPrint('⚠️ Device ran out of memory during model loading');
        debugPrint('💡 Try freeing up memory and restarting the app');
      }
    }
  }

  /// Cleanup resources
  Future<void> dispose() async {
    if (_usesFFI && _ffiClient != null) {
      try {
        _ffiClient!.shutdown();
        debugPrint('✅ FFI client shutdown successfully');
      } catch (e) {
        debugPrint('❌ Error shutting down FFI client: $e');
      }
    }
    _chat = null;
    _model = null;
    _ffiClient = null;
    _ffiChat = null;
    _initialised = false;
  }

  /// Send message and stream response token by token
  Future<void> sendWithStreaming({
    required String text,
    List<Uint8List>? images,
    required Function(String) onToken,
    required Function(app_models.MessageStats) onComplete,
  }) async {
    if (!_initialised || _chat == null) {
      throw Exception('GemmaService not initialized. Error: $_initError');
    }

    try {
      // Manage KV cache before each message
      await _manageKVCache();
      
      final startTime = DateTime.now();
      DateTime? firstTokenTime;
      int tokenCount = 0;
      final buffer = StringBuffer();

      debugPrint('🚀 Sending: $text ${images?.length ?? 0} images');

      // Add user message to chat
      final message = images != null
          ? app_models.AppMessage.multimodal(text: text, isUser: true, images: images)
          : app_models.AppMessage.text(text: text, isUser: true);

      await _chat.addQuery(message);
      
      // Stream responses token by token using generateChatResponseAsync
      final responseStream = _chat.generateChatResponseAsync();
      
      await for (final response in responseStream) {
        // Handle text responses (tokens)
        if (response is app_models.AppTextResponse) {
          firstTokenTime ??= DateTime.now();
          tokenCount++;
          final token = response.token;
          buffer.write(token);
          onToken(token);
        }
      }

      final fullResponse = buffer.toString();
      debugPrint('✅ Response complete: ${fullResponse.length} characters, $tokenCount tokens');

      final stats = app_models.MessageStats(
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
}
