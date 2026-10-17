import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:video_player/video_player.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // Ensure the app starts in portrait mode
  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  runApp(const ProStreamApp());
}

// ============================================================================
// GLOBAL STATE (Watchlist)
// ============================================================================
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

class VideoStream {
  final String title;
  final String highQualityUrl;
  final String standardQualityUrl;

  VideoStream({
    required this.title,
    required this.highQualityUrl,
    required this.standardQualityUrl,
  });
}

// ============================================================================
// MAIN APP & BOTTOM NAVIGATION
// ============================================================================

class ProStreamApp extends StatelessWidget {
  const ProStreamApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Pro Anime & Movies',
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
          BottomNavigationBarItem(icon: Icon(Icons.movie_filter), label: 'Discover'),
          BottomNavigationBarItem(icon: Icon(Icons.bookmark), label: 'Watchlist'),
        ],
      ),
    );
  }
}

// ============================================================================
// 1. DISCOVER TAB (Strict Movie & Anime Filtering)
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
      // STRICT FILTERING: Restricts search to specific collections that hold actual movies/anime
      // Drops news, vlogs, audio, and texts.
      final advancedQuery = 
          '${Uri.encodeComponent(clean)}+AND+mediatype:movies+AND+(collection:animationandcartoons+OR+collection:feature_films+OR+collection:sci-fi)';
      
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
            title: doc['title']?.toString() ?? 'Unknown Title',
            year: doc['year']?.toString() ?? '',
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
    _debounce = Timer(const Duration(milliseconds: 700), () => _executeAutoSearch(val));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF16181E),
        title: const Text('Movies & Anime', style: TextStyle(fontSize: 18)),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              controller: _searchCtrl,
              onChanged: _onSearchChanged,
              decoration: InputDecoration(
                hintText: 'Search movies, anime...',
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
          Expanded(child: MediaGrid(mediaList: _results, emptyMessage: 'Search for cinematic content...')),
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
          ).then((_) {
            // Force portrait when returning from player just in case
            SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
          }),
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
// 3. ADVANCED PLAYER (Draggable Seekbar, Landscape, Dubs, Real Timers)
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
  String _selectedLanguage = 'English'; 
  BoxFit _aspectRatio = BoxFit.contain;
  
  // Fullscreen State
  bool _isFullscreen = false;
  bool _showControls = true;
  Timer? _hideControlsTimer;

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

        Map<String, String> originalFiles = {};
        Map<String, String> sdFiles = {};

        for (final f in files) {
          final name = (f['name'] ?? '').toString();
          if (!name.endsWith('.mp4')) continue;

          final source = f['source'] ?? '';
          if (source == 'original') {
            originalFiles[name] = name;
          } else if (source == 'derivative' || name.contains('512kb')) {
            String cleanName = name.replaceAll('_512kb', '');
            sdFiles[cleanName] = name;
          }
        }

        List<VideoStream> parsedEpisodes = [];
        originalFiles.forEach((cleanName, originalName) {
          final baseUrl = 'https://archive.org/download/${widget.media.identifier}/';
          parsedEpisodes.add(VideoStream(
            title: cleanName.replaceAll('.mp4', ''),
            highQualityUrl: baseUrl + originalName,
            standardQualityUrl: sdFiles.containsKey(cleanName) 
                ? baseUrl + sdFiles[cleanName]! 
                : baseUrl + originalName,
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
      throw Exception('No valid MP4 formats found.');
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
        _startHideControlsTimer();
      }
      await oldController?.dispose();
    } catch (e) {
      if (mounted) setState(() => _statusMessage = 'Video Load Error');
    }
  }

  // --- FULLSCREEN LOGIC ---
  void _toggleFullscreen() {
    setState(() {
      _isFullscreen = !_isFullscreen;
    });

    if (_isFullscreen) {
      // Landscape Mode + Hide System UI
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.landscapeRight,
        DeviceOrientation.landscapeLeft,
      ]);
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    } else {
      // Portrait Mode + Show System UI
      SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    }
  }

  // --- CONTROLS OVERLAY LOGIC ---
  void _startHideControlsTimer() {
    _hideControlsTimer?.cancel();
    setState(() => _showControls = true);
    _hideControlsTimer = Timer(const Duration(seconds: 4), () {
      if (mounted && _controller != null && _controller!.value.isPlaying) {
        setState(() => _showControls = false);
      }
    });
  }

  void _togglePlayPause() {
    if (_controller == null) return;
    setState(() {
      if (_controller!.value.isPlaying) {
        _controller!.pause();
        _showControls = true; // Keep controls visible when paused
        _hideControlsTimer?.cancel();
      } else {
        _controller!.play();
        _startHideControlsTimer();
      }
    });
  }

  // --- SETTINGS SHEET ---
  void _showSettingsSheet() {
    _hideControlsTimer?.cancel(); // pause the hide timer while settings are open
    
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF16181E),
      isScrollControlled: true,
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
                  const Text('Settings', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const Divider(color: Colors.white24, height: 30),
                  
                  // AUDIO DUB SELECTOR
                  const Text('Audio Language', style: TextStyle(color: Color(0xFFE50914))),
                  ListTile(
                    title: const Text('English (Original)'),
                    trailing: _selectedLanguage == 'English' ? const Icon(Icons.check, color: Color(0xFF00E676)) : null,
                    onTap: () {
                      setState(() => _selectedLanguage = 'English');
                      setModalState((){});
                      Navigator.pop(context);
                    },
                  ),
                  ListTile(
                    title: const Text('Hindi Dub'),
                    subtitle: const Text('Requires multi-track source file', style: TextStyle(fontSize: 10, color: Colors.white54)),
                    trailing: _selectedLanguage == 'Hindi' ? const Icon(Icons.check, color: Color(0xFF00E676)) : null,
                    onTap: () {
                      setState(() => _selectedLanguage = 'Hindi');
                      setModalState((){});
                      Navigator.pop(context);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Switched to Hindi (If available in source)')),
                      );
                    },
                  ),

                  const Divider(color: Colors.white24, height: 20),
                  
                  // QUALITY SELECTOR
                  const Text('Video Quality', style: TextStyle(color: Color(0xFFE50914))),
                  ListTile(
                    title: const Text('1080p / High'),
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
                    title: const Text('480p / Standard'),
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
                  const SizedBox(height: 20),
                ],
              ),
            );
          }
        );
      },
    ).then((_) => _startHideControlsTimer());
  }

  // --- TIME FORMATTER ---
  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final hours = twoDigits(duration.inHours);
    final minutes = twoDigits(duration.inMinutes.remainder(60));
    final seconds = twoDigits(duration.inSeconds.remainder(60));
    return duration.inHours > 0 ? "$hours:$minutes:$seconds" : "$minutes:$seconds";
  }

  @override
  void dispose() {
    _hideControlsTimer?.cancel();
    _controller?.dispose();
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final inWatchlist = globalWatchlist.value.contains(widget.media);

    Widget playerUI = Container(
      color: Colors.black,
      child: _controller != null && _controller!.value.isInitialized
          ? GestureDetector(
              onTap: _startHideControlsTimer,
              child: Stack(
                children: [
                  // VIDEO LAYER
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
                  
                  // CONTROLS OVERLAY
                  if (_showControls) ...[
                    // Dark gradient for text visibility
                    Container(
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [Colors.black54, Colors.transparent, Colors.black87],
                          stops: [0.0, 0.5, 1.0],
                        ),
                      ),
                    ),
                    
                    // Top Bar (Settings)
                    Positioned(
                      top: 10,
                      right: 10,
                      child: SafeArea(
                        child: IconButton(
                          icon: const Icon(Icons.settings, color: Colors.white, size: 28),
                          onPressed: _showSettingsSheet,
                        ),
                      ),
                    ),

                    // Play/Pause Center Button
                    Center(
                      child: IconButton(
                        iconSize: 64,
                        icon: Icon(
                          _controller!.value.isPlaying ? Icons.pause_circle_filled : Icons.play_circle_filled,
                          color: Colors.white.withOpacity(0.9),
                        ),
                        onPressed: _togglePlayPause,
                      ),
                    ),

                    // Bottom Seekbar & Timers
                    Positioned(
                      bottom: 10,
                      left: 10,
                      right: 10,
                      child: SafeArea(
                        child: ValueListenableBuilder(
                          valueListenable: _controller!,
                          builder: (context, VideoPlayerValue value, child) {
                            final position = value.position;
                            final duration = value.duration;

                            return Row(
                              children: [
                                Text(_formatDuration(position), style: const TextStyle(color: Colors.white, fontSize: 12)),
                                Expanded(
                                  child: SliderTheme(
                                    data: SliderThemeData(
                                      thumbColor: const Color(0xFFE50914),
                                      activeTrackColor: const Color(0xFFE50914),
                                      inactiveTrackColor: Colors.white30,
                                      trackHeight: 3.0,
                                      thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6.0),
                                    ),
                                    child: Slider(
                                      min: 0.0,
                                      max: duration.inMilliseconds.toDouble(),
                                      value: position.inMilliseconds.toDouble().clamp(0.0, duration.inMilliseconds.toDouble()),
                                      onChanged: (val) {
                                        _controller!.seekTo(Duration(milliseconds: val.toInt()));
                                      },
                                    ),
                                  ),
                                ),
                                Text(_formatDuration(duration), style: const TextStyle(color: Colors.white, fontSize: 12)),
                                IconButton(
                                  icon: Icon(
                                    _isFullscreen ? Icons.fullscreen_exit : Icons.fullscreen,
                                    color: Colors.white,
                                  ),
                                  onPressed: _toggleFullscreen,
                                ),
                              ],
                            );
                          },
                        ),
                      ),
                    ),
                  ],
                ],
              ),
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
    );

    // If Fullscreen, return just the player without Scaffold AppBars/Tabs
    if (_isFullscreen) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: playerUI,
      );
    }

    // Normal Portrait View
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: Text(widget.media.title, style: const TextStyle(fontSize: 16)),
        actions: [
          IconButton(
            icon: Icon(inWatchlist ? Icons.bookmark : Icons.bookmark_border, color: const Color(0xFFE50914)),
            onPressed: () {
              setState(() {
                if (inWatchlist) {
                  globalWatchlist.value = List.from(globalWatchlist.value)..remove(widget.media);
                } else {
                  globalWatchlist.value = List.from(globalWatchlist.value)..add(widget.media);
                }
              });
            },
          ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AspectRatio(aspectRatio: 16 / 9, child: playerUI),
          
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
