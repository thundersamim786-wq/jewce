import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:video_player/video_player.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const AdvancedStreamApp());
}

// ============================================================================
// GLOBAL STATE (Watchlist)
// ============================================================================
// For educational simplicity in a single file, we use a global notifier.
final ValueNotifier<List<MediaEntry>> globalWatchlist = ValueNotifier([]);

class MediaEntry {
  final String identifier;
  final String title;
  final String year;
  final String description;
  final String posterUrl;

  MediaEntry({
    required this.identifier,
    required this.title,
    required this.year,
    required this.description,
    required this.posterUrl,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MediaEntry &&
          runtimeType == other.runtimeType &&
          identifier == other.identifier;

  @override
  int get hashCode => identifier.hashCode;
}

// Data model for parsed video files inside a series/movie
class VideoStream {
  final String title;
  final String highQualityUrl; // e.g., 1080p / Original
  final String standardQualityUrl; // e.g., 480p / 512Kbps

  VideoStream({
    required this.title,
    required this.highQualityUrl,
    required this.standardQualityUrl,
  });
}

// ============================================================================
// MAIN APP & BOTTOM NAVIGATION
// ============================================================================

class AdvancedStreamApp extends StatelessWidget {
  const AdvancedStreamApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Anime & Movies VOD',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF0B0C10),
        primaryColor: const Color(0xFFE50914),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFFE50914),
          surface: Color(0xFF16181E),
        ),
      ),
      home: const MainNavigator(),
    );
  }
}

class MainNavigator extends StatefulWidget {
  const MainNavigator({super.key});

  @override
  State<MainNavigator> createState() => _MainNavigatorState();
}

class _MainNavigatorState extends State<MainNavigator> {
  int _currentIndex = 0;
  final List<Widget> _screens = [
    const AutoCatalogScreen(),
    const WatchlistScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: _screens,
      ),
      bottomNavigationBar: BottomNavigationBar(
        backgroundColor: const Color(0xFF16181E),
        selectedItemColor: const Color(0xFFE50914),
        unselectedItemColor: Colors.white54,
        currentIndex: _currentIndex,
        onTap: (index) => setState(() => _currentIndex = index),
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.search), label: 'Discover'),
          BottomNavigationBarItem(icon: Icon(Icons.bookmark), label: 'Watchlist'),
        ],
      ),
    );
  }
}

// ============================================================================
// 1. DISCOVER TAB (Filtered Search)
// ============================================================================

class AutoCatalogScreen extends StatefulWidget {
  const AutoCatalogScreen({super.key});

  @override
  State<AutoCatalogScreen> createState() => _AutoCatalogScreenState();
}

class _AutoCatalogScreenState extends State<AutoCatalogScreen> {
  final TextEditingController _searchCtrl = TextEditingController();
  List<MediaEntry> _results = [];
  bool _isLoading = false;
  Timer? _debounce;

  Future<void> _executeAutoSearch(String query) async {
    final clean = query.trim();
    if (clean.isEmpty) {
      setState(() => _results = []);
      return;
    }
    setState(() => _isLoading = true);

    try {
      // ADVANCED FILTERING: We exclude short formats (-subject:tiktok, shorts, reels)
      // and force the collection to be movies or animation.
      final advancedQuery = 
          '${Uri.encodeComponent(clean)}+AND+mediatype:movies+AND+-subject:"tiktok"+AND+-subject:"shorts"';
      final uri = Uri.parse(
        'https://archive.org/advancedsearch.php?q=$advancedQuery&fl[]=identifier,title,description,year&rows=30&output=json',
      );

      final response = await http.get(uri).timeout(const Duration(seconds: 8));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final List docs = data['response']['docs'] ?? [];

        final List<MediaEntry> parsed = docs.map((doc) {
          final id = doc['identifier']?.toString() ?? '';
          return MediaEntry(
            identifier: id,
            title: doc['title']?.toString() ?? 'Untitled Video',
            year: doc['year']?.toString() ?? 'Unknown Year',
            description: doc['description']?.toString() ?? 'No description available.',
            posterUrl: 'https://archive.org/services/img/$id',
          );
        }).toList();

        if (mounted) setState(() => _results = parsed);
      }
    } catch (e) {
      debugPrint('Search error: $e');
    }
    if (mounted) setState(() => _isLoading = false);
  }

  void _onSearchChanged(String val) {
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    _debounce = Timer(const Duration(milliseconds: 600), () => _executeAutoSearch(val));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF16181E),
        title: const Text('Discover Movies & Anime', style: TextStyle(fontSize: 18)),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              controller: _searchCtrl,
              onChanged: _onSearchChanged,
              decoration: InputDecoration(
                hintText: 'Search anime, series, movies...',
                prefixIcon: const Icon(Icons.search, color: Color(0xFFE50914)),
                filled: true,
                fillColor: const Color(0xFF16181E),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          if (_isLoading) const LinearProgressIndicator(color: Color(0xFFE50914), minHeight: 2),
          Expanded(child: MediaGrid(mediaList: _results, emptyMessage: 'Search for content...')),
        ],
      ),
    );
  }
}

// ============================================================================
// 2. WATCHLIST TAB
// ============================================================================

class WatchlistScreen extends StatelessWidget {
  const WatchlistScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF16181E),
        title: const Text('My Watchlist', style: TextStyle(fontSize: 18)),
      ),
      body: ValueListenableBuilder<List<MediaEntry>>(
        valueListenable: globalWatchlist,
        builder: (context, watchlist, child) {
          return MediaGrid(
            mediaList: watchlist,
            emptyMessage: 'Your watchlist is empty.',
          );
        },
      ),
    );
  }
}

// Shared Grid UI
class MediaGrid extends StatelessWidget {
  final List<MediaEntry> mediaList;
  final String emptyMessage;

  const MediaGrid({super.key, required this.mediaList, required this.emptyMessage});

  @override
  Widget build(BuildContext context) {
    if (mediaList.isEmpty) return Center(child: Text(emptyMessage, style: const TextStyle(color: Colors.white54)));
    
    return GridView.builder(
      padding: const EdgeInsets.all(12),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        childAspectRatio: 0.65,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
      ),
      itemCount: mediaList.length,
      itemBuilder: (context, idx) {
        final item = mediaList[idx];
        return GestureDetector(
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => AutoPlayerScreen(media: item)),
          ),
          child: Container(
            decoration: BoxDecoration(
              color: const Color(0xFF16181E),
              borderRadius: BorderRadius.circular(10),
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Image.network(
                    item.posterUrl,
                    fit: BoxFit.cover,
                    width: double.infinity,
                    errorBuilder: (_, __, ___) => const ColoredBox(
                      color: Colors.black26,
                      child: Icon(Icons.movie, size: 40),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(8),
                  child: Text(
                    item.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

// ============================================================================
// 3. ADVANCED PLAYER (Episodes, Quality, Aspect Ratio)
// ============================================================================

class AutoPlayerScreen extends StatefulWidget {
  final MediaEntry media;
  const AutoPlayerScreen({super.key, required this.media});

  @override
  State<AutoPlayerScreen> createState() => _AutoPlayerScreenState();
}

class _AutoPlayerScreenState extends State<AutoPlayerScreen> {
  VideoPlayerController? _controller;
  bool _isResolving = true;
  String? _statusMessage;
  
  List<VideoStream> _episodes = [];
  int _currentEpisodeIndex = 0;
  
  // Settings States
  bool _isHighQuality = true;
  BoxFit _aspectRatio = BoxFit.contain; // Default Aspect Ratio

  @override
  void initState() {
    super.initState();
    _fetchEpisodesAndPlay();
  }

  Future<void> _fetchEpisodesAndPlay() async {
    setState(() {
      _isResolving = true;
      _statusMessage = 'Fetching episodes...';
    });

    try {
      final metaUri = Uri.parse('https://archive.org/metadata/${widget.media.identifier}');
      final response = await http.get(metaUri).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final List files = data['files'] ?? [];

        // Parse Multiple Episodes & Qualities
        Map<String, String> originalFiles = {};
        Map<String, String> sdFiles = {};

        for (final f in files) {
          final name = (f['name'] ?? '').toString();
          if (!name.endsWith('.mp4')) continue;

          final source = f['source'] ?? '';
          if (source == 'original') {
            originalFiles[name] = name;
          } else if (source == 'derivative' || name.contains('512kb')) {
            // Find corresponding SD file by removing _512kb
            String cleanName = name.replaceAll('_512kb', '');
            sdFiles[cleanName] = name;
          }
        }

        // Combine into Episode Objects
        List<VideoStream> parsedEpisodes = [];
        originalFiles.forEach((cleanName, originalName) {
          final baseUrl = 'https://archive.org/download/${widget.media.identifier}/';
          
          parsedEpisodes.add(VideoStream(
            title: cleanName.replaceAll('.mp4', ''),
            highQualityUrl: baseUrl + originalName,
            standardQualityUrl: sdFiles.containsKey(cleanName) 
                ? baseUrl + sdFiles[cleanName]! 
                : baseUrl + originalName, // Fallback to original if no SD
          ));
        });

        if (parsedEpisodes.isNotEmpty) {
          setState(() {
            _episodes = parsedEpisodes;
            _currentEpisodeIndex = 0;
          });
          await _initializePlayer();
          return;
        }
      }
      throw Exception('No playable video formats found.');
    } catch (e) {
      if (mounted) setState(() {
        _isResolving = false;
        _statusMessage = 'Playback failed: $e';
      });
    }
  }

  Future<void> _initializePlayer({Duration? seekTo}) async {
    final oldController = _controller;
    
    final currentEpisode = _episodes[_currentEpisodeIndex];
    final url = _isHighQuality ? currentEpisode.highQualityUrl : currentEpisode.standardQualityUrl;

    setState(() {
      _isResolving = true;
      _statusMessage = 'Buffering...';
    });

    final newController = VideoPlayerController.networkUrl(
      Uri.parse(url),
      httpHeaders: {'User-Agent': 'Mozilla/5.0 (Android; Mobile)'},
    );

    try {
      await newController.initialize();
      if (seekTo != null) await newController.seekTo(seekTo);
      await newController.play();

      if (mounted) {
        setState(() {
          _controller = newController;
          _isResolving = false;
        });
      }
      await oldController?.dispose();
    } catch (e) {
      if (mounted) setState(() => _statusMessage = 'Video Load Error');
    }
  }

  void _toggleWatchlist() {
    setState(() {
      if (globalWatchlist.value.contains(widget.media)) {
        globalWatchlist.value = List.from(globalWatchlist.value)..remove(widget.media);
      } else {
        globalWatchlist.value = List.from(globalWatchlist.value)..add(widget.media);
      }
    });
  }

  void _showSettingsSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF16181E),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(15))),
      builder: (context) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setModalState) {
            return Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Video Settings', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const Divider(color: Colors.white24, height: 30),
                  
                  const Text('Video Quality', style: TextStyle(color: Color(0xFFE50914))),
                  ListTile(
                    title: const Text('1080p / High (Original)'),
                    trailing: _isHighQuality ? const Icon(Icons.check, color: Color(0xFF00E676)) : null,
                    onTap: () async {
                      Navigator.pop(context);
                      if (!_isHighQuality) {
                        _isHighQuality = true;
                        final pos = await _controller?.position;
                        _initializePlayer(seekTo: pos);
                      }
                    },
                  ),
                  ListTile(
                    title: const Text('480p / Standard (Data Saver)'),
                    trailing: !_isHighQuality ? const Icon(Icons.check, color: Color(0xFF00E676)) : null,
                    onTap: () async {
                      Navigator.pop(context);
                      if (_isHighQuality) {
                        _isHighQuality = false;
                        final pos = await _controller?.position;
                        _initializePlayer(seekTo: pos);
                      }
                    },
                  ),

                  const Divider(color: Colors.white24, height: 20),
                  const Text('Aspect Ratio', style: TextStyle(color: Color(0xFFE50914))),
                  Wrap(
                    spacing: 10,
                    children: [
                      ChoiceChip(
                        label: const Text('Fit'),
                        selected: _aspectRatio == BoxFit.contain,
                        onSelected: (v) {
                          setState(() => _aspectRatio = BoxFit.contain);
                          setModalState((){});
                        },
                      ),
                      ChoiceChip(
                        label: const Text('Fill'),
                        selected: _aspectRatio == BoxFit.fill,
                        onSelected: (v) {
                          setState(() => _aspectRatio = BoxFit.fill);
                          setModalState((){});
                        },
                      ),
                      ChoiceChip(
                        label: const Text('Zoom/Cover'),
                        selected: _aspectRatio == BoxFit.cover,
                        onSelected: (v) {
                          setState(() => _aspectRatio = BoxFit.cover);
                          setModalState((){});
                        },
                      ),
                    ],
                  )
                ],
              ),
            );
          }
        );
      },
    );
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final inWatchlist = globalWatchlist.value.contains(widget.media);

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: Text(widget.media.title, style: const TextStyle(fontSize: 16)),
        actions: [
          IconButton(
            icon: Icon(inWatchlist ? Icons.bookmark : Icons.bookmark_border, color: const Color(0xFFE50914)),
            onPressed: _toggleWatchlist,
          ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // THE VIDEO PLAYER (With Aspect Ratio support)
          AspectRatio(
            aspectRatio: 16 / 9,
            child: Container(
              color: Colors.black,
              child: _controller != null && _controller!.value.isInitialized
                  ? Stack(
                      children: [
                        // Video scaling wrapper
                        SizedBox.expand(
                          child: FittedBox(
                            fit: _aspectRatio,
                            child: SizedBox(
                              width: _controller!.value.size.width,
                              height: _controller!.value.size.height,
                              child: VideoPlayer(_controller!),
                            ),
                          ),
                        ),
                        
                        // Overlays & Controls
                        Positioned.fill(
                          child: GestureDetector(
                            onTap: () {
                              setState(() {
                                _controller!.value.isPlaying ? _controller!.pause() : _controller!.play();
                              });
                            },
                            child: !_controller!.value.isPlaying
                                ? const Center(child: Icon(Icons.play_circle_fill, color: Colors.white70, size: 60))
                                : const SizedBox.shrink(),
                          ),
                        ),

                        // Settings Icon Overlay
                        Positioned(
                          top: 10,
                          right: 10,
                          child: IconButton(
                            icon: const Icon(Icons.settings, color: Colors.white, shadows: [Shadow(blurRadius: 10)]),
                            onPressed: _showSettingsSheet,
                          ),
                        ),

                        // Progress Bar
                        Positioned(
                          bottom: 0,
                          left: 0,
                          right: 0,
                          child: VideoProgressIndicator(
                            _controller!,
                            allowScrubbing: true,
                            colors: const VideoProgressColors(
                              playedColor: Color(0xFFE50914),
                              bufferedColor: Colors.white24,
                              backgroundColor: Colors.transparent,
                            ),
                          ),
                        ),
                      ],
                    )
                  : Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (_isResolving) const CircularProgressIndicator(color: Color(0xFFE50914)),
                          const SizedBox(height: 12),
                          Text(_statusMessage ?? 'Preparing...', style: const TextStyle(color: Colors.white70)),
                        ],
                      ),
                    ),
            ),
          ),
          
          // TAB UI (Episodes vs Details)
          Expanded(
            child: DefaultTabController(
              length: 2,
              child: Column(
                children: [
                  const TabBar(
                    indicatorColor: Color(0xFFE50914),
                    tabs: [
                      Tab(text: 'Episodes / Files'),
                      Tab(text: 'Details'),
                    ],
                  ),
                  Expanded(
                    child: TabBarView(
                      children: [
                        // EPISODES TAB
                        _episodes.isEmpty 
                            ? const Center(child: Text('Loading episodes...'))
                            : ListView.builder(
                                itemCount: _episodes.length,
                                itemBuilder: (ctx, i) {
                                  final ep = _episodes[i];
                                  final isPlaying = i == _currentEpisodeIndex;
                                  return ListTile(
                                    tileColor: isPlaying ? const Color(0xFFE50914).withOpacity(0.1) : null,
                                    leading: Text('${i + 1}', style: const TextStyle(fontSize: 18, color: Colors.white54)),
                                    title: Text(ep.title, maxLines: 2, overflow: TextOverflow.ellipsis),
                                    trailing: isPlaying ? const Icon(Icons.volume_up, color: Color(0xFFE50914)) : null,
                                    onTap: () {
                                      if (i != _currentEpisodeIndex) {
                                        setState(() => _currentEpisodeIndex = i);
                                        _initializePlayer();
                                      }
                                    },
                                  );
                                },
                              ),
                        
                        // DETAILS TAB
                        SingleChildScrollView(
                          padding: const EdgeInsets.all(16),
                          child: Text(
                            widget.media.description,
                            style: const TextStyle(fontSize: 14, color: Colors.white70, height: 1.5),
                          ),
                        ),
                      ],
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
}
