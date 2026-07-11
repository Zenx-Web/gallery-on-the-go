import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:photo_manager_image_provider/photo_manager_image_provider.dart';

class LocalGalleryScreen extends StatefulWidget {
  const LocalGalleryScreen({super.key});

  @override
  State<LocalGalleryScreen> createState() => _LocalGalleryScreenState();
}

class _LocalGalleryScreenState extends State<LocalGalleryScreen> with WidgetsBindingObserver {
  List<AssetPathEntity> _albums = [];
  bool _loading = true;
  bool _permissionDenied = false;

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
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_permissionDenied) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.photo_library_outlined, size: 64, color: Colors.white38),
              const SizedBox(height: 16),
              Text(
                'Gallery Access Required',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              const Text(
                'This app needs access to your photos and videos to browse your gallery locally and stream them to your panel.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white70),
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: () => PhotoManager.openSetting(),
                icon: const Icon(Icons.settings),
                label: const Text('Open Settings'),
              ),
            ],
          ),
        ),
      );
    }

    if (_albums.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'No albums found on this device.',
            textAlign: TextAlign.center,
          ),
        ),
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

  @override
  void initState() {
    super.initState();
    _loadAssets();
  }

  Future<void> _loadAssets() async {
    final count = await widget.album.assetCountAsync;
    final assets = await widget.album.getAssetListRange(start: 0, end: count);
    if (mounted) {
      setState(() {
        _assets = assets;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.album.name)),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
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

class FullscreenMediaViewer extends StatelessWidget {
  final AssetEntity asset;
  const FullscreenMediaViewer({super.key, required this.asset});

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
        child: InteractiveViewer(
          child: AssetEntityImage(
            asset,
            isOriginal: true,
            fit: BoxFit.contain,
          ),
        ),
      ),
    );
  }
}
