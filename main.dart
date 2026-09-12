import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'converters/image_converter.dart';
import 'converters/mht_to_pdf.dart';
import 'converters/text_converter.dart';

void main() => runApp(const FormatConverterApp());

class FormatConverterApp extends StatelessWidget {
  const FormatConverterApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'محول الصيغ',
      debugShowCheckedModeBanner: false,
      locale: const Locale('ar'),
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: const Color(0xFF2F6F4E),
        fontFamily: 'Roboto',
      ),
      builder: (context, child) => Directionality(
        textDirection: TextDirection.rtl,
        child: child!,
      ),
      home: const ConverterHomePage(),
    );
  }
}

enum FileCategory { image, text, mht, unknown }

class ConverterHomePage extends StatefulWidget {
  const ConverterHomePage({super.key});
  @override
  State<ConverterHomePage> createState() => _ConverterHomePageState();
}

class _ConverterHomePageState extends State<ConverterHomePage> {
  PlatformFile? _pickedFile;
  Uint8List? _pickedBytes;
  String? _sourceExt;
  FileCategory _category = FileCategory.unknown;

  ImageFormatOption? _selectedImageTarget;
  TextFormatOption? _selectedTextTarget;

  bool _isConverting = false;
  String? _statusMessage;
  String? _savedPath;
  bool _hasError = false;

  Future<void> _pickFile() async {
    final result = await FilePicker.platform.pickFiles(withData: true);
    if (result == null || result.files.isEmpty) return;

    final file = result.files.single;
    final ext = (file.extension ?? p.extension(file.name).replaceFirst('.', ''))
        .toLowerCase();

    setState(() {
      _pickedFile = file;
      _pickedBytes = file.bytes;
      _sourceExt = ext;
      _savedPath = null;
      _statusMessage = null;
      _hasError = false;
      _category = _detectCategory(ext);
      _selectedImageTarget = null;
      _selectedTextTarget = null;
    });
  }

  FileCategory _detectCategory(String ext) {
    if (ext == 'mht' || ext == 'mhtml') return FileCategory.mht;
    if (ImageConverter.supportedSourceExtensions.contains(ext)) {
      return FileCategory.image;
    }
    if (['txt', 'csv', 'json', 'md'].contains(ext)) return FileCategory.text;
    return FileCategory.unknown;
  }

  Future<Directory> _resolveOutputDir() async {
    if (Platform.isAndroid) {
      // نحفظ داخل مجلد التطبيق الخاص على التخزين الخارجي (لا يحتاج صلاحيات
      // في أندرويد 10+ بسبب Scoped Storage)، ثم نعرض المسار الكامل للمستخدم.
      final dir = await getExternalStorageDirectory();
      if (dir != null) {
        final outDir = Directory(p.join(dir.path, 'المحول'));
        if (!await outDir.exists()) await outDir.create(recursive: true);
        return outDir;
      }
    }
    final docs = await getApplicationDocumentsDirectory();
    final outDir = Directory(p.join(docs.path, 'المحول'));
    if (!await outDir.exists()) await outDir.create(recursive: true);
    return outDir;
  }

  Future<void> _saveBytes(Uint8List bytes, String newExtension) async {
    final outDir = await _resolveOutputDir();
    final baseName = p.basenameWithoutExtension(_pickedFile!.name);
    var targetFile = File(p.join(outDir.path, '$baseName.$newExtension'));

    int counter = 1;
    while (await targetFile.exists()) {
      targetFile =
          File(p.join(outDir.path, '$baseName($counter).$newExtension'));
      counter++;
    }
    await targetFile.writeAsBytes(bytes, flush: true);
    setState(() => _savedPath = targetFile.path);
  }

  Future<void> _runMhtConversion() async {
    setState(() {
      _isConverting = true;
      _statusMessage = 'جاري تفكيك ملف MHT واستخراج المحتوى...';
      _hasError = false;
    });
    try {
      final pdfBytes = await MhtToPdfConverter.convert(_pickedBytes!);
      setState(() => _statusMessage = 'جاري حفظ ملف PDF...');
      await _saveBytes(pdfBytes, 'pdf');
      setState(() => _statusMessage = 'تم التحويل بنجاح ✅');
    } catch (e) {
      setState(() {
        _hasError = true;
        _statusMessage = 'فشل التحويل: $e';
      });
    } finally {
      setState(() => _isConverting = false);
    }
  }

  Future<void> _runImageConversion() async {
    if (_selectedImageTarget == null) return;
    setState(() {
      _isConverting = true;
      _statusMessage = 'جاري تحويل الصورة...';
      _hasError = false;
    });
    try {
      final bytes = ImageConverter.convert(_pickedBytes!, _selectedImageTarget!);
      await _saveBytes(bytes, _selectedImageTarget!.extension);
      setState(() => _statusMessage = 'تم التحويل بنجاح ✅');
    } catch (e) {
      setState(() {
        _hasError = true;
        _statusMessage = 'فشل التحويل: $e';
      });
    } finally {
      setState(() => _isConverting = false);
    }
  }

  Future<void> _runTextConversion() async {
    if (_selectedTextTarget == null) return;
    setState(() {
      _isConverting = true;
      _statusMessage = 'جاري تحويل الملف النصي...';
      _hasError = false;
    });
    try {
      final bytes = await TextConverter.convert(
        sourceExt: _sourceExt!,
        target: _selectedTextTarget!,
        sourceBytes: _pickedBytes!,
      );
      await _saveBytes(bytes, _selectedTextTarget!.extension);
      setState(() => _statusMessage = 'تم التحويل بنجاح ✅');
    } catch (e) {
      setState(() {
        _hasError = true;
        _statusMessage = 'فشل التحويل: $e';
      });
    } finally {
      setState(() => _isConverting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('محوّل الصيغ')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                FilledButton.icon(
                  onPressed: _isConverting ? null : _pickFile,
                  icon: const Icon(Icons.upload_file),
                  label: const Text('اختيار ملف'),
                ),
                const SizedBox(height: 16),
                if (_pickedFile != null) _buildFileInfoCard(),
                const SizedBox(height: 16),
                if (_category == FileCategory.mht) _buildMhtSection(),
                if (_category == FileCategory.image) _buildImageSection(),
                if (_category == FileCategory.text) _buildTextSection(),
                if (_category == FileCategory.unknown && _pickedFile != null)
                  const Card(
                    color: Color(0xFFFFF3E0),
                    child: Padding(
                      padding: EdgeInsets.all(12),
                      child: Text('صيغة هذا الملف غير مدعومة حاليًا للتحويل.'),
                    ),
                  ),
                const SizedBox(height: 20),
                if (_isConverting) const Center(child: CircularProgressIndicator()),
                if (_statusMessage != null) _buildStatusCard(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFileInfoCard() {
    return Card(
      child: ListTile(
        leading: const Icon(Icons.description_outlined),
        title: Text(_pickedFile!.name),
        subtitle: Text(
          'الصيغة المكتشفة تلقائيًا: ${(_sourceExt ?? '').toUpperCase()}',
        ),
      ),
    );
  }

  Widget _buildMhtSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Card(
          color: Color(0xFFE8F5E9),
          child: Padding(
            padding: EdgeInsets.all(12),
            child: Text('تم اكتشاف ملف MHT — سيتم تحويله مباشرة إلى PDF.'),
          ),
        ),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: _isConverting ? null : _runMhtConversion,
          icon: const Icon(Icons.picture_as_pdf_outlined),
          label: const Text('تحويل إلى PDF'),
        ),
      ],
    );
  }

  Widget _buildImageSection() {
    final targets = ImageConverter.targetsExcluding(_sourceExt ?? '');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DropdownButtonFormField<ImageFormatOption>(
          decoration: const InputDecoration(
            labelText: 'اختر الصيغة المطلوب التحويل إليها',
            border: OutlineInputBorder(),
          ),
          value: _selectedImageTarget,
          items: targets
              .map((f) => DropdownMenuItem(value: f, child: Text(f.label)))
              .toList(),
          onChanged: (v) => setState(() => _selectedImageTarget = v),
        ),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: (_selectedImageTarget == null || _isConverting)
              ? null
              : _runImageConversion,
          icon: const Icon(Icons.image_outlined),
          label: const Text('تحويل الصورة'),
        ),
      ],
    );
  }

  Widget _buildTextSection() {
    final targets = TextFormatOption.values
        .where((f) => f.extension != (_sourceExt ?? '').toLowerCase())
        .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DropdownButtonFormField<TextFormatOption>(
          decoration: const InputDecoration(
            labelText: 'اختر الصيغة المطلوب التحويل إليها',
            border: OutlineInputBorder(),
          ),
          value: _selectedTextTarget,
          items: targets
              .map((f) => DropdownMenuItem(value: f, child: Text(f.label)))
              .toList(),
          onChanged: (v) => setState(() => _selectedTextTarget = v),
        ),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: (_selectedTextTarget == null || _isConverting)
              ? null
              : _runTextConversion,
          icon: const Icon(Icons.article_outlined),
          label: const Text('تحويل الملف'),
        ),
      ],
    );
  }

  Widget _buildStatusCard() {
    return Card(
      color: _hasError ? const Color(0xFFFFEBEE) : const Color(0xFFE8F5E9),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(_statusMessage ?? ''),
            if (_savedPath != null) ...[
              const SizedBox(height: 8),
              Text(
                'تم الحفظ في:\n$_savedPath',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: () => OpenFilex.open(_savedPath!),
                icon: const Icon(Icons.open_in_new),
                label: const Text('فتح الملف'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
