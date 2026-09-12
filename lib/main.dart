import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:mime/mime.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'converters/image_converter.dart';
import 'converters/mht_to_pdf.dart';
import 'converters/text_converter.dart';

void main() => runApp(const FormatConverterApp());

enum FileKind { image, video, audio, text, document, archive, unknown }

class FormatConverterApp extends StatefulWidget {
  const FormatConverterApp({super.key});
  @override
  State<FormatConverterApp> createState() => _FormatConverterAppState();
}

class _FormatConverterAppState extends State<FormatConverterApp> {
  ThemeMode themeMode = ThemeMode.light;
  bool showMetadata = true;

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'المحوّل الشامل',
        debugShowCheckedModeBanner: false,
        themeMode: themeMode,
        theme: ThemeData(useMaterial3: true, colorSchemeSeed: const Color(0xff176b5b)),
        darkTheme: ThemeData.dark(useMaterial3: true),
        home: ConverterHome(
          showMetadata: showMetadata,
          onSettings: () async {
            final result = await Navigator.push<SettingsResult>(context, MaterialPageRoute(
              builder: (_) => SettingsPage(darkMode: themeMode == ThemeMode.dark, showMetadata: showMetadata),
            ));
            if (result != null) setState(() {
              themeMode = result.darkMode ? ThemeMode.dark : ThemeMode.light;
              showMetadata = result.showMetadata;
            });
          },
        ),
      );
}

class SettingsResult {
  final bool darkMode;
  final bool showMetadata;
  const SettingsResult(this.darkMode, this.showMetadata);
}

class SettingsPage extends StatefulWidget {
  final bool darkMode;
  final bool showMetadata;
  const SettingsPage({super.key, required this.darkMode, required this.showMetadata});
  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late bool darkMode = widget.darkMode;
  late bool showMetadata = widget.showMetadata;

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('الإعدادات')),
        body: ListView(padding: const EdgeInsets.all(16), children: [
          SwitchListTile(title: const Text('الوضع الداكن'), value: darkMode, onChanged: (value) => setState(() => darkMode = value)),
          SwitchListTile(title: const Text('عرض بيانات الملف'), value: showMetadata, onChanged: (value) => setState(() => showMetadata = value)),
          const Divider(),
          const ListTile(title: Text('الصيغ المدعومة'), subtitle: Text('الصور: PNG JPG BMP GIF\nالنصوص: TXT CSV JSON MD PDF\nMHT: PDF\nيتم التعرف على الفيديو والصوت والمستندات والأرشيفات تلقائيًا.')),
          const ListTile(title: Text('المصمم'), subtitle: Text('نواف فراج العنزي')),
          FilledButton.icon(onPressed: () => Navigator.pop(context, SettingsResult(darkMode, showMetadata)), icon: const Icon(Icons.save_outlined), label: const Text('حفظ')),
        ]),
      );
}

class ConverterHome extends StatefulWidget {
  final bool showMetadata;
  final VoidCallback onSettings;
  const ConverterHome({super.key, required this.showMetadata, required this.onSettings});
  @override
  State<ConverterHome> createState() => _ConverterHomeState();
}

class _ConverterHomeState extends State<ConverterHome> {
  PlatformFile? file;
  Uint8List? bytes;
  String extension = '';
  FileKind kind = FileKind.unknown;
  String? target;
  String? message;
  String? savedPath;
  bool busy = false;

  static const imageFormats = ['png', 'jpg', 'bmp', 'gif'];
  static const textFormats = ['txt', 'csv', 'json', 'md', 'pdf'];

  Future<void> chooseFile() async {
    final result = await FilePicker.platform.pickFiles(withData: true);
    if (result == null || result.files.isEmpty) return;
    final selected = result.files.single;
    final ext = (selected.extension ?? p.extension(selected.name).replaceFirst('.', '')).toLowerCase();
    setState(() {
      file = selected;
      bytes = selected.bytes;
      extension = ext;
      kind = detectKind(ext, lookupMimeType(selected.name));
      target = null;
      message = null;
      savedPath = null;
    });
  }

  FileKind detectKind(String ext, String? mime) {
    if (imageFormats.contains(ext) || ['webp', 'heic', 'svg', 'tga'].contains(ext) || mime?.startsWith('image/') == true) return FileKind.image;
    if (['mp4', 'mkv', 'avi', 'mov', 'webm', '3gp', 'flv'].contains(ext) || mime?.startsWith('video/') == true) return FileKind.video;
    if (['mp3', 'wav', 'aac', 'flac', 'ogg', 'm4a'].contains(ext) || mime?.startsWith('audio/') == true) return FileKind.audio;
    if (['txt', 'csv', 'json', 'md', 'log', 'xml', 'html', 'htm', 'mht', 'mhtml'].contains(ext) || mime?.startsWith('text/') == true) return FileKind.text;
    if (['pdf', 'doc', 'docx', 'xls', 'xlsx', 'ppt', 'pptx', 'rtf'].contains(ext)) return FileKind.document;
    if (['zip', 'rar', '7z', 'tar', 'gz'].contains(ext)) return FileKind.archive;
    return FileKind.unknown;
  }

  List<String> availableTargets() {
    if (kind == FileKind.image) return imageFormats.where((item) => item != extension && !(item == 'jpg' && extension == 'jpeg')).toList();
    if (kind == FileKind.text && extension != 'mht' && extension != 'mhtml') return textFormats.where((item) => item != extension).toList();
    if (kind == FileKind.text && (extension == 'mht' || extension == 'mhtml')) return ['pdf'];
    return [];
  }

  Future<void> convert() async {
    if (file == null || bytes == null || target == null) return;
    setState(() { busy = true; message = 'جارٍ التحويل...'; savedPath = null; });
    try {
      Uint8List result;
      if (kind == FileKind.image) {
        result = ImageConverter.convert(bytes!, ImageFormatOption.values.firstWhere((value) => value.extension == target));
      } else if (extension == 'mht' || extension == 'mhtml') {
        result = await MhtToPdfConverter.convert(bytes!);
      } else {
        result = await TextConverter.convert(sourceExt: extension, target: TextFormatOption.values.firstWhere((value) => value.extension == target), sourceBytes: bytes!);
      }
      final base = Platform.isAndroid ? await getExternalStorageDirectory() : await getApplicationDocumentsDirectory();
      final folder = Directory(p.join(base?.path ?? '.', 'المحوّل الشامل'));
      await folder.create(recursive: true);
      var output = File(p.join(folder.path, '${p.basenameWithoutExtension(file!.name)}.$target'));
      var count = 1;
      while (await output.exists()) {
        output = File(p.join(folder.path, '${p.basenameWithoutExtension(file!.name)}-${count++}.$target'));
      }
      await output.writeAsBytes(result, flush: true);
      setState(() { savedPath = output.path; message = 'تم التحويل بنجاح'; });
    } catch (error) {
      setState(() => message = 'تعذر التحويل: $error');
    } finally {
      setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Directionality(textDirection: TextDirection.rtl, child: Scaffold(
        appBar: AppBar(title: const Text('المحوّل الشامل'), actions: [IconButton(onPressed: widget.onSettings, icon: const Icon(Icons.settings_outlined))]),
        body: ListView(padding: const EdgeInsets.all(16), children: [
          const Text('المحوّل الشامل', style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold)),
          const Text('يتعرف على نوع الملف ويعرض الصيغ المناسبة للتحويل'),
          const SizedBox(height: 18),
          FilledButton.icon(onPressed: busy ? null : chooseFile, icon: const Icon(Icons.attach_file), label: const Text('إرفاق ملف')),
          if (file != null) ...[const SizedBox(height: 16), _fileInfo(), const SizedBox(height: 12), if (availableTargets().isNotEmpty) _conversionBox() else _unsupportedBox()],
          if (busy) const Padding(padding: EdgeInsets.all(20), child: Center(child: CircularProgressIndicator())),
          if (message != null) _resultBox(),
          const SizedBox(height: 22),
          const Center(child: Text('تصميم وتطوير: نواف فراج العنزي', style: TextStyle(fontSize: 12))),
        ]),
      ));

  Widget _fileInfo() => Card(child: ListTile(leading: Icon(kind == FileKind.image ? Icons.image_outlined : Icons.insert_drive_file_outlined), title: Text(file!.name), subtitle: widget.showMetadata ? Text('النوع: ${kind.name}\nالصيغة: ${extension.toUpperCase()}\nالحجم: ${(file!.size / 1024 / 1024).toStringAsFixed(2)} MB\nMIME: ${lookupMimeType(file!.name) ?? 'غير معروف'}') : null));

  Widget _conversionBox() => Card(child: Padding(padding: const EdgeInsets.all(14), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [const Text('الصيغ المتاحة', style: TextStyle(fontWeight: FontWeight.bold)), const SizedBox(height: 8), DropdownButtonFormField<String>(value: target, decoration: const InputDecoration(border: OutlineInputBorder(), labelText: 'الصيغة الجديدة'), items: availableTargets().map((item) => DropdownMenuItem(value: item, child: Text(item.toUpperCase()))).toList(), onChanged: (value) => setState(() => target = value)), const SizedBox(height: 10), FilledButton.icon(onPressed: busy || target == null ? null : convert, icon: const Icon(Icons.transform), label: const Text('تحويل وحفظ'))])));

  Widget _unsupportedBox() => const Card(child: Padding(padding: EdgeInsets.all(14), child: Text('تم التعرف على نوع الملف، لكن تحويل هذا النوع غير متاح حاليًا.')));

  Widget _resultBox() => Card(color: Theme.of(context).colorScheme.primaryContainer, child: Padding(padding: const EdgeInsets.all(14), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(message!, style: const TextStyle(fontWeight: FontWeight.bold)), if (savedPath != null) ...[const SizedBox(height: 8), Text('مكان الحفظ:\n$savedPath'), OutlinedButton.icon(onPressed: () => OpenFilex.open(savedPath!), icon: const Icon(Icons.open_in_new), label: const Text('فتح الملف الناتج'))]]));
}
