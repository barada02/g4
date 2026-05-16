import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_litert/flutter_litert.dart';
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';

void main() {
  runApp(const MainApp());
}

class MainApp extends StatelessWidget {
  const MainApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'LiteRT LLM Chat',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      home: const ChatScreen(),
    );
  }
}

// Model Service
class ModelService {
  static const String modelFileName = 'gemma-4-E2B-it.litertlm';
  static const String modelDownloadUrl = 'https://huggingface.co/litert-community/gemma-4-E2B-it-litert-lm/resolve/main/gemma-4-E2B-it.litertlm';
  
  final Dio _dio = Dio();
  
  Future<String> getModelPath() async {
    final dir = await getApplicationDocumentsDirectory();
    return '${dir.path}/$modelFileName';
  }

  Future<bool> isModelReady() async {
    try {
      final path = await getModelPath();
      final file = File(path);
      final exists = await file.exists();
      
      if (exists) {
        final fileSize = await file.length();
        return fileSize > 0;
      }
      return false;
    } catch (e) {
      debugPrint('Error checking model: $e');
      return false;
    }
  }

  Future<void> downloadModel({
    required Function(double) onProgress,
    required Function() onCompleted,
    required Function(String) onError,
  }) async {
    try {
      final path = await getModelPath();
      debugPrint('Downloading model to: $path');
      
      await _dio.download(
        modelDownloadUrl,
        path,
        onReceiveProgress: (received, total) {
          if (total != -1) {
            onProgress(received / total);
          }
        },
      );
      
      final file = File(path);
      final fileSize = await file.length();
      debugPrint('Download complete. File size: ${(fileSize / (1024 * 1024)).toStringAsFixed(2)} MB');
      
      onCompleted();
    } catch (e) {
      debugPrint('Download error: $e');
      onError(e.toString());
    }
  }
}

// Chat Screen
class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final ModelService _modelService = ModelService();
  final TextEditingController _controller = TextEditingController();
  final List<Map<String, String>> _messages = [];
  
  bool _modelReady = false;
  bool _isDownloading = false;
  bool _isGenerating = false;
  double _downloadProgress = 0;
  String? _errorMessage;
  
  Interpreter? _interpreter;

  @override
  void initState() {
    super.initState();
    _checkModel();
  }

  Future<void> _checkModel() async {
    final ready = await _modelService.isModelReady();
    if (ready) {
      final loaded = await _loadModel();
      setState(() {
        _modelReady = loaded;
      });
    } else {
      setState(() {
        _modelReady = false;
      });
    }
  }

  Future<bool> _loadModel() async {
    try {
      final modelPath = await _modelService.getModelPath();
      final file = File(modelPath);
      
      if (!await file.exists()) {
        throw Exception('Model file not found');
      }
      
      final fileSize = await file.length();
      debugPrint('Loading model from: $modelPath (${(fileSize / (1024 * 1024)).toStringAsFixed(2)} MB)');
      
      _interpreter = await Interpreter.fromFile(file);
      debugPrint('Model loaded successfully');
      return true;
    } catch (e) {
      debugPrint('Error loading model: $e');
      setState(() {
        _errorMessage = 'Failed to load model: $e';
        _modelReady = false;
      });
      return false;
    }
  }

  Future<void> _downloadModel() async {
    setState(() {
      _isDownloading = true;
      _errorMessage = null;
    });

    _modelService.downloadModel(
      onProgress: (progress) {
        setState(() {
          _downloadProgress = progress;
        });
      },
      onCompleted: () async {
        final success = await _loadModel();
        setState(() {
          _isDownloading = false;
          if (success) {
            _modelReady = true;
          }
        });
      },
      onError: (error) {
        setState(() {
          _isDownloading = false;
          _errorMessage = error;
        });
      },
    );
  }

  Future<void> _sendMessage() async {
    if (_interpreter == null) {
      setState(() {
        _messages.add({"role": "bot", "text": "Error: Model not loaded. Please wait or reload the model."});
      });
      return;
    }
    final text = _controller.text.trim();
    if (text.isEmpty || _interpreter == null) return;

    setState(() {
      _messages.add({"role": "user", "text": text});
      _isGenerating = true;
    });
    _controller.clear();

    try {
      // TODO: Implement actual LLM inference here
      // var input = [/* encoded tokens */];
      // var output = List.filled(outputSize, 0.0).reshape([1, outputSize]);
      // _interpreter!.run(input, output);
      
      await Future.delayed(const Duration(milliseconds: 500));
      final response = "Echo: $text";
      
      setState(() {
        _messages.add({"role": "bot", "text": response});
      });
    } catch (e) {
      setState(() {
        _messages.add({"role": "bot", "text": "Error: $e"});
      });
    } finally {
      setState(() {
        _isGenerating = false;
      });
    }
  }

  @override
  void dispose() {
    _interpreter?.close();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('LiteRT LLM Chat'),
        centerTitle: true,
      ),
      body: Column(
        children: [
          // Status bar
          Container(
            padding: const EdgeInsets.all(12),
            color: _modelReady ? Colors.green.shade100 : Colors.orange.shade100,
            child: Row(
              children: [
                Icon(
                  _modelReady ? Icons.check_circle : Icons.warning,
                  color: _modelReady ? Colors.green : Colors.orange,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    _modelReady ? 'Model Ready' : 'Model Not Ready',
                    style: TextStyle(
                      color: _modelReady ? Colors.green.shade900 : Colors.orange.shade900,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Download UI
          if (!_modelReady) ...[
            Expanded(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.cloud_download,
                        size: 64,
                        color: Colors.blue.shade300,
                      ),
                      const SizedBox(height: 24),
                      Text(
                        'Model (~1-2GB)',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 24),
                      if (!_isDownloading)
                        ElevatedButton(
                          onPressed: _downloadModel,
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
                          ),
                          child: const Text('Download Model'),
                        ),
                      if (_isDownloading) ...[
                        LinearProgressIndicator(value: _downloadProgress),
                        const SizedBox(height: 12),
                        Text('${(_downloadProgress * 100).toStringAsFixed(1)}%'),
                      ],
                      if (_errorMessage != null) ...[
                        const SizedBox(height: 16),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.red.shade50,
                            border: Border.all(color: Colors.red),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            _errorMessage!,
                            style: TextStyle(color: Colors.red.shade900),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ],

          // Chat UI
          if (_modelReady) ...[
            Expanded(
              child: ListView.builder(
                reverse: true,
                itemCount: _messages.length,
                itemBuilder: (context, index) {
                  final message = _messages[_messages.length - 1 - index];
                  final isUser = message['role'] == 'user';
                  
                  return Align(
                    alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
                    child: Container(
                      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: isUser ? Colors.blue : Colors.grey.shade200,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        message['text']!,
                        style: TextStyle(
                          color: isUser ? Colors.white : Colors.black,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],

          // Input area
          if (_modelReady)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: Colors.grey.shade300)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      decoration: InputDecoration(
                        hintText: 'Type your message...',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                        ),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      ),
                      enabled: !_isGenerating,
                    ),
                  ),
                  const SizedBox(width: 8),
                  FloatingActionButton(
                    mini: true,
                    onPressed: _isGenerating ? null : _sendMessage,
                    child: _isGenerating
                        ? SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation(Colors.white),
                            ),
                          )
                        : const Icon(Icons.send),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
