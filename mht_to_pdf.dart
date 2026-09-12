// محوّل MHT/MHTML -> PDF
//
// ملف MHT هو رسالة MIME متعددة الأجزاء (نفس فكرة رسائل البريد):
// - يحتوي على جزء رئيسي من نوع text/html
// - وأجزاء فرعية (صور، CSS، خطوط...) مرمّزة base64 أو quoted-printable
// - كل جزء له Content-Location أو Content-ID يُستخدم داخل HTML للإشارة إليه
//
// الاستراتيجية:
// 1) استخراج boundary من الترويسة العليا (Content-Type: multipart/related; boundary=...)
// 2) تقسيم الملف الى أجزاء بواسطة boundary
// 3) لكل جزء: قراءة ترويسته (Content-Type / Content-Transfer-Encoding / Content-Location / Content-ID)
//    وفك ترميز محتواه (quoted-printable أو base64 أو نص خام)
// 4) تحديد الجزء الرئيسي (text/html) وإعادة كتابة أي إشارة داخله لموارد أخرى
//    (عن طريق Content-Location أو cid:) كـ data:URI مضمّن مباشرة
// 5) تمرير HTML المستقل الناتج الى Printing.convertHtml التي تستخدم WebView حقيقي
//    لعرضه وتحويله الى PDF بنفس التنسيق تقريبًا (خطوط، صور، تخطيط)

import 'dart:convert';
import 'dart:typed_data';

import 'package:printing/printing.dart';

class MhtPart {
  final Map<String, String> headers;
  final Uint8List bytes;
  MhtPart(this.headers, this.bytes);

  String? get contentType => headers['content-type'];
  String? get transferEncoding => headers['content-transfer-encoding'];
  String? get contentLocation => headers['content-location'];
  String? get contentId => headers['content-id'];

  String get mimeOnly {
    final ct = contentType ?? 'application/octet-stream';
    final idx = ct.indexOf(';');
    return (idx == -1 ? ct : ct.substring(0, idx)).trim();
  }
}

class MhtParseException implements Exception {
  final String message;
  MhtParseException(this.message);
  @override
  String toString() => 'MhtParseException: $message';
}

class MhtToPdfConverter {
  /// يحوّل بايتات ملف MHT الى بايتات PDF جاهزة للحفظ.
  static Future<Uint8List> convert(Uint8List fileBytes) async {
    final html = await _rebuildStandaloneHtml(fileBytes);
    final pdfBytes = await Printing.convertHtml(
      html: html,
      // يمكن ترك الحجم تلقائي بحسب المحتوى؛ نستخدم A4 كافتراضي معقول
    );
    return pdfBytes;
  }

  /// يعيد بناء HTML مستقل بذاته (كل الصور/الموارد مضمّنة كـ data URI)
  static Future<String> _rebuildStandaloneHtml(Uint8List fileBytes) async {
    // نحوّل البايتات الى نص latin1 لقراءة الترويسات بأمان (لأنها ASCII غالبًا)
    final raw = latin1.decode(fileBytes, allowInvalid: true);

    // إيجاد سطر Content-Type في الترويسة العليا لاستخراج boundary
    final headerEnd = raw.indexOf('\r\n\r\n');
    if (headerEnd == -1) {
      throw MhtParseException('لم يتم العثور على ترويسة صالحة في الملف');
    }
    final topHeadersRaw = raw.substring(0, headerEnd);
    final topHeaders = _parseHeaderBlock(topHeadersRaw);

    final topContentType = topHeaders['content-type'] ?? '';
    final boundaryMatch = RegExp(
      r'boundary\s*=\s*"?([^";]+)"?',
      caseSensitive: false,
    ).firstMatch(topContentType);

    if (boundaryMatch == null) {
      throw MhtParseException(
        'الملف ليس بصيغة MHT متعددة الأجزاء صحيحة (لا يوجد boundary)',
      );
    }
    final boundary = boundaryMatch.group(1)!.trim();

    // تقسيم الملف كاملاً (بالبايتات) عبر الـ boundary
    final parts = _splitByBoundary(fileBytes, boundary);

    if (parts.isEmpty) {
      throw MhtParseException('تعذر تقسيم أجزاء ملف MHT');
    }

    // تحديد الجزء الرئيسي: أول جزء نوعه text/html
    MhtPart? mainPart;
    final resourceByLocation = <String, MhtPart>{};
    final resourceById = <String, MhtPart>{};

    for (final part in parts) {
      final mime = part.mimeOnly.toLowerCase();
      if (mainPart == null && mime == 'text/html') {
        mainPart = part;
      }
      final loc = part.contentLocation;
      if (loc != null && loc.isNotEmpty) {
        resourceByLocation[loc] = part;
      }
      final cid = part.contentId?.replaceAll('<', '').replaceAll('>', '');
      if (cid != null && cid.isNotEmpty) {
        resourceById[cid] = part;
      }
    }

    mainPart ??= parts.first;

    // فك ترميز HTML الرئيسي بترميز الحروف المناسب (utf-8 غالبًا)
    String html = _decodeTextPart(mainPart);

    // استبدال أي إشارة الى موارد خارجية بـ data URI
    // الحالات الشائعة: src="cid:xxx" ، src="https://original/location/img.png"
    html = _inlineResources(html, resourceByLocation, resourceById);

    return html;
  }

  static Map<String, String> _parseHeaderBlock(String block) {
    final headers = <String, String>{};
    // دعم استمرار السطر (unfolding): سطر يبدأ بمسافة يعني تكملة للسطر السابق
    final lines = block.split('\r\n');
    String? currentKey;
    for (final line in lines) {
      if (line.isEmpty) continue;
      if ((line.startsWith(' ') || line.startsWith('\t')) &&
          currentKey != null) {
        headers[currentKey] = '${headers[currentKey]} ${line.trim()}';
        continue;
      }
      final idx = line.indexOf(':');
      if (idx == -1) continue;
      final key = line.substring(0, idx).trim().toLowerCase();
      final value = line.substring(idx + 1).trim();
      headers[key] = value;
      currentKey = key;
    }
    return headers;
  }

  /// يقسم الملف بالكامل (بايتات) بناءً على boundary MIME،
  /// ويحلل كل جزء الى ترويسة + محتوى بعد فك الترميز المناسب.
  static List<MhtPart> _splitByBoundary(Uint8List fileBytes, String boundary) {
    final delimiter = latin1.encode('--$boundary');
    final all = fileBytes;
    final segments = <Uint8List>[];

    int start = _indexOfBytes(all, delimiter, 0);
    if (start == -1) return segments.map((e) => MhtPart({}, e)).toList();

    int cursor = start + delimiter.length;
    while (true) {
      final next = _indexOfBytes(all, delimiter, cursor);
      if (next == -1) break;
      // المحتوى بين نهاية هذا الـ boundary وبداية التالي
      final segment = all.sublist(cursor, next);
      segments.add(segment);
      cursor = next + delimiter.length;
      // تحقق من نهاية الرسالة (بعد الـ boundary مباشرة "--")
      if (cursor + 1 < all.length && all[cursor] == 45 && all[cursor + 1] == 45) {
        break;
      }
    }

    final parts = <MhtPart>[];
    for (final seg in segments) {
      final parsed = _parseOnePart(seg);
      if (parsed != null) parts.add(parsed);
    }
    return parts;
  }

  static MhtPart? _parseOnePart(Uint8List segment) {
    // إزالة \r\n في البداية إن وجد (فاصل بعد boundary)
    int offset = 0;
    if (segment.length >= 2 && segment[0] == 13 && segment[1] == 10) {
      offset = 2;
    }
    // إيجاد فاصل الترويسة/المحتوى: \r\n\r\n
    final headerSepBytes = latin1.encode('\r\n\r\n');
    final sepIndex = _indexOfBytes(segment, headerSepBytes, offset);
    if (sepIndex == -1) return null;

    final headerBytes = segment.sublist(offset, sepIndex);
    final headerText = latin1.decode(headerBytes, allowInvalid: true);
    final headers = _parseHeaderBlock(headerText);

    var bodyBytes = segment.sublist(sepIndex + headerSepBytes.length);
    // إزالة \r\n زائدة في نهاية الجزء إن وجدت
    while (bodyBytes.isNotEmpty &&
        (bodyBytes.last == 10 || bodyBytes.last == 13)) {
      bodyBytes = bodyBytes.sublist(0, bodyBytes.length - 1);
    }

    final encoding = (headers['content-transfer-encoding'] ?? '')
        .toLowerCase()
        .trim();

    Uint8List decoded;
    switch (encoding) {
      case 'base64':
        final cleaned = latin1
            .decode(bodyBytes)
            .replaceAll(RegExp(r'\s+'), '');
        try {
          decoded = base64.decode(cleaned);
        } catch (_) {
          decoded = bodyBytes;
        }
        break;
      case 'quoted-printable':
        decoded = _decodeQuotedPrintable(bodyBytes);
        break;
      default:
        // 7bit / 8bit / binary / غير محدد
        decoded = bodyBytes;
    }

    return MhtPart(headers, decoded);
  }

  static Uint8List _decodeQuotedPrintable(Uint8List input) {
    final text = latin1.decode(input, allowInvalid: true);
    // إزالة الأسطر اللينة (soft line breaks): "=\r\n" أو "=\n"
    final softBreakRemoved = text
        .replaceAll('=\r\n', '')
        .replaceAll('=\n', '');

    final out = <int>[];
    int i = 0;
    while (i < softBreakRemoved.length) {
      final ch = softBreakRemoved[i];
      if (ch == '=' && i + 2 < softBreakRemoved.length) {
        final hex = softBreakRemoved.substring(i + 1, i + 3);
        final byte = int.tryParse(hex, radix: 16);
        if (byte != null) {
          out.add(byte);
          i += 3;
          continue;
        }
      }
      out.add(ch.codeUnitAt(0));
      i += 1;
    }
    return Uint8List.fromList(out);
  }

  static String _decodeTextPart(MhtPart part) {
    final ct = (part.contentType ?? '').toLowerCase();
    final charsetMatch = RegExp(r'charset\s*=\s*"?([\w-]+)"?').firstMatch(ct);
    final charset = charsetMatch?.group(1)?.toLowerCase() ?? 'utf-8';

    try {
      if (charset.contains('utf-8')) {
        return utf8.decode(part.bytes, allowMalformed: true);
      } else if (charset.contains('1256') || charset.contains('windows')) {
        // ترميزات عربية شائعة (Windows-1256) غير مدعومة افتراضيًا في dart:convert
        // كحل بديل معقول نستخدم latin1 ثم utf8 كخطة أخيرة
        return latin1.decode(part.bytes, allowInvalid: true);
      } else {
        return utf8.decode(part.bytes, allowMalformed: true);
      }
    } catch (_) {
      return latin1.decode(part.bytes, allowInvalid: true);
    }
  }

  static String _inlineResources(
    String html,
    Map<String, MhtPart> byLocation,
    Map<String, MhtPart> byId,
  ) {
    var result = html;

    // 1) استبدال مراجع cid: مثل src="cid:image001.png@..."
    final cidPattern = RegExp('cid:([^"\'\\)\\s]+)', caseSensitive: false);
    result = result.replaceAllMapped(cidPattern, (m) {
      final id = m.group(1)!;
      final part = byId[id];
      if (part == null) return m.group(0)!;
      final dataUri =
          'data:${part.mimeOnly};base64,${base64.encode(part.bytes)}';
      return dataUri;
    });

    // 2) استبدال المراجع المباشرة بروابط Content-Location الأصلية
    // نرتب المفاتيح من الأطول للأقصر لتفادي تطابقات جزئية خاطئة
    final locations = byLocation.keys.toList()
      ..sort((a, b) => b.length.compareTo(a.length));
    for (final loc in locations) {
      if (loc.isEmpty) continue;
      final part = byLocation[loc]!;
      // تجاهل استبدال الرابط الرئيسي لنفسه لو تطابق مع HTML نفسه
      if (part.mimeOnly == 'text/html') continue;
      final dataUri =
          'data:${part.mimeOnly};base64,${base64.encode(part.bytes)}';
      result = result.replaceAll(loc, dataUri);
    }

    return result;
  }

  static int _indexOfBytes(Uint8List haystack, List<int> needle, int start) {
    if (needle.isEmpty) return -1;
    final limit = haystack.length - needle.length;
    for (int i = start; i <= limit; i++) {
      bool match = true;
      for (int j = 0; j < needle.length; j++) {
        if (haystack[i + j] != needle[j]) {
          match = false;
          break;
        }
      }
      if (match) return i;
    }
    return -1;
  }
}
