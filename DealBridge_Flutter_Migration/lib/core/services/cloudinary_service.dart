import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';

import '../constants/app_constants.dart';

/// Result of a successful Cloudinary upload.
class CloudinaryUpload {
  const CloudinaryUpload({
    required this.publicId,
    required this.secureUrl,
    required this.resourceType,
    this.format = '',
    this.width = 0,
    this.height = 0,
  });

  final String publicId;
  final String secureUrl;
  final String resourceType;
  final String format;
  final int width;
  final int height;

  bool get isImage => resourceType == 'image';
}

/// Raised when an upload cannot be completed.
class CloudinaryException implements Exception {
  const CloudinaryException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Uploads media to Cloudinary using the unsigned `dealbridge_media` preset.
///
/// The client never holds a Cloudinary API secret: deletions go through the
/// `deleteCloudinaryMedia` callable instead.
class CloudinaryService {
  const CloudinaryService({http.Client? client})
      : _client = client ?? http.Client();

  final http.Client _client;

  /// Uploads raw image bytes.
  Future<CloudinaryUpload> uploadImageBytes(
    Uint8List bytes, {
    required String folder,
    String? filename,
  }) {
    return _upload(
      bytes,
      filename: filename ?? 'upload.jpg',
      folder: folder,
      contentType: 'image/jpeg',
    );
  }

  /// Uploads an image file picked from the device.
  Future<CloudinaryUpload> uploadImageFile(
    File file, {
    required String folder,
  }) {
    return _upload(
      file.readAsBytesSync(),
      filename: file.path.split('/').last,
      folder: folder,
      contentType: _contentTypeFor(file.path),
    );
  }

  /// Uploads a video file picked from the device.
  Future<CloudinaryUpload> uploadVideoFile(
    File file, {
    required String folder,
  }) {
    return _upload(
      file.readAsBytesSync(),
      filename: file.path.split('/').last,
      folder: folder,
      contentType: 'video/mp4',
    );
  }

  Future<CloudinaryUpload> _upload(
    Uint8List bytes, {
    required String filename,
    required String folder,
    required String contentType,
  }) async {
    final request = http.MultipartRequest(
      'POST',
      Uri.parse(CloudinaryConfig.uploadUrl('auto')),
    )
      ..fields['upload_preset'] = CloudinaryConfig.uploadPreset
      ..fields['folder'] = folder
      ..files.add(
        http.MultipartFile.fromBytes(
          'file',
          bytes,
          filename: filename,
          contentType: _mediaType(contentType),
        ),
      );

    http.Response response;
    try {
      response = await _client.send(request).then(http.Response.fromStream);
    } on SocketException {
      throw const CloudinaryException(
        'Network error while uploading. Check your connection.',
      );
    }

    Map<String, dynamic> body;
    try {
      body = jsonDecode(response.body) as Map<String, dynamic>;
    } on FormatException {
      throw CloudinaryException(
        'Upload failed (HTTP ${response.statusCode}).',
      );
    }

    if (response.statusCode != 200 || body['error'] != null) {
      final error = body['error'];
      final message = error is Map
          ? (error['message'] ?? 'Upload failed').toString()
          : 'Upload failed (HTTP ${response.statusCode}).';
      throw CloudinaryException(message);
    }

    return CloudinaryUpload(
      publicId: (body['public_id'] ?? '').toString(),
      secureUrl: (body['secure_url'] ?? '').toString(),
      resourceType: (body['resource_type'] ?? 'image').toString(),
      format: (body['format'] ?? '').toString(),
      width: (body['width'] as num?)?.toInt() ?? 0,
      height: (body['height'] as num?)?.toInt() ?? 0,
    );
  }

  static String _contentTypeFor(String path) {
    final lower = path.toLowerCase();
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.webp')) return 'image/webp';
    if (lower.endsWith('.heic')) return 'image/heic';
    return 'image/jpeg';
  }

  static MediaType _mediaType(String contentType) {
    final parts = contentType.split('/');
    if (parts.length != 2) return MediaType('application', 'octet-stream');
    return MediaType(parts[0], parts[1]);
  }
}
