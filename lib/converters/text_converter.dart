import 'dart:convert';
import 'dart:typed_data';

import 'package:csv/csv.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

enum TextFormatOption { txt, csv, json, md, html, xml, pdf }

extension TextFormatOptionX on TextFormatOption {
  String get extension => toString().split('.').last;
  String get label => extension.toUpperCase();
}

class TextConversionException implements Exception {
  final String message;
  TextConversionException(this.message);
  @override
  String toString() => message;
}

class TextConverter {
  static Future<Uint8List> convert({
    required String sourceExt,
    required TextFormatOption target,
    required Uint8List sourceBytes,
  }) async {
    final content = utf8.decode(sourceBytes, allowMalformed: true);
    final source = sourceExt.toLowerCase();
    List<List<dynamic>>? table;
    if (source == 'csv') {
      table = const CsvToListConverter().convert(content, eol: '\n');
    } else if (source == 'json') {
      table = _jsonToTable(content);
    }
    switch (target) {
      case TextFormatOption.txt:
      case TextFormatOption.md:
      case TextFormatOption.html:
      case TextFormatOption.xml:
        final value = table == null
            ? content
            : table.map((row) => row.join('\t')).join('\n');
        if (target == TextFormatOption.html) {
          return Uint8List.fromList(utf8.encode('<!doctype html><html><body><pre>${_escape(value)}</pre></body></html>'));
        }
        if (target == TextFormatOption.xml) {
          return Uint8List.fromList(utf8.encode('<?xml version="1.0" encoding="UTF-8"?>\n<document><content>${_escape(value)}</content></document>'));
        }
        return Uint8List.fromList(utf8.encode(value));
      case TextFormatOption.csv:
        final value = table == null
            ? const ListToCsvConverter().convert(
                content.split('\n').map((line) => [line]).toList(),
              )
            : const ListToCsvConverter().convert(table);
        return Uint8List.fromList(utf8.encode(value));
      case TextFormatOption.json:
        final value = table == null
            ? jsonEncode({'lines': content.split('\n')})
            : _tableToJson(table);
        return Uint8List.fromList(utf8.encode(value));
      case TextFormatOption.pdf:
        final value = table == null
            ? content
            : table.map((row) => row.join('  |  ')).join('\n');
        return _textToPdf(value);
    }
  }

  static List<List<dynamic>> _jsonToTable(String content) {
    final decoded = jsonDecode(content);
    if (decoded is List) {
      if (decoded.isNotEmpty && decoded.first is Map) {
        final keys = (decoded.first as Map).keys.toList();
        return [keys, ...decoded.map((item) => keys.map((key) => (item as Map)[key]).toList())];
      }
      return decoded.map<List<dynamic>>((item) => [item]).toList();
    }
    if (decoded is Map) {
      return decoded.entries.map((entry) => [entry.key, entry.value]).toList();
    }
    throw TextConversionException('تنسيق JSON غير متوقع');
  }

  static String _tableToJson(List<List<dynamic>> table) {
    if (table.isEmpty) return '[]';
    final headers = table.first.map((value) => value.toString()).toList();
    return const JsonEncoder.withIndent('  ').convert(table.skip(1).map((row) {
      final item = <String, dynamic>{};
      for (var i = 0; i < headers.length && i < row.length; i++) {
        item[headers[i]] = row[i];
      }
      return item;
    }).toList());
  }

  static Future<Uint8List> _textToPdf(String content) async {
    final document = pw.Document();
    for (var start = 0; start < content.length; start += 3500) {
      final end = (start + 3500).clamp(0, content.length);
      document.addPage(pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        build: (_) => pw.Text(content.substring(start, end)),
      ));
    }
    if (content.isEmpty) {
      document.addPage(pw.Page(build: (_) => pw.Text('')));
    }
    return document.save();
  }

  static String _escape(String value) => value
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;');
}
