import 'package:flutter/material.dart';
import '../services/model_service.dart';
import 'chat_screen.dart';

class LandingScreen extends StatefulWidget {
  const LandingScreen({super.key});

  @override
  State<LandingScreen> createState() => _LandingScreenState();
}

class _LandingScreenState extends State<LandingScreen> {
  final ModelService _modelService = ModelService();
  bool _isReady = false;
  bool _isDownloading = false;
  double _progress = 0;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _checkModelState();
  }

  Future<void> _checkModelState() async {
    final ready = await _modelService.isModelSaved();
    setState(() {
      _isReady = ready;
    });
  }

  void _startDownload() {
    setState(() {
      _isDownloading = true;
      _errorMessage = null;
    });

    _modelService.downloadModel(
      onProgress: (progress) {
        setState(() {
          _progress = progress;
        });
      },
      onCompleted: () {
        setState(() {
          _isDownloading = false;
          _isReady = true;
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

  void _navigateToChat() {
    if (_isReady && !_isDownloading) {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (context) => const ChatScreen()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('LiteRT LLM Downloader')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                _isReady ? Icons.check_circle : Icons.download,
                size: 80,
                color: _isReady ? Colors.green : Colors.blue,
              ),
              const SizedBox(height: 24),
              Text(
                _isReady ? 'Model Ready' : 'Model not found on device',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 24),
              if (!_isReady && !_isDownloading)
                ElevatedButton(
                  onPressed: _startDownload,
                  child: const Text('Download Model (~1-2GB)'),
                ),
              if (_isDownloading) ...[
                LinearProgressIndicator(value: _progress),
                const SizedBox(height: 8),
                Text('${(_progress * 100).toStringAsFixed(1)}%'),
              ],
              if (_errorMessage != null) ...[
                const SizedBox(height: 16),
                Text(
                  _errorMessage!,
                  style: const TextStyle(color: Colors.red),
                  textAlign: TextAlign.center,
                ),
              ],
              const Spacer(),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: (_isReady && !_isDownloading) ? _navigateToChat : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blueAccent,
                    foregroundColor: Colors.white,
                  ),
                  child: const Text('Start Chat', style: TextStyle(fontSize: 18)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
