import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'dart:developer' as developer;

class TextbookDiagramWidget extends StatelessWidget {
  final String rawSvgString;

  const TextbookDiagramWidget({super.key, required this.rawSvgString});

  @override
  Widget build(BuildContext context) {
    // Sanitize the SVG string
    final cleaned = _sanitizeSvg(rawSvgString);

    if (cleaned.isEmpty) {
      return _buildErrorState('Diagram could not be rendered');
    }

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 12),
      padding: const EdgeInsets.all(16.0),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade300),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header badge
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFF1A237E).withOpacity(0.08),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.image_outlined, size: 12, color: Color(0xFF1A237E)),
                    SizedBox(width: 4),
                    Text(
                      'Diagram',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF1A237E),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // The SVG
          ConstrainedBox(
            constraints: const BoxConstraints(
              maxHeight: 400, // Prevent gigantic SVGs
              minHeight: 150,
            ),
            child: SvgPicture.string(
              cleaned,
              placeholderBuilder: (context) => const SizedBox(
                height: 150,
                child: Center(
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
              // If render fails, show error
              errorBuilder: (context, error, stackTrace) {
                developer.log('SVG render error: $error');
                return _buildErrorState('Diagram could not be rendered');
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorState(String message) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.orange.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.orange.shade200),
      ),
      child: Row(
        children: [
          const Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(fontSize: 13, color: Colors.orange),
            ),
          ),
        ],
      ),
    );
  }

  /// Clean up common issues from AI-generated SVGs
  String _sanitizeSvg(String input) {
    var svg = input.trim();

    // Remove any markdown wrappers if present
    svg = svg.replaceAll(RegExp(r'^```(?:xml|svg|html)?\s*', multiLine: true), '');
    svg = svg.replaceAll(RegExp(r'```\s*$', multiLine: true), '');
    svg = svg.trim();

    // Must start with <svg
    if (!svg.startsWith('<svg')) {
      final idx = svg.indexOf('<svg');
      if (idx == -1) return '';
      svg = svg.substring(idx);
    }

    // Must end with </svg>
    final endIdx = svg.lastIndexOf('</svg>');
    if (endIdx == -1) return '';
    svg = svg.substring(0, endIdx + 6);

    // Ensure xmlns attribute exists
    if (!svg.contains('xmlns=')) {
      svg = svg.replaceFirst(
        '<svg',
        '<svg xmlns="http://www.w3.org/2000/svg"',
      );
    }

    // Ensure viewBox exists
    if (!svg.contains('viewBox')) {
      svg = svg.replaceFirst(
        '<svg',
        '<svg viewBox="0 0 400 400"',
      );
    }

    return svg;
  }
}