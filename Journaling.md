# Gemma 4 On-Device Inference - Problem Resolution Journal

## Overview
This document chronicles all issues encountered while implementing the Gemma 4 on-device inference chat application and their solutions.

---

## Problem 1: Out of Memory Error During Model Download

### Issue
The app crashed with "Out of Memory" error when downloading the 2.4GB Gemma 4 model.

### Root Cause
The code was buffering the entire model file in memory before writing to disk:
```dart
// ❌ WRONG - Buffered entire file in RAM
final bytes = <int>[];
await streamedResponse.stream.forEach((chunk) {
  bytes.addAll(chunk);  // 2.4GB accumulating in memory!
});
await modelFile.writeAsBytes(bytes);
```

### Solution
Stream file chunks directly to disk without buffering:
```dart
// ✅ CORRECT - Direct disk write
final raf = modelFile.openSync(FileMode.write);
await streamedResponse.stream.forEach((chunk) {
  raf.writeFromSync(chunk);  // Write immediately to disk
});
raf.closeSync();
```

**Result**: Model downloads successfully without OOM errors, regardless of file size.

---

## Problem 2: FlutterGemma Plugin Not Initialized

### Issue
App crashed with error:
```
Bad state: FlutterGemma not initialized! 
You must call FlutterGemma.initialize() in main()
```

### Root Cause
The flutter_gemma plugin requires explicit initialization before any usage, but this wasn't called in the app entry point.

### Solution
Add initialization in `main.dart`:
```dart
import 'package:flutter_gemma/flutter_gemma.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await FlutterGemma.initialize();  // ✅ Initialize plugin first
  runApp(const MyApp());
}
```

**Result**: Plugin properly initialized before service tries to use it.

---

## Problem 3: Model Initialization Starting Before Download Completed

### Issue
The initialization sequence was trying to load the model while download was still in progress, causing file access errors.

### Root Cause
No synchronization between download completion and model initialization phases.

### Solution
Implement strict two-phase initialization:
```dart
// Phase 1: Download (must reach 100%)
final modelPath = await _downloadModelIfNeeded();
assert(_downloadProgress == 100, 'Download not complete!');

// Phase 2: Initialize (only after phase 1 done)
_gemma.createModel(modelType: ModelType.gemmaIt, maxTokens: 2048);
_chat = _model.createChat(...);
```

**Result**: Model only initializes after download is verified at 100%.

---

## Problem 4: Wrong InferenceChat API Calls

### Issue
Multiple API errors in sequence:
```
Error 1: NoSuchMethodError: Class 'InferenceChat' has no instance method 'addMessage'
Error 2: NoSuchMethodError: Class 'InferenceChat' has no instance method 'streamResponse'
Error 3: NoSuchMethodError: Class 'InferenceChat' has no instance method 'respondStream'
Error 4: NoSuchMethodError: Class 'InferenceChat' has no instance method 'respond'
```

### Root Cause
Incorrect assumptions about flutter_gemma 0.12.6 API. The `InferenceChat` class doesn't have any of these methods - they were guesses based on common patterns.

### Solution
Research the actual flutter_gemma 0.12.6 API documentation:

| Operation | ❌ Wrong | ✅ Correct |
|-----------|---------|-----------|
| Add message | `_chat.addMessage(text)` | `await _chat.addQuery(Message.text(text: text, isUser: true))` |
| Get response | `_chat.streamResponse(callback)` | `_chat.generateChatResponseAsync()` returns `Stream<ModelResponse>` |
| Handle tokens | `callback(token)` | `await for (response in stream) { if (response is TextResponse) { token = response.token; } }` |

**Correct Implementation**:
```dart
// Add user message to conversation
await _chat.addQuery(Message.text(text: text, isUser: true));

// Stream responses token-by-token
final responseStream = _chat.generateChatResponseAsync();

await for (final response in responseStream) {
  if (response is TextResponse) {
    onToken(response.token);  // Each token streamed individually
  }
}
```

**Result**: Correct API method calls, tokens stream successfully to UI.

---

## Problem 5: ScrollController Crash on Message Arrival

### Issue
App crashed when auto-scrolling to new message:
```
Bad state: No active positions
```

### Root Cause
Called `_scrollController.animateTo()` before the scroll view was rendered/attached.

### Solution
Add safety check:
```dart
// ❌ WRONG
_scrollController.animateTo(_scrollController.position.maxScrollExtent);

// ✅ CORRECT
if (_scrollController.positions.isNotEmpty) {
  _scrollController.animateTo(_scrollController.position.maxScrollExtent);
}
```

**Result**: No crash, smooth auto-scroll when messages arrive.

---

## Summary of Key Fixes

| Problem | Type | Impact | Solution |
|---------|------|--------|----------|
| Memory buffering | Architecture | ❌ OOM crash | Stream to disk directly |
| Plugin not initialized | Setup | ❌ Plugin error | Call `FlutterGemma.initialize()` in main() |
| Download-init timing | Orchestration | ❌ File errors | Two-phase: download→init |
| Wrong API methods | API mismatch | ❌ Multiple crashes | Use correct `addQuery()` + `generateChatResponseAsync()` |
| ScrollController timing | UI timing | ❌ Crash | Check `positions.isNotEmpty` |

---

## Final Working Implementation

### Model Download (Streaming, No OOM)
- Location: `lib/services/gemma_service.dart` → `_downloadModelIfNeeded()`
- Streams chunks directly: `raf.writeFromSync(chunk)`
- Updates UI progress every 1% or 5MB
- Returns model path when complete

### Plugin Initialization
- Location: `lib/main.dart` → `main()`
- Calls: `await FlutterGemma.initialize()`
- Happens before `runApp()`

### Two-Phase Initialization
- Location: `lib/services/gemma_service.dart` → `init()`
- Phase 1: Download model to 100%
- Phase 2: Load model and create chat session

### Token Streaming
- Location: `lib/services/gemma_service.dart` → `sendWithStreaming()`
- Adds message: `await _chat.addQuery(Message.text(...))`
- Streams tokens: `await for (response in _chat.generateChatResponseAsync())`
- Filters: `if (response is TextResponse)`
- Calls: `onToken(response.token)` for each token

---

## Problem 6: LiteRT-LM Model Format Mismatch (v0.15.3 Upgrade)

### Issue
Upgraded to newer gemma-4-E2B-it model in `.litertlm` format (LiteRT-LM optimized). App crashed:
```
IllegalArgumentException: /data/user/0/com.example.g4/cache/gemma-4-E2B-it.litertlm 
is a LiteRT-LM model — it should be handled by Dart FFI (LiteRtLmFfiClient), 
not by EngineFactory.
```

### Root Cause
Old platform channel API (`createModel()` via JNI/EngineFactory) only supports `.task` format. New `.litertlm` format requires **Dart FFI backend** for native token-level streaming.

### Solution: Backend Migration
Migrated from **platform channel** → **Dart FFI**:

| Layer | Old (`.task`) | New (`.litertlm`) |
|-------|---|---|
| Dart → Native | Platform Channel (JNI) | Dart FFI (direct C bindings) |
| API | `FlutterGemmaPlugin.createModel()` | `LiteRtLmFfiClient.initialize()` |
| Response | Platform streaming | Native callbacks |

**Implementation**:
```dart
// Detect model format and route appropriately
if (modelPath.endsWith('.litertlm')) {
  _ffiClient = LiteRtLmFfiClient();
  await _ffiClient.initialize(modelPath: modelPath, backend: 'gpu');
  _ffiChat = _FFIChatWrapper(_ffiClient);  // Wrapper for compatibility
} else {
  // Use old platform channel for .task models
  await _gemma.modelManager.setModelPath(modelPath);
}
```

**Result**: Model loads via FFI, avoids EngineFactory error ✅

---

## Problem 7: Non-Streaming Response Display (FFI Integration)

### Issue
After FFI migration, responses appeared **instantly all at once** instead of token-by-token streaming.

### Root Cause
Was using `_client.chat()` which wraps `sendMessageStreamRaw()` but may buffer intermediate chunks. The native token stream wasn't being consumed properly.

### Solution: Use Low-Level Streaming API
Switch to `sendMessageStreamRaw()` (lowest-level native callback API) + proper JSON parsing:

```dart
// Use sendMessageStreamRaw for true token-by-token from native engine
final messageJson = LiteRtLmFfiClient.buildMessageJson(lastMessage['content']);

await for (final jsonChunk in _client.sendMessageStreamRaw(messageJson)) {
  final textToken = LiteRtLmFfiClient.extractTextFromResponse(jsonChunk);
  if (textToken.isNotEmpty) {
    yield TextResponse(token: textToken);
    await Future.delayed(const Duration(milliseconds: 25)); // Smooth UI
  }
}
```

**Key insight**: 
- `sendMessageStreamRaw()` = native callbacks (true streaming)
- `chat()` = wrapper around above (may batch chunks)
- `sendMessage()` = blocks until full response (buffered)

**Result**: Real token-by-token streaming from LiteRT-LM engine ✅

---

## Problem 8: Deprecated flutter_gemma API

### Issue
Code used deprecated `setModelPath()` method which triggered lint warning:
```
(deprecated) Future<void> setModelPath(String path, {String? loraPath})
Use FlutterGemma.installModel().fromFile() instead.
```

### Root Cause
flutter_gemma updated its API. The old `modelManager.setModelPath()` is deprecated in favor of a new builder pattern using `FlutterGemma.installModel()`.

### Solution: Use New Builder API
Migrated from deprecated platform channel model registration to new API:

```dart
// ❌ OLD (deprecated)
await _gemma.modelManager.setModelPath(modelPath);

// ✅ NEW (current API)
FlutterGemma.installModel(modelType: ModelType.gemmaIt).fromFile(modelPath);
```

**Key Points**:
- Use `FlutterGemma` class directly, not the plugin instance (`_gemma`)
- Provide required `modelType: ModelType.gemmaIt` parameter
- `fromFile()` returns `InferenceInstallationBuilder` (not a Future) - no `await` needed
- Method automatically sets the model as active

**Result**: No deprecation warnings, code uses current flutter_gemma API ✅

---

## Lessons Learned


1. **Always verify API contracts** - Don't assume method names; check actual package documentation
2. **Stream large files** - Never buffer large downloads in memory
3. **Explicit initialization** - Platform plugins often need explicit setup calls
4. **Orchestration matters** - Proper sequencing of async operations is critical
5. **UI safety checks** - Always verify UI state before calling animation methods
6. **Model format matters** - `.task` vs `.litertlm` require different backends (platform vs FFI)
7. **Use lowest-level API for streaming** - `sendMessageStreamRaw()` provides true native callbacks, not wrapped APIs

---

## Problem 9: Image & Text Both Broken After Multimodal Integration

### Issue
After implementing image support:
- Text-only messages stopped getting responses from model
- Image messages weren't being processed at all
- No error messages - just silent failures with no response tokens

### Root Cause
Manual JSON encoding was incorrect. The code was:
```dart
// ❌ WRONG - Manual JSON construction
final messageData = {'text': content};
if (images.isNotEmpty) {
  messageData['images'] = imageBytes;  // Raw Uint8List, not base64!
}
final messageJson = jsonEncode(messageData);
```

**The problems**:
1. **Images not base64-encoded** - FFI layer expects base64 strings, not raw bytes
2. **Missing type metadata** - JSON needed `'type': 'image'` for each image
3. **Incorrect content structure** - Should be array with text + image objects, not flat dict
4. **Model couldn't parse message** - Malformed JSON meant model got nothing to process

### Solution: Use Library's Built-In Encoding

The flutter_gemma library has a static method that handles all encoding correctly:

```dart
// ✅ CORRECT - Use library's method
final messageJson = LiteRtLmFfiClient.buildMessageJson(
  lastMessage.content,
  imagesBytes: imageBytes.isNotEmpty ? imageBytes : null,
);
```

**What `buildMessageJson()` does**:
1. Takes `List<Uint8List>` raw image bytes
2. Base64-encodes each image automatically
3. Wraps in proper JSON: `{ 'type': 'image', 'blob': 'base64string' }`
4. Creates correct content array: `[ { image1 }, { image2 }, { text } ]`
5. Returns valid JSON string ready for FFI

**Why this works**:
- ✅ Text-only: Pass `imagesBytes: null` → library creates text-only message
- ✅ Single image: Pass `List<Uint8List>` with 1 item → message with image + text
- ✅ Multi-image: Pass `List<Uint8List>` with multiple items → multimodal message
- ✅ All go through same path → no branching logic needed

### Implementation Details

**File**: `lib/services/gemma_service.dart` → `_FFIChatWrapper.generateChatResponseAsync()`

**Changes**:
```dart
// OLD (broken)
final multimodalMsg = Message.withImages(...);  // High-level API wrapper
final Map<String, dynamic> messageData = {'text': ...};  // Manual construction
if (imageBytes.isNotEmpty) {
  messageData['images'] = imageBytes;  // ❌ Wrong format
}
final messageJson = jsonEncode(messageData);

// NEW (fixed)
final messageJson = LiteRtLmFfiClient.buildMessageJson(
  lastMessage.content,
  imagesBytes: imageBytes.isNotEmpty ? imageBytes : null,  // ✅ Uses library method
);
```

**Also optimized**:
- Reduced token delay from 300ms → 30ms (faster UI without slowing model)
- Added debug logs: `📤 Sending message with X images`
- Clearer image count tracking

**Result**: 
- ✅ Text-only messages work again
- ✅ Single image + text works
- ✅ Multiple images + text works
- ✅ Model processes all message types correctly
- ✅ Real token-by-token streaming works for all cases

---

## Current Status ✅ (FULLY WORKING)

### Text & Image Support
- ✅ Text-only messages: Stream tokens successfully
- ✅ Single image + text: Multimodal processing works
- ✅ Multiple images + text: All images processed together
- ✅ Camera integration: Ready to capture and send images
- ✅ Gallery integration: Supports multi-image selection

### Model & Infrastructure
- ✅ Model: Gemma 4 E2B (LiteRT-LM format, `.litertlm`)
- ✅ Backend: Dart FFI (native C bindings)
- ✅ Model downloads without OOM (2.4GB handled successfully)
- ✅ FFI initialization with GPU backend (CPU fallback)
- ✅ Real token-by-token streaming via `sendMessageStreamRaw()`
- ✅ Smooth UI rendering with 30ms token delay
- ✅ No crashes during operation

### Ready For
- ✅ Camera app: Full image capture → AI processing
- ✅ Gallery app: Multi-image selection → batch analysis
- ✅ Real-time chat: Images + follow-up questions
- ✅ Production deployment

**Status**: 🎉 **COMPLETE & TESTED**
