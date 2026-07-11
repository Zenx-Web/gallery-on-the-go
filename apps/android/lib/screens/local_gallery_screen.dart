import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:photo_manager_image_provider/photo_manager_image_provider.dart';
import 'package:video_player/video_player.dart';

/// Shared icon+message(+action) panel used for permission-denied, empty and
/// error states so they read as one consistent visual language.
class _InfoPanel extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  const _InfoPanel({
    required this.icon,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 64, color: Colors.white38),
            const SizedBox(height: 16),
            Text(title, style: Theme.of(context).textTheme.titleLarge, textAlign: TextAlign.center),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70),
            ),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: onAction,
                icon: const Icon(Icons.refresh),
                label: Text(actionLabel!),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class LocalGalleryScreen extends StatefulWidget {
  const LocalGalleryScreen({super.key});

  @override
  State<LocalGalleryScreen> createState() => _LocalGalleryScreenState();
}

class _LocalGalleryScreenState extends State<LocalGalleryScreen> with WidgetsBindingObserver {
  List<AssetPathEntity> _albums = [];
  bool _loading = true;
  bool _permissionDenied = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadAlbums();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _loadAlbums();
    }
  }

  Future<void> _loadAlbums() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final permitted = await PhotoManager.requestPermissionExtend();
      if (!permitted.isAuth && !permitted.hasAccess) {
        if (mounted) {
          setState(() {
            _albums = [];
            _loading = false;
            _permissionDenied = true;
          });
        }
        return;
      }

      final albums = await PhotoManager.getAssetPathList(
        type: RequestType.common,
      );

      if (mounted) {
        setState(() {
          _albums = albums;
          _loading = false;
          _permissionDenied = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'Could not load your photo albums. ${e.toString()}';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_permissionDenied) {
      return _InfoPanel(
        icon: Icons.photo_library_outlined,
        title: 'Gallery Access Required',
        message:
            'This app needs access to your photos and videos to browse your gallery locally and stream them to your panel.',
        actionLabel: 'Open Settings',
        onAction: () => PhotoManager.openSetting(),
      );
    }

    if (_error != null) {
      return _InfoPanel(
        icon: Icons.error_outline,
        title: 'Something went wrong',
        message: _error!,
        actionLabel: 'Retry',
        onAction: _loadAlbums,
      );
    }

    if (_albums.isEmpty) {
      return _InfoPanel(
        icon: Icons.image_not_supported_outlined,
        title: 'No Albums Found',
        message: 'This device doesn\'t have any accessible photos or videos yet.',
        actionLabel: 'Refresh',
        onAction: _loadAlbums,
      );
    }

    return GridView.builder(
      padding: const EdgeInsets.all(12),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: 0.8,
      ),
      itemCount: _albums.length,
      itemBuilder: (context, index) {
        final album = _albums[index];
        return GestureDetector(
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => AlbumFilesScreen(album: album)),
            );
          },
          child: Card(
            clipBehavior: Clip.antiAlias,
            elevation: 2,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: FutureBuilder<List<AssetEntity>>(
                    future: album.getAssetListRange(start: 0, end: 1),
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.done &&
                          snapshot.data != null &&
                          snapshot.data!.isNotEmpty) {
                        return AssetEntityImage(
                          snapshot.data!.first,
                          isOriginal: false,
                          thumbnailSize: const ThumbnailSize.square(250),
                          fit: BoxFit.cover,
                        );
                      }
                      return const ColoredBox(
                        color: Colors.grey,
                        child: Icon(Icons.folder, size: 48, color: Colors.white70),
                      );
                    },
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        album.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 2),
                      FutureBuilder<int>(
                        future: album.assetCountAsync,
                        builder: (context, snapshot) {
                          return Text(
                            '${snapshot.data ?? 0} items',
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Colors.white60,
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                )
              ],
            ),
          ),
        );
      },
    );
  }
}

class AlbumFilesScreen extends StatefulWidget {
  final AssetPathEntity album;
  const AlbumFilesScreen({super.key, required this.album});

  @override
  State<AlbumFilesScreen> createState() => _AlbumFilesScreenState();
}

class _AlbumFilesScreenState extends State<AlbumFilesScreen> {
  List<AssetEntity> _assets = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadAssets();
  }

  Future<void> _loadAssets() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final count = await widget.album.assetCountAsync;
      final assets = await widget.album.getAssetListRange(start: 0, end: count);
      if (mounted) {
        setState(() {
          _assets = assets;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'Could not load this album. ${e.toString()}';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.album.name)),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _InfoPanel(
                  icon: Icons.error_outline,
                  title: 'Something went wrong',
                  message: _error!,
                  actionLabel: 'Retry',
                  onAction: _loadAssets,
                )
              : _assets.isEmpty
                  ? const _InfoPanel(
                      icon: Icons.image_not_supported_outlined,
                      title: 'No Media Found',
                      message: 'This album is empty.',
                    )
                  : GridView.builder(
                      padding: const EdgeInsets.all(4),
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 3,
                        crossAxisSpacing: 4,
                        mainAxisSpacing: 4,
                      ),
                      itemCount: _assets.length,
                      itemBuilder: (context, index) {
                        final asset = _assets[index];
                        return GestureDetector(
                          onTap: () {
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => FullscreenMediaViewer(asset: asset),
                              ),
                            );
                          },
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              AssetEntityImage(
                                asset,
                                isOriginal: false,
                                thumbnailSize: const ThumbnailSize.square(200),
                                fit: BoxFit.cover,
                              ),
                              if (asset.type == AssetType.video)
                                const Positioned(
                                  right: 8,
                                  bottom: 8,
                                  child: Icon(Icons.play_circle_fill, color: Colors.white, size: 24),
                                ),
                            ],
                          ),
                        );
                      },
                    ),
    );
  }
}

class FullscreenMediaViewer extends StatefulWidget {
  final AssetEntity asset;
  const FullscreenMediaViewer({super.key, required this.asset});

  @override
  State<FullscreenMediaViewer> createState() => _FullscreenMediaViewerState();
}

class _FullscreenMediaViewerState extends State<FullscreenMediaViewer> {
  VideoPlayerController? _controller;
  bool _videoFailed = false;

  @override
  void initState() {
    super.initState();
    if (widget.asset.type == AssetType.video) {
      _initVideo();
    }
  }

  Future<void> _initVideo() async {
    final file = await widget.asset.file;
    if (file == null) {
      if (mounted) setState(() => _videoFailed = true);
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
      if (mounted) setState(() => _videoFailed = true);
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        iconTheme: const IconThemeData(color: Colors.white),
        elevation: 0,
      ),
      body: Center(
        child: widget.asset.type == AssetType.video
            ? _buildVideo()
            : InteractiveViewer(
                child: AssetEntityImage(
                  widget.asset,
                  isOriginal: true,
                  fit: BoxFit.contain,
                ),
              ),
      ),
    );
  }

  Widget _buildVideo() {
    if (_videoFailed) {
      return const _InfoPanel(
        icon: Icons.error_outline,
        title: 'Playback failed',
        message: 'This video could not be played.',
      );
    }
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) {
      return const CircularProgressIndicator();
    }
    return GestureDetector(
      onTap: () {
        setState(() {
          controller.value.isPlaying ? controller.pause() : controller.play();
        });
      },
      child: AspectRatio(
        aspectRatio: controller.value.aspectRatio,
        child: Stack(
          alignment: Alignment.center,
          children: [
            VideoPlayer(controller),
            if (!controller.value.isPlaying)
              const Icon(Icons.play_circle_fill, color: Colors.white70, size: 64),
          ],
        ),
      ),
    );
  }
}
