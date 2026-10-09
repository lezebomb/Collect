import 'package:shou_cang_gui/harmony_media.dart';

class OcrService {
  Future<List<String>> recognize(XFile photo) async {
    final lines = await harmonyChannel.invokeListMethod<String>(
      'recognizeText',
      {'path': photo.path},
    );
    return (lines ?? <String>[])
        .map((line) => line.trim())
        .where((line) => line.length >= 2 && line.length <= 80)
        .toSet()
        .take(12)
        .toList();
  }
}
