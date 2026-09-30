import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image_picker/image_picker.dart';

class OcrService {
  Future<List<String>> recognize(XFile photo) async {
    final recognizer = TextRecognizer(script: TextRecognitionScript.chinese);
    try {
      final result = await recognizer.processImage(
        InputImage.fromFilePath(photo.path),
      );
      return result.blocks
          .expand((block) => block.lines)
          .map((line) => line.text.trim())
          .where((line) => line.length >= 2 && line.length <= 80)
          .toSet()
          .take(12)
          .toList();
    } finally {
      await recognizer.close();
    }
  }
}
