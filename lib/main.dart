import 'package:flutter/material.dart';
import 'services/gemma_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    await GemmaService.instance.init();
  } catch (e) {
    debugPrint('Failed to initialize Gemma: $e');
  }

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Gemma 4 Chat',
      theme: ThemeData.dark(useMaterial3: true),
      home: const ChatPage(),
      debugShowCheckedModeBanner: false,
    );
  }
}

class ChatMessage {
  final bool isUser;
  final String content;

  ChatMessage({required this.isUser, required this.content});
}

class ChatPage extends StatefulWidget {
  const ChatPage({super.key});

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  final List<ChatMessage> _messages = [];
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  bool _isInitializing = true;
  bool _isGenerating = false;
  String _status = 'Initializing Gemma...';
  String _responseBuffer = '';

  @override
  void initState() {
    super.initState();
    _initializeModel();
  }

  Future<void> _initializeModel() async {
    try {
      // Service already initialized in main, check if ready
      if (GemmaService.instance.isInitialised) {
        setState(() {
          _isInitializing = false;
          _status = 'Gemma 4 Ready ✅';
          _messages.add(ChatMessage(
            isUser: false,
            content: 'Hi! I\'m Gemma 4 E2B. Ask me anything about any topic!',
          ));
        });
      } else {
        setState(() {
          _isInitializing = false;
          _status = 'Model not available';
        });
      }
    } catch (e) {
      setState(() {
        _isInitializing = false;
        _status = 'Error: $e';
      });
    }
  }

  void _scrollToBottom() {
    Future.microtask(() {
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    });
  }

  Future<void> _sendMessage() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _isGenerating) return;

    _controller.clear();

    // Add user message
    setState(() {
      _messages.add(ChatMessage(isUser: true, content: text));
      _isGenerating = true;
      _responseBuffer = '';
    });

    _scrollToBottom();

    try {
      await GemmaService.instance.sendWithStreaming(
        text: text,
        onToken: (token) {
          setState(() {
            _responseBuffer += token;
          });
          _scrollToBottom();
        },
        onComplete: (stats) {
          // Add assistant message with complete response
          setState(() {
            _messages.add(ChatMessage(isUser: false, content: _responseBuffer));
            _isGenerating = false;
            _responseBuffer = '';
          });
          _scrollToBottom();
        },
      );
    } catch (e) {
      setState(() {
        _messages.add(ChatMessage(
          isUser: false,
          content: 'Error: Failed to generate response. Please try again.',
        ));
        _isGenerating = false;
        _responseBuffer = '';
      });
      debugPrint('Error sending message: $e');
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isInitializing) {
      return Scaffold(
        appBar: AppBar(title: const Text('Gemma 4 Chat')),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 20),
              Text(_status),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Gemma 4 Chat'),
        centerTitle: true,
        elevation: 2,
      ),
      body: Column(
        children: [
          // Chat messages
          Expanded(
            child: _messages.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.chat_bubble_outline,
                          size: 64,
                          color: Colors.grey[600],
                        ),
                        const SizedBox(height: 20),
                        Text(
                          'Start a conversation',
                          style: TextStyle(
                            color: Colors.grey[400],
                            fontSize: 16,
                          ),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.all(16),
                    itemCount: _messages.length,
                    itemBuilder: (context, index) {
                      final msg = _messages[index];
                      final isLastMessage = index == _messages.length - 1;
                      final isAssistantGenerating =
                          isLastMessage && _isGenerating;

                      return Align(
                        alignment: msg.isUser
                            ? Alignment.centerRight
                            : Alignment.centerLeft,
                        child: Container(
                          margin: const EdgeInsets.only(bottom: 12),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 12,
                          ),
                          constraints: BoxConstraints(
                            maxWidth:
                                MediaQuery.of(context).size.width * 0.75,
                          ),
                          decoration: BoxDecoration(
                            color: msg.isUser
                                ? Colors.blue[700]
                                : Colors.grey[800],
                            borderRadius: BorderRadius.circular(18),
                          ),
                          child: isAssistantGenerating
                              ? Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      msg.content,
                                      style: const TextStyle(fontSize: 15),
                                    ),
                                    const SizedBox(width: 8),
                                    SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        valueColor:
                                            AlwaysStoppedAnimation<Color>(
                                          Colors.blue[300]!,
                                        ),
                                      ),
                                    ),
                                  ],
                                )
                              : Text(
                                  msg.content,
                                  style: const TextStyle(fontSize: 15),
                                ),
                        ),
                      );
                    },
                  ),
          ),

          // Input field
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: Colors.grey[700]!)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    decoration: InputDecoration(
                      hintText: 'Type your message...',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(30),
                      ),
                      filled: true,
                      fillColor: Colors.grey[900],
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                    ),
                    enabled: !_isGenerating,
                    maxLines: null,
                    onSubmitted: (_) {
                      if (!_isGenerating) _sendMessage();
                    },
                  ),
                ),
                const SizedBox(width: 8),
                FloatingActionButton(
                  mini: true,
                  onPressed: _isGenerating ? null : _sendMessage,
                  child: const Icon(Icons.send),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

