import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';

import '../theme/app_theme.dart';
import '../widgets/empty_state.dart';
import '../widgets/filter_sort_bar.dart';
import '../widgets/media_tile.dart';
import '../widgets/search_field.dart';
import 'media_viewer_screen.dart';

/// A single album's contents — same filter/sort/search affordances as the
/// Photos tab on the home screen, scoped to this album.
class AlbumDetailScreen extends StatefulWidget {
  final AssetPathEntity album;
  const AlbumDetailScreen({super.key, required this.album});

  @override
  State<AlbumDetailScreen> createState() => _AlbumDetailScreenState();
}

class _AlbumDetailScreenState extends State<AlbumDetailScreen> {
  List<AssetEntity> _assets = [];
  bool _loading = true;
  String? _error;

  String _query = '';
  MediaTypeFilter _typeFilter = MediaTypeFilter.all;
  SortOption _sortOption = SortOption.newest;

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

  List<AssetEntity> get _filteredSortedAssets {
    final query = _query.trim().toLowerCase();
    final filtered = _assets.where((a) {
      if (!_typeFilter.matches(a)) return false;
      if (query.isEmpty) return true;
      return (a.title ?? '').toLowerCase().contains(query);
    }).toList();
    filtered.sort(_sortOption.compare);
    return filtered;
  }

  @override
  Widget build(BuildContext context) {
    final assets = _loading ? <AssetEntity>[] : _filteredSortedAssets;

    return Scaffold(
      appBar: AppBar(title: Text(widget.album.name)),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? EmptyState(
                  icon: Icons.error_outline,
                  title: 'Something went wrong',
                  message: _error!,
                  actionLabel: 'Retry',
                  onAction: _loadAssets,
                )
              : Column(
                  children: [
                    SearchField(onChanged: (v) => setState(() => _query = v)),
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
                              title: 'No Media Found',
                              message: _query.isNotEmpty
                                  ? 'No results for "$_query".'
                                  : 'This album is empty.',
                            )
                          : GridView.builder(
                              padding: const EdgeInsets.all(AppSpacing.md),
                              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: 3,
                                crossAxisSpacing: AppSpacing.sm,
                                mainAxisSpacing: AppSpacing.sm,
                              ),
                              itemCount: assets.length,
                              itemBuilder: (context, index) {
                                final asset = assets[index];
                                return MediaTile(
                                  asset: asset,
                                  heroTag: 'album_${widget.album.id}_${asset.id}',
                                  onTap: () {
                                    Navigator.of(context)
                                        .push(
                                          MaterialPageRoute(
                                            builder: (_) => MediaViewerScreen(
                                              assets: assets,
                                              initialIndex: index,
                                              heroPrefix: 'album_${widget.album.id}_',
                                            ),
                                          ),
                                        )
                                        .then((_) => _loadAssets());
                                  },
                                );
                              },
                            ),
                    ),
                  ],
                ),
    );
  }
}
