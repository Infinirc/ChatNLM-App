class ImageGenerationResponse {
  final bool needsImage;
  final String? message;
  final String? promptUsed;
  final List<ImageData>? images;

  ImageGenerationResponse({
    required this.needsImage,
    this.message,
    this.promptUsed,
    this.images,
  });

  factory ImageGenerationResponse.fromJson(Map<String, dynamic> json) {
    List<ImageData>? images;
    if (json['images'] != null) {
      images = (json['images'] as List).map((img) => ImageData.fromJson(img)).toList();
    }

    return ImageGenerationResponse(
      needsImage: json['needs_image'] ?? false,
      message: json['message'],
      promptUsed: json['prompt_used'],
      images: images,
    );
  }
}

class ImageData {
  final String path;
  final String filename;

  ImageData({
    required this.path,
    required this.filename,
  });

  factory ImageData.fromJson(Map<String, dynamic> json) {
    return ImageData(
      path: json['path'],
      filename: json['filename'],
    );
  }
}