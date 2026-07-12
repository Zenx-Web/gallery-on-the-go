import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:photo_manager/photo_manager.dart';
import 'package:photo_manager_image_provider/photo_manager_image_provider.dart';
import 'package:photo_view/photo_view.dart';
import 'package:photo_view/photo_view_gallery.dart';
import 'package:share_plus/share_plus.dart';
import 'package:video_player/video_player.dart';

import '../theme/app_theme.dart';
import '../widgets/empty_state.dart';

/// Fullscreen, swipeable photo/video viewer. Photos get real pinch-zoom via
/// `photo_view`; videos play inline with a lightweight custom scrubber.
/// Chrome (top app bar + bottom info bar) fades in/out on tap, and the
/// initial photo Hero-transitions in from whichever grid it was opened from.
class MediaViewerScreen extends StatefulWidget {
  final List<AssetEntity> assets;
  final int initialIndex;

  /// Must match the `heroTag` prefix used by the grid this was opened from
  /// (`MediaTile.heroTag`), so the entrance Hero animation connects to the
  /// right originating tile instead of a mismatched/absent one.
  final String heroPrefix;

  const MediaViewerScreen({
    super.key,
    required this.assets,
    required this.initialIndex,
    this.heroPrefix = 'photo_',
  });

  @override
  State<MediaViewerScreen> createState() => _MediaViewerScreenState();
}

class _MediaViewerScreenState extends State<MediaViewerScreen> {
  late final PageController _pageController;
  late int _index;
  bool _chromeVisible = true;
  bool _showEditPanel = false;
  bool _saving = false;
  int _rotateDegrees = 0;
  double _brightness = 1.0;
  double _contrast = 1.0;

  @override
  void initState() {
    super.initState();
    _index = widget.initialIndex;
    _pageController = PageController(initialPage: widget.initialIndex);
  }

  AssetEntity get _current => widget.assets[_index];

  void _toggleChrome() => setState(() => _chromeVisible = !_chromeVisible);

  Future<void> _share() async {
    final file = await _current.file;
    if (file == null || !mounted) return;
    await Share.shareXFiles([XFile(file.path)]);
  }

  void _resetEditState() {
    _rotateDegrees = 0;
    _brightness = 1.0;
    _contrast = 1.0;
  }

  /// Applies rotate/brightness/contrast and saves the result. photo_manager
  /// always creates a NEW asset rather than overwriting in place (a
  /// scoped-storage restriction), so this replaces the entry in
  /// [widget.assets] — the same List instance the caller's grid holds — so
  /// the change is visible without a full gallery re-fetch, then trashes the
  /// original. Mirrors the equivalent web-side edit flow in
  /// file_stream_service.dart's handleEditRequest.
  Future<void> _applyEdit() async {
    if (_rotateDegrees == 0 && _brightness == 1.0 && _contrast == 1.0) {
      setState(() => _showEditPanel = false);
      return;
    }

    setState(() => _saving = true);
    final original = _current;

    try {
      final file = await original.file;
      if (file == null) throw StateError('Could not read source file');

      final bytes = await file.readAsBytes();
      var image = img.decodeImage(bytes);
      if (image == null) throw StateError('Could not decode image');

      if (_rotateDegrees != 0) {
        image = img.copyRotate(image, angle: _rotateDegrees);
      }
      if (_brightness != 1.0 || _contrast != 1.0) {
        image = img.adjustColor(image, brightness: _brightness, contrast: _contrast);
      }

      final isPng = file.path.toLowerCase().endsWith('.png');
      final encoded = isPng ? img.encodePng(image) : img.encodeJpg(image, quality: 92);
      final title = original.title ?? 'edited.${isPng ? 'png' : 'jpg'}';

      final newAsset = await PhotoManager.editor.saveImage(
        Uint8List.fromList(encoded),
        filename: title,
        title: title,
      );

      try {
        if (Platform.isAndroid) {
          await PhotoManager.editor.android.moveToTrash([original]);
        } else {
          await PhotoManager.editor.deleteWithIds([original.id]);
        }
      } catch (_) {
        // Edit already saved successfully — cleanup failure isn't fatal.
      }

      if (!mounted) return;
      setState(() {
        widget.assets[_index] = newAsset;
        _showEditPanel = false;
        _saving = false;
        _resetEditState();
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Edit failed: $e')),
      );
    }
  }

  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  String _formatDate(DateTime date) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    final h = date.hour % 12 == 0 ? 12 : date.hour % 12;
    final ampm = date.hour < 12 ? 'AM' : 'PM';
    return '${months[date.month - 1]} ${date.day}, ${date.year} · $h:${date.minute.toString().padLeft(2, '0')} $ampm';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      extendBodyBehindAppBar: true,
      appBar: _chromeVisible
          ? AppBar(
              backgroundColor: Colors.black.withValues(alpha: 0.4),
              elevation: 0,
              iconTheme: const IconThemeData(color: Colors.white),
              actions: [
                if (_current.type != AssetType.video)
                  IconButton(
                    icon: const Icon(Icons.tune_rounded),
                    tooltip: 'Edit',
                    onPressed: () => setState(() => _showEditPanel = !_showEditPanel),
                  ),
                IconButton(
                  icon: const Icon(Icons.share_outlined),
                  tooltip: 'Share',
                  onPressed: _share,
                ),
              ],
            )
          : null,
      body: GestureDetector(
        onTap: _toggleChrome,
        child: Stack(
          children: [
            PhotoViewGallery.builder(
              pageController: _pageController,
              itemCount: widget.assets.length,
              onPageChanged: (i) => setState(() => _index = i),
              backgroundDecoration: const BoxDecoration(color: Colors.black),
              loadingBuilder: (context, event) => const Center(
                child: CircularProgressIndicator(color: AppColors.accent),
              ),
              builder: (context, index) {
                final asset = widget.assets[index];
                final heroTag = '${widget.heroPrefix}${asset.id}';

                if (asset.type == AssetType.video) {
                  return PhotoViewGalleryPageOptions.customChild(
                    heroAttributes: PhotoViewHeroAttributes(tag: heroTag),
                    minScale: PhotoViewComputedScale.contained,
                    maxScale: PhotoViewComputedScale.contained,
                    initialScale: PhotoViewComputedScale.contained,
                    disableGestures: true,
                    child: _VideoPage(asset: asset),
                  );
                }

                return PhotoViewGalleryPageOptions(
                  imageProvider: AssetEntityImageProvider(asset, isOriginal: true),
                  heroAttributes: PhotoViewHeroAttributes(tag: heroTag),
                  minScale: PhotoViewComputedScale.contained,
                  maxScale: PhotoViewComputedScale.covered * 3,
                );
              },
            ),
            AnimatedOpacity(
              opacity: _chromeVisible ? 1 : 0,
              duration: const Duration(milliseconds: 180),
              child: IgnorePointer(
                ignoring: !_chromeVisible,
                child: Align(
                  alignment: Alignment.bottomCenter,
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.lg,
                      AppSpacing.xl,
                      AppSpacing.lg,
                      AppSpacing.xl,
                    ),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Colors.transparent, Colors.black.withValues(alpha: 0.75)],
                      ),
                    ),
                    child: SafeArea(
                      top: false,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _current.title ?? _current.id,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 14),
                          ),
                          const SizedBox(height: 4),
                          FutureBuilder<File?>(
                            future: _current.file,
                            builder: (context, snapshot) {
                              final size = snapshot.data?.lengthSync();
                              final dateLabel = _formatDate(_current.createDateTime);
                              return Text(
                                size != null ? '$dateLabel · ${_formatSize(size)}' : dateLabel,
                                style: const TextStyle(color: Colors.white70, fontSize: 12),
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
            if (_showEditPanel) _buildEditPanel(),
            if (_saving)
              Container(
                color: Colors.black54,
                child: const Center(
                  child: CircularProgressIndicator(color: AppColors.accent),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildEditPanel() {
    return Align(
      alignment: Alignment.bottomCenter,
      child: GestureDetector(
        onTap: () {}, // absorb taps so they don't fall through to _toggleChrome
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.lg, AppSpacing.lg, AppSpacing.xl),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.85),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: SafeArea(
            top: false,
            child: StatefulBuilder(
              builder: (context, setPanelState) {
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Edit', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 15)),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        const Text('Rotate', style: TextStyle(color: Colors.white70, fontSize: 12)),
                        const SizedBox(width: 12),
                        IconButton(
                          icon: const Icon(Icons.rotate_right_rounded, color: Colors.white),
                          onPressed: () => setPanelState(() => _rotateDegrees = (_rotateDegrees + 90) % 360),
                        ),
                        Text('$_rotateDegrees°', style: const TextStyle(color: Colors.white70, fontSize: 12)),
                      ],
                    ),
                    Row(
                      children: [
                        const SizedBox(width: 70, child: Text('Brightness', style: TextStyle(color: Colors.white70, fontSize: 12))),
                        Expanded(
                          child: Slider(
                            value: _brightness,
                            min: 0.5,
                            max: 1.5,
                            activeColor: AppColors.accent,
                            onChanged: (v) => setPanelState(() => _brightness = v),
                          ),
                        ),
                      ],
                    ),
                    Row(
                      children: [
                        const SizedBox(width: 70, child: Text('Contrast', style: TextStyle(color: Colors.white70, fontSize: 12))),
                        Expanded(
                          child: Slider(
                            value: _contrast,
                            min: 0.5,
                            max: 1.5,
                            activeColor: AppColors.accent,
                            onChanged: (v) => setPanelState(() => _contrast = v),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: FilledButton(
                            onPressed: _applyEdit,
                            child: const Text('Apply'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        TextButton(
                          onPressed: () => setState(() {
                            _showEditPanel = false;
                            _resetEditState();
                          }),
                          child: const Text('Cancel'),
                        ),
                      ],
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _VideoPage extends StatefulWidget {
  final AssetEntity asset;
  const _VideoPage({required this.asset});

  @override
  State<_VideoPage> createState() => _VideoPageState();
}

class _VideoPageState extends State<_VideoPage> {
  VideoPlayerController? _controller;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final file = await widget.asset.file;
    if (file == null) {
      if (mounted) setState(() => _failed = true);
      return;
    }
    final controller = VideoPlayerController.file(file);
    try {
      await controller.initialize();
      if (!mounted) {
        controller.dispose();
        return;
      }
      setState(() => _controller = controller);
      controller.play();
      controller.setLooping(true);
    } catch (_) {
      controller.dispose();
      if (mounted) setState(() => _failed = true);
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_failed) {
      return const EmptyState(
        icon: Icons.error_outline,
        title: 'Playback failed',
        message: 'This video could not be played.',
      );
    }
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) {
      return const Center(child: CircularProgressIndicator(color: AppColors.accent));
    }
    return Center(
      child: AspectRatio(
        aspectRatio: controller.value.aspectRatio,
        child: Stack(
          alignment: Alignment.center,
          children: [
            VideoPlayer(controller),
            GestureDetector(
              onTap: () {
                setState(() {
                  controller.value.isPlaying ? controller.pause() : controller.play();
                });
              },
              child: AnimatedOpacity(
                opacity: controller.value.isPlaying ? 0 : 1,
                duration: const Duration(milliseconds: 150),
                child: Container(
                  color: Colors.black26,
                  child: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 64),
                ),
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: ValueListenableBuilder(
                valueListenable: controller,
                builder: (context, value, _) {
                  final duration = value.duration.inMilliseconds;
                  final position = value.position.inMilliseconds.clamp(0, duration);
                  return SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      trackHeight: 2,
                      thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
                      overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
                    ),
                    child: Slider(
                      value: duration == 0 ? 0 : position.toDouble(),
                      min: 0,
                      max: duration == 0 ? 1 : duration.toDouble(),
                      activeColor: AppColors.accent,
                      inactiveColor: Colors.white24,
                      onChanged: (v) => controller.seekTo(Duration(milliseconds: v.toInt())),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
