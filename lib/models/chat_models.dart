import 'dart:typed_data';

/// Chat message model for history
class ChatMessage {
  final bool isUser;
  final String content;
  final List<Uint8List>? images;

  ChatMessage({required this.isUser, required this.content, this.images});
}

/// Text response model (custom - different from flutter_gemma's TextResponse)
class AppTextResponse {
  final String token;
  AppTextResponse({required this.token});
}

/// Message model (custom - different from flutter_gemma's Message)
class AppMessage {
  final String content;
  final bool isUser;
  final List<Uint8List>? images;

  AppMessage({required this.content, required this.isUser, this.images});

  factory AppMessage.text({required String text, required bool isUser}) {
    return AppMessage(content: text, isUser: isUser);
  }

  factory AppMessage.multimodal({
    required String text,
    required bool isUser,
    required List<Uint8List> images,
  }) {
    return AppMessage(content: text, isUser: isUser, images: images);
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
