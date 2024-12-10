// lib/services/stub_html.dart
// 這個文件用於非 Web 平台的存根實現

class Window {
  Navigator get navigator => Navigator();
}

class Navigator {
  MediaDevices? get mediaDevices => null;
}

class MediaDevices {
  Future<dynamic> getUserMedia(Map<String, dynamic> constraints) async {
    throw UnsupportedError('getUserMedia is only supported on Web platform');
  }
}

class Blob {
  Blob(List<dynamic> parts, [String? type]);
}

class FileReader {
  dynamic get result => null;
  
  void readAsArrayBuffer(dynamic blob) {}
  
  Stream<dynamic> get onLoadEnd => Stream.empty();
}

class BlobEvent {
  final dynamic data;
  BlobEvent(this.data);
}

final window = Window();