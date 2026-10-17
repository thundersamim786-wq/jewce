import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:video_player/video_player.dart';

// ============================================================================
// GLOBAL STATE (For Educational Purposes - Watchlist)
// ============================================================================
final ValueNotifier<List<MediaEntry>> globalWatchlist = ValueNotifier([]);

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const UltimateStreamApp());
}

class UltimateStreamApp extends StatelessWidget {
  const UltimateStreamApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Stream UI Pro',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF0B0C10),
        primaryColor: const Color(0xFFE50914),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFFE50914),
          surface: Color(0xFF16181E),
        ),
      ),
      home: const MainNavigation(),
    );
  }
}

// ============================================================================
// DATA MODELS
// ============================================================================
class MediaEntry {
  final String identifier;
  final String title;
  final String year;
  final String description;
  final String posterUrl;
  final bool isAnime;

  MediaEntry({
    required this.identifier,
    required this.title,
    required this.year,
    required this.description,
    required this.posterUrl,
    this.isAnime = false,
  });
}

// ============================================================================
// BOTTOM NAVIGATION WRAPPER
// ============================================================================
class MainNavigation extends StatefulWidget {
  const MainNavigation({super.key});

  @override
  State<MainNavigation> createState() => _MainNavigationState();
}

class _MainNavigationState extends State<MainNavigation> {
  int _currentIndex = 0;

  final List<Widget> _screens = [
    const AutoCatalogScreen(title: 'Movies & Series', baseFilter: ''),
    const AutoCatalogScreen(
        title: 'Anime Hub',
        baseFilter: 'AND (collection:anime OR subject:animation)'),
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
        onTap: (idx) => setState(() => _currentIndex = idx),
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home), label: 'Home'),
          BottomNavigationBarItem(
              icon: Icon(Icons.animation), label: 'Anime'),
          BottomNavigationBarItem(
              icon: Icon(Icons.bookmark), label: 'Watchlist'),
        ],
      ),
    );
  }
}

// ============================================================================
// DYNAMIC CATALOG (Search + API Filter)
// ============================================================================
class AutoCatalogScreen extends StatefulWidget {
  final String title;
  final String baseFilter;

  const AutoCatalogScreen(
      {super.key, required this.title, required this.baseFilter});

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
      // API Query Builder: Automatically removes tiktok/shorts/vlogs
      final String filterOutSocialMedia =
          'AND NOT subject:(tiktok OR shorts OR reels OR vlog)';
      final uri = Uri.parse(
        'https://archive.org/advancedsearch.php?q=(${Uri.encodeComponent(clean)})+AND+mediatype:movies+${widget.baseFilter}+$filterOutSocialMedia&fl[]=identifier,title,description,year&rows=20&output=json',
      );

      final response = await http.get(uri).timeout(const Duration(seconds: 8));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final List docs = data['response']['docs'] ?? [];

        final List<MediaEntry> parsed = docs.map((doc) {
          final id = doc['identifier']?.toString() ?? '';
          return MediaEntry(
            identifier: id,
            title: doc['title']?.toString() ?? 'Untitled',
            year: doc['year']?.toString() ?? 'Unknown',
            description: doc['description']?.toString() ?? 'No synopsis.',
            posterUrl: 'https://archive.org/services/img/$id',
            isAnime: widget.baseFilter.contains('anime'),
          );
        }).toList();

        if (mounted) {
          setState(() {
            _results = parsed;
            _isLoading = false;
          });
        }
        return;
      }
    } catch (e) {
      debugPrint('Search error: $e');
    }

    if (mounted) setState(() => _isLoading = false);
  }

  void _onSearchChanged(String val) {
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    _debounce = Timer(const Duration(milliseconds: 600), () {
      _executeAutoSearch(val);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF16181E),
        title: Text(widget.title,
            style: const TextStyle(fontWeight: FontWeight.bold)),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              controller: _searchCtrl,
              onChanged: _onSearchChanged,
              decoration: InputDecoration(
                hintText: 'Search titles...',
                prefixIcon: const Icon(Icons.search, color: Color(0xFF00E676)),
                filled: true,
                fillColor: const Color(0xFF16181E),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          if (_isLoading)
            const LinearProgressIndicator(color: Color(0xFF00E676), minHeight: 2),
          Expanded(
            child: _results.isEmpty && !_isLoading
                ? const Center(
                    child: Text('Type to search for movies/series.',
                        style: TextStyle(color: Colors.white54)))
                : GridView.builder(
                    padding: const EdgeInsets.all(12),
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      childAspectRatio: 0.65,
                      crossAxisSpacing: 12,
                      mainAxisSpacing: 12,
                    ),
                    itemCount: _results.length,
                    itemBuilder: (context, idx) => MediaCard(media: _results[idx]),
                  ),
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// WATCHLIST SCREEN
// ============================================================================
class WatchlistScreen extends StatelessWidget {
  const WatchlistScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF16181E),
        title: const Text('My Watchlist',
            style: TextStyle(fontWeight: FontWeight.bold)),
      ),
      body: ValueListenableBuilder<List<MediaEntry>>(
        valueListenable: globalWatchlist,
        builder: (context, list, child) {
          if (list.isEmpty) {
            return const Center(
              child: Text('Your watchlist is empty.',
                  style: TextStyle(color: Colors.white54)),
            );
          }
          return GridView.builder(
            padding: const EdgeInsets.all(12),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              childAspectRatio: 0.65,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
            ),
            itemCount: list.length,
            itemBuilder: (context, idx) => MediaCard(media: list[idx]),
          );
        },
      ),
    );
  }
}

class MediaCard extends StatelessWidget {
  final MediaEntry media;
  const MediaCard({super.key, required this.media});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => AutoPlayerScreen(media: media)),
        );
      },
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
                media.posterUrl,
                fit: BoxFit.cover,
                width: double.infinity,
                errorBuilder: (_, __, ___) => Container(
                  color: Colors.black26,
                  child: const Icon(Icons.movie, size: 40),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    media.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                  Text(
                    media.year,
                    style: const TextStyle(color: Colors.white54, fontSize: 11),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================================
// ADVANCED PLAYER & SEASONS TABS
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
  
  // Player Settings State
  BoxFit _currentFit = BoxFit.contain;
  String _currentQuality = "1080p";

  @override
  void initState() {
    super.initState();
    _resolveAndPlay();
  }

  Future<void> _resolveAndPlay() async {
    setState(() {
      _isResolving = true;
      _statusMessage = 'Locating playable video file...';
    });

    try {
      final metaUri = Uri.parse('https://archive.org/metadata/${widget.media.identifier}');
      final response = await http.get(metaUri).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final List files = data['files'] ?? [];

        String? targetFile;
        for (final f in files) {
          final name = (f['name'] ?? '').toString();
          if (name.endsWith('.mp4')) {
            targetFile = name;
            break;
          }
        }

        if (targetFile != null) {
          final streamUrl = 'https://archive.org/download/${widget.media.identifier}/$targetFile';
          
          _controller = VideoPlayerController.networkUrl(
            Uri.parse(streamUrl),
          );

          await _controller!.initialize();
          await _controller!.play();

          if (mounted) {
            setState(() => _isResolving = false);
          }
          return;
        }
      }
      throw Exception('No playable MP4 found in this archive entry.');
    } catch (e) {
      if (mounted) {
        setState(() {
          _isResolving = false;
          _statusMessage = 'Playback failed: $e';
        });
      }
    }
  }

  void _toggleWatchlist() {
    final list = List<MediaEntry>.from(globalWatchlist.value);
    final exists = list.any((e) => e.identifier == widget.media.identifier);
    if (exists) {
      list.removeWhere((e) => e.identifier == widget.media.identifier);
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Removed from Watchlist")));
    } else {
      list.add(widget.media);
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Added to Watchlist")));
    }
    globalWatchlist.value = list;
    setState(() {}); // refresh icon
  }

  // --- SETTINGS BOTTOM SHEET ---
  void _openSettingsDialog() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF16181E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Video Settings',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 20),
                  
                  // Aspect Ratio Selector
                  const Text('Aspect Ratio', style: TextStyle(color: Colors.white54)),
                  Wrap(
                    spacing: 10,
                    children: [
                      ChoiceChip(
                        label: const Text('Fit'),
                        selected: _currentFit == BoxFit.contain,
                        onSelected: (_) {
                          setState(() => _currentFit = BoxFit.contain);
                          setModalState(() {});
                        },
                      ),
                      ChoiceChip(
                        label: const Text('Fill'),
                        selected: _currentFit == BoxFit.cover,
                        onSelected: (_) {
                          setState(() => _currentFit = BoxFit.cover);
                          setModalState(() {});
                        },
                      ),
                      ChoiceChip(
                        label: const Text('Stretch'),
                        selected: _currentFit == BoxFit.fill,
                        onSelected: (_) {
                          setState(() => _currentFit = BoxFit.fill);
                          setModalState(() {});
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),

                  // Quality Selector (Educational Mock UI)
                  const Text('Quality (Mock HLS)', style: TextStyle(color: Colors.white54)),
                  Wrap(
                    spacing: 10,
                    children: ["Auto", "1080p", "720p", "480p"].map((q) {
                      return ChoiceChip(
                        label: Text(q),
                        selected: _currentQuality == q,
                        onSelected: (_) {
                          setState(() => _currentQuality = q);
                          setModalState(() {});
                          Navigator.pop(context);
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text("Quality set to $q (UI Demo)"))
                          );
                        },
                      );
                    }).toList(),
                  ),
                ],
              ),
            );
          },
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
    final inWatchlist = globalWatchlist.value
        .any((e) => e.identifier == widget.media.identifier);

    return DefaultTabController(
      length: 2, // Episodes | Details
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: Colors.black,
          title: Text(widget.media.title, style: const TextStyle(fontSize: 16)),
          actions: [
            IconButton(
              icon: Icon(inWatchlist ? Icons.bookmark : Icons.bookmark_border,
                  color: const Color(0xFFE50914)),
              onPressed: _toggleWatchlist,
            )
          ],
        ),
        body: Column(
          children: [
            // ==========================================
            // VIDEO PLAYER WITH OVERLAYS
            // ==========================================
            AspectRatio(
              aspectRatio: 16 / 9,
              child: Container(
                color: Colors.black,
                child: _controller != null && _controller!.value.isInitialized
                    ? Stack(
                        children: [
                          // Custom Aspect Ratio Wrapper
                          Center(
                            child: SizedBox.expand(
                              child: FittedBox(
                                fit: _currentFit,
                                child: SizedBox(
                                  width: _controller!.value.size.width,
                                  height: _controller!.value.size.height,
                                  child: VideoPlayer(_controller!),
                                ),
                              ),
                            ),
                          ),
                          
                          // Play/Pause Overlay
                          GestureDetector(
                            behavior: HitTestBehavior.translucent,
                            onTap: () {
                              setState(() {
                                _controller!.value.isPlaying
                                    ? _controller!.pause()
                                    : _controller!.play();
                              });
                            },
                            child: !_controller!.value.isPlaying
                                ? const Center(
                                    child: Icon(Icons.play_arrow,
                                        color: Colors.white, size: 54),
                                  )
                                : const SizedBox.expand(),
                          ),
                          
                          // Settings Button
                          Positioned(
                            top: 10,
                            right: 10,
                            child: IconButton(
                              icon: const Icon(Icons.settings, color: Colors.white),
                              onPressed: _openSettingsDialog,
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
                                backgroundColor: Colors.white10,
                              ),
                            ),
                          ),
                        ],
                      )
                    : Center(
                        child: _isResolving
                            ? const CircularProgressIndicator(
                                color: Color(0xFFE50914))
                            : Text(_statusMessage ?? 'Failed',
                                style: const TextStyle(color: Colors.white70)),
                      ),
              ),
            ),
            
            // ==========================================
            // TABS (Episodes | Details)
            // ==========================================
            const TabBar(
              indicatorColor: Color(0xFFE50914),
              tabs: [
                Tab(text: "EPISODES"),
                Tab(text: "DETAILS"),
              ],
            ),
            Expanded(
              child: TabBarView(
                children: [
                  // --- EPISODES TAB ---
                  _buildEpisodesTab(),
                  
                  // --- DETAILS TAB ---
                  Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(widget.media.title,
                              style: const TextStyle(
                                  fontSize: 20, fontWeight: FontWeight.bold)),
                          const SizedBox(height: 8),
                          Text("Release Year: ${widget.media.year}",
                              style: const TextStyle(color: Color(0xFF00E676))),
                          const SizedBox(height: 16),
                          Text(widget.media.description,
                              style: const TextStyle(
                                  fontSize: 14, color: Colors.white70, height: 1.5)),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Educational UI generator for Seasons/Episodes
  Widget _buildEpisodesTab() {
    return Column(
      children: [
        // Season Dropdown Mock
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          alignment: Alignment.centerLeft,
          color: const Color(0xFF16181E),
          child: DropdownButton<String>(
            value: 'Season 1',
            dropdownColor: const Color(0xFF22252D),
            underline: const SizedBox(),
            items: ['Season 1', 'Season 2', 'Season 3']
                .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                .toList(),
            onChanged: (val) {}, // Mock logic
          ),
        ),
        Expanded(
          child: ListView.builder(
            itemCount: 12, // Fake 12 episodes
            itemBuilder: (context, index) {
              return ListTile(
                leading: Container(
                  width: 100,
                  height: 60,
                  decoration: BoxDecoration(
                    color: Colors.grey[900],
                    image: DecorationImage(
                      image: NetworkImage(widget.media.posterUrl),
                      fit: BoxFit.cover,
                      colorFilter: ColorFilter.mode(
                        Colors.black.withOpacity(0.5), BlendMode.darken)
                    )
                  ),
                  child: const Icon(Icons.play_circle_outline, color: Colors.white),
                ),
                title: Text("Episode ${index + 1}"),
                subtitle: const Text("24m", style: TextStyle(color: Colors.white54)),
                onTap: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text("Playing Episode ${index + 1}..."))
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}
