import 'dart:io';
import 'package:camera/camera.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import '../services/notes_storage.dart';
import '../services/permission_gate.dart';
import '../theme/app_theme.dart';

// ─── Scanner Screen ───────────────────────────────────────────────────────────

class ScannerScreen extends StatefulWidget {
  const ScannerScreen({super.key, this.isActive = true});

  /// Whether the Scanner tab is currently visible.
  /// The shell keeps every tab mounted via IndexedStack, so without this flag
  /// the camera would turn on at app launch regardless of which tab shows.
  final bool isActive;

  @override
  State<ScannerScreen> createState() => _ScannerScreenState();
}

class _ScannerScreenState extends State<ScannerScreen>
    with WidgetsBindingObserver {
  final List<XFile> _pages = [];

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
      final status =
          await PermissionGate.run(() => Permission.camera.request());
      if (!status.isGranted) {
        if (mounted) {
          setState(
            () => _cameraError =
                'Camera permission denied. Enable it in Settings.',
          );
        }
        return;
      }
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        if (mounted) {
          setState(() => _cameraError = 'No camera found on this device.');
        }
        return;
      }
      final ctrl = CameraController(
        cameras.first,
        ResolutionPreset.high,
        enableAudio: false,
      );
      await ctrl.initialize();
      if (!mounted) {
        ctrl.dispose();
        return;
      }
      setState(() {
        _cameraCtrl = ctrl;
        _cameraReady = true;
        _cameraError = null;
      });
    } catch (e) {
      if (mounted) setState(() => _cameraError = 'Camera error: $e');
    }
  }

  // ── Actions ─────────────────────────────────────────────────────────────────

  Future<void> _capture() async {
    final ctrl = _cameraCtrl;
    if (ctrl == null || !_cameraReady) return;
    try {
      final file = await ctrl.takePicture();
      setState(() => _pages.add(file));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Capture failed: $e')),
        );
      }
    }
  }

  Future<void> _importFromGallery() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      allowMultiple: true,
    );
    if (result == null) return;
    final picked = result.files
        .where((f) => f.path != null)
        .map((f) => XFile(f.path!));
    setState(() => _pages.addAll(picked));
  }

  Future<void> _goNext() async {
    if (_pages.isEmpty) return;

    // Push the naming screen — it returns true if saved successfully
    final saved = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => _NamingScreen(pages: List.unmodifiable(_pages)),
        fullscreenDialog: true,
      ),
    );

    if (saved == true && mounted) {
      setState(() => _pages.clear());
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('✅ Note saved! Find it in the Notes tab.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  // ── UI ──────────────────────────────────────────────────────────────────────

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
      body: SafeArea(
        child: Column(
          children: [
            Expanded(child: _buildViewfinder()),
            if (_pages.isNotEmpty) _buildPageStrip(),
            _buildBottomActions(),
          ],
        ),
      ),
    );
  }

  Widget _buildViewfinder() {
    return Container(
      margin: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        0,
        AppSpacing.lg,
        AppSpacing.md,
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
            const Icon(
              Icons.no_photography_outlined,
              size: 48,
              color: AppColors.onSurfaceTertiary,
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              _cameraError!,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
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
      final left =
          alignment == Alignment.topLeft || alignment == Alignment.bottomLeft;
      final top =
          alignment == Alignment.topLeft || alignment == Alignment.topRight;
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

  Widget _buildPageStrip() {
    return SizedBox(
      height: 80,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
        itemCount: _pages.length,
        itemBuilder: (context, i) => Stack(
          children: [
            GestureDetector(
              onLongPress: () => setState(() => _pages.removeAt(i)),
              child: Container(
                width: 54,
                height: 72,
                margin: const EdgeInsets.only(right: AppSpacing.sm),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                  border: Border.all(color: AppColors.accent),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(AppRadius.sm - 1),
                  child: Image.file(
                    File(_pages[i].path),
                    fit: BoxFit.cover,
                    cacheWidth: 160,
                  ),
                ),
              ),
            ),
            // Page number badge
            Positioned(
              bottom: 6,
              left: 4,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  '${i + 1}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 9,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomActions() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.xl,
        AppSpacing.md,
        AppSpacing.xl,
        AppSpacing.xl,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          // Import from gallery
          _ActionButton(
            icon: Icons.photo_library_outlined,
            label: 'Gallery',
            onTap: _importFromGallery,
          ),

          // Shutter button
          GestureDetector(
            onTap: _capture,
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

          // Next → (enabled only when at least 1 page captured)
          _pages.isEmpty
              ? const _ActionButton(
                  icon: Icons.arrow_forward_rounded,
                  label: 'Next',
                  onTap: null,
                )
              : _ActionButton(
                  icon: Icons.arrow_forward_rounded,
                  label: 'Next',
                  onTap: _goNext,
                  accent: true,
                ),
        ],
      ),
    );
  }
}

// ─── Naming Screen ────────────────────────────────────────────────────────────

/// Full-screen step shown after capturing pages.
/// Student types a Subject and Topic name then hits Save.
class _NamingScreen extends StatefulWidget {
  const _NamingScreen({required this.pages});
  final List<XFile> pages;

  @override
  State<_NamingScreen> createState() => _NamingScreenState();
}

class _NamingScreenState extends State<_NamingScreen> {
  final _subjectCtrl = TextEditingController();
  final _topicCtrl = TextEditingController();
  final _subjectFocus = FocusNode();
  final _topicFocus = FocusNode();

  List<String> _existingSubjects = [];
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _loadSubjects();
  }

  @override
  void dispose() {
    _subjectCtrl.dispose();
    _topicCtrl.dispose();
    _subjectFocus.dispose();
    _topicFocus.dispose();
    super.dispose();
  }

  Future<void> _loadSubjects() async {
    final subjects = await NotesStorage.loadSubjects();
    if (mounted) setState(() => _existingSubjects = subjects);
  }

  bool get _canSave =>
      _subjectCtrl.text.trim().isNotEmpty &&
      _topicCtrl.text.trim().isNotEmpty;

  Future<void> _save() async {
    if (!_canSave || _saving) return;
    setState(() => _saving = true);
    try {
      await NotesStorage.saveTopic(
        subject: _subjectCtrl.text.trim(),
        topic: _topicCtrl.text.trim(),
        pagePaths: widget.pages.map((p) => p.path).toList(),
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Save failed: $e')),
        );
      }
      setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Name Your Note'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.pop(context, false),
        ),
      ),
      body: GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.xl),
          children: [
            // ── Page previews ──
            Text(
              '${widget.pages.length} page${widget.pages.length == 1 ? '' : 's'} ready to save',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppColors.onSurfaceSecondary,
                  ),
            ),
            const SizedBox(height: AppSpacing.sm),
            SizedBox(
              height: 100,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: widget.pages.length,
                itemBuilder: (_, i) => Container(
                  width: 72,
                  height: 96,
                  margin: const EdgeInsets.only(right: AppSpacing.sm),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                    border: Border.all(color: AppColors.divider),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(AppRadius.sm - 1),
                    child: Image.file(
                      File(widget.pages[i].path),
                      fit: BoxFit.cover,
                    ),
                  ),
                ),
              ),
            ),

            const SizedBox(height: AppSpacing.xl),
            const Divider(),
            const SizedBox(height: AppSpacing.xl),

            // ── Subject field ──
            Text(
              'Subject',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: AppSpacing.sm),
            TextField(
              controller: _subjectCtrl,
              focusNode: _subjectFocus,
              textCapitalization: TextCapitalization.words,
              decoration: InputDecoration(
                hintText: 'e.g. Mathematics, Physics, History',
                prefixIcon: const Icon(Icons.menu_book_outlined),
                filled: true,
                fillColor: AppColors.surface,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  borderSide: const BorderSide(color: AppColors.divider),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  borderSide: const BorderSide(color: AppColors.divider),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  borderSide: const BorderSide(color: AppColors.accent),
                ),
              ),
              onChanged: (_) => setState(() {}),
              onSubmitted: (_) => _topicFocus.requestFocus(),
            ),

            // Existing subject chips (quick-pick)
            if (_existingSubjects.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.sm),
              Wrap(
                spacing: AppSpacing.sm,
                children: _existingSubjects.map((s) {
                  final selected = _subjectCtrl.text.trim() == s;
                  return ActionChip(
                    label: Text(s),
                    onPressed: () {
                      _subjectCtrl.text = s;
                      setState(() {});
                      _topicFocus.requestFocus();
                    },
                    backgroundColor: selected
                        ? AppColors.accent.withOpacity(0.2)
                        : AppColors.surface,
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
                  );
                }).toList(),
              ),
            ],

            const SizedBox(height: AppSpacing.xl),

            // ── Topic field ──
            Text(
              'Topic / Chapter',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: AppSpacing.sm),
            TextField(
              controller: _topicCtrl,
              focusNode: _topicFocus,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                hintText: 'e.g. Chapter 3 – Algebra, Waves & Sound',
                prefixIcon: const Icon(Icons.bookmark_outline),
                filled: true,
                fillColor: AppColors.surface,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  borderSide: const BorderSide(color: AppColors.divider),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  borderSide: const BorderSide(color: AppColors.divider),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  borderSide: const BorderSide(color: AppColors.accent),
                ),
              ),
              onChanged: (_) => setState(() {}),
              onSubmitted: (_) => _save(),
            ),

            const SizedBox(height: AppSpacing.xxxl),

            // ── Save button ──
            SizedBox(
              width: double.infinity,
              height: 52,
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: _canSave
                      ? AppColors.accent
                      : AppColors.onSurfaceTertiary,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppRadius.md),
                  ),
                ),
                onPressed: _canSave && !_saving ? _save : null,
                icon: _saving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.check_rounded, color: Colors.white),
                label: Text(
                  _saving ? 'Saving…' : 'Save Note',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Sub-widgets ──────────────────────────────────────────────────────────────

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.icon,
    required this.label,
    this.onTap,
    this.accent = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool accent;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    final color = enabled
        ? (accent ? AppColors.accent : AppColors.onSurface)
        : AppColors.onSurfaceTertiary;

    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 26),
          const SizedBox(height: 4),
          Text(
            label,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: enabled
                      ? (accent
                          ? AppColors.accent
                          : AppColors.onSurfaceSecondary)
                      : AppColors.onSurfaceTertiary,
                  fontWeight:
                      accent ? FontWeight.w600 : FontWeight.normal,
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
