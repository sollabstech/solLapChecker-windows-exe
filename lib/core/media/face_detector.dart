import '../services/helper_service.dart';

/// Finds faces in still camera frames.
abstract class FaceDetector {
  /// Number of faces in the JPEG/PNG at [imagePath].
  Future<int> countFaces(String imagePath);
}

/// Windows' built-in face detector, run through SolHelper.exe.
class HelperFaceDetector implements FaceDetector {
  HelperFaceDetector([SolHelperService? helper]) : _helper = helper ?? SolHelperService();

  final SolHelperService _helper;

  @override
  Future<int> countFaces(String imagePath) => _helper.detectFaces(imagePath);
}
