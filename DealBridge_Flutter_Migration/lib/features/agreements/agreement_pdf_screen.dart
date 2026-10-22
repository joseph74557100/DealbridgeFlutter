import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_pdfview/flutter_pdfview.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

import '../../core/theme/app_colors.dart';
import '../../core/widgets/state_message.dart';

/// Renders an agreement PDF.
///
/// The native viewer needs either a local file or the raw bytes, so remote
/// documents are downloaded first.
class AgreementPdfScreen extends StatefulWidget {
  const AgreementPdfScreen({super.key, required this.url, this.title = ''});

  final String url;
  final String title;

  @override
  State<AgreementPdfScreen> createState() => _AgreementPdfScreenState();
}

class _AgreementPdfScreenState extends State<AgreementPdfScreen> {
  Uint8List? _bytes;
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _download();
  }

  Future<void> _download() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final response = await http.get(Uri.parse(widget.url));
      if (response.statusCode != 200) {
        throw Exception('HTTP ${response.statusCode}');
      }
      if (!mounted) return;
      setState(() {
        _bytes = response.bodyBytes;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Could not download the agreement document.';
      });
    }
  }

  Future<void> _openExternally() async {
    final uri = Uri.tryParse(widget.url);
    if (uri == null) return;
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not open that link.'),
          backgroundColor: AppColors.danger,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title.isEmpty ? 'Agreement' : widget.title),
        actions: [
          IconButton(
            tooltip: 'Open in browser',
            onPressed: _openExternally,
            icon: const Icon(Icons.open_in_new),
          ),
          IconButton(
            tooltip: 'Reload',
            onPressed: _download,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: Builder(
        builder: (context) {
          if (_loading) {
            return const Center(child: CircularProgressIndicator());
          }
          final bytes = _bytes;
          if (_error != null || bytes == null) {
            return StateMessage.error(
              title: _error ?? 'No document available',
              subtitle: 'The agreement file could not be loaded.',
              action: FilledButton(
                onPressed: _download,
                child: const Text('Try again'),
              ),
            );
          }
          return PDFView(
            pdfData: bytes,
            enableSwipe: true,
            swipeHorizontal: false,
            autoSpacing: true,
            pageFling: true,
            nightMode: true,
            backgroundColor: AppColors.navy,
            onError: (_) {
              if (mounted) {
                setState(() => _error = 'The document could not be rendered.');
              }
            },
          );
        },
      ),
    );
  }
}
