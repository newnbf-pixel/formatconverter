import 'dart:convert';
import 'dart:typed_data';

import 'package:printing/printing.dart';

class MhtToPdfConverter {
  static Future<Uint8List> convert(Uint8List fileBytes) async {
    final source = utf8.decode(fileBytes, allowMalformed: true);
    final html = source.contains('<html') ? source : '<pre>${_escape(source)}</pre>';
    return Printing.convertHtml(html: html);
  }

  static String _escape(String value) => value
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;');
}
