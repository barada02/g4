import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import '../constants/app_constants.dart';

class ModelService {
  final Dio _dio = Dio();
  
  Future<String> getModelPath() async {
    final dir = await getApplicationDocumentsDirectory();
    return '${dir.path}/${AppConstants.modelFileName}';
  }

  Future<bool> isModelSaved() async {
    try {
      final path = await getModelPath();
      final file = File(path);
      final exists = await file.exists();
      
      if (exists) {
        // Verify file is not corrupted (has reasonable size)
        final fileSize = await file.length();
        debugPrint('Model file exists at: $path, size: ${(fileSize / (1024 * 1024)).toStringAsFixed(2)} MB');
        return fileSize > 0;
      }
      return false;
    } catch (e) {
      debugPrint('Error checking model file: $e');
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
      debugPrint('Starting download to: $path');
      
      await _dio.download(
        AppConstants.modelDownloadUrl,
        path,
        onReceiveProgress: (received, total) {
          if (total != -1) {
            onProgress(received / total);
          }
        },
      );
      
      // Verify file was actually created and has content
      final file = File(path);
      final exists = await file.exists();
      final fileSize = exists ? await file.length() : 0;
      
      debugPrint('Download complete. File exists: $exists, Size: $fileSize bytes');
      
      if (!exists || fileSize == 0) {
        throw Exception('Model file not created or is empty after download');
      }
      
      onCompleted();
    } catch (e) {
      debugPrint('Download error: $e');
      onError(e.toString());
    }
  }
}
