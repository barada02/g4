import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_litert/flutter_litert.dart';
import '../services/model_service.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _controller = TextEditingController();
  final List<Map<String, String>> _messages = [];
  bool _isLoading = true;
  bool _isGenerating = false;
  Interpreter? _interpreter;

  @override
  void initState() {
    super.initState();
    _initModel();
  }

  Future<void> _initModel() async {
    try {
      final modelPath = await ModelService().getModelPath();
      final file = File(modelPath);
      
      // Debug: Verify file exists before loading
      final fileExists = await file.exists();
      debugPrint('Model file exists: $fileExists at path: $modelPath');
      
      if (!fileExists) {
        throw Exception('Model file not found at: $modelPath');
      }
      
      final fileSize = await file.length();
      debugPrint('Model file size: ${(fileSize / (1024 * 1024)).toStringAsFixed(2)} MB');
      
      // Initialize the LiteRT Interpreter with the model file
      _interpreter = await Interpreter.fromFile(file);
      
      debugPrint('Model loaded successfully');
      setState(() {
        _isLoading = false;
      });
    } catch (e) {
      debugPrint("Error loading model: $e");
      setState(() {
        _messages.add({"role": "bot", "text": "Failed load model: $e"});
        _isLoading = false;
      });
    }
  }

  void _sendMessage() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;

    setState(() {
      _messages.add({"role": "user", "text": text});
      _isGenerating = true;
    });
    _controller.clear();

    try {
      if (_interpreter == null) {
        throw Exception("Interpreter not loaded.");
      }

      // NOTE: For full LLM generation via raw TFLite (LiteRT), you generally need
      // to tokenize the input text, pass token IDs to the interpreter, and decode
      // the output logits. Since flutter_litert provides raw Interpreter bindings,
      // you will need the specific input/output shapes for your Gemma version.
      
      // Mocking the raw interpreter behavior so the app doesn't crash on run
      // var input = [/* encoded tokens */];
      // var output = List.filled(outputShape, 0).reshape([1, outputShape]);
      // _interpreter!.run(input, output);
      
      await Future.delayed(const Duration(seconds: 1)); // Mock delay
      final response = "Echo from LiteRT model: $text (Raw interpreter loaded! Full tokenization pipeline implementation required for LLM output)";
      
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
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Local LLM Chat')),
      body: _isLoading 
        ? const Center(child: CircularProgressIndicator())
        : Column(
            children: [
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.all(16.0),
                  itemCount: _messages.length,
                  itemBuilder: (context, index) {
                    final msg = _messages[index];
                    final isUser = msg["role"] == "user";
                    return Align(
                      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
                      child: Container(
                        margin: const EdgeInsets.symmetric(vertical: 4.0),
                        padding: const EdgeInsets.all(12.0),
                        decoration: BoxDecoration(
                          color: isUser ? Colors.blueAccent : Colors.grey[300],
                          borderRadius: BorderRadius.circular(8.0),
                        ),
                        child: Text(
                          msg["text"] ?? "",
                          style: TextStyle(color: isUser ? Colors.white : Colors.black87),
                        ),
                      ),
                    );
                  },
                ),
              ),
              if (_isGenerating)
                const Padding(
                  padding: EdgeInsets.all(8.0),
                  child: CircularProgressIndicator(),
                ),
              Padding(
                padding: const EdgeInsets.all(8.0),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _controller,
                        decoration: const InputDecoration(
                          hintText: 'Type your message...',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      icon: const Icon(Icons.send),
                      onPressed: _isGenerating ? null : _sendMessage,
                    )
                  ],
                ),
              ),
            ],
          ),
    );
  }
}
