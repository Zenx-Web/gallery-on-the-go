import 'dart:io';
import 'package:camera/camera.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:permission_handler/permission_handler.dart';
import '../services/permission_gate.dart';
import '../services/study_storage.dart';
import '../theme/app_theme.dart';
import '../widgets/glass_background.dart';

class ScannerScreen extends StatefulWidget {
  const ScannerScreen({super.key, this.isActive = true});

  /// Whether the Scanner tab is the one currently visible to the user. The
  /// shell keeps every tab mounted via IndexedStack, so without this flag
  /// the camera would turn on at app launch regardless of which tab shows.
  final bool isActive;

  @override
  State<ScannerScreen> createState() => _ScannerScreenState();
}

enum _Filter { color, bw, grayscale }

class _ScannerScreenState extends State<ScannerScreen> with WidgetsBindingObserver {
  _Filter _selectedFilter = _Filter.color;
  final List<XFile> _pages = [];
  bool _saving = false;

  CameraController? _cameraCtrl;
  bool _cameraReady = false;
  String? _cameraError;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (widget.isActive) _initCamera();
  }

  @override
  void didUpdateWidget(covariant ScannerScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isActive && !oldWidget.isActive) {
      _initCamera();
    } else if (!widget.isActive && oldWidget.isActive) {
      _releaseCamera();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _cameraCtrl?.dispose();
    super.dispose();
  }

  void _releaseCamera() {
    final ctrl = _cameraCtrl;
    _cameraCtrl = null;
    if (mounted) setState(() => _cameraReady = false);
    ctrl?.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive) {
      _releaseCamera();
    } else if (state == AppLifecycleState.resumed && widget.isActive) {
      _initCamera();
    }
  }

  Future<void> _initCamera() async {
    try {
      final status = await PermissionGate.run(() => Permission.camera.request());
      if (!status.isGranted) {
        if (mounted) setState(() => _cameraError = 'Camera permission denied. Enable it in Settings.');
        return;
      }
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        if (mounted) setState(() => _cameraError = 'No camera found on this device.');
        return;
      }
      final ctrl = CameraController(cameras.first, ResolutionPreset.high, enableAudio: false);
      await ctrl.initialize();
      if (!mounted) { ctrl.dispose(); return; }
      setState(() { _cameraCtrl = ctrl; _cameraReady = true; _cameraError = null; });
    } catch (e) {
      if (mounted) setState(() => _cameraError = 'Camera error: $e');
    }
  }

  Future<void> _capture() async {
    final ctrl = _cameraCtrl;
    if (ctrl == null || !_cameraReady) return;
    try {
      final file = await ctrl.takePicture();
      setState(() => _pages.add(file));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Capture failed: $e')));
    }
  }

  Future<void> _importFromGallery() async {
    final result = await FilePicker.platform.pickFiles(type: FileType.image, allowMultiple: true);
    if (result == null) return;
    final picked = result.files.where((f) => f.path != null).map((f) => XFile(f.path!));
    setState(() => _pages.addAll(picked));
  }

  Future<Directory> _scansDir() async {
    final docsDir = await getApplicationDocumentsDirectory();
    final dir = Directory('${docsDir.path}/Scans');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  Future<void> _saveScans(_SaveScanResult result) async {
    setState(() => _saving = true);
    try {
      final dir = await _scansDir();
      final safeName = result.name.trim().isEmpty
          ? 'Scan ${DateTime.now().millisecondsSinceEpoch}'
          : result.name.trim();

      if (result.asPdf) {
        final doc = pw.Document();
        for (final page in _pages) {
          final bytes = await File(page.path).readAsBytes();
          final image = pw.MemoryImage(bytes);
          doc.addPage(pw.Page(build: (_) => pw.Center(child: pw.Image(image))));
        }
        final file = File(
          '${dir.path}/${safeName}_${DateTime.now().millisecondsSinceEpoch}.pdf',
        );
        await file.writeAsBytes(await doc.save());
        await StudyStorage.instance.addFileToLibrary(
          folderName: result.folderName,
          subjectName: result.subjectName,
          filePath: file.path,
        );
      } else {
        final timestamp = DateTime.now().millisecondsSinceEpoch;
        for (var i = 0; i < _pages.length; i++) {
          final suffix = _pages.length > 1 ? '_${i + 1}' : '';
          final destFile = File('${dir.path}/${safeName}_$timestamp$suffix.jpg');
          await File(_pages[i].path).copy(destFile.path);
          await StudyStorage.instance.addFileToLibrary(
            folderName: result.folderName,
            subjectName: result.subjectName,
            filePath: destFile.path,
          );
        }
      }

      await StudyStorage.instance.incrementScansCount();
      await StudyStorage.instance.recordActivity();

      final pageCount = _pages.length;
      setState(() => _pages.clear());
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Saved "$safeName" ($pageCount page(s)) to ${result.folderName} → ${result.subjectName}',
          ),
        ),
      );
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Save failed: $e')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const Text('Scanner'),
        actions: [
          TextButton.icon(
            icon: const Icon(Icons.photo_library_outlined, size: 18),
            label: const Text('Import'),
            onPressed: _importFromGallery,
          ),
        ],
      ),
      body: Stack(
        children: [
          const Positioned.fill(child: GlassBackground()),
          SafeArea(
            child: Column(
              children: [
                Expanded(child: _buildViewfinder()),
                _buildFilterRow(),
                if (_pages.isNotEmpty) _buildPageStrip(),
                _buildBottomActions(context),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildViewfinder() {
    return Container(
      margin: const EdgeInsets.fromLTRB(
        AppSpacing.lg, 0, AppSpacing.lg, AppSpacing.md,
      ),
      decoration: BoxDecoration(
        color: const Color(0xFF060608),
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: AppColors.divider),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        child: _cameraError != null
            ? _buildCameraError()
            : !_cameraReady
                ? const Center(child: CircularProgressIndicator())
                : Stack(
                    fit: StackFit.expand,
                    children: [
                      CameraPreview(_cameraCtrl!),
                      ..._cornerGuides(),
                    ],
                  ),
      ),
    );
  }

  Widget _buildCameraError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.no_photography_outlined, size: 48, color: AppColors.onSurfaceTertiary),
            const SizedBox(height: AppSpacing.md),
            Text(_cameraError!, textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: AppSpacing.lg),
            TextButton(onPressed: _initCamera, child: const Text('Retry')),
          ],
        ),
      ),
    );
  }

  List<Widget> _cornerGuides() {
    const length = 24.0;
    const weight = 3.0;
    return [
      Alignment.topLeft,
      Alignment.topRight,
      Alignment.bottomLeft,
      Alignment.bottomRight,
    ].map((alignment) {
      final left = alignment == Alignment.topLeft ||
          alignment == Alignment.bottomLeft;
      final top = alignment == Alignment.topLeft ||
          alignment == Alignment.topRight;
      return Positioned(
        left: left ? 20 : null,
        right: left ? null : 20,
        top: top ? 20 : null,
        bottom: top ? null : 20,
        child: SizedBox(
          width: length,
          height: length,
          child: CustomPaint(
            painter: _CornerPainter(
              isLeft: left,
              isTop: top,
              color: AppColors.accent,
              thickness: weight,
            ),
          ),
        ),
      );
    }).toList();
  }

  Widget _buildFilterRow() {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.sm,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: _Filter.values.map((f) {
          final label = switch (f) {
            _Filter.color => 'Color',
            _Filter.bw => 'B&W',
            _Filter.grayscale => 'Grayscale',
          };
          final selected = f == _selectedFilter;
          return Padding(
            padding: const EdgeInsets.only(right: AppSpacing.sm),
            child: ChoiceChip(
              label: Text(label),
              selected: selected,
              onSelected: (_) => setState(() => _selectedFilter = f),
              selectedColor: AppColors.accent.withOpacity(0.2),
              backgroundColor: AppColors.surface,
              side: BorderSide(
                color: selected ? AppColors.accent : AppColors.divider,
              ),
              labelStyle: TextStyle(
                color: selected
                    ? AppColors.accent
                    : AppColors.onSurfaceSecondary,
                fontWeight:
                    selected ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildPageStrip() {
    return SizedBox(
      height: 76,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
        itemCount: _pages.length,
        itemBuilder: (context, i) => GestureDetector(
          onLongPress: () => setState(() => _pages.removeAt(i)),
          child: Container(
            width: 52,
            height: 68,
            margin: const EdgeInsets.only(right: AppSpacing.sm),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppRadius.sm),
              border: Border.all(color: AppColors.accent),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(AppRadius.sm - 1),
              child: Image.file(File(_pages[i].path), fit: BoxFit.cover),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBottomActions(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.xl, AppSpacing.md, AppSpacing.xl, AppSpacing.xl,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _ActionButton(
            icon: Icons.photo_library_outlined,
            label: 'Gallery',
            onTap: _saving ? null : _importFromGallery,
          ),
          GestureDetector(
            onTap: _saving ? null : _capture,
            child: Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.accent,
                boxShadow: [
                  BoxShadow(
                    color: AppColors.accent.withOpacity(0.4),
                    blurRadius: 16,
                    spreadRadius: 2,
                  ),
                ],
              ),
              child: const Icon(Icons.camera_alt, color: Colors.white, size: 28),
            ),
          ),
          _saving
              ? const SizedBox(
                  width: 26,
                  height: 26,
                  child: CircularProgressIndicator(strokeWidth: 2.5, color: AppColors.accent),
                )
              : _ActionButton(
                  icon: Icons.save_alt_outlined,
                  label: 'Save',
                  onTap: _pages.isEmpty ? null : () => _showSaveSheet(context),
                ),
        ],
      ),
    );
  }

  Future<void> _showSaveSheet(BuildContext context) async {
    final folders = await StudyStorage.instance.loadFolders();
    if (!context.mounted) return;
    final result = await showModalBottomSheet<_SaveScanResult>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surfaceElevated,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.lg)),
      ),
      builder: (ctx) => _SaveScanSheet(pageCount: _pages.length, initialFolders: folders),
    );
    if (result != null) await _saveScans(result);
  }
}

// ─── Save-as-note flow ────────────────────────────────────────────────────────

class _SaveScanResult {
  const _SaveScanResult({
    required this.name,
    required this.asPdf,
    required this.folderName,
    required this.subjectName,
  });

  final String name;
  final bool asPdf;
  final String folderName;
  final String subjectName;
}

/// The "next" step after capturing/importing pages — name the note and file
/// it into a folder/subject before it's written to disk and added to Library.
class _SaveScanSheet extends StatefulWidget {
  const _SaveScanSheet({required this.pageCount, required this.initialFolders});

  final int pageCount;
  final List<FolderItem> initialFolders;

  @override
  State<_SaveScanSheet> createState() => _SaveScanSheetState();
}

class _SaveScanSheetState extends State<_SaveScanSheet> {
  late final _nameCtrl = TextEditingController(text: _defaultName());
  late List<FolderItem> _folders = widget.initialFolders;
  bool _asPdf = true;
  String? _folderName;
  String? _subjectName;

  @override
  void initState() {
    super.initState();
    if (_folders.isNotEmpty) {
      _folderName = _folders.first.name;
      _subjectName = _folders.first.subjects.firstOrNull?.name;
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  String _defaultName() {
    final now = DateTime.now();
    final month = now.month.toString().padLeft(2, '0');
    final day = now.day.toString().padLeft(2, '0');
    return 'Scan $month/$day';
  }

  FolderItem? get _selectedFolder =>
      _folders.where((f) => f.name == _folderName).firstOrNull;

  Future<void> _createFolder() async {
    final name = await _promptForName(context, title: 'New Folder', hint: 'Folder name (e.g. Semester 3)');
    if (name == null || name.isEmpty) return;
    setState(() {
      _folders = [..._folders, FolderItem(name: name)];
      _folderName = name;
      _subjectName = null;
    });
  }

  Future<void> _createSubject() async {
    final folder = _selectedFolder;
    if (folder == null) return;
    final name = await _promptForName(context, title: 'New Subject', hint: 'Subject name');
    if (name == null || name.isEmpty) return;
    setState(() {
      folder.subjects.add(SubjectItem(name: name));
      _subjectName = name;
    });
  }

  void _confirm() {
    final folderName = _folderName;
    final subjectName = _subjectName;
    if (folderName == null || subjectName == null) return;
    Navigator.pop(
      context,
      _SaveScanResult(
        name: _nameCtrl.text,
        asPdf: _asPdf,
        folderName: folderName,
        subjectName: subjectName,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final subjects = _selectedFolder?.subjects ?? [];
    final canConfirm = _folderName != null && _subjectName != null;

    return Padding(
      padding: EdgeInsets.fromLTRB(
        AppSpacing.xl,
        AppSpacing.md,
        AppSpacing.xl,
        AppSpacing.xl + MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Save ${widget.pageCount} page(s) as a note',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: AppSpacing.lg),
            TextField(
              controller: _nameCtrl,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Name',
                hintText: 'e.g. Chapter 4 Notes',
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            Text('Format', style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                ChoiceChip(
                  label: const Text('PDF Document'),
                  selected: _asPdf,
                  onSelected: (_) => setState(() => _asPdf = true),
                ),
                const SizedBox(width: AppSpacing.sm),
                ChoiceChip(
                  label: const Text('Image Files'),
                  selected: !_asPdf,
                  onSelected: (_) => setState(() => _asPdf = false),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),
            Text('Organize', style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: AppSpacing.sm),
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: _folders.isEmpty
                      ? const Text('No folders yet')
                      : DropdownButtonFormField<String>(
                          initialValue: _folderName,
                          dropdownColor: AppColors.surfaceElevated,
                          decoration: const InputDecoration(labelText: 'Folder'),
                          items: _folders
                              .map((f) => DropdownMenuItem(
                                    value: f.name,
                                    child: Text(f.name, overflow: TextOverflow.ellipsis),
                                  ))
                              .toList(),
                          onChanged: (v) => setState(() {
                            _folderName = v;
                            _subjectName = _selectedFolder?.subjects.firstOrNull?.name;
                          }),
                        ),
                ),
                IconButton(
                  icon: const Icon(Icons.create_new_folder_outlined),
                  tooltip: 'New folder',
                  onPressed: _createFolder,
                ),
              ],
            ),
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: subjects.isEmpty
                      ? Text(_selectedFolder == null ? 'Choose a folder first' : 'No subjects yet')
                      : DropdownButtonFormField<String>(
                          initialValue: _subjectName,
                          dropdownColor: AppColors.surfaceElevated,
                          decoration: const InputDecoration(labelText: 'Subject'),
                          items: subjects
                              .map((s) => DropdownMenuItem(
                                    value: s.name,
                                    child: Text(s.name, overflow: TextOverflow.ellipsis),
                                  ))
                              .toList(),
                          onChanged: (v) => setState(() => _subjectName = v),
                        ),
                ),
                IconButton(
                  icon: const Icon(Icons.add),
                  tooltip: 'New subject',
                  onPressed: _selectedFolder == null ? null : _createSubject,
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.xl),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                style: FilledButton.styleFrom(backgroundColor: AppColors.accent),
                onPressed: canConfirm ? _confirm : null,
                child: const Text('Save Note'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

Future<String?> _promptForName(
  BuildContext context, {
  required String title,
  required String hint,
}) {
  final ctrl = TextEditingController();
  return showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: AppColors.surfaceElevated,
      title: Text(title),
      content: TextField(controller: ctrl, autofocus: true, decoration: InputDecoration(hintText: hint)),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
        TextButton(
          onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
          child: const Text('Create'),
        ),
      ],
    ),
  );
}

// ─── Sub-widgets ──────────────────────────────────────────────────────────────

class _ActionButton extends StatelessWidget {
  const _ActionButton({required this.icon, required this.label, this.onTap});

  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            color: enabled ? AppColors.onSurface : AppColors.onSurfaceTertiary,
            size: 26,
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: enabled
                      ? AppColors.onSurfaceSecondary
                      : AppColors.onSurfaceTertiary,
                ),
          ),
        ],
      ),
    );
  }
}

class _CornerPainter extends CustomPainter {
  const _CornerPainter({
    required this.isLeft,
    required this.isTop,
    required this.color,
    required this.thickness,
  });

  final bool isLeft;
  final bool isTop;
  final Color color;
  final double thickness;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = thickness
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    final x = isLeft ? 0.0 : size.width;
    final y = isTop ? 0.0 : size.height;
    final dx = isLeft ? size.width : -size.width;
    final dy = isTop ? size.height : -size.height;
    canvas.drawLine(Offset(x, y), Offset(x + dx, y), paint);
    canvas.drawLine(Offset(x, y), Offset(x, y + dy), paint);
  }

  @override
  bool shouldRepaint(_CornerPainter old) => false;
}
