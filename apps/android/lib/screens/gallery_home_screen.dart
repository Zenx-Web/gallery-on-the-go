import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';

import '../theme/app_theme.dart';
import '../widgets/album_card.dart';
import '../widgets/empty_state.dart';
import '../widgets/filter_sort_bar.dart';
import '../widgets/media_tile.dart';
import '../widgets/search_field.dart';
import '../widgets/section_header.dart';
import 'album_detail_screen.dart';
import 'media_viewer_screen.dart';

/// Top-level gallery screen — a unified "Photos" timeline (all assets,
/// grouped by date, filterable/sortable/searchable) and an "Albums" tab
/// (grid of albums, unchanged behavior from the original app, restyled).
class GalleryHomeScreen extends StatefulWidget {
  const GalleryHomeScreen({super.key});

  @override
  State<GalleryHomeScreen> createState() => _GalleryHomeScreenState();
}

class _GalleryHomeScreenState extends State<GalleryHomeScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final TabController _tabController;

  bool _loading = true;
  bool _permissionDenied = false;
  String? _error;

  List<AssetEntity> _allAssets = [];
  List<AssetPathEntity> _albums = [];

  String _query = '';
  MediaTypeFilter _typeFilter = MediaTypeFilter.all;
  SortOption _sortOption = SortOption.newest;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _tabController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final permitted = await PhotoManager.requestPermissionExtend();
      if (!permitted.isAuth && !permitted.hasAccess) {
        if (mounted) {
          setState(() {
            _loading = false;
            _permissionDenied = true;
          });
        }
        return;
      }

      final allPaths = await PhotoManager.getAssetPathList(
        type: RequestType.common,
        onlyAll: true,
      );
      final albums = await PhotoManager.getAssetPathList(
        type: RequestType.common,
        onlyAll: false,
      );

      List<AssetEntity> assets = [];
      if (allPaths.isNotEmpty) {
        final all = allPaths.first;
        final count = await all.assetCountAsync;
        assets = await all.getAssetListRange(start: 0, end: count);
      }

      if (mounted) {
        setState(() {
          _allAssets = assets;
          _albums = albums;
          _loading = false;
          _permissionDenied = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'Could not load your photo library. ${e.toString()}';
        });
      }
    }
  }

  List<AssetEntity> get _filteredSortedAssets {
    final query = _query.trim().toLowerCase();
    final filtered = _allAssets.where((a) {
      if (!_typeFilter.matches(a)) return false;
      if (query.isEmpty) return true;
      return (a.title ?? '').toLowerCase().contains(query);
    }).toList();
    filtered.sort(_sortOption.compare);
    return filtered;
  }

  List<AssetPathEntity> get _filteredAlbums {
    final query = _query.trim().toLowerCase();
    if (query.isEmpty) return _albums;
    return _albums.where((a) => a.name.toLowerCase().contains(query)).toList();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_permissionDenied) {
      return EmptyState(
        icon: Icons.photo_library_outlined,
        title: 'Gallery Access Required',
        message:
            'This app needs access to your photos and videos to browse your gallery locally and stream them to your panel.',
        actionLabel: 'Open Settings',
        onAction: () => PhotoManager.openSetting(),
      );
    }

    if (_error != null) {
      return EmptyState(
        icon: Icons.error_outline,
        title: 'Something went wrong',
        message: _error!,
        actionLabel: 'Retry',
        onAction: _load,
      );
    }

    return Column(
      children: [
        SearchField(
          hintText: 'Search photos and albums…',
          onChanged: (v) => setState(() => _query = v),
        ),
        TabBar(
          controller: _tabController,
          indicatorColor: AppColors.accent,
          indicatorSize: TabBarIndicatorSize.label,
          labelColor: AppColors.onSurface,
          unselectedLabelColor: AppColors.onSurfaceTertiary,
          labelStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
          tabs: const [
            Tab(text: 'Photos'),
            Tab(text: 'Albums'),
          ],
        ),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              _buildPhotosTab(),
              _buildAlbumsTab(),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildPhotosTab() {
    final assets = _filteredSortedAssets;

    return Column(
      children: [
        FilterSortBar(
          typeFilter: _typeFilter,
          onTypeChanged: (v) => setState(() => _typeFilter = v),
          sortOption: _sortOption,
          onSortChanged: (v) => setState(() => _sortOption = v),
        ),
        Expanded(
          child: assets.isEmpty
              ? EmptyState(
                  icon: Icons.image_not_supported_outlined,
                  title: 'No Photos Found',
                  message: _query.isNotEmpty
                      ? 'No results for "$_query".'
                      : "This device doesn't have any accessible photos or videos yet.",
                  actionLabel: 'Refresh',
                  onAction: _load,
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  color: AppColors.accent,
                  backgroundColor: AppColors.surface,
                  child: _buildPhotosGrid(assets),
                ),
        ),
      ],
    );
  }

  Widget _buildPhotosGrid(List<AssetEntity> assets) {
    // Grouping by date only makes sense alongside newest/oldest sort — name
    // sort intentionally shows a flat grid instead.
    if (_sortOption == SortOption.name) {
      return GridView.builder(
        padding: const EdgeInsets.all(AppSpacing.md),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          crossAxisSpacing: AppSpacing.sm,
          mainAxisSpacing: AppSpacing.sm,
        ),
        itemCount: assets.length,
        itemBuilder: (context, index) => _tile(assets, assets[index]),
      );
    }

    final slivers = <Widget>[];
    String? currentGroup;
    List<AssetEntity> currentBucket = [];

    void flushBucket() {
      if (currentBucket.isEmpty) return;
      final bucket = currentBucket;
      slivers.add(SliverToBoxAdapter(child: SectionHeader(label: currentGroup!)));
      slivers.add(
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
          sliver: SliverGrid(
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              crossAxisSpacing: AppSpacing.sm,
              mainAxisSpacing: AppSpacing.sm,
            ),
            delegate: SliverChildBuilderDelegate(
              (context, i) => _tile(assets, bucket[i]),
              childCount: bucket.length,
            ),
          ),
        ),
      );
      currentBucket = [];
    }

    for (final asset in assets) {
      final label = dateGroupLabel(asset.createDateTime);
      if (label != currentGroup) {
        flushBucket();
        currentGroup = label;
      }
      currentBucket.add(asset);
    }
    flushBucket();

    return CustomScrollView(slivers: [...slivers, const SliverToBoxAdapter(child: SizedBox(height: AppSpacing.xl))]);
  }

  /// [allAssets] is the full filtered/sorted list currently on screen — passed
  /// in rather than recomputed per-tile to avoid re-filtering/re-sorting the
  /// whole library on every single grid cell build.
  Widget _tile(List<AssetEntity> allAssets, AssetEntity asset) {
    final openIndex = allAssets.indexOf(asset);
    return MediaTile(
      asset: asset,
      heroTag: 'photo_${asset.id}',
      onTap: () {
        Navigator.of(context)
            .push(
              MaterialPageRoute(
                builder: (_) => MediaViewerScreen(assets: allAssets, initialIndex: openIndex),
              ),
            )
            // Re-fetch on return — picks up in-viewer edits (which save as a
            // new asset + trash the original) without a separate callback
            // plumbed all the way back from MediaViewerScreen.
            .then((_) => _load());
      },
    );
  }

  Widget _buildAlbumsTab() {
    final albums = _filteredAlbums;

    if (albums.isEmpty) {
      return EmptyState(
        icon: Icons.folder_off_outlined,
        title: 'No Albums Found',
        message: _query.isNotEmpty
            ? 'No albums match "$_query".'
            : "This device doesn't have any accessible albums yet.",
        actionLabel: 'Refresh',
        onAction: _load,
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      color: AppColors.accent,
      backgroundColor: AppColors.surface,
      child: GridView.builder(
        padding: const EdgeInsets.all(AppSpacing.md),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          crossAxisSpacing: AppSpacing.md,
          mainAxisSpacing: AppSpacing.md,
          childAspectRatio: 0.8,
        ),
        itemCount: albums.length,
        itemBuilder: (context, index) {
          final album = albums[index];
          return AlbumCard(
            album: album,
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => AlbumDetailScreen(album: album)),
              );
            },
          );
        },
      ),
    );
  }
}
