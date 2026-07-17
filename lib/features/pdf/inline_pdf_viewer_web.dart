import 'dart:ui_web' as ui;
import 'package:universal_html/html.dart' as html;

void registerPdfViewer(String viewId, String pdfUrl) {
  ui.platformViewRegistry.registerViewFactory(viewId, (int viewId) {
    final iframe = html.IFrameElement()
      ..src = '$pdfUrl#toolbar=0&navpanes=0&scrollbar=1'
      ..style.width = '100%'
      ..style.height = '100%'
      ..style.border = 'none'
      ..style.borderRadius = '8px';
    return iframe;
  });
}