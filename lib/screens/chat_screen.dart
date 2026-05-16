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
  // Make sure to match the actual Litert model runner class.
  // This is a placeholder for the actual API.
  dynamic _engine; 

  @override
  void initState() {
    super.initState();
    _initModel();
  }

  Future<void> _initModel() async {
    try {
      final modelPath = await ModelService().getModelPath();
      // Initialize the model with the downloaded path. 
      // Replace this initialization with accurate flutter_litert implementation.
      // _engine = await LiteRTEngine.load(modelPath);
      
      setState(() {
        _isLoading = false;
      });
    } catch (e) {
      debugPrint("Error loading model: $e");
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
      // Simulate inference prompt or call the actual Litert plugin here
      // final response = await _engine.generate(text);
      await Future.delayed(const Duration(seconds: 2)); // Mock delay
      final response = "Echo from LiteRT model: $text (Implementation pending flutter_litert API specifics)";
      
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
