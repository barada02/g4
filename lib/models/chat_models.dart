/// Chat message model for history
class ChatMessage {
  final bool isUser;
  final String content;

  ChatMessage({required this.isUser, required this.content});
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

  AppMessage({required this.content, required this.isUser});

  factory AppMessage.text({required String text, required bool isUser}) {
    return AppMessage(content: text, isUser: isUser);
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
