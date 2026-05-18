import 'package:flutter/material.dart';
import 'package:flutter_gemma/flutter_gemma.dart';
import 'services/gemma_service.dart';
import 'models/chat_models.dart' as app_models;
import 'services/settings_service.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:typed_data';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Initialize services
  await SettingsService.instance.init();
  await FlutterGemma.initialize();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Gemma 4 Chat',
      theme: ThemeData.dark(useMaterial3: true).copyWith(
        useMaterial3: true,
        primaryColor: const Color(0xFF6366F1),
        scaffoldBackgroundColor: const Color(0xFF0F172A),
        appBarTheme: AppBarTheme(
          backgroundColor: const Color(0xFF1E293B),
          elevation: 0,
          centerTitle: true,
          titleTextStyle: const TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
      ),
      home: const ChatPage(),
      debugShowCheckedModeBanner: false,
    );
  }
}

class ChatPage extends StatefulWidget {
  const ChatPage({super.key});

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  final List<app_models.ChatMessage> _messages = [];
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final ImagePicker _picker = ImagePicker();
  List<Uint8List> _selectedImages = [];

  bool _isInitializing = true;
  bool _isGenerating = false;
  String _status = 'Initializing Gemma...';
  String _responseBuffer = '';
  int _downloadProgress = 0;
  app_models.MessageStats? _lastStats;

  @override
  void initState() {
    super.initState();
    _initializeModel();
  }

  Future<void> _pickImage() async {
    final XFile? image = await _picker.pickImage(source: ImageSource.gallery);
    if (image != null) {
      final bytes = await image.readAsBytes();
      setState(() {
        _selectedImages.add(bytes);
      });
    }
  }

  void _removeImage(int index) {
    setState(() {
      _selectedImages.removeAt(index);
    });
  }

  Future<void> _initializeModel() async {
    try {
      Future.microtask(() async {
        try {
          await GemmaService.instance.init();

          if (GemmaService.instance.isInitialised) {
            setState(() {
              _isInitializing = false;
              _status = 'Gemma 4 Ready ✅';
              _downloadProgress = 100;
              _messages.add(app_models.ChatMessage(
                isUser: false,
                content: 'Hi! I\'m Gemma 4 E2B. Ask me anything!',
              ));
            });
          } else {
            final error = GemmaService.instance.initError ?? 'Unknown error';
            setState(() {
              _isInitializing = false;
              _status = 'Model Setup Failed';
              _downloadProgress = 0;
              _messages.add(app_models.ChatMessage(
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
            _messages.add(app_models.ChatMessage(
              isUser: false,
              content: '⚠️ Initialization error: $e\n\n'
                  'Please restart the app and try again.',
            ));
          });
        }
      });

      while (_isInitializing) {
        await Future.delayed(const Duration(milliseconds: 500));

        setState(() {
          _downloadProgress = GemmaService.instance.downloadProgress;
          _status = GemmaService.instance.downloadStatus;
        });

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
        _scrollController.jumpTo(
          _scrollController.position.maxScrollExtent,
        );
      }
    });
  }

  Future<void> _sendMessage() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _isGenerating) return;

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

    setState(() {
      _messages.add(app_models.ChatMessage(
        isUser: true,
        content: text,
        images: List.from(_selectedImages),
      ));
      _isGenerating = true;
      _responseBuffer = '';
      _lastStats = null;
    });

    _scrollToBottom();

    try {
      await GemmaService.instance.sendWithStreaming(
        text: text,
        images: _selectedImages,
        onToken: (token) {
          setState(() {
            _responseBuffer += token;
          });
          _scrollToBottom();
        },
        onComplete: (stats) {
          setState(() {
            _messages.add(app_models.ChatMessage(isUser: false, content: _responseBuffer));
            _isGenerating = false;
            _responseBuffer = '';
            _lastStats = stats;
            _selectedImages.clear();
          });
          _scrollToBottom();
        },
      );
    } catch (e) {
      setState(() {
        _messages.add(app_models.ChatMessage(
          isUser: false,
          content: '❌ Error: ${e.toString()}',
        ));
        _isGenerating = false;
        _responseBuffer = '';
      });
      debugPrint('Error sending message: $e');
    }
  }

  Future<void> _clearChat() async {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        title: const Text('Clear Chat?'),
        content: const Text(
          'This will clear all messages and reset the conversation. KV cache will be deleted.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              await GemmaService.instance.clearChat();
              setState(() {
                _messages.clear();
                _lastStats = null;
                _messages.add(app_models.ChatMessage(
                  isUser: false,
                  content: 'Chat cleared! KV cache reset. Ready for new conversation.',
                ));
              });
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('✅ Chat cleared')),
              );
            },
            child: const Text('Clear', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  void _showSettingsPanel() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E293B),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => _SettingsPanel(
        onClose: () => Navigator.pop(context),
      ),
    );
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
                valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF6366F1)),
              ),
              const SizedBox(height: 40),
              Text(
                _status,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 30),
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
                            Color(0xFF6366F1),
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
        elevation: 2,
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: _showSettingsPanel,
            tooltip: 'Settings',
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            onPressed: _clearChat,
            tooltip: 'Clear Chat',
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: _messages.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            color: const Color(0xFF6366F1).withOpacity(0.1),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Icon(
                            Icons.chat_bubble_outline,
                            size: 64,
                            color: Colors.grey[400],
                          ),
                        ),
                        const SizedBox(height: 20),
                        Text(
                          'Start a conversation',
                          style: TextStyle(
                            color: Colors.grey[400],
                            fontSize: 18,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Ask anything and get instant responses',
                          style: TextStyle(
                            color: Colors.grey[600],
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.all(16),
                    itemCount: _messages.length + (_lastStats != null ? 1 : 0),
                    itemBuilder: (context, index) {
                      if (index == _messages.length) {
                        return Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Center(
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0xFF6366F1).withOpacity(0.2),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                _lastStats!.formattedStats,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey[400],
                                ),
                              ),
                            ),
                          ),
                        );
                      }

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
                                ? const Color(0xFF6366F1)
                                : const Color(0xFF334155),
                            borderRadius: BorderRadius.circular(18),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.2),
                                blurRadius: 8,
                                offset: const Offset(0, 2),
                              ),
                            ],
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
                                          Colors.grey[400]!,
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
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              border: Border(
                top: BorderSide(color: Colors.grey[800]!),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_selectedImages.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12, left: 8),
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: _selectedImages.asMap().entries.map((entry) {
                          int index = entry.key;
                          Uint8List bytes = entry.value;
                          return Stack(
                            children: [
                              Container(
                                margin: const EdgeInsets.only(right: 8),
                                width: 60,
                                height: 60,
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(8),
                                  image: DecorationImage(
                                    image: MemoryImage(bytes),
                                    fit: BoxFit.cover,
                                  ),
                                ),
                              ),
                              Positioned(
                                right: 0,
                                top: 0,
                                child: GestureDetector(
                                  onTap: () => _removeImage(index),
                                  child: Container(
                                    decoration: const BoxDecoration(
                                      color: Colors.red,
                                      shape: BoxShape.circle,
                                    ),
                                    child: const Icon(
                                      Icons.close,
                                      size: 16,
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          );
                        }).toList(),
                      ),
                    ),
                  ),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _controller,
                        decoration: InputDecoration(
                          hintText: 'Type your message...',
                          prefixIcon: IconButton(
                            icon: const Icon(Icons.image, color: Colors.grey),
                            onPressed: _pickImage,
                            tooltip: 'Pick Image',
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(30),
                            borderSide: BorderSide(
                              color: Colors.grey[700]!,
                            ),
                          ),
                          filled: true,
                          fillColor: const Color(0xFF1E293B),
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
                      backgroundColor: const Color(0xFF6366F1),
                      onPressed: _isGenerating ? null : _sendMessage,
                      child: Icon(
                        Icons.send,
                        color: _isGenerating ? Colors.grey : Colors.white,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SettingsPanel extends StatefulWidget {
  final VoidCallback onClose;

  const _SettingsPanel({required this.onClose});

  @override
  State<_SettingsPanel> createState() => _SettingsPanelState();
}

class _SettingsPanelState extends State<_SettingsPanel> {
  late double _temperature;
  late int _topK;
  late double _topP;
  late int _maxTokens;

  @override
  void initState() {
    super.initState();
    _temperature = SettingsService.instance.temperature;
    _topK = SettingsService.instance.topK;
    _topP = SettingsService.instance.topP;
    _maxTokens = SettingsService.instance.maxTokens;
  }

  Future<void> _saveSettings() async {
    await SettingsService.instance.setTemperature(_temperature);
    await SettingsService.instance.setTopK(_topK);
    await SettingsService.instance.setTopP(_topP);
    await SettingsService.instance.setMaxTokens(_maxTokens);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('✅ Settings saved')),
      );
      widget.onClose();
    }
  }

  Future<void> _resetToDefaults() async {
    await SettingsService.instance.resetToDefaults();
    setState(() {
      _temperature = SettingsService.instance.temperature;
      _topK = SettingsService.instance.topK;
      _topP = SettingsService.instance.topP;
      _maxTokens = SettingsService.instance.maxTokens;
    });

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('🔄 Reset to defaults')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey[600],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'Model Settings',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 24),
            _SettingSlider(
              label: 'Temperature',
              value: _temperature,
              min: 0.0,
              max: 2.0,
              divisions: 40,
              onChanged: (value) {
                setState(() => _temperature = value);
              },
              subtitle: 'Controls randomness (0 = deterministic, 2 = creative)',
            ),
            const SizedBox(height: 24),
            _SettingSlider(
              label: 'Top K',
              value: _topK.toDouble(),
              min: 1,
              max: 100,
              divisions: 99,
              onChanged: (value) {
                setState(() => _topK = value.toInt());
              },
              subtitle: 'Limits to top K most likely tokens',
            ),
            const SizedBox(height: 24),
            _SettingSlider(
              label: 'Top P (Nucleus)',
              value: _topP,
              min: 0.0,
              max: 1.0,
              divisions: 20,
              onChanged: (value) {
                setState(() => _topP = value);
              },
              subtitle: 'Cumulative probability threshold',
            ),
            const SizedBox(height: 24),
            _SettingSlider(
              label: 'Max Tokens',
              value: _maxTokens.toDouble(),
              min: 256,
              max: 4096,
              divisions: 15,
              onChanged: (value) {
                setState(() => _maxTokens = value.toInt());
              },
              subtitle: 'Maximum response length',
            ),
            const SizedBox(height: 32),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _resetToDefaults,
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      side: const BorderSide(color: Colors.orange),
                    ),
                    child: const Text('Reset'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: _saveSettings,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF6366F1),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    child: const Text('Save Settings'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}

class _SettingSlider extends StatelessWidget {
  final String label;
  final double value;
  final double min;
  final double max;
  final int divisions;
  final ValueChanged<double> onChanged;
  final String subtitle;

  const _SettingSlider({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.onChanged,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    final isInt = min == min.toInt() && max == max.toInt();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              label,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFF6366F1).withOpacity(0.2),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                isInt ? value.toInt().toString() : value.toStringAsFixed(2),
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF6366F1),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Slider(
          value: value,
          min: min,
          max: max,
          divisions: divisions,
          onChanged: onChanged,
          activeColor: const Color(0xFF6366F1),
          inactiveColor: Colors.grey[800],
        ),
        const SizedBox(height: 4),
        Text(
          subtitle,
          style: TextStyle(
            fontSize: 12,
            color: Colors.grey[500],
          ),
        ),
      ],
    );
  }
}

