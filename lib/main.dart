import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:video_player/video_player.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  runApp(const UltimateStreamApp());
}

// ============================================================================
// DATA MODEL & GLOBAL WATCHLIST
// ============================================================================
class MovieMetadata {
  final int id;
  final String title;
  final String releaseYear;
  final double rating;
  final String posterUrl;
  final String description;
  final String mediaType;

  MovieMetadata({
    required this.id,
    required this.title,
    required this.releaseYear,
    required this.rating,
    required this.posterUrl,
    required this.description,
    required this.mediaType,
  });
}

final ValueNotifier<List<MovieMetadata>> globalWatchlist = ValueNotifier([]);

// ============================================================================
// MAIN APP NAVIGATION
// ============================================================================
class UltimateStreamApp extends StatelessWidget {
  const UltimateStreamApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Ultimate VOD',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF0D0E12),
        primaryColor: const Color(0xFFE50914),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFFE50914),
          surface: Color(0xFF16181F),
        ),
      ),
      home: const MainTabNavigator(),
    );
  }
}

class MainTabNavigator extends StatefulWidget {
  const MainTabNavigator({super.key});

  @override
  State<MainTabNavigator> createState() => _MainTabNavigatorState();
}

class _MainTabNavigatorState extends State<MainTabNavigator> {
  int _tab = 0;
  final List<Widget> _screens = [const CatalogScreen(), const WatchlistScreen()];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _tab, children: _screens),
      bottomNavigationBar: BottomNavigationBar(
        backgroundColor: const Color(0xFF16181F),
        selectedItemColor: const Color(0xFFE50914),
        unselectedItemColor: Colors.white54,
        currentIndex: _tab,
        onTap: (i) => setState(() => _tab = i),
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.movie_creation_outlined), label: 'Discover'),
          BottomNavigationBarItem(icon: Icon(Icons.bookmark_border), label: 'Watchlist'),
        ],
      ),
    );
  }
}

// ============================================================================
// DISCOVER TAB (TMDb METADATA SEARCH)
// ============================================================================
class CatalogScreen extends StatefulWidget {
  const CatalogScreen({super.key});

  @override
  State<CatalogScreen> createState() => _CatalogScreenState();
}

class _CatalogScreenState extends State<CatalogScreen> {
  final TextEditingController _searchCtrl = TextEditingController();
  List<MovieMetadata> _movies = [];
  bool _isLoading = false;
  Timer? _debounce;

  // Insert real TMDb API key to fetch millions of live titles
  final String _tmdbApiKey = "YOUR_TMDB_API_KEY_HERE";

  Future<void> _searchTitles(String query) async {
    final clean = query.trim();
    if (clean.isEmpty) {
      setState(() => _movies = []);
      return;
    }

    setState(() => _isLoading = true);

    try {
      if (_tmdbApiKey != "YOUR_TMDB_API_KEY_HERE") {
        final uri = Uri.parse('https://api.themoviedb.org/3/search/multi?api_key=$_tmdbApiKey&query=${Uri.encodeComponent(clean)}&include_adult=false');
        final res = await http.get(uri).timeout(const Duration(seconds: 8));
        if (res.statusCode == 200) {
          final data = json.decode(res.body);
          final List results = data['results'] ?? [];
          final List<MovieMetadata> items = [];
          
          for (final doc in results) {
            final type = doc['media_type'] ?? 'movie';
            if (type != 'movie' && type != 'tv') continue;
            
            final title = doc['title'] ?? doc['name'] ?? 'Untitled';
            final date = doc['release_date'] ?? doc['first_air_date'] ?? '';
            final posterPath = doc['poster_path'];
            
            items.add(MovieMetadata(
              id: doc['id'],
              title: title,
              releaseYear: date.length >= 4 ? date.substring(0, 4) : 'N/A',
              rating: (doc['vote_average'] as num?)?.toDouble() ?? 0.0,
              posterUrl: posterPath != null ? 'https://image.tmdb.org/t/p/w500$posterPath' : 'https://via.placeholder.com/400x600/16181F/FFFFFF?text=No+Poster',
              description: doc['overview'] ?? 'No overview available.',
              mediaType: type,
            ));
          }
          if (mounted) setState(() => _movies = items);
        }
      } else {
        // DEMO FALLBACK: Shows exactly how a real API populates data
        await Future.delayed(const Duration(milliseconds: 500));
        setState(() {
          _movies = [
            MovieMetadata(
              id: 872585, title: 'Oppenheimer', releaseYear: '2023', rating: 8.9,
              posterUrl: 'https://image.tmdb.org/t/p/w500/8Gxv8gSFCU0XGDykEGv7zR1n2ua.jpg',
              description: 'The story of J. Robert Oppenheimer’s role in the development of the atomic bomb.', mediaType: 'movie',
            ),
            MovieMetadata(
              id: 37854, title: 'One Piece', releaseYear: '1999', rating: 8.9,
              posterUrl: 'https://image.tmdb.org/t/p/w500/fcXdJUSDiDiFupuDuKFfuP2JEz5.jpg',
              description: 'Monkey D. Luffy sets out to sea to become the Pirate King.', mediaType: 'tv',
            ),
            MovieMetadata(
              id: 94605, title: 'Arcane', releaseYear: '2021', rating: 9.0,
              posterUrl: 'https://image.tmdb.org/t/p/w500/fqldf2t8ztc9aiwn397FvFeNz9H.jpg',
              description: 'Amid the conflict between the twin cities, two sisters fight on rival sides.', mediaType: 'tv',
            ),
          ].where((m) => m.title.toLowerCase().contains(clean.toLowerCase())).toList();
        });
      }
    } catch (_) {}

    if (mounted) setState(() => _isLoading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF16181F),
        title: const Text('Cinematic Library', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              controller: _searchCtrl,
              onChanged: (val) {
                _debounce?.cancel();
                _debounce = Timer(const Duration(milliseconds: 500), () => _searchTitles(val));
              },
              decoration: InputDecoration(
                hintText: 'Search Oppenheimer, Anime, Shows...',
                prefixIcon: const Icon(Icons.search, color: Color(0xFFE50914)),
                filled: true,
                fillColor: const Color(0xFF16181F),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
              ),
            ),
          ),
          if (_isLoading) const LinearProgressIndicator(color: Color(0xFFE50914), minHeight: 2),
          Expanded(
            child: GridView.builder(
              padding: const EdgeInsets.all(12),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2, childAspectRatio: 0.62, crossAxisSpacing: 12, mainAxisSpacing: 12,
              ),
              itemCount: _movies.length,
              itemBuilder: (ctx, i) {
                final movie = _movies[i];
                return GestureDetector(
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => UltimatePlayerScreen(movie: movie))),
                  child: Container(
                    decoration: BoxDecoration(color: const Color(0xFF16181F), borderRadius: BorderRadius.circular(10)),
                    clipBehavior: Clip.antiAlias,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Stack(
                            children: [
                              Image.network(movie.posterUrl, fit: BoxFit.cover, width: double.infinity, height: double.infinity),
                              Positioned(
                                top: 6, right: 6,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(color: Colors.black.withOpacity(0.8), borderRadius: BorderRadius.circular(4)),
                                  child: Row(
                                    children: [
                                      const Icon(Icons.star, color: Colors.amber, size: 12),
                                      const SizedBox(width: 3),
                                      Text(movie.rating > 0 ? movie.rating.toStringAsFixed(1) : 'NR', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.all(8),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(movie.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                              const SizedBox(height: 3),
                              Text('${movie.releaseYear} • ${movie.mediaType.toUpperCase()}', style: const TextStyle(color: Colors.white54, fontSize: 11)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// WATCHLIST VIEW
// ============================================================================
class WatchlistScreen extends StatelessWidget {
  const WatchlistScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF16181F),
        title: const Text('My Watchlist', style: TextStyle(fontWeight: FontWeight.bold)),
      ),
      body: ValueListenableBuilder<List<MovieMetadata>>(
        valueListenable: globalWatchlist,
        builder: (context, list, _) {
          if (list.isEmpty) return const Center(child: Text('Your watchlist is empty.', style: TextStyle(color: Colors.white54)));
          return ListView.builder(
            itemCount: list.length,
            itemBuilder: (ctx, i) {
              final item = list[i];
              return ListTile(
                leading: Image.network(item.posterUrl, width: 40, fit: BoxFit.cover),
                title: Text(item.title),
                subtitle: Text('${item.releaseYear} • Rating: ★ ${item.rating}'),
                trailing: const Icon(Icons.play_arrow, color: Color(0xFFE50914)),
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => UltimatePlayerScreen(movie: item))),
              );
            },
          );
        },
      ),
    );
  }
}

// ============================================================================
// ULTIMATE STREAM PLAYER (YouTube Extraction + Gestures + Settings)
// ============================================================================
class UltimatePlayerScreen extends StatefulWidget {
  final MovieMetadata movie;
  const UltimatePlayerScreen({super.key, required this.movie});

  @override
  State<UltimatePlayerScreen> createState() => _UltimatePlayerScreenState();
}

class _UltimatePlayerScreenState extends State<UltimatePlayerScreen> {
  VideoPlayerController? _controller;
  bool _isInit = false;
  String _statusMessage = "Connecting to streaming servers...";

  // Gestures & Playback
  double _volume = 1.0;
  double _brightness = 1.0;
  bool _isDragging = false;
  String _dragLabel = "";
  double _dragValue = 0.0;
  bool _isLeftHalf = false;

  bool _isFullscreen = false;
  bool _showControls = true;
  Timer? _hideControlsTimer;

  // Advanced Settings
  bool _isMirrored = false;
  BoxFit _aspectRatio = BoxFit.contain;
  bool _showSubtitles = true;
  String _selectedLang = 'English';

  @override
  void initState() {
    super.initState();
    _extractAndPlay();
  }

  // ------------------------------------------------------------------------
  // THE MAGIC: Silent YouTube Search & MP4 Extraction
  // ------------------------------------------------------------------------
  Future<void> _extractAndPlay() async {
    final yt = YoutubeExplode();
    try {
      // 1. Search YouTube for the video (Appending 'trailer' ensures we get a safe MP4 file to test playback)
      final query = '${widget.movie.title} official trailer';
      setState(() => _statusMessage = 'Searching streams for "$query"...');
      
      final searchResults = await yt.search.search(query);
      if (searchResults.isEmpty) throw Exception("No streams found");
      final videoId = searchResults.first.id;

      // 2. Extract the hidden MP4 Manifest
      setState(() => _statusMessage = 'Extracting secure stream manifest...');
      final manifest = await yt.videos.streamsClient.getManifest(videoId);
      final streamInfo = manifest.muxed.withHighestVideoQuality();
      
      // 3. Mount the raw MP4 into the Flutter Native Player
      setState(() => _statusMessage = 'Buffering high-speed stream...');
      _controller = VideoPlayerController.networkUrl(Uri.parse(streamInfo.url.toString()));
      
      await _controller!.initialize();
      await _controller!.play();
      
      if (mounted) {
        setState(() => _isInit = true);
        _startHideControlsTimer();
      }
    } catch (e) {
      if (mounted) setState(() => _statusMessage = 'Stream blocked or unavailable. Error: $e');
    } finally {
      yt.close();
    }
  }

  // --- PLAYER CONTROLS ---
  void _startHideControlsTimer() {
    _hideControlsTimer?.cancel();
    setState(() => _showControls = true);
    _hideControlsTimer = Timer(const Duration(seconds: 4), () {
      if (mounted && _controller != null && _controller!.value.isPlaying && !_isDragging) {
        setState(() => _showControls = false);
      }
    });
  }

  void _togglePlayPause() {
    if (_controller == null) return;
    setState(() {
      _controller!.value.isPlaying ? _controller!.pause() : _controller!.play();
    });
    _startHideControlsTimer();
  }

  void _skip(int seconds) async {
    if (_controller == null) return;
    final pos = await _controller!.position;
    if (pos != null) {
      _controller!.seekTo(pos + Duration(seconds: seconds));
      _startHideControlsTimer();
    }
  }

  void _toggleFullscreen() {
    setState(() => _isFullscreen = !_isFullscreen);
    if (_isFullscreen) {
      SystemChrome.setPreferredOrientations([DeviceOrientation.landscapeRight, DeviceOrientation.landscapeLeft]);
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    } else {
      SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    }
  }

  String _formatTime(Duration d) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final h = d.inHours;
    final m = twoDigits(d.inMinutes.remainder(60));
    final s = twoDigits(d.inSeconds.remainder(60));
    return h > 0 ? '${twoDigits(h)}:$m:$s' : '$m:$s';
  }

  // --- SETTINGS SHEET ---
  void _showSettingsSheet() {
    _hideControlsTimer?.cancel();
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF16181F),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(15))),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setModalState) {
            return SafeArea(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Player Settings', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    const Divider(color: Colors.white24, height: 30),
                    
                    // MIRROR FIX UPGRADE
                    SwitchListTile(
                      title: const Text('Fix Mirrored Video'),
                      subtitle: const Text('Flips horizontally bypassed uploads', style: TextStyle(color: Colors.white54, fontSize: 11)),
                      value: _isMirrored,
                      activeColor: const Color(0xFFE50914),
                      onChanged: (val) {
                        setState(() => _isMirrored = val);
                        setModalState((){});
                      },
                    ),

                    // ASPECT RATIO UPGRADE
                    const SizedBox(height: 10),
                    const Text('Aspect Ratio', style: TextStyle(color: Color(0xFFE50914))),
                    Wrap(
                      spacing: 10,
                      children: [
                        ChoiceChip(
                          label: const Text('Fit'), selected: _aspectRatio == BoxFit.contain,
                          selectedColor: const Color(0xFFE50914),
                          onSelected: (v) { setState(() => _aspectRatio = BoxFit.contain); setModalState((){}); },
                        ),
                        ChoiceChip(
                          label: const Text('Stretch'), selected: _aspectRatio == BoxFit.fill,
                          selectedColor: const Color(0xFFE50914),
                          onSelected: (v) { setState(() => _aspectRatio = BoxFit.fill); setModalState((){}); },
                        ),
                        ChoiceChip(
                          label: const Text('Zoom'), selected: _aspectRatio == BoxFit.cover,
                          selectedColor: const Color(0xFFE50914),
                          onSelected: (v) { setState(() => _aspectRatio = BoxFit.cover); setModalState((){}); },
                        ),
                      ],
                    ),
                    const Divider(color: Colors.white24, height: 30),

                    // SUBTITLE & DUB MOCK
                    SwitchListTile(
                      title: const Text('Show Subtitles'),
                      value: _showSubtitles,
                      activeColor: const Color(0xFFE50914),
                      onChanged: (val) { setState(() => _showSubtitles = val); setModalState((){}); },
                    ),
                    ListTile(
                      title: const Text('Audio Language'),
                      trailing: Text(_selectedLang, style: const TextStyle(color: Color(0xFFE50914))),
                      onTap: () {
                        setState(() => _selectedLang = _selectedLang == 'English' ? 'Hindi' : 'English');
                        setModalState((){});
                      },
                    ),
                  ],
                ),
              ),
            );
          }
        );
      },
    ).then((_) => _startHideControlsTimer());
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
    final inWatchlist = globalWatchlist.value.contains(widget.movie);

    Widget playerUI = Container(
      color: Colors.black,
      child: _isInit && _controller != null
          ? GestureDetector(
              onTap: () {
                _showControls ? setState(() => _showControls = false) : _startHideControlsTimer();
              },
              // GESTURES: Brightness & Volume
              onVerticalDragStart: (details) {
                _isLeftHalf = details.localPosition.dx < MediaQuery.of(context).size.width / 2;
                setState(() => _isDragging = true);
              },
              onVerticalDragUpdate: (details) {
                double delta = -details.primaryDelta! / 200;
                setState(() {
                  if (_isLeftHalf) {
                    _volume = (_volume + delta).clamp(0.0, 1.0);
                    _controller!.setVolume(_volume);
                    _dragLabel = "Volume"; _dragValue = _volume;
                  } else {
                    _brightness = (_brightness + delta).clamp(0.0, 1.0);
                    _dragLabel = "Brightness"; _dragValue = _brightness;
                  }
                });
              },
              onVerticalDragEnd: (_) => setState(() => _isDragging = false),
              child: Stack(
                children: [
                  // 1. VIDEO LAYER WITH ASPECT RATIO AND MIRROR FIX
                  SizedBox.expand(
                    child: FittedBox(
                      fit: _aspectRatio,
                      child: SizedBox(
                        width: _controller!.value.size.width, height: _controller!.value.size.height,
                        child: Transform.flip(
                          flipX: _isMirrored,
                          child: VideoPlayer(_controller!),
                        ),
                      ),
                    ),
                  ),

                  // 2. BRIGHTNESS OVERLAY TRICK
                  IgnorePointer(
                    child: Container(color: Colors.black.withOpacity(1.0 - _brightness)),
                  ),

                  // 3. SUBTITLE RENDERER
                  if (_showSubtitles)
                    Positioned(
                      bottom: _isFullscreen ? 70 : 50, left: 20, right: 20,
                      child: ValueListenableBuilder(
                        valueListenable: _controller!,
                        builder: (ctx, VideoPlayerValue val, _) {
                          bool show = val.position.inSeconds % 6 < 4; // Mock logic
                          return show ? Container(
                            padding: const EdgeInsets.all(8), color: Colors.black54,
                            child: const Text("[English Subtitles]\nPlaying extracted stream...", textAlign: TextAlign.center, style: TextStyle(color: Colors.white)),
                          ) : const SizedBox.shrink();
                        },
                      ),
                    ),

                  // 4. GESTURE FEEDBACK WIDGET
                  if (_isDragging)
                    Center(
                      child: Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(color: Colors.black87, borderRadius: BorderRadius.circular(10)),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(_isLeftHalf ? Icons.volume_up : Icons.brightness_6, color: Colors.white, size: 36),
                            const SizedBox(height: 8),
                            Text('${(_dragValue * 100).toInt()}%', style: const TextStyle(fontSize: 16, color: Colors.white)),
                          ],
                        ),
                      ),
                    ),

                  // 5. CONTROLS OVERLAY
                  if (_showControls && !_isDragging) ...[
                    Container(decoration: const BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Colors.black54, Colors.transparent, Colors.black87], stops: [0.0, 0.5, 1.0]))),
                    
                    Positioned(
                      top: 10, right: 10,
                      child: SafeArea(
                        child: IconButton(icon: const Icon(Icons.settings, color: Colors.white, size: 28), onPressed: _showSettingsSheet),
                      ),
                    ),

                    // CENTER 10s SKIP & PLAY BUTTONS
                    Center(
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          IconButton(iconSize: 42, icon: const Icon(Icons.replay_10, color: Colors.white), onPressed: () => _skip(-10)),
                          const SizedBox(width: 20),
                          IconButton(
                            iconSize: 64,
                            icon: Icon(_controller!.value.isPlaying ? Icons.pause_circle_filled : Icons.play_circle_filled, color: Colors.white),
                            onPressed: _togglePlayPause,
                          ),
                          const SizedBox(width: 20),
                          IconButton(iconSize: 42, icon: const Icon(Icons.forward_10, color: Colors.white), onPressed: () => _skip(10)),
                        ],
                      ),
                    ),

                    // DRAGGABLE REAL-TIME SEEKBAR
                    Positioned(
                      bottom: 10, left: 10, right: 10,
                      child: SafeArea(
                        child: ValueListenableBuilder(
                          valueListenable: _controller!,
                          builder: (context, VideoPlayerValue val, child) {
                            final max = val.duration.inMilliseconds > 0 ? val.duration.inMilliseconds.toDouble() : 1.0;
                            final current = val.position.inMilliseconds.toDouble().clamp(0.0, max);
                            return Row(
                              children: [
                                Text(_formatTime(val.position), style: const TextStyle(color: Colors.white, fontSize: 12)),
                                Expanded(
                                  child: SliderTheme(
                                    data: SliderThemeData(
                                      thumbColor: const Color(0xFFE50914), activeTrackColor: const Color(0xFFE50914), inactiveTrackColor: Colors.white30,
                                      trackHeight: 3.0, thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6.0),
                                    ),
                                    child: Slider(
                                      min: 0.0, max: max, value: current,
                                      onChanged: (pos) => _controller!.seekTo(Duration(milliseconds: pos.toInt())),
                                    ),
                                  ),
                                ),
                                Text(_formatTime(val.duration), style: const TextStyle(color: Colors.white, fontSize: 12)),
                                IconButton(
                                  icon: Icon(_isFullscreen ? Icons.fullscreen_exit : Icons.fullscreen, color: Colors.white),
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
                  const CircularProgressIndicator(color: Color(0xFFE50914)),
                  const SizedBox(height: 16),
                  Text(_statusMessage, style: const TextStyle(color: Colors.white70, fontSize: 12)),
                ],
              ),
            ),
    );

    // FULLSCREEN OVERRIDE
    if (_isFullscreen) return Scaffold(backgroundColor: Colors.black, body: playerUI);

    // PORTRAIT UI
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.black, title: Text(widget.movie.title, style: const TextStyle(fontSize: 16)),
        actions: [
          IconButton(
            icon: Icon(inWatchlist ? Icons.bookmark : Icons.bookmark_border, color: const Color(0xFFE50914)),
            onPressed: () => setState(() => inWatchlist ? globalWatchlist.value = List.from(globalWatchlist.value)..remove(widget.movie) : globalWatchlist.value = List.from(globalWatchlist.value)..add(widget.movie)),
          ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AspectRatio(aspectRatio: 16 / 9, child: playerUI),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(widget.movie.title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 6),
                  Text('${widget.movie.releaseYear} • Rating: ★ ${widget.movie.rating}', style: const TextStyle(color: Color(0xFFE50914), fontWeight: FontWeight.bold)),
                  const Divider(height: 24, color: Colors.white12),
                  const Text('Overview', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                  const SizedBox(height: 6),
                  Text(widget.movie.description, style: const TextStyle(color: Colors.white70, fontSize: 13, height: 1.4)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
