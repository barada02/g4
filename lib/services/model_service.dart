import 'dart:io';
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';
import '../constants/app_constants.dart';

class ModelService {
  final Dio _dio = Dio();
  
  Future<String> getModelPath() async {
    final dir = await getApplicationDocumentsDirectory();
    return '${dir.path}/${AppConstants.modelFileName}';
  }

  Future<bool> isModelSaved() async {
    final path = await getModelPath();
    final file = File(path);
    return await file.exists();
  }

  Future<void> downloadModel({
    required Function(double) onProgress,
    required Function() onCompleted,
    required Function(String) onError,
  }) async {
    try {
      final path = await getModelPath();
      await _dio.download(
        AppConstants.modelDownloadUrl,
        path,
        onReceiveProgress: (received, total) {
          if (total != -1) {
            onProgress(received / total);
          }
        },
      );
      onCompleted();
    } catch (e) {
      onError(e.toString());
    }
  }
}
