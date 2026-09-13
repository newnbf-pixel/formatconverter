import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:mime/mime.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'converters/image_converter.dart';
import 'converters/mht_to_pdf.dart';
import 'converters/text_converter.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final preferences = await SharedPreferences.getInstance();
  runApp(FormatConverterApp(preferences: preferences));
}

enum FileKind { image, video, audio, text, document, archive, unknown }

class AppSettings {
  final ThemeMode themeMode;
  final bool showMetadata;
  final String saveFolderName;
  final int maxFileSizeMb;
  final int colorSeed;
  final bool enableImageConversion;
  final bool enableTextConversion;

  const AppSettings({
    this.themeMode = ThemeMode.system,
    this.showMetadata = true,
    this.saveFolderName = 'المحوّل الشامل',
    this.maxFileSizeMb = 500,
    this.colorSeed = 0xff176b5b,
    this.enableImageConversion = true,
    this.enableTextConversion = true,
  });
}

class FormatConverterApp extends StatefulWidget {
  final SharedPreferences preferences;
  const FormatConverterApp({super.key, required this.preferences});
  @override
  State<FormatConverterApp> createState() => _FormatConverterAppState();
}

class _FormatConverterAppState extends State<FormatConverterApp> {
  late AppSettings settings = AppSettings(
        themeMode: ThemeMode.values[widget.preferences.getInt('themeMode') ?? ThemeMode.system.index],
        showMetadata: widget.preferences.getBool('showMetadata') ?? true,
        saveFolderName: widget.preferences.getString('saveFolderName') ?? 'المحوّل الشامل',
        maxFileSizeMb: widget.preferences.getInt('maxFileSizeMb') ?? 500,
        colorSeed: widget.preferences.getInt('colorSeed') ?? 0xff176b5b,
        enableImageConversion: widget.preferences.getBool('enableImageConversion') ?? true,
        enableTextConversion: widget.preferences.getBool('enableTextConversion') ?? true,
      );

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'المحوّل الشامل',
        debugShowCheckedModeBanner: false,
        themeMode: settings.themeMode,
        theme: ThemeData(useMaterial3: true, colorSchemeSeed: Color(settings.colorSeed)),
        darkTheme: ThemeData.dark(useMaterial3: true),
        home: ConverterHome(
          settings: settings,
          onSettings: () async {
            final result = await Navigator.push<SettingsResult>(context, MaterialPageRoute(
              builder: (_) => SettingsPage(settings: settings),
            ));
            if (result != null) {
              setState(() => settings = result.settings);
              await _saveSettings(result.settings);
            }
          },
        ),
      );

  Future<void> _saveSettings(AppSettings value) async {
    await widget.preferences.setInt('themeMode', value.themeMode.index);
    await widget.preferences.setBool('showMetadata', value.showMetadata);
    await widget.preferences.setString('saveFolderName', value.saveFolderName);
    await widget.preferences.setInt('maxFileSizeMb', value.maxFileSizeMb);
    await widget.preferences.setInt('colorSeed', value.colorSeed);
    await widget.preferences.setBool('enableImageConversion', value.enableImageConversion);
    await widget.preferences.setBool('enableTextConversion', value.enableTextConversion);
  }
}

class SettingsResult {
  final AppSettings settings;
  const SettingsResult(this.settings);
}

class SettingsPage extends StatefulWidget {
  final AppSettings settings;
  const SettingsPage({super.key, required this.settings});
  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late ThemeMode themeMode = widget.settings.themeMode;
  late bool showMetadata = widget.settings.showMetadata;
  late String saveFolderName = widget.settings.saveFolderName;
  late double maxFileSizeMb = widget.settings.maxFileSizeMb.toDouble();
  late int colorSeed = widget.settings.colorSeed;
  late bool enableImageConversion = widget.settings.enableImageConversion;
  late bool enableTextConversion = widget.settings.enableTextConversion;

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('الإعدادات')),
        body: ListView(padding: const EdgeInsets.all(16), children: [
        const Text('إعدادات المحوّل الشامل', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
        const SizedBox(height: 6),
        const Text('تحكم في طريقة العرض، الصيغ، حجم الملفات، ومكان حفظ النتائج.'),
        const SizedBox(height: 18),
          DropdownButtonFormField<ThemeMode>(
            value: themeMode,
            decoration: const InputDecoration(labelText: 'الثيم', border: OutlineInputBorder()),
            items: const [
              DropdownMenuItem(value: ThemeMode.system, child: Text('تلقائي حسب الجهاز')),
              DropdownMenuItem(value: ThemeMode.light, child: Text('فاتح')),
              DropdownMenuItem(value: ThemeMode.dark, child: Text('داكن')),
            ],
            onChanged: (value) => setState(() => themeMode = value ?? ThemeMode.system),
          ),
          const SizedBox(height: 12),
          const Text('لون التطبيق'),
          Wrap(spacing: 10, children: [
            _colorChoice(0xff176b5b), _colorChoice(0xff2457a6), _colorChoice(0xff8a3d72), _colorChoice(0xffa85618),
          ]),
          SwitchListTile(title: const Text('عرض بيانات الملف والناتج'), value: showMetadata, onChanged: (value) => setState(() => showMetadata = value)),
          SwitchListTile(title: const Text('تفعيل تحويل الصور'), value: enableImageConversion, onChanged: (value) => setState(() => enableImageConversion = value)),
          SwitchListTile(title: const Text('تفعيل تحويل الملفات النصية'), value: enableTextConversion, onChanged: (value) => setState(() => enableTextConversion = value)),
          TextFormField(initialValue: saveFolderName, decoration: const InputDecoration(labelText: 'مجلد الحفظ داخل مساحة التطبيق'), onChanged: (value) => saveFolderName = value.trim().isEmpty ? 'المحوّل الشامل' : value.trim()),
          Text('الحد الأقصى لحجم الملف: ${maxFileSizeMb.round()} MB'),
          Slider(value: maxFileSizeMb, min: 10, max: 2000, divisions: 199, label: '${maxFileSizeMb.round()} MB', onChanged: (value) => setState(() => maxFileSizeMb = value)),
          const Divider(),
          const ListTile(title: Text('التعرف والتحويل'), subtitle: Text('يتم التعرف تلقائيًا على الصور والفيديو والصوت والنصوص والمستندات والأرشيفات. التحويل المباشر متاح للصور والنصوص و MHT إلى PDF، وتظهر الأنواع غير القابلة للتحويل بوضوح.')),
          const ListTile(title: Text('المصمم'), subtitle: Text('نواف فراج العنزي')),
          FilledButton.icon(onPressed: () => Navigator.pop(context, SettingsResult(AppSettings(themeMode: themeMode, showMetadata: showMetadata, saveFolderName: saveFolderName, maxFileSizeMb: maxFileSizeMb.round(), colorSeed: colorSeed, enableImageConversion: enableImageConversion, enableTextConversion: enableTextConversion))), icon: const Icon(Icons.save_outlined), label: const Text('حفظ الإعدادات')),
        ]),
      );

  Widget _colorChoice(int value) => InkWell(onTap: () => setState(() => colorSeed = value), child: CircleAvatar(backgroundColor: Color(value), child: colorSeed == value ? const Icon(Icons.check, color: Colors.white) : null));
}

class ConverterHome extends StatefulWidget {
  final AppSettings settings;
  final VoidCallback onSettings;
  const ConverterHome({super.key, required this.settings, required this.onSettings});
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
  static const textFormats = ['txt', 'csv', 'json', 'md', 'html', 'xml', 'pdf'];

  Future<void> chooseFile() async {
    final result = await FilePicker.platform.pickFiles(withData: true);
    if (result == null || result.files.isEmpty) return;
    final selected = result.files.single;
    final ext = (selected.extension ?? p.extension(selected.name).replaceFirst('.', '')).toLowerCase();
    if (selected.size > widget.settings.maxFileSizeMb * 1024 * 1024) {
      setState(() => message = 'حجم الملف أكبر من الحد المسموح (${widget.settings.maxFileSizeMb} MB)');
      return;
    }
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
    if (imageFormats.contains(ext) || ['jpeg', 'webp', 'heic', 'svg', 'tga', 'ico', 'tiff'].contains(ext) || mime?.startsWith('image/') == true) return FileKind.image;
    if (['mp4', 'mkv', 'avi', 'mov', 'webm', '3gp', 'flv', 'wmv', 'mpeg', 'mpg', 'm4v'].contains(ext) || mime?.startsWith('video/') == true) return FileKind.video;
    if (['mp3', 'wav', 'aac', 'flac', 'ogg', 'm4a', 'wma', 'opus', 'aiff'].contains(ext) || mime?.startsWith('audio/') == true) return FileKind.audio;
    if (['txt', 'csv', 'json', 'md', 'log', 'xml', 'html', 'htm', 'mht', 'mhtml', 'yaml', 'yml', 'ini', 'conf', 'sql', 'css', 'js', 'ts', 'dart', 'py', 'java', 'kt', 'sh'].contains(ext) || mime?.startsWith('text/') == true) return FileKind.text;
    if (['pdf', 'doc', 'docx', 'xls', 'xlsx', 'ppt', 'pptx', 'rtf', 'odt', 'ods', 'odp'].contains(ext)) return FileKind.document;
    if (['zip', 'rar', '7z', 'tar', 'gz', 'bz2', 'xz', 'iso', 'apk'].contains(ext)) return FileKind.archive;
    return FileKind.unknown;
  }

  List<String> availableTargets() {
    if (kind == FileKind.image && widget.settings.enableImageConversion) return imageFormats.where((item) => item != extension && !(item == 'jpg' && extension == 'jpeg')).toList();
    if (kind == FileKind.text && widget.settings.enableTextConversion && extension != 'mht' && extension != 'mhtml') return textFormats.where((item) => item != extension).toList();
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
      final folder = Directory(p.join(base?.path ?? '.', widget.settings.saveFolderName));
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
          const SizedBox(height: 10),
          OutlinedButton.icon(onPressed: busy ? null : widget.onSettings, icon: const Icon(Icons.settings_outlined), label: const Text('فتح الإعدادات')),
          if (file != null) ...[const SizedBox(height: 16), _fileInfo(), const SizedBox(height: 12), if (availableTargets().isNotEmpty) _conversionBox() else _unsupportedBox()],
          if (busy) const Padding(padding: EdgeInsets.all(20), child: Center(child: CircularProgressIndicator())),
          if (message != null) _resultBox(),
          const SizedBox(height: 22),
          const Center(child: Text('تصميم وتطوير: نواف فراج العنزي', style: TextStyle(fontSize: 12))),
        ]),
      ));

  Widget _fileInfo() => Card(child: ListTile(leading: Icon(_kindIcon()), title: Text(file!.name), subtitle: widget.settings.showMetadata ? Text('النوع: ${_kindLabel()}\nالصيغة: ${extension.toUpperCase()}\nالحجم: ${(file!.size / 1024 / 1024).toStringAsFixed(2)} MB\nMIME: ${lookupMimeType(file!.name) ?? 'غير معروف'}') : null));

  IconData _kindIcon() => switch (kind) { FileKind.image => Icons.image_outlined, FileKind.video => Icons.movie_outlined, FileKind.audio => Icons.audiotrack_outlined, FileKind.text => Icons.text_snippet_outlined, FileKind.document => Icons.description_outlined, FileKind.archive => Icons.archive_outlined, FileKind.unknown => Icons.insert_drive_file_outlined };

  String _kindLabel() => switch (kind) { FileKind.image => 'صورة', FileKind.video => 'فيديو', FileKind.audio => 'صوت', FileKind.text => 'ملف نصي', FileKind.document => 'مستند', FileKind.archive => 'أرشيف مضغوط', FileKind.unknown => 'غير معروف' };

  Widget _conversionBox() => Card(child: Padding(padding: const EdgeInsets.all(14), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [const Text('الصيغ المتاحة', style: TextStyle(fontWeight: FontWeight.bold)), const SizedBox(height: 8), DropdownButtonFormField<String>(value: target, decoration: const InputDecoration(border: OutlineInputBorder(), labelText: 'الصيغة الجديدة'), items: availableTargets().map((item) => DropdownMenuItem(value: item, child: Text(item.toUpperCase()))).toList(), onChanged: (value) => setState(() => target = value)), const SizedBox(height: 10), FilledButton.icon(onPressed: busy || target == null ? null : convert, icon: const Icon(Icons.transform), label: const Text('تحويل وحفظ'))])));

  Widget _unsupportedBox() => const Card(child: Padding(padding: EdgeInsets.all(14), child: Text('تم التعرف على نوع الملف، لكن تحويل هذا النوع غير متاح حاليًا.')));

  Widget _resultBox() => Card(
        color: Theme.of(context).colorScheme.primaryContainer,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(message!, style: const TextStyle(fontWeight: FontWeight.bold)),
              if (savedPath != null) ...[
                const SizedBox(height: 8),
                Text('الصيغة الناتجة: ${target?.toUpperCase()}\nحجم الناتج: ${_outputSizeLabel()}\nمكان الحفظ:\n$savedPath'),
                OutlinedButton.icon(
                  onPressed: () => OpenFilex.open(savedPath!),
                  icon: const Icon(Icons.open_in_new),
                  label: const Text('فتح الملف الناتج'),
                ),
              ],
            ],
          ),
        ),
      );

  String _outputSizeLabel() {
    final path = savedPath;
    if (path == null) return 'غير معروف';
    final size = File(path).lengthSync();
    return '${(size / 1024 / 1024).toStringAsFixed(2)} MB';
  }
}
