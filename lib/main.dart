import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as im;
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

const ink = Color(0xff172e31), teal = Color(0xff087f78);
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const PapertrailApp());
}

class PapertrailApp extends StatelessWidget {
  const PapertrailApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Papertrail',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      useMaterial3: true,
      scaffoldBackgroundColor: const Color(0xfff6f8f7),
      colorScheme: ColorScheme.fromSeed(seedColor: teal, primary: teal),
      appBarTheme: const AppBarTheme(
        backgroundColor: Color(0xfff6f8f7),
        foregroundColor: ink,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(0, 52),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      ),
    ),
    home: const LibraryScreen(),
  );
}

class ScanDoc {
  String id, name, category;
  List<String> pages;
  bool starred;
  DateTime created;
  ScanDoc({
    required this.id,
    required this.name,
    required this.pages,
    this.category = 'Personal',
    this.starred = false,
    DateTime? created,
  }) : created = created ?? DateTime.now();
  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'pages': pages,
    'category': category,
    'starred': starred,
    'created': created.toIso8601String(),
  };
  factory ScanDoc.fromJson(Map<String, dynamic> j) => ScanDoc(
    id: j['id'],
    name: j['name'],
    pages: List<String>.from(j['pages']),
    category: j['category'],
    starred: j['starred'],
    created: DateTime.parse(j['created']),
  );
}

class ScanStore {
  late Directory root;
  List<ScanDoc> docs = [];
  Future<void> load() async {
    root = Directory(
      '${(await getApplicationDocumentsDirectory()).path}/scans',
    );
    await root.create(recursive: true);
    final f = File('${root.path}/index.json');
    if (await f.exists()) {
      docs = (jsonDecode(await f.readAsString()) as List)
          .map((j) => ScanDoc.fromJson(j))
          .toList();
    }
  }

  Future<void> _pending = Future.value();
  Future<void> save() {
    final snapshot = jsonEncode(docs.map((d) => d.toJson()).toList());
    final write = _pending.then((_) async {
      final f = File('${root.path}/index.tmp');
      await f.writeAsString(snapshot, flush: true);
      await f.rename('${root.path}/index.json');
    });
    _pending = write.catchError((Object _) {});
    return write;
  }
  Future<String> addPage(String source) async {
    final bytes = await compute(
      normalizeImage,
      await File(source).readAsBytes(),
    );
    final f = File('${root.path}/${DateTime.now().microsecondsSinceEpoch}.jpg');
    await f.writeAsBytes(bytes);
    return f.path;
  }
}

Uint8List normalizeImage(Uint8List bytes) {
  var image = im.decodeImage(bytes);
  if (image == null) {
    throw Exception('Unsupported image format');
  }
  image = im.bakeOrientation(image);
  if (image.width > 2200 || image.height > 2200) {
    image = im.copyResize(
      image,
      width: image.width >= image.height ? 2200 : null,
      height: image.height > image.width ? 2200 : null,
    );
  }
  return im.encodeJpg(image, quality: 92);
}

class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key});
  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  final store = ScanStore();
  String query = '', filter = 'All';
  bool loaded = false, busy = false;
  String? loadError;
  @override
  void initState() {
    super.initState();
    init();
  }

  Future<void> init() async {
    try {
      await store.load();
      final recovery = await ImagePicker().retrieveLostData();
      if (recovery.files?.isNotEmpty ?? false) {
        await importFiles(recovery.files!);
      }
    } catch (e) {
      loadError = 'Could not load your library: $e';
    }
    if (mounted) {
      setState(() => loaded = true);
    }
  }

  void message(String text) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
    }
  }

  Future<void> importFiles(List<XFile> files) async {
    final pages = <String>[];
    for (final f in files) {
      pages.add(await store.addPage(f.path));
    }
    if (pages.isEmpty) {
      return;
    }
    final now = DateTime.now();
    final doc = ScanDoc(
      id: '${now.microsecondsSinceEpoch}',
      name: 'Scan ${now.day}.${now.month}.${now.year}',
      pages: pages,
    );
    store.docs.insert(0, doc);
    await store.save();
    if (mounted) {
      setState(() {});
      await open(doc);
    }
  }

  Future<void> capture(bool camera) async {
    if (busy) {
      return;
    }
    setState(() => busy = true);
    try {
      final picker = ImagePicker();
      final files = <XFile>[];
      if (camera) {
        final f = await picker.pickImage(source: ImageSource.camera);
        if (f != null) {
          files.add(f);
        }
      } else {
        files.addAll(await picker.pickMultiImage());
      }
      await importFiles(files);
    } catch (e) {
      message('Unable to import image: $e');
    } finally {
      if (mounted) {
        setState(() => busy = false);
      }
    }
  }

  Future<void> open(ScanDoc doc) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => DocumentScreen(store: store, doc: doc),
      ),
    );
    if (mounted) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final docs = store.docs
        .where(
          (d) =>
              d.name.toLowerCase().contains(query.toLowerCase()) &&
              (filter == 'All' ||
                  (filter == 'Starred' ? d.starred : d.category == filter)),
        )
        .toList();
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 78,
        title: const Row(
          children: [
            Icon(Icons.document_scanner_outlined, color: teal, size: 31),
            SizedBox(width: 10),
            Text(
              'papertrail',
              style: TextStyle(
                fontSize: 27,
                fontWeight: FontWeight.w800,
                letterSpacing: -1,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'About',
            icon: const Icon(Icons.info_outline),
            onPressed: () => showAboutDialog(
              context: context,
              applicationName: 'Papertrail',
              applicationVersion: '1.0',
              children: const [
                Text(
                  'Scan, organize, and share. Documents stay on this device. Export important documents before uninstalling.\n\nCamera capture, manual crop, filters, and PDF sharing. No account required.',
                ),
              ],
            ),
          ),
        ],
      ),
      body: !loaded
          ? const Center(child: CircularProgressIndicator())
          : loadError != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(loadError!),
              ),
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(22, 10, 22, 120),
              children: [
                const Text(
                  'A little less paper.\nA lot more space.',
                  style: TextStyle(
                    fontSize: 32,
                    height: 1.12,
                    fontWeight: FontWeight.w800,
                    color: ink,
                    letterSpacing: -1,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  '${store.docs.length} documents, right where you need them.',
                  style: TextStyle(color: Colors.blueGrey.shade600),
                ),
                const SizedBox(height: 25),
                Container(
                  decoration: BoxDecoration(
                    color: ink,
                    borderRadius: BorderRadius.circular(24),
                  ),
                  padding: const EdgeInsets.all(22),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(
                        children: [
                          Icon(
                            Icons.auto_awesome_outlined,
                            color: Color(0xff9de1ca),
                            size: 19,
                          ),
                          SizedBox(width: 8),
                          Text(
                            'PAPER TO POSSIBILITY',
                            style: TextStyle(
                              color: Color(0xff9de1ca),
                              fontSize: 10,
                              letterSpacing: 1.8,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'Your next scan\nstarts here.',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 25,
                          height: 1.2,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 9),
                      const Text(
                        'Receipts, notes, or the next big idea.',
                        style: TextStyle(
                          color: Color(0xffbacdca),
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(height: 20),
                      Row(
                        children: [
                          Expanded(
                            child: FilledButton.icon(
                              onPressed: busy ? null : () => capture(true),
                              icon: const Icon(Icons.camera_alt_outlined),
                              label: const Text('Scan document'),
                              style: FilledButton.styleFrom(
                                backgroundColor: const Color(0xffbcecd9),
                                foregroundColor: ink,
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          IconButton.filledTonal(
                            onPressed: busy ? null : () => capture(false),
                            tooltip: 'Import photos',
                            icon: const Icon(
                              Icons.add_photo_alternate_outlined,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 28),
                const Row(
                  children: [
                    Text(
                      'Your documents',
                      style: TextStyle(
                        fontSize: 21,
                        fontWeight: FontWeight.w800,
                        color: ink,
                      ),
                    ),
                    Spacer(),
                    Icon(Icons.shield_outlined, size: 15, color: teal),
                    SizedBox(width: 4),
                    Text(
                      'On device',
                      style: TextStyle(fontSize: 11, color: teal),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                TextField(
                  onChanged: (v) => setState(() => query = v),
                  decoration: InputDecoration(
                    hintText: 'Find a document',
                    prefixIcon: const Icon(Icons.search),
                    filled: true,
                    fillColor: Colors.white,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(15),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: ['All', 'Starred', 'Personal', 'Work', 'Receipts']
                        .map(
                          (f) => Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: ChoiceChip(
                              label: Text(f),
                              selected: filter == f,
                              onSelected: (_) => setState(() => filter = f),
                              showCheckmark: false,
                            ),
                          ),
                        )
                        .toList(),
                  ),
                ),
                const SizedBox(height: 16),
                if (busy)
                  const Padding(
                    padding: EdgeInsets.all(16),
                    child: LinearProgressIndicator(),
                  ),
                if (docs.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 35),
                    child: Column(
                      children: [
                        Icon(
                          Icons.library_books_outlined,
                          size: 48,
                          color: Colors.blueGrey.shade200,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          query.isNotEmpty || filter != 'All'
                              ? 'No matching documents'
                              : 'Make room for your first scan',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w600,
                            color: ink,
                          ),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Capture a page or import photos to get started.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.blueGrey),
                        ),
                      ],
                    ),
                  ),
                ...docs.map(
                  (d) => Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Material(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(18),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(18),
                        onTap: () => open(d),
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Row(
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(9),
                                child: Image.file(
                                  File(d.pages.first),
                                  width: 62,
                                  height: 80,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, error, stack) =>
                                      const Icon(Icons.description, size: 60),
                                ),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      d.name,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w700,
                                        color: ink,
                                        fontSize: 16,
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      '${d.pages.length} pages · ${d.category}',
                                      style: const TextStyle(
                                        fontSize: 12,
                                        color: Colors.blueGrey,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      '${d.created.day}/${d.created.month}/${d.created.year}',
                                      style: const TextStyle(
                                        fontSize: 11,
                                        color: Colors.blueGrey,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              IconButton(
                                tooltip: 'Star document',
                                icon: Icon(
                                  d.starred
                                      ? Icons.star_rounded
                                      : Icons.star_border_rounded,
                                  color: d.starred
                                      ? Colors.amber.shade700
                                      : Colors.blueGrey.shade300,
                                ),
                                onPressed: () async {
                                  setState(() => d.starred = !d.starred);
                                  await store.save();
                                },
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
      floatingActionButton: loaded && loadError == null
          ? FloatingActionButton.extended(
              onPressed: busy ? null : () => capture(true),
              backgroundColor: teal,
              foregroundColor: Colors.white,
              icon: const Icon(Icons.document_scanner_outlined),
              label: const Text('New scan'),
            )
          : null,
    );
  }
}

class DocumentScreen extends StatefulWidget {
  final ScanStore store;
  final ScanDoc doc;
  const DocumentScreen({super.key, required this.store, required this.doc});
  @override
  State<DocumentScreen> createState() => _DocumentScreenState();
}

class _DocumentScreenState extends State<DocumentScreen> {
  bool busy = false;
  ScanDoc get doc => widget.doc;
  Future<void> action(Future<void> Function() work) async {
    setState(() => busy = true);
    try {
      await work();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not complete action: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => busy = false);
      }
    }
  }

  Future<void> rename() async {
    final input = TextEditingController(text: doc.name);
    final name = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Rename document'),
        content: TextField(controller: input, autofocus: true, maxLength: 80),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              if (input.text.trim().isNotEmpty) {
                Navigator.pop(c, input.text.trim());
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (name != null) {
      setState(() => doc.name = name);
      await widget.store.save();
    }
  }

  Future<void> add(bool camera) => action(() async {
    final picker = ImagePicker();
    final files = <XFile>[];
    if (camera) {
      final f = await picker.pickImage(source: ImageSource.camera);
      if (f != null) {
        files.add(f);
      }
    } else {
      files.addAll(await picker.pickMultiImage());
    }
    for (final f in files) {
      doc.pages.add(await widget.store.addPage(f.path));
    }
    await widget.store.save();
  });
  Future<void> export() => action(() async {
    final path = await const MethodChannel(
      'papertrail/pdf',
    ).invokeMethod<String>('export', {'pages': doc.pages, 'name': doc.name});
    if (path == null) {
      throw Exception('PDF export failed');
    }
    await Share.shareXFiles([
      XFile(path, mimeType: 'application/pdf'),
    ], subject: doc.name);
  });
  Future<bool> confirm(String title, String body) async =>
      await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: Text(title),
          content: Text(body),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('Delete'),
            ),
          ],
        ),
      ) ??
      false;
  Future<void> removePage(int i) async {
    if (!await confirm(
      'Delete page?',
      'This page will be permanently removed.',
    )) {
      return;
    }
    final path = doc.pages.removeAt(i);
    await widget.store.save();
    await File(path).delete();
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> delete() async {
    if (!await confirm(
      'Delete document?',
      'All pages will be permanently removed from this device.',
    )) {
      return;
    }
    await action(() async {
      widget.store.docs.remove(doc);
      await widget.store.save();
      for (final p in doc.pages) {
        final f = File(p);
        if (await f.exists()) {
          await f.delete();
        }
      }
      if (mounted) {
        Navigator.pop(context);
      }
    });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(
        doc.name,
        style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w700),
      ),
      actions: [
        IconButton(
          onPressed: busy ? null : rename,
          tooltip: 'Rename',
          icon: const Icon(Icons.edit_outlined),
        ),
        IconButton(
          onPressed: busy ? null : delete,
          tooltip: 'Delete document',
          icon: const Icon(Icons.delete_outline),
        ),
      ],
    ),
    body: Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 8),
          child: Row(
            children: [
              Text(
                '${doc.pages.length} pages',
                style: const TextStyle(color: Colors.blueGrey),
              ),
              const Spacer(),
              DropdownButton<String>(
                value: doc.category,
                underline: const SizedBox(),
                items: ['Personal', 'Work', 'Receipts']
                    .map((v) => DropdownMenuItem(value: v, child: Text(v)))
                    .toList(),
                onChanged: busy
                    ? null
                    : (v) async {
                        setState(() => doc.category = v!);
                        await widget.store.save();
                      },
              ),
            ],
          ),
        ),
        if (busy) const LinearProgressIndicator(),
        Expanded(
          child: ReorderableListView.builder(
            padding: const EdgeInsets.all(20),
            itemCount: doc.pages.length,
            onReorder: (a, b) async {
              if (busy) {
                return;
              }
              setState(() {
                if (b > a) {
                  b--;
                }
                final p = doc.pages.removeAt(a);
                doc.pages.insert(b, p);
              });
              await widget.store.save();
            },
            itemBuilder: (c, i) => Card(
              key: ValueKey(doc.pages[i]),
              margin: const EdgeInsets.only(bottom: 20),
              clipBehavior: Clip.antiAlias,
              color: Colors.white,
              child: Column(
                children: [
                  InkWell(
                    onTap: busy
                        ? null
                        : () async {
                            await Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) =>
                                    EditorScreen(path: doc.pages[i]),
                              ),
                            );
                            if (mounted) {
                              setState(() {});
                            }
                          },
                    child: SizedBox(
                      height: 290,
                      width: double.infinity,
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Image.file(
                          File(doc.pages[i]),
                          fit: BoxFit.contain,
                          key: ValueKey(
                            '${doc.pages[i]}-${File(doc.pages[i]).lastModifiedSync()}',
                          ),
                        ),
                      ),
                    ),
                  ),
                  ListTile(
                    title: Text('Page ${i + 1}'),
                    subtitle: const Text(
                      'Tap to edit · Hold to reorder',
                      style: TextStyle(fontSize: 12),
                    ),
                    trailing: IconButton(
                      onPressed: busy || doc.pages.length == 1
                          ? null
                          : () => action(() => removePage(i)),
                      icon: const Icon(Icons.delete_outline),
                      tooltip: 'Delete page',
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 16),
            child: Row(
              children: [
                IconButton.filledTonal(
                  onPressed: busy ? null : () => add(true),
                  tooltip: 'Scan another page',
                  icon: const Icon(Icons.add_a_photo_outlined),
                ),
                const SizedBox(width: 8),
                IconButton.filledTonal(
                  onPressed: busy ? null : () => add(false),
                  tooltip: 'Import pages',
                  icon: const Icon(Icons.photo_library_outlined),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: busy ? null : export,
                    icon: const Icon(Icons.ios_share),
                    label: const Text('Share PDF'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    ),
  );
}

Uint8List processImage(Map<String, dynamic> args) {
  var image = im.decodeImage(args['bytes'] as Uint8List)!;
  final turns = args['turns'] as int;
  if (turns != 0) {
    image = im.copyRotate(image, angle: turns * 90);
  }
  final crop = args['crop'] as List<double>;
  final x = (crop[0] * image.width).round().clamp(0, image.width - 1),
      y = (crop[1] * image.height).round().clamp(0, image.height - 1);
  image = im.copyCrop(
    image,
    x: x,
    y: y,
    width: ((crop[2] - crop[0]) * image.width).round().clamp(
      1,
      image.width - x,
    ),
    height: ((crop[3] - crop[1]) * image.height).round().clamp(
      1,
      image.height - y,
    ),
  );
  if (args['filter'] == 'Gray') {
    image = im.grayscale(image);
  }
  if (args['filter'] == 'Clean') {
    image = im.adjustColor(
      image,
      contrast: 1.35,
      brightness: 1.08,
      saturation: 0.65,
    );
  }
  if (args['filter'] == 'B&W') {
    image = im.luminanceThreshold(image, threshold: 0.58);
  }
  return im.encodeJpg(image, quality: 93);
}

class EditorScreen extends StatefulWidget {
  final String path;
  const EditorScreen({super.key, required this.path});
  @override
  State<EditorScreen> createState() => _EditorScreenState();
}

class _EditorScreenState extends State<EditorScreen> {
  Uint8List? original, preview;
  int turns = 0;
  String filter = 'Original';
  bool saving = false, rendering = false;
  int revision = 0;
  RangeValues horizontal = const RangeValues(0, 1),
      vertical = const RangeValues(0, 1);
  @override
  void initState() {
    super.initState();
    File(widget.path).readAsBytes().then((b) {
      if (mounted) {
        setState(() {
          original = b;
          preview = b;
        });
      }
    });
  }

  Map<String, dynamic> get args => {
    'bytes': original!,
    'turns': turns,
    'filter': filter,
    'crop': <double>[
      horizontal.start,
      vertical.start,
      horizontal.end,
      vertical.end,
    ],
  };
  Future<void> render() async {
    if (original == null) {
      return;
    }
    final token = ++revision;
    setState(() => rendering = true);
    try {
      final bytes = await compute(processImage, args);
      if (mounted && token == revision) {
        setState(() {
          preview = bytes;
          rendering = false;
        });
      }
    } catch (e) {
      if (mounted && token == revision) {
        setState(() => rendering = false);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Unable to preview image: $e')));
      }
    }
  }

  Future<void> save() async {
    setState(() => saving = true);
    try {
      final bytes = await compute(processImage, args);
      final temp = File('${widget.path}.tmp');
      await temp.writeAsBytes(bytes, flush: true);
      await temp.rename(widget.path);
      await FileImage(File(widget.path)).evict();
      if (mounted) {
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        setState(() => saving = false);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Could not save page: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !saving,
    child: Scaffold(
      backgroundColor: ink,
      appBar: AppBar(
        backgroundColor: ink,
        foregroundColor: Colors.white,
        title: const Text('Refine your scan'),
        actions: [
          TextButton(
            onPressed: original == null || saving || rendering ? null : save,
            child: Text(
              saving ? 'Saving…' : 'Save',
              style: const TextStyle(color: Color(0xffbcecd9)),
            ),
          ),
        ],
      ),
      body: original == null
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Expanded(
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(20),
                        child: Image.memory(
                          preview!,
                          gaplessPlayback: true,
                          fit: BoxFit.contain,
                        ),
                      ),
                      if (rendering || saving)
                        const CircularProgressIndicator(
                          color: Color(0xffbcecd9),
                        ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: const BoxDecoration(
                    color: Color(0xfff6f8f7),
                    borderRadius: BorderRadius.vertical(
                      top: Radius.circular(26),
                    ),
                  ),
                  child: SafeArea(
                    top: false,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            children: ['Original', 'Clean', 'Gray', 'B&W']
                                .map(
                                  (f) => Padding(
                                    padding: const EdgeInsets.only(right: 8),
                                    child: ChoiceChip(
                                      label: Text(f),
                                      selected: filter == f,
                                      onSelected: saving
                                          ? null
                                          : (_) {
                                              setState(() => filter = f);
                                              render();
                                            },
                                    ),
                                  ),
                                )
                                .toList(),
                          ),
                        ),
                        Row(
                          children: [
                            const Icon(Icons.crop, size: 20),
                            const SizedBox(width: 8),
                            const Text('Crop width'),
                            Expanded(
                              child: RangeSlider(
                                values: horizontal,
                                onChanged: saving
                                    ? null
                                    : (v) {
                                        if (v.end - v.start > .1) {
                                          setState(() => horizontal = v);
                                        }
                                      },
                                onChangeEnd: (_) => render(),
                              ),
                            ),
                          ],
                        ),
                        Row(
                          children: [
                            const Icon(Icons.height, size: 20),
                            const SizedBox(width: 8),
                            const Text('Crop height'),
                            Expanded(
                              child: RangeSlider(
                                values: vertical,
                                onChanged: saving
                                    ? null
                                    : (v) {
                                        if (v.end - v.start > .1) {
                                          setState(() => vertical = v);
                                        }
                                      },
                                onChangeEnd: (_) => render(),
                              ),
                            ),
                          ],
                        ),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            TextButton.icon(
                              onPressed: saving
                                  ? null
                                  : () {
                                      setState(() {
                                        turns = (turns + 1) % 4;
                                        horizontal = vertical =
                                            const RangeValues(0, 1);
                                      });
                                      render();
                                    },
                              icon: const Icon(Icons.rotate_right),
                              label: const Text('Rotate'),
                            ),
                            TextButton(
                              onPressed: saving
                                  ? null
                                  : () {
                                      setState(() {
                                        turns = 0;
                                        filter = 'Original';
                                        horizontal = vertical =
                                            const RangeValues(0, 1);
                                      });
                                      render();
                                    },
                              child: const Text('Reset'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
    ),
  );
}
