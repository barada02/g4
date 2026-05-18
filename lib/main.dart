import 'package:flutter/material.dart';
import 'package:flutter_gemma/flutter_gemma.dart';
import 'services/gemma_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Initialize flutter_gemma plugin BEFORE using it
  await FlutterGemma.initialize();
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
  int _downloadProgress = 0;
  String? _selectedBackend;  // Track selected GPU/CPU backend

  @override
  void initState() {
    super.initState();
    _initializeModel();
  }

  Future<void> _initializeModel() async {
    try {
      // Kick off initialization in the background
      // This will handle both download and model setup
      Future.microtask(() async {
        try {
          // Initialize service - it will download model if needed, then set it up
          await GemmaService.instance.init();

          // After init() completes, check if it was successful
          if (GemmaService.instance.isInitialised) {
            setState(() {
              _isInitializing = false;
              _status = 'Gemma 4 Ready ✅';
              _downloadProgress = 100;
              _messages.add(ChatMessage(
                isUser: false,
                content: 'Hi! I\'m Gemma 4 E2B. Ask me anything!',
              ));
            });
          } else {
            // Show initialization error
            final error = GemmaService.instance.initError ?? 'Unknown error';
            setState(() {
              _isInitializing = false;
              _status = 'Model Setup Failed';
              _downloadProgress = 0;
              _messages.add(ChatMessage(
                isUser: false,
                content: '⚠️ Failed to initialize model.\n\n'
                    'Error: $error\n\n'
                    'Please restart the app and try again.',
              ));
            });
          }
        } catch (e) {
          setState(() {
            _isInitializing = false;
            _status = 'Initialization Error: $e';
            _downloadProgress = 0;
            _messages.add(ChatMessage(
              isUser: false,
              content: '⚠️ Initialization error: $e\n\n'
                  'Please restart the app and try again.',
            ));
          });
        }
      });

      // Continuously update UI while downloading/initializing (500ms polling)
      while (_isInitializing) {
        await Future.delayed(const Duration(milliseconds: 500));
        
        setState(() {
          _downloadProgress = GemmaService.instance.downloadProgress;
          _status = GemmaService.instance.downloadStatus;
        });

        // Exit polling if initialization completed
        if (GemmaService.instance.isInitialised || 
            GemmaService.instance.initError != null) {
          break;
        }
      }
    } catch (e) {
      setState(() {
        _isInitializing = false;
        _status = 'Error: $e';
        _downloadProgress = 0;
      });
    }
  }

  void _scrollToBottom() {
    Future.microtask(() {
      if (_scrollController.positions.isNotEmpty) {
        // Jump immediately to bottom during streaming (no animation)
        _scrollController.jumpTo(
          _scrollController.position.maxScrollExtent,
        );
      }
    });
  }

  Future<void> _sendMessage() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _isGenerating) return;

    // Check if model is initialized before sending
    if (!GemmaService.instance.isInitialised) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('⚠️ Model not ready. Error: ${GemmaService.instance.initError}'),
          duration: const Duration(seconds: 3),
        ),
      );
      return;
    }

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
          _scrollToBottom();  // Scroll on every token for smooth following
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
          content: '❌ Error: ${e.toString()}',
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
              const CircularProgressIndicator(
                strokeWidth: 3,
                valueColor: AlwaysStoppedAnimation<Color>(Colors.blue),
              ),
              const SizedBox(height: 40),
              // Status text
              Text(
                _status,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 30),
              // Progress bar and percentage
              if (_downloadProgress > 0 && _downloadProgress < 100)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 32),
                  child: Column(
                    children: [
                      SizedBox(
                        width: double.infinity,
                        child: LinearProgressIndicator(
                          value: _downloadProgress / 100,
                          minHeight: 10,
                          backgroundColor: Colors.grey[800],
                          valueColor: const AlwaysStoppedAnimation<Color>(
                            Colors.blue,
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        '${_downloadProgress.toStringAsFixed(0)}%',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                )
              else if (_downloadProgress == 100)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 32),
                  child: Column(
                    children: [
                      SizedBox(
                        width: double.infinity,
                        child: LinearProgressIndicator(
                          value: 1.0,
                          minHeight: 10,
                          backgroundColor: Colors.grey[800],
                          valueColor: const AlwaysStoppedAnimation<Color>(
                            Colors.green,
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'Finalizing...',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                          color: Colors.green,
                        ),
                      ),
                    ],
                  ),
                ),
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
                    reverse: false,  // Messages flow bottom-up naturally
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
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    Flexible(
                                      child: Text(
                                        msg.content,
                                        style: const TextStyle(fontSize: 15),
                                        softWrap: true,
                                      ),
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

