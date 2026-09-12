import 'dart:convert';
import 'dart:typed_data';

import 'package:csv/csv.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

enum TextFormatOption { txt, csv, json, md, pdf }

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
  /// يحوّل محتوى نصي من صيغة المصدر الى الصيغة الهدف.
  /// يرجع بايتات جاهزة للحفظ مباشرة (لأن PDF بايتات ثنائية بينما الباقي UTF-8).
  static Future<Uint8List> convert({
    required String sourceExt,
    required TextFormatOption target,
    required Uint8List sourceBytes,
  }) async {
    final content = utf8.decode(sourceBytes, allowMalformed: true);
    final srcExt = sourceExt.toLowerCase();

    // أولاً: نحصل على تمثيل "بيانات جدولية" موحّد إذا كان المصدر CSV أو JSON (مصفوفة كائنات)
    List<List<dynamic>>? table;
    if (srcExt == 'csv') {
      table = const CsvToListConverter().convert(content, eol: '\n');
    } else if (srcExt == 'json') {
      table = _jsonToTable(content);
    }

    switch (target) {
      case TextFormatOption.txt:
      case TextFormatOption.md:
        if (table != null) {
          final asText = table.map((row) => row.join('\t')).join('\n');
          return Uint8List.fromList(utf8.encode(asText));
        }
        return Uint8List.fromList(utf8.encode(content));

      case TextFormatOption.csv:
        if (table != null) {
          final csvOut = const ListToCsvConverter().convert(table);
          return Uint8List.fromList(utf8.encode(csvOut));
        }
        // نص عادي بدون بنية جدولية: كل سطر يصبح صفًا بخلية واحدة
        final lines = content.split('\n');
        final csvOut =
            const ListToCsvConverter().convert(lines.map((l) => [l]).toList());
        return Uint8List.fromList(utf8.encode(csvOut));

      case TextFormatOption.json:
        if (table != null) {
          final jsonOut = _tableToJson(table);
          return Uint8List.fromList(utf8.encode(jsonOut));
        }
        // نص عادي: نغلفه كمصفوفة أسطر JSON صالحة
        final lines = content.split('\n');
        return Uint8List.fromList(utf8.encode(jsonEncode({'lines': lines})));

      case TextFormatOption.pdf:
        return _textToPdf(table != null
            ? table.map((row) => row.join('  |  ')).join('\n')
            : content);
    }
  }

  static List<List<dynamic>> _jsonToTable(String content) {
    final decoded = jsonDecode(content);
    if (decoded is List) {
      if (decoded.isNotEmpty && decoded.first is Map) {
        final keys = (decoded.first as Map).keys.toList();
        final rows = <List<dynamic>>[keys];
        for (final item in decoded) {
          rows.add(keys.map((k) => (item as Map)[k]).toList());
        }
        return rows;
      }
      return decoded.map<List<dynamic>>((e) => [e]).toList();
    }
    if (decoded is Map) {
      return decoded.entries.map((e) => [e.key, e.value]).toList();
    }
    throw TextConversionException('تنسيق JSON غير متوقع لتحويله لجدول');
  }

  static String _tableToJson(List<List<dynamic>> table) {
    if (table.isEmpty) return '[]';
    final header = table.first.map((e) => e.toString()).toList();
    final rows = table.skip(1);
    final list = rows.map((row) {
      final map = <String, dynamic>{};
      for (var i = 0; i < header.length && i < row.length; i++) {
        map[header[i]] = row[i];
      }
      return map;
    }).toList();
    return const JsonEncoder.withIndent('  ').convert(list);
  }

  static Future<Uint8List> _textToPdf(String content) async {
    final doc = pw.Document();
    const maxCharsPerPage = 3500;

    final chunks = <String>[];
    for (var i = 0; i < content.length; i += maxCharsPerPage) {
      chunks.add(
        content.substring(
          i,
          i + maxCharsPerPage > content.length
              ? content.length
              : i + maxCharsPerPage,
        ),
      );
    }
    if (chunks.isEmpty) chunks.add('');

    for (final chunk in chunks) {
      doc.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(32),
          build: (ctx) => pw.Text(
            chunk,
            style: const pw.TextStyle(fontSize: 11),
          ),
        ),
      );
    }
    return doc.save();
  }
}
