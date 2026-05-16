# Gemma Vision Flutter - AI Model Integration Skill

**Description**: Complete guide for building Flutter apps with Google's Gemma AI model, featuring offline inference, camera integration, speech I/O, and accessibility-first design. Covers model setup, streaming inference, image handling, voice features, and multi-service bootstrap patterns.

**Used by**: Implementing gemma-vision features or creating similar Flutter+AI applications
**Complexity**: Advanced - Multi-service orchestration, background isolates, streaming responses
**Time to Complete**: 30-60 mins per feature (varies by scope)

---

## Core Architecture

The gemma-vision app follows a **layered service-based pattern** with clear separation of concerns:

```
┌─────────────────────────────────┐
│   UI Layer (Pages & Widgets)    │
│ ┌─────────────────────────────┐ │
│ │ ChatPage | DownloadPage     │ │
│ │ SettingsPage | ErrorPage    │ │
│ └─────────────────────────────┘ │
└────────────┬────────────────────┘
             │
┌────────────▼────────────────────────────────────────┐
│       Service Layer (Singleton Pattern)            │
│ ┌──────────┬──────────┬──────────┬───────────┐    │
│ │ Gemma    │ Speech   │ Text     │ Download  │    │
│ │ Service  │ Service  │ Recog    │ Manager   │    │
│ └──────────┴──────────┴──────────┴───────────┘    │
│ ┌──────────┬──────────┬──────────┬───────────┐    │
│ │ TTS      │ Bootstrap│ Camera   │ Keyboard  │    │
│ │ Service  │ Manager  │ Handler  │ Handler   │    │
│ └──────────┴──────────┴──────────┴───────────┘    │
└────────────┬────────────────────────────────────┘
             │
┌────────────▼─────────────────────────────────┐
│   Platform Layer (Native Integration)       │
│ flutter_gemma | camera | speech_to_text     │
│ flutter_tts | permission_handler | etc      │
└──────────────────────────────────────────────┘
```

---

## Step 1: Project Setup & Dependencies

### 1.1 Initialize Flutter Project
```bash
flutter create gemma_app --platforms=android,ios
cd gemma_app
```

### 1.2 Add Required Dependencies

Key dependencies in `pubspec.yaml`:
```yaml
dependencies:
  flutter_gemma: ^0.10.0          # Gemma AI model plugin
  camera: ^0.11.2                  # Camera capture
  speech_to_text: ^7.2.0           # Voice input
  flutter_tts: ^4.2.3              # Text-to-speech
  google_mlkit_text_recognition: ^0.15.0  # OCR
  flutter_downloader: ^1.12.0      # Background downloads
  permission_handler: ^11.3.0      # Permissions
  path_provider: ^2.1.5            # File storage
  shared_preferences: ^2.5.3       # Settings persistence
  wakelock_plus: ^1.3.2            # Prevent sleep during operations
  audioplayers: ^6.5.0             # Audio playback
  http: ^1.4.0                     # Network requests
  crypto: ^3.0.6                   # Hash generation
```

### 1.3 Platform-Specific Configuration

**Android (android/app/build.gradle.kts)**:
```kotlin
android {
    compileSdk = 35  // Must support ML Kit
    
    packagingOptions {
        exclude 'META-INF/proguard/androidx-*.pro'
    }
}

dependencies {
    implementation("com.google.mlkit:text-recognition:16.0.0")
}
```

**iOS (ios/Podfile)**:
```ruby
target 'Runner' do
  # Flutter plugins
  flutter_install_all_ios_pods
  
  pod 'GoogleMLKit/TextRecognition'
end

post_install do |installer|
  installer.pods_project.targets.each do |target|
    flutter_additional_ios_build_settings(target)
  end
end
```

---

## Step 2: Gemma Model Service Setup

### 2.1 Create GemmaService Singleton

```dart
// lib/services/gemma_service.dart
import 'dart:io';
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:path_provider/path_provider.dart';

class GemmaService {
  GemmaService._internal();  // Private constructor for singleton
  static final GemmaService instance = GemmaService._internal();

  final _gemma = FlutterGemmaPlugin.instance;
  InferenceModel? _model;
  InferenceChat? _chat;
  bool _initialised = false;

  /// Initialize Gemma model with vision support
  /// Backend: CPU (default) or GPU (if available)
  Future<void> init(PreferredBackend backend) async {
    if (_initialised) return;  // Idempotent - prevent reinit

    final dir = await getApplicationDocumentsDirectory();
    final modelPath = '${dir.path}/gemma-3n-E2B-it-int4.task';

    // Point to local model if it exists
    if (!await _gemma.modelManager.isModelInstalled &&
        File(modelPath).existsSync()) {
      await _gemma.modelManager.setModelPath(modelPath);
    }

    // Create model with vision + streaming support
    _model ??= await _gemma.createModel(
      preferredBackend: backend,
      modelType: ModelType.gemmaIt,  // Instruction-tuned
      supportImage: true,             // Enable vision
      maxTokens: 8192,                # Context window
      maxNumImages: 1,
    );

    // Create persistent chat session
    _chat ??= await _model!.createChat(
      randomSeed: 1,
      temperature: 1.0,     // Balanced creativity
      topK: 64,
      topP: 0.95,
      supportImage: true,
      tokenBuffer: 512,
    );

    _initialised = true;
  }

  /// Stream-based response with image support and performance metrics
  Future<void> sendWithStreaming({
    required String text,
    File? image,
    required Function(String) onToken,        // Fired for each token
    required Function(MessageStats) onComplete, // Final stats
  }) async {
    if (!_initialised || _chat == null) {
      throw Exception('GemmaService not initialized');
    }

    final startTime = DateTime.now();
    DateTime? firstTokenTime;
    int tokenCount = 0;
    final buffer = StringBuffer();

    // Add user message (with optional image)
    if (image != null) {
      final bytes = await image.readAsBytes();
      await _chat!.addMessageWithImage(text, bytes);
    } else {
      await _chat!.addMessage(text);
    }

    // Stream response token by token
    await _chat!.streamResponse(
      (token) {
        firstTokenTime ??= DateTime.now();  // Track TTFT
        tokenCount++;
        buffer.write(token);
        onToken(token);
      },
    );

    final stats = MessageStats(
      totalTokens: tokenCount,
      timeToFirstToken: firstTokenTime?.difference(startTime).inMilliseconds,
      totalTime: DateTime.now().difference(startTime).inMilliseconds,
    );
    onComplete(stats);
  }

  /// Get current chat history
  Future<List<ChatMessage>> getChatHistory() async {
    if (_chat == null) return [];
    return await _chat!.getHistory();
  }

  /// Clear chat session
  Future<void> clearChat() async {
    await _chat?.clear();
  }

  /// Cleanup resources
  Future<void> dispose() async {
    _chat = null;
    _model = null;
    _initialised = false;
  }
}

// Models for streaming responses
class MessageStats {
  final int totalTokens;
  final int? timeToFirstToken;  // ms to first token
  final int totalTime;           // Total response time
  MessageStats({
    required this.totalTokens,
    this.timeToFirstToken,
    required this.totalTime,
  });
}
```

### 2.2 Model Download Management

Create `DownloadManager` for handling the ~3GB model file:

```dart
// lib/services/download_manager.dart
import 'package:flutter_downloader/flutter_downloader.dart';

class DownloadManager {
  static final DownloadManager _instance = DownloadManager._internal();
  factory DownloadManager() => _instance;
  DownloadManager._internal();

  String? _taskId;

  /// Start model download from HuggingFace
  Future<void> downloadModel({
    required String url,  // HF model URL
    required Function(int progress) onProgress,
    required Function(bool success) onComplete,
  }) async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      
      _taskId = await FlutterDownloader.enqueue(
        url: url,
        savedDir: dir.path,
        fileName: 'gemma-3n-E2B-it-int4.task',
        showNotification: true,
        openFileFromNotification: false,
      );

      // Listen for progress updates
      FlutterDownloader.registerCallback((id, status, progress) {
        if (id == _taskId) {
          onProgress(progress);
          if (status == DownloadTaskStatus.complete) {
            onComplete(true);
          } else if (status == DownloadTaskStatus.failed) {
            onComplete(false);
          }
        }
      });
    } catch (e) {
      onComplete(false);
    }
  }

  /// Cancel download
  Future<void> cancelDownload() async {
    if (_taskId != null) {
      await FlutterDownloader.cancel(taskId: _taskId!);
    }
  }
}
```

---

## Step 3: Multi-Service Bootstrap

### 3.1 Bootstrap Manager (Orchestrates Initialization)

```dart
// lib/services/bootstrap_manager.dart
import 'package:flutter/material.dart';
import 'package:flutter_gemma/pigeon.g.dart';

class BootstrapManager {
  static bool _globalBootstrapping = false;
  static Completer<void>? _globalBootstrapCompleter;

  /// Initialize ALL services in correct dependency order
  static Future<BootstrapResult> bootstrap({
    required BuildContext context,
    required String systemContext,
    required PreferredBackend backend,
    required VoidCallback onToggleCamera,
    required bool Function() isMounted,
  }) async {
    // Prevent concurrent bootstrap (deadlock prevention)
    if (_globalBootstrapping) {
      await _globalBootstrapCompleter?.future
          .timeout(const Duration(seconds: 30));
      return BootstrapResult.success();
    }

    _globalBootstrapping = true;
    _globalBootstrapCompleter = Completer<void>();

    try {
      // 1. Initialize Gemma model (longest operation)
      await GemmaService.instance.init(backend);

      // 2. Initialize Text Recognition (ML Kit)
      await TextRecognitionService.instance.initialize();

      // 3. Initialize TTS for accessibility
      final tts = FlutterTts();
      await tts.setLanguage('en-US');

      // 4. Initialize Speech Recognition
      final speechService = SpeechService(
        tts: tts,
        onStateChanged: () {},
        promptBarKey: GlobalKey(),
        isGenerating: () => false,
      );
      await speechService.initialize();

      // 5. Setup keyboard handlers for 8BitDo controller
      SystemChannels.keyEvent.setMessageHandler(
        (message) => _handleKeyEvent(message),
      );

      return BootstrapResult.success();
    } catch (e) {
      debugPrint('[Bootstrap] Error: $e');
      return BootstrapResult.failure(error: e.toString());
    } finally {
      _globalBootstrapping = false;
      _globalBootstrapCompleter?.complete();
    }
  }
}

class BootstrapResult {
  final bool success;
  final String? error;
  
  BootstrapResult.success() : success = true, error = null;
  BootstrapResult.failure({required this.error}) : success = false;
}
```

---

## Step 4: Speech & Audio Integration

### 4.1 Speech-to-Text Service

```dart
// lib/services/speech_service.dart
import 'package:speech_to_text/speech_to_text.dart';

class SpeechService {
  final SpeechToText _speech = SpeechToText();
  bool _listening = false;

  /// Initialize speech recognition
  Future<void> initialize() async {
    try {
      final available = await _speech.initialize(
        onError: (error) => debugPrint('Speech error: $error'),
        onStatus: (status) => debugPrint('Speech status: $status'),
      );
      if (!available) {
        throw Exception('Speech recognition not available');
      }
    } catch (e) {
      rethrow;
    }
  }

  /// Start listening to user voice input
  Future<String> startListening() async {
    if (!_speech.isAvailable) {
      throw Exception('Speech not available');
    }

    String result = '';
    _listening = true;

    _speech.listen(
      onResult: (result) {
        debugPrint('Heard: ${result.recognizedWords}');
      },
      localeId: 'en_US',
    );

    // Return final result
    return result;
  }

  /// Stop listening and get final transcription
  Future<void> stopListening() async {
    await _speech.stop();
    _listening = false;
  }

  bool get isListening => _listening;
}
```

### 4.2 Text-to-Speech Service

```dart
// lib/services/streaming_tts_service.dart
import 'package:flutter_tts/flutter_tts.dart';

class StreamingTtsService {
  final FlutterTts _tts = FlutterTts();

  /// Initialize TTS
  Future<void> initialize() async {
    await _tts.setLanguage('en-US');
    await _tts.setSpeechRate(0.5);  // Normal pace
    await _tts.setVolume(1.0);
  }

  /// Speak text (used for AI responses & accessibility)
  Future<void> speak(String text) async {
    await _tts.speak(text);
  }

  /// Stop current speech
  Future<void> stop() async {
    await _tts.stop();
  }

  /// Stream response word-by-word (for blind users)
  Future<void> streamSpeak(Stream<String> tokens) async {
    await for (String token in tokens) {
      // Buffer words and speak every N tokens
      await _tts.speak(token);
      await Future.delayed(const Duration(milliseconds: 100));
    }
  }
}
```

---

## Step 5: Camera Integration

### 5.1 Camera Handler

```dart
// lib/handlers/camera_handler.dart
import 'package:camera/camera.dart';

class CameraHandler {
  late CameraController _controller;
  List<CameraDescription>? _cameras;

  /// Initialize camera
  Future<void> initialize() async {
    _cameras = await availableCameras();
    if (_cameras!.isEmpty) {
      throw Exception('No camera available');
    }

    // Use back camera
    final camera = _cameras!.first;
    _controller = CameraController(
      camera,
      ResolutionPreset.high,
      enableAudio: false,  // Reduce resource usage
    );

    await _controller.initialize();
  }

  /// Capture image and return file
  Future<File> captureImage() async {
    try {
      final image = await _controller.takePicture();
      return File(image.path);
    } catch (e) {
      throw Exception('Failed to capture image: $e');
    }
  }

  /// Get preview widget
  Widget getPreview() => CameraPreview(_controller);

  Future<void> dispose() async {
    await _controller.dispose();
  }
}
```

### 5.2 Text Recognition (OCR)

```dart
// lib/services/text_recognition_service.dart
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

class TextRecognitionService {
  static final TextRecognitionService _instance =
      TextRecognitionService._internal();
  static TextRecognitionService get instance => _instance;

  TextRecognitionService._internal();

  late final TextRecognizer _recognizer;
  bool _initialized = false;

  /// Initialize text recognizer
  Future<void> initialize() async {
    if (_initialized) return;
    
    _recognizer = TextRecognizer(
      script: TextRecognitionScript.latin,
    );
    _initialized = true;
  }

  /// Extract text from image
  Future<String> extractText(File imageFile) async {
    if (!_initialized) await initialize();

    try {
      final input = InputImage.fromFile(imageFile);
      final recognizedText = await _recognizer.processImage(input);
      return recognizedText.text;
    } catch (e) {
      debugPrint('OCR Error: $e');
      return '';  // Gracefully return empty
    }
  }

  Future<void> dispose() async {
    await _recognizer.close();
    _initialized = false;
  }
}
```

---

## Step 6: Main Chat Page Implementation

### 6.1 Chat Page Structure

```dart
// lib/pages/chat_page.dart
import 'dart:io';
import 'package:flutter/material.dart';

class ChatPage extends StatefulWidget {
  final String systemContext;
  final PreferredBackend backend;

  const ChatPage({
    required this.systemContext,
    required this.backend,
  });

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  final GemmaService _gemma = GemmaService.instance;
  final List<ChatMessage> _messages = [];
  bool _isGenerating = false;
  String _currentResponse = '';
  
  File? _capturedImage;
  
  late SpeechService _speechService;
  late StreamingTtsService _ttsService;

  @override
  void initState() {
    super.initState();
    _initializeServices();
  }

  Future<void> _initializeServices() async {
    _speechService = SpeechService(...);
    _ttsService = StreamingTtsService();
    await _ttsService.initialize();
    await _speechService.initialize();
  }

  /// Send message with optional image
  Future<void> _sendMessage(String text) async {
    if (text.isEmpty) return;

    setState(() {
      _isGenerating = true;
      _currentResponse = '';
      _messages.add(ChatMessage(
        role: 'user',
        content: text,
        image: _capturedImage,
      ));
    });

    try {
      await _gemma.sendWithStreaming(
        text: text,
        image: _capturedImage,
        onToken: (token) {
          setState(() {
            _currentResponse += token;
          });
          // Stream tokens to TTS for blind users
          _ttsService.speak(token);
        },
        onComplete: (stats) {
          setState(() {
            _isGenerating = false;
            _messages.add(ChatMessage(
              role: 'assistant',
              content: _currentResponse,
            ));
            _currentResponse = '';
            _capturedImage = null;
          });
          debugPrint(
            'Response: ${stats.totalTokens} tokens in ${stats.totalTime}ms'
          );
        },
      );
    } catch (e) {
      _showError('Error: $e');
      setState(() => _isGenerating = false);
    }
  }

  /// Capture image and send with question
  Future<void> _captureAndSend(String question) async {
    try {
      final cameraHandler = CameraHandler();
      await cameraHandler.initialize();
      
      _capturedImage = await cameraHandler.captureImage();
      await _sendMessage(question);
      
      await cameraHandler.dispose();
    } catch (e) {
      _showError('Camera error: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Gemma Vision Chat')),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              itemCount: _messages.length,
              itemBuilder: (context, index) {
                final msg = _messages[index];
                return ChatBubble(message: msg);
              },
            ),
          ),
          if (_isGenerating)
            Padding(
              padding: const EdgeInsets.all(8),
              child: CircularProgressIndicator(),
            ),
          PromptBar(
            onSend: _sendMessage,
            onCapture: _captureAndSend,
          ),
        ],
      ),
    );
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  void dispose() {
    _ttsService.stop();
    _speechService.dispose();
    super.dispose();
  }
}
```

### 6.2 Message Data Model

```dart
// lib/models/message_models.dart
import 'dart:io';

class ChatMessage {
  final String role;           // 'user' or 'assistant'
  final String content;
  final File? image;
  final DateTime timestamp;

  ChatMessage({
    required this.role,
    required this.content,
    this.image,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  Map<String, dynamic> toJson() => {
    'role': role,
    'content': content,
    'timestamp': timestamp.toIso8601String(),
  };
}

class MessageStats {
  final int totalTokens;
  final int? timeToFirstToken;
  final int totalTime;
  MessageStats({
    required this.totalTokens,
    this.timeToFirstToken,
    required this.totalTime,
  });
}
```

---

## Step 7: Accessibility & Keyboard Support

### 7.1 Keyboard Handler (8BitDo Controller)

```dart
// lib/handlers/keyboard_handler.dart
import 'package:flutter/services.dart';

class KeyboardHandler {
  static void setupKeyboardBindings({
    required VoidCallback onToggleCamera,
    required VoidCallback onToggleVoice,
    required VoidCallback onSendMessage,
    required VoidCallback onToggleSettings,
  }) {
    RawKeyboard.instance.addListener((event) {
      if (event.isKeyPressed(LogicalKeyboardKey.keyA)) {
        onToggleCamera();
      } else if (event.isKeyPressed(LogicalKeyboardKey.keyB)) {
        onToggleVoice();
      } else if (event.isKeyPressed(LogicalKeyboardKey.keyX)) {
        onSendMessage();
      } else if (event.isKeyPressed(LogicalKeyboardKey.keyY)) {
        onToggleSettings();
      }
    });
  }
}
```

### 7.2 Semantic Buttons (Screen Reader Support)

```dart
// lib/widgets/semantic_material_button.dart
class SemanticMaterialButton extends StatelessWidget {
  final String label;
  final VoidCallback onPressed;
  final String? semanticLabel;

  const SemanticMaterialButton({
    required this.label,
    required this.onPressed,
    this.semanticLabel,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: semanticLabel ?? label,
      button: true,
      enabled: true,
      onTap: onPressed,
      child: ElevatedButton(
        onPressed: onPressed,
        child: Text(label),
      ),
    );
  }
}
```

---

## Step 8: Error Recovery & State Persistence

### 8.1 Error Recovery Page

```dart
// lib/pages/error_recovery_page.dart
class ErrorRecoveryPage extends StatelessWidget {
  final String errorMessage;
  final VoidCallback onRetry;

  const ErrorRecoveryPage({
    required this.errorMessage,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Error')),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error, size: 64, color: Colors.red),
            const SizedBox(height: 16),
            Text(errorMessage),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: onRetry,
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}
```

### 8.2 Settings Persistence

```dart
// lib/services/settings_manager.dart
import 'package:shared_preferences/shared_preferences.dart';

class SettingsManager {
  static final SettingsManager _instance = SettingsManager._internal();
  factory SettingsManager() => _instance;
  SettingsManager._internal();

  late final SharedPreferences _prefs;

  Future<void> initialize() async {
    _prefs = await SharedPreferences.getInstance();
  }

  /// Get saved system context
  String getSystemContext() =>
      _prefs.getString('systemContext') ??
      'You are a helpful AI assistant for blind users.';

  /// Save system context
  Future<void> setSystemContext(String context) =>
      _prefs.setString('systemContext', context);

  /// Get preferred backend
  String getBackend() =>
      _prefs.getString('backend') ?? 'CPU';

  Future<void> setBackend(String backend) =>
      _prefs.setString('backend', backend);
}
```

---

## Step 9: Model Download Flow

### 9.1 Download Page with Progress

```dart
// lib/pages/model_download_page.dart
class ModelDownloadPage extends StatefulWidget {
  @override
  State<ModelDownloadPage> createState() => _ModelDownloadPageState();
}

class _ModelDownloadPageState extends State<ModelDownloadPage> {
  int _downloadProgress = 0;
  bool _isDownloading = false;
  final DownloadManager _downloadManager = DownloadManager();

  @override
  void initState() {
    super.initState();
    _checkModelStatus();
  }

  Future<void> _checkModelStatus() async {
    final dir = await getApplicationDocumentsDirectory();
    final modelPath = '${dir.path}/gemma-3n-E2B-it-int4.task';
    
    if (File(modelPath).existsSync()) {
      // Model already downloaded
      _navigateToChat();
    }
  }

  Future<void> _startDownload() async {
    setState(() => _isDownloading = true);

    const modelUrl =
        'https://huggingface.co/google/gemma-3n/resolve/main/model.task';

    await _downloadManager.downloadModel(
      url: modelUrl,
      onProgress: (progress) {
        setState(() => _downloadProgress = progress);
      },
      onComplete: (success) {
        if (success) {
          _navigateToChat();
        } else {
          _showError('Download failed');
          setState(() => _isDownloading = false);
        }
      },
    );
  }

  void _navigateToChat() {
    Navigator.of(context).pushReplacementNamed('/chat');
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Download AI Model')),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text('Model size: ~3 GB'),
            const SizedBox(height: 24),
            if (_isDownloading) ...[
              CircularProgressIndicator(
                value: _downloadProgress / 100,
              ),
              const SizedBox(height: 16),
              Text('$_downloadProgress%'),
            ] else ...[
              ElevatedButton(
                onPressed: _startDownload,
                child: const Text('Download Model'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
```

---

## Step 10: Permissions & Initialization

### 10.1 Permission Handling

```dart
// lib/services/permission_manager.dart
import 'package:permission_handler/permission_handler.dart';

class PermissionManager {
  static Future<bool> requestAllPermissions() async {
    final statuses = await [
      Permission.camera,
      Permission.microphone,
      Permission.storage,
      Permission.photos,
    ].request();

    return statuses.values.every(
      (status) => status.isGranted || status.isDenied,
    );
  }

  static Future<bool> requestCamera() async {
    final status = await Permission.camera.request();
    return status.isGranted;
  }

  static Future<bool> requestMicrophone() async {
    final status = await Permission.microphone.request();
    return status.isGranted;
  }
}
```

### 10.2 Main App Initialization

```dart
// lib/main.dart
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize downloader for background downloads
  await FlutterDownloader.initialize(
    debug: kDebugMode,
    ignoreSsl: false,
  );

  // Register callback for download progress
  FlutterDownloader.registerCallback(downloadCallback);

  // Prevent device from sleeping during long operations
  await WakelockPlus.enable();

  // Initialize settings
  await SettingsManager().initialize();

  runApp(const MyApp());
}

@pragma('vm:entry-point')
void downloadCallback(String id, int status, int progress) {
  final SendPort? send = IsolateNameServer.lookupPortByName(
    'downloader_send_port',
  );
  send?.send([id, status, progress]);
}
```

---

## Reusable Patterns

### Pattern 1: Singleton Service
Used for: Model, TTS, Speech, Text Recognition, Download Manager

```dart
class MyService {
  static final MyService _instance = MyService._internal();
  factory MyService() => _instance;
  MyService._internal();

  Future<void> initialize() { /* ... */ }
}
```

### Pattern 2: Streaming Responses
Used for: Gemma inference, TTS output

```dart
StreamController<String> responseStream = StreamController<String>();

// Producer
await gemmaService.sendWithStreaming(
  onToken: (token) => responseStream.add(token),
  onComplete: (_) => responseStream.close(),
);

// Consumer
responseStream.stream.listen((token) { /* handle token */ });
```

### Pattern 3: Bootstrap with Dependency Order
```dart
// 1. Long initialization → Gemma model
// 2. Short initialization → ML Kit text recognition
// 3. Platform → Camera, Keyboard handlers
// 4. UI-dependent → Speech/TTS services
```

### Pattern 4: Error Recovery
```dart
try {
  // operation
} catch (e) {
  // Log error
  // Show error page
  // Provide recovery option
}
```

---

## Common Implementation Scenarios

### Scenario 1: "Describe what you see"
1. User presses camera button
2. Capture image with CameraHandler
3. Extract text with TextRecognitionService (optional)
4. Send image + question to GemmaService
5. Stream response via TTS

### Scenario 2: "Ask follow-up question"
1. Chat history is maintained in GemmaService._chat
2. New message references previous context automatically
3. Send text-only (no image) to sendWithStreaming()

### Scenario 3: "Read text from screen"
1. Capture image
2. Call TextRecognitionService.extractText()
3. Send extracted text to Gemma for summary
4. Speak result

### Scenario 4: "Custom AI behavior"
1. Edit system context in SettingsPage
2. Saved via SettingsManager
3. Used in BootstrapManager when initializing Gemma
4. Affects all subsequent responses

### Scenario 5: "Add new feature with camera input"
1. Create widget in chat_page/widgets/
2. Use CameraHandler for capture
3. Process image (OCR, custom ML Kit, etc)
4. Send to Gemma with context
5. Handle response streaming

---

## Testing Patterns

### Unit Test: GemmaService
```dart
test('GemmaService.init should not reinitialize', () async {
  await GemmaService.instance.init(PreferredBackend.cpu);
  await GemmaService.instance.init(PreferredBackend.gpu);  // No-op
  // Verify single initialization
});
```

### Integration Test: Full Chat Flow
```dart
testWidgets('Chat sends message and receives response', (tester) async {
  await tester.pumpWidget(const MyApp());
  await tester.pumpAndSettle();

  await tester.enterText(find.byType(TextField), 'Hello');
  await tester.tap(find.byIcon(Icons.send));
  await tester.pumpAndSettle();

  expect(find.text('Hello'), findsOneWidget);
  // Verify response received
});
```

---

## Performance Tips

1. **Model Loading**: Takes ~10-30s on first init. Show loading spinner.
2. **Memory**: Keep model in singleton. Clear old chats periodically.
3. **Streaming**: Each token ~50-200ms. Expected for edge devices.
4. **Battery**: Use CPU backend if GPU causes thermal throttling.
5. **Background Download**: Use FlutterDownloader to prevent ANR.

---

## Common Issues & Solutions

| Issue | Cause | Solution |
|-------|-------|----------|
| Model won't load | Wrong path or corrupted file | Verify file exists & isn't partial download |
| Crashes on second chat | Memory not freed | Call `_chat?.clear()` between sessions |
| Speech recognition dead | Permission denied | Check manifest + request at runtime |
| Camera permission hanging | Missing platform config | Add to Android/iOS manifests |
| TTS cutting off | Buffer too small | Increase tokenBuffer in GemmaService |
| Download never completes | URL unreachable | Use HuggingFace API token |

---

## Next Steps After Implementation

1. **Add Preferences UI** - Let users customize system context
2. **Add Chat Export** - Save conversations as JSON/PDF
3. **Add Offline Voice** - Use local speech recognition
4. **Add Image History** - Cache images to improve context
5. **Add Custom Handlers** - For 8BitDo button combinations
6. **Add Analytics** - Track usage patterns
7. **Performance Profiling** - Use Dart DevTools
8. **CI/CD Setup** - Automated builds for Android/iOS

---

## Resources & References

- **flutter_gemma**: https://pub.dev/packages/flutter_gemma
- **Google ML Kit**: https://developers.google.com/ml-kit
- **Flutter Camera**: https://pub.dev/packages/camera
- **Speech Recognition**: https://pub.dev/packages/speech_to_text
- **Gemma Model Weights**: https://huggingface.co/google/gemma-3n
- **Accessibility Guide**: https://flutter.dev/docs/development/accessibility-and-localization/accessibility

---

## Key Takeaways

✅ Use singleton services for persistent resources (model, TTS)  
✅ Initialize services in dependency order (model → recognition → handlers)  
✅ Stream responses token-by-token for better UX  
✅ Always handle permissions explicitly  
✅ Use background isolates for large downloads  
✅ Cache chat history to avoid redundant inference  
✅ Test error scenarios (network, permissions, device)  
✅ Design for accessibility from the start (TTS, keyboard)
