import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:video_player/video_player.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  runApp(const ProStreamApp());
}

// ============================================================================
// GLOBAL STATE
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
// MAIN APP
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
// DISCOVER TAB
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
// WATCHLIST TAB
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
// ULTIMATE ADVANCED PLAYER
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
  
  // App States
  bool _isHighQuality = true;
  String _selectedLanguage = 'English'; 
  bool _showSubtitles = true; 
  BoxFit _aspectRatio = BoxFit.contain;
  
  bool _isFullscreen = false;
  bool _showControls = true;
  Timer? _hideControlsTimer;

  // Gesture Controls (Volume & Brightness)
  double _volume = 1.0;
  double _brightness = 1.0; 
  bool _isDragging = false;
  String _dragLabel = "";
  double _dragPercentage = 0.0;
  bool _isLeftHalf = false;

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
            standardQualityUrl: sdFiles.containsKey(cleanName) ? baseUrl + sdFiles[cleanName]! : baseUrl + originalName,
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
      if (mounted) setState(() => _statusMessage = 'Playback failed: $e');
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
      newController.setVolume(_volume);
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

  // --- PLAYER CONTROLS ---
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
      if (_controller!.value.isPlaying) {
        _controller!.pause();
        _showControls = true;
        _hideControlsTimer?.cancel();
      } else {
        _controller!.play();
        _startHideControlsTimer();
      }
    });
  }

  void _skipForward(int seconds) async {
    if (_controller == null) return;
    final pos = await _controller!.position;
    if (pos != null) {
      _controller!.seekTo(pos + Duration(seconds: seconds));
      _startHideControlsTimer();
    }
  }

  // --- SETTINGS SHEET ---
  void _showSettingsSheet() {
    _hideControlsTimer?.cancel();
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
                  const Text('Player Settings', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const Divider(color: Colors.white24, height: 30),
                  
                  const Text('Subtitles & Audio', style: TextStyle(color: Color(0xFFE50914))),
                  SwitchListTile(
                    title: const Text('English Subtitles'),
                    value: _showSubtitles,
                    activeColor: const Color(0xFFE50914),
                    onChanged: (val) {
                      setState(() => _showSubtitles = val);
                      setModalState((){});
                    },
                  ),
                  ListTile(
                    title: const Text('Audio Language'),
                    subtitle: Text(_selectedLanguage, style: const TextStyle(color: Colors.white54)),
                    trailing: const Icon(Icons.arrow_forward_ios, size: 14),
                    onTap: () {
                      setState(() => _selectedLanguage = _selectedLanguage == 'English' ? 'Hindi' : 'English');
                      setModalState((){});
                    },
                  ),
                  const Divider(color: Colors.white24, height: 20),
                  
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
              onTap: () {
                if (_showControls) {
                  setState(() => _showControls = false);
                } else {
                  _startHideControlsTimer();
                }
              },
              // Vertical Drag for Volume and Brightness
              onVerticalDragStart: (details) {
                final screenWidth = MediaQuery.of(context).size.width;
                _isLeftHalf = details.localPosition.dx < screenWidth / 2;
                setState(() => _isDragging = true);
                _hideControlsTimer?.cancel(); // keep controls hidden or visible while dragging
              },
              onVerticalDragUpdate: (details) {
                // Moving UP is negative delta. So subtracting negative increases value.
                double delta = -details.primaryDelta! / 200; 
                setState(() {
                  if (_isLeftHalf) {
                    _volume = (_volume + delta).clamp(0.0, 1.0);
                    _controller!.setVolume(_volume);
                    _dragLabel = "Volume";
                    _dragPercentage = _volume;
                  } else {
                    _brightness = (_brightness + delta).clamp(0.0, 1.0);
                    _dragLabel = "Brightness";
                    _dragPercentage = _brightness;
                  }
                });
              },
              onVerticalDragEnd: (details) {
                setState(() => _isDragging = false);
                _startHideControlsTimer();
              },
              child: Stack(
                children: [
                  // 1. VIDEO LAYER
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

                  // 2. BRIGHTNESS OVERLAY (Clever Trick: Black box with variable opacity)
                  IgnorePointer(
                    child: Container(
                      color: Colors.black.withOpacity(1.0 - _brightness),
                    ),
                  ),

                  // 3. SUBTITLES (Architecture Example)
                  if (_showSubtitles)
                    Positioned(
                      bottom: _isFullscreen ? 70 : 50,
                      left: 20, right: 20,
                      child: ValueListenableBuilder(
                        valueListenable: _controller!,
                        builder: (context, VideoPlayerValue value, child) {
                          // Simulating dynamic subtitles based on time
                          bool show = value.position.inSeconds % 5 < 3; 
                          return show ? Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            color: Colors.black54,
                            child: const Text(
                              "[English Subtitles On]\nSimulated dialogue processing...", 
                              textAlign: TextAlign.center, 
                              style: TextStyle(color: Colors.white, fontSize: 14)
                            ),
                          ) : const SizedBox.shrink();
                        },
                      ),
                    ),
                  
                  // 4. GESTURE FEEDBACK OVERLAY (Volume/Brightness Icon)
                  if (_isDragging)
                    Center(
                      child: Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(color: Colors.black87, borderRadius: BorderRadius.circular(10)),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              _isLeftHalf ? Icons.volume_up : Icons.brightness_6, 
                              color: Colors.white, size: 36
                            ),
                            const SizedBox(height: 8),
                            Text('${(_dragPercentage * 100).toInt()}%', style: const TextStyle(fontSize: 16)),
                          ],
                        ),
                      ),
                    ),

                  // 5. CONTROLS OVERLAY
                  if (_showControls && !_isDragging) ...[
                    Container(
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter, end: Alignment.bottomCenter,
                          colors: [Colors.black54, Colors.transparent, Colors.black87],
                          stops: [0.0, 0.5, 1.0],
                        ),
                      ),
                    ),
                    
                    Positioned(
                      top: 10, right: 10,
                      child: SafeArea(
                        child: IconButton(
                          icon: const Icon(Icons.settings, color: Colors.white, size: 28),
                          onPressed: _showSettingsSheet,
                        ),
                      ),
                    ),

                    // CENTER SKIP / PLAY ROW
                    Center(
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          IconButton(
                            iconSize: 42,
                            icon: const Icon(Icons.replay_10, color: Colors.white),
                            onPressed: () => _skipForward(-10),
                          ),
                          const SizedBox(width: 20),
                          IconButton(
                            iconSize: 64,
                            icon: Icon(
                              _controller!.value.isPlaying ? Icons.pause_circle_filled : Icons.play_circle_filled,
                              color: Colors.white,
                            ),
                            onPressed: _togglePlayPause,
                          ),
                          const SizedBox(width: 20),
                          IconButton(
                            iconSize: 42,
                            icon: const Icon(Icons.forward_10, color: Colors.white),
                            onPressed: () => _skipForward(10),
                          ),
                        ],
                      ),
                    ),

                    // SEEKBAR & REAL TIMERS
                    Positioned(
                      bottom: 10, left: 10, right: 10,
                      child: SafeArea(
                        child: ValueListenableBuilder(
                          valueListenable: _controller!,
                          builder: (context, VideoPlayerValue value, child) {
                            final position = value.position;
                            final duration = value.duration;
                            
                            // Safety check for dynamic duration length
                            final maxDuration = duration.inMilliseconds > 0 ? duration.inMilliseconds.toDouble() : 1.0;
                            final currentPos = position.inMilliseconds.toDouble().clamp(0.0, maxDuration);

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
                                      max: maxDuration,
                                      value: currentPos,
                                      onChanged: (val) {
                                        _controller!.seekTo(Duration(milliseconds: val.toInt()));
                                      },
                                    ),
                                  ),
                                ),
                                // REAL DURATION DISPLAYED HERE
                                Text(_formatDuration(duration), style: const TextStyle(color: Colors.white, fontSize: 12)),
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
                  if (_isResolving) const CircularProgressIndicator(color: Color(0xFFE50914)),
                  const SizedBox(height: 12),
                  Text(_statusMessage ?? 'Preparing...', style: const TextStyle(color: Colors.white70)),
                ],
              ),
            ),
    );

    if (_isFullscreen) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: playerUI,
      );
    }

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
                    tabs: [Tab(text: 'Episodes / Files'), Tab(text: 'Details')],
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
