import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_pdfview/flutter_pdfview.dart';
import 'package:path_provider/path_provider.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

class PdfViewerScreen extends StatefulWidget {
  final String url;
  final String title;

  const PdfViewerScreen({
    super.key,
    required this.url,
    required this.title,
  });

  @override
  State<PdfViewerScreen> createState() => _PdfViewerScreenState();
}

class _PdfViewerScreenState extends State<PdfViewerScreen> {
  bool _isLoading = true;
  String? _error;
  String? _localPath;
  int _totalPages = 0;
  int _currentPage = 0;

  @override
  void initState() {
    super.initState();
    
    if (kIsWeb) {
      // ✅ Web: Open directly in new tab
      _openInBrowser();
    } else {
      // Mobile/Desktop: Download and show native
      _loadPdf();
    }
  }

  Future<void> _openInBrowser() async {
    try {
      final uri = Uri.parse(widget.url);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
      // Go back after opening
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Could not open PDF';
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _loadPdf() async {
    try {
      final response = await http.get(Uri.parse(widget.url));
      
      if (response.statusCode == 404) {
        throw Exception('File not found. The document may have been removed.');
      }
      
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/document_${DateTime.now().millisecondsSinceEpoch}.pdf');
      await file.writeAsBytes(response.bodyBytes);

      if (mounted) {
        setState(() {
          _localPath = file.path;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Failed to load: $e';
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title, style: const TextStyle(fontSize: 16)),
        backgroundColor: const Color(0xFF1A237E),
        foregroundColor: Colors.white,
        actions: [
          if (_totalPages > 0)
            Center(
              child: Padding(
                padding: const EdgeInsets.only(right: 12),
                child: Text(
                  '${_currentPage + 1} / $_totalPages',
                  style: const TextStyle(color: Colors.white, fontSize: 13),
                ),
              ),
            ),
          if (!kIsWeb)
            IconButton(
              icon: const Icon(Icons.open_in_browser),
              tooltip: 'Open in browser',
              onPressed: () async {
                final uri = Uri.parse(widget.url);
                if (await canLaunchUrl(uri)) {
                  await launchUrl(uri, mode: LaunchMode.externalApplication);
                }
              },
            ),
        ],
      ),
      body: _isLoading
          ? const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(color: Color(0xFF1A237E)),
                  SizedBox(height: 16),
                  Text('Loading document...', style: TextStyle(color: Colors.grey)),
                ],
              ),
            )
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.error_outline, size: 64, color: Colors.red),
                        const SizedBox(height: 16),
                        Text(_error!, textAlign: TextAlign.center,
                            style: const TextStyle(color: Colors.red)),
                        const SizedBox(height: 24),
                        ElevatedButton.icon(
                          onPressed: () async {
                            final uri = Uri.parse(widget.url);
                            if (await canLaunchUrl(uri)) {
                              await launchUrl(uri, mode: LaunchMode.externalApplication);
                            }
                          },
                          icon: const Icon(Icons.open_in_browser),
                          label: const Text('Open in Browser'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF1A237E),
                            foregroundColor: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 8),
                        TextButton(
                          onPressed: () {
                            setState(() {
                              _isLoading = true;
                              _error = null;
                            });
                            _loadPdf();
                          },
                          child: const Text('Retry'),
                        ),
                      ],
                    ),
                  ),
                )
              : _buildNativeViewer(),
    );
  }

  Widget _buildNativeViewer() {
    if (_localPath == null) {
      return const Center(child: Text('PDF file not available'));
    }

    return PDFView(
      filePath: _localPath!,
      enableSwipe: true,
      swipeHorizontal: false,
      autoSpacing: true,
      pageFling: true,
      pageSnap: true,
      defaultPage: 0,
      fitPolicy: FitPolicy.WIDTH,
      onRender: (pages) {
        if (mounted) setState(() => _totalPages = pages ?? 0);
      },
      onPageChanged: (page, total) {
        if (mounted) {
          setState(() {
            _currentPage = page ?? 0;
            _totalPages = total ?? 0;
          });
        }
      },
      onError: (error) {
        if (mounted) {
          setState(() => _error = 'Error: $error');
        }
      },
    );
  }

  @override
  void dispose() {
    if (_localPath != null && !kIsWeb) {
      try {
        File(_localPath!).delete();
      } catch (_) {}
    }
    super.dispose();
  }
}