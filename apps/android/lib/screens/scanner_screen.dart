import 'dart:io';
import 'package:camera/camera.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:permission_handler/permission_handler.dart';
import '../services/study_storage.dart';
import '../theme/app_theme.dart';
import '../widgets/glass_background.dart';

class ScannerScreen extends StatefulWidget {
  const ScannerScreen({super.key});

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
    _initCamera();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _cameraCtrl?.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive) {
      _cameraCtrl?.dispose();
      if (mounted) setState(() => _cameraReady = false);
    } else if (state == AppLifecycleState.resumed) {
      _initCamera();
    }
  }

  Future<void> _initCamera() async {
    final status = await Permission.camera.request();
    if (!status.isGranted) {
      if (mounted) setState(() => _cameraError = 'Camera permission denied. Enable it in Settings.');
      return;
    }
    try {
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

  Future<void> _saveAsPdf() async {
    setState(() => _saving = true);
    try {
      final doc = pw.Document();
      for (final page in _pages) {
        final bytes = await File(page.path).readAsBytes();
        final image = pw.MemoryImage(bytes);
        doc.addPage(pw.Page(build: (_) => pw.Center(child: pw.Image(image))));
      }

      final dir = await _scansDir();
      final fileName = 'scan_${DateTime.now().millisecondsSinceEpoch}.pdf';
      final file = File('${dir.path}/$fileName');
      await file.writeAsBytes(await doc.save());

      await StudyStorage.instance.addFileToLibrary(
        folderName: 'Scanned Documents',
        subjectName: 'Scans',
        filePath: file.path,
      );
      await StudyStorage.instance.incrementScansCount();
      await StudyStorage.instance.recordActivity();

      final pageCount = _pages.length;
      setState(() => _pages.clear());
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Saved $pageCount page(s) as $fileName to Library')),
      );
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Save failed: $e')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _saveAsImages() async {
    setState(() => _saving = true);
    try {
      final dir = await _scansDir();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      var saved = 0;
      for (final page in _pages) {
        final fileName = 'scan_${timestamp}_$saved.jpg';
        final destFile = File('${dir.path}/$fileName');
        await File(page.path).copy(destFile.path);
        await StudyStorage.instance.addFileToLibrary(
          folderName: 'Scanned Documents',
          subjectName: 'Scans',
          filePath: destFile.path,
        );
        saved++;
      }
      await StudyStorage.instance.incrementScansCount();
      await StudyStorage.instance.recordActivity();

      setState(() => _pages.clear());
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Saved $saved image(s) to Library')),
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
          Column(
            children: [
              Expanded(child: _buildViewfinder()),
              _buildFilterRow(),
              if (_pages.isNotEmpty) _buildPageStrip(),
              _buildBottomActions(context),
            ],
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

  void _showSaveSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surfaceElevated,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.lg)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Save ${_pages.length} page(s) as…',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: AppSpacing.lg),
            ListTile(
              leading: const Icon(Icons.picture_as_pdf, color: AppColors.accent),
              title: const Text('PDF Document'),
              subtitle: const Text('Saved to Library → Scanned Documents'),
              onTap: () {
                Navigator.pop(ctx);
                _saveAsPdf();
              },
            ),
            ListTile(
              leading: const Icon(Icons.image_outlined, color: AppColors.accent),
              title: const Text('Image Files'),
              subtitle: const Text('Saved to Library → Scanned Documents'),
              onTap: () {
                Navigator.pop(ctx);
                _saveAsImages();
              },
            ),
          ],
        ),
      ),
    );
  }
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
