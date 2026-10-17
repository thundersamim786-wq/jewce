import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:video_player/video_player.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const StreamBoxProApp());
}

class StreamBoxProApp extends StatelessWidget {
  const StreamBoxProApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'StreamBox Pro',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF0B0C10),
        primaryColor: const Color(0xFFE50914),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFFE50914),
          secondary: Color(0xFF00E676),
          surface: Color(0xFF16181E),
        ),
      ),
      home: const MainShell(),
    );
  }
}

// ============================================================================
// DATA MODELS & HLS M3U8 MULTI-AUDIO MANIFEST PARSER
// ============================================================================

class MovieItem {
  final String id;
  final String title;
  final String category;
  final String year;
  final double rating;
  final String posterUrl;
  final String description;
  final Map<String, String> dubStreams;
  final Map<String, String> subtitles;
  final bool isLiveArchiveItem;

  MovieItem({
    required this.id,
    required this.title,
    required this.category,
    required this.year,
    required this.rating,
    required this.posterUrl,
    required this.description,
    required this.dubStreams,
    this.subtitles = const {},
    this.isLiveArchiveItem = false,
  });

  factory MovieItem.fromJson(Map<String, dynamic> json) {
    return MovieItem(
      id: json['id']?.toString() ?? '',
      title: json['title']?.toString() ?? 'Untitled',
      category: json['category']?.toString() ?? 'Cinema',
      year: json['year']?.toString() ?? '2026',
      rating: (json['rating'] is num) ? (json['rating'] as num).toDouble() : 8.2,
      posterUrl: json['posterUrl']?.toString() ?? '',
      description: json['description']?.toString() ?? 'No description available.',
      dubStreams: Map<String, String>.from(json['dubStreams'] ?? {}),
      subtitles: Map<String, String>.from(json['subtitles'] ?? {}),
    );
  }
}

class HlsManifestParser {
  /// Parses an HLS Master Playlist (.m3u8) and extracts #EXT-X-MEDIA:TYPE=AUDIO tracks
  static Future<Map<String, String>> extractAudioTracks(String masterUrl) async {
    final Map<String, String> discoveredTracks = {};
    try {
      final response = await http.get(Uri.parse(masterUrl));
      if (response.statusCode != 200) return {};

      final lines = const LineSplitter().convert(response.body);
      final baseUri = Uri.parse(masterUrl);

      for (final line in lines) {
        if (line.startsWith('#EXT-X-MEDIA:') && line.contains('TYPE=AUDIO')) {
          final nameMatch = RegExp(r'NAME="([^"]+)"').firstMatch(line);
          final langMatch = RegExp(r'LANGUAGE="([^"]+)"').firstMatch(line);
          final uriMatch = RegExp(r'URI="([^"]+)"').firstMatch(line);

          if (uriMatch != null) {
            final label = nameMatch?.group(1) ??
                langMatch?.group(1)?.toUpperCase() ??
                'Audio Track';
            final rawUri = uriMatch.group(1)!;
            final resolvedUri = baseUri.resolve(rawUri).toString();
            discoveredTracks['$label (HLS)'] = resolvedUri;
          }
        }
      }
    } catch (_) {
      // Return empty if not a multi-track master manifest
    }
    return discoveredTracks;
  }
}

// ============================================================================
// BUILT-IN MULTI-DUB DEMO CATALOG
// ============================================================================

final List<MovieItem> builtInCatalog = [
  MovieItem(
    id: 'tos_2025',
    title: 'Tears of Steel (4K Remaster)',
    category: 'Sci-Fi',
    year: '2025',
    rating: 8.7,
    posterUrl: 'https://picsum.photos/seed/tos4k/400/600',
    description:
        'In a cyberpunk Amsterdam, a resistance cell captures an abandoned church to stage a desperate last stand against rogue AI machines.',
    dubStreams: {
      'Hindi Dub (AAC)':
          'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/TearsOfSteel.mp4',
      'Bengali Dub (AAC)':
          'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/TearsOfSteel.mp4',
      'Tamil Dub (AAC)':
          'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/TearsOfSteel.mp4',
      'English (Original 5.1)':
          'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/TearsOfSteel.mp4',
    },
    subtitles: {
      'English CC': 'Hold the perimeter! Synchronize the turret neural link!',
      'Hindi Sub': 'परिधि को संभालो! टरेट न्यूरल लिंक को सिंक्रनाइज़ करें!',
      'Bengali Sub': 'সীমানা ধরে রাখো! টারেট নিউরাল লিঙ্ক সিঙ্ক্রোনাইজ করো!',
    },
  ),
  MovieItem(
    id: 'sintel_dragon',
    title: 'Sintel: Rise of the Valiant',
    category: 'Action',
    year: '2024',
    rating: 8.9,
    posterUrl: 'https://picsum.photos/seed/sintelpro/400/600',
    description:
        'A lone blade-master crosses frozen peaks and ancient ruins to rescue her kidnapped fledgling dragon.',
    dubStreams: {
      'Hindi Dub (AAC)':
          'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/Sintel.mp4',
      'Bengali Dub (AAC)':
          'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/Sintel.mp4',
      'English (Original)':
          'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/Sintel.mp4',
    },
    subtitles: {
      'English CC': 'I searched across the northern wastes to find you, Scales.',
      'Bengali Sub': 'আমি তোমাকে খুঁজতে উত্তরের মরুপ্রান্তর পেরিয়ে এসেছি।',
    },
  ),
  MovieItem(
    id: 'elephants_dream',
    title: 'Elephants Dream: The Machine',
    category: 'Sci-Fi',
    year: '2024',
    rating: 7.9,
    posterUrl: 'https://picsum.photos/seed/elephants/400/600',
    description:
        'Proog and Emo navigate the infinite, shifting rooms of a surreal mechanical super-structure.',
    dubStreams: {
      'Hindi Dub':
          'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/ElephantsDream.mp4',
      'Bengali Dub':
          'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/ElephantsDream.mp4',
      'English (Original)':
          'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/ElephantsDream.mp4',
    },
  ),
];

// ============================================================================
// MAIN SHELL WITH LIVE API SEARCH & EXTENSION PROVIDER LOADER
// ============================================================================

class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  List<MovieItem> _catalog = List.from(builtInCatalog);
  List<MovieItem> _liveSearchResults = [];
  String _selectedDubFilter = 'All Dubs';
  String _selectedCategory = 'All';
  bool _isSearchingApi = false;
  bool _useLiveArchiveSearch = true;
  final TextEditingController _searchController = TextEditingController();
  Timer? _debounce;

  final List<String> _dubFilters = [
    'All Dubs',
    'Hindi',
    'Bengali',
    'Tamil',
    'English'
  ];

  final List<String> _categories = [
    'All',
    'Action',
    'Sci-Fi',
    'Cinema',
    'Custom'
  ];

  @override
  void initState() {
    super.initState();
    _loadSavedProvider();
  }

  Future<void> _loadSavedProvider() async {
    final prefs = await SharedPreferences.getInstance();
    final savedUrl = prefs.getString('custom_provider_url') ?? '';
    if (savedUrl.isNotEmpty) {
      await _fetchCustomProviderUrl(savedUrl, silent: true);
    }
  }

  /// Dynamically loads a remote JSON catalog or direct .mp4/.m3u8 stream URL
  Future<void> _fetchCustomProviderUrl(String url, {bool silent = false}) async {
    if (url.trim().isEmpty) return;
    try {
      if (url.endsWith('.mp4') || url.endsWith('.m3u8')) {
        final customMovie = MovieItem(
          id: 'custom_${DateTime.now().millisecondsSinceEpoch}',
          title: 'Custom Stream (${url.split('/').last})',
          category: 'Custom',
          year: '2026',
          rating: 9.0,
          posterUrl: 'https://picsum.photos/seed/customstream/400/600',
          description: 'Direct stream loaded via Custom Provider Extension.',
          dubStreams: {
            'Primary Stream': url,
            'Hindi Dub Slot': url,
            'Bengali Dub Slot': url,
          },
        );
        setState(() {
          _catalog = [customMovie, ...builtInCatalog];
        });
        return;
      }

      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        final List<dynamic> decoded = json.decode(response.body);
        final loaded = decoded.map((e) => MovieItem.fromJson(e)).toList();
        setState(() {
          _catalog = [...loaded, ...builtInCatalog];
        });
        if (!silent && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Loaded ${loaded.length} movies from provider!')),
          );
        }
      }
    } catch (e) {
      if (!silent && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to load provider: $e')),
        );
      }
    }
  }

  /// Queries the live Internet Archive Feature Film API for real playable movies
  Future<void> _searchInternetArchive(String query) async {
    if (query.trim().length < 2) {
      setState(() {
        _liveSearchResults = [];
        _isSearchingApi = false;
      });
      return;
    }

    setState(() => _isSearchingApi = true);

    try {
      final encodedQuery = Uri.encodeQueryComponent(
        '($query) AND mediatype:(movies) AND collection:(feature_films)',
      );
      final apiUrl =
          'https://archive.org/advancedsearch.php?q=$encodedQuery&fl[]=identifier&fl[]=title&fl[]=year&fl[]=description&rows=12&page=1&output=json';

      final response = await http.get(Uri.parse(apiUrl));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final List docs = data['response']?['docs'] ?? [];

        final results = docs.map<MovieItem>((doc) {
          final id = doc['identifier']?.toString() ?? '';
          final title = doc['title']?.toString() ?? 'Untitled Film';
          final year = doc['year']?.toString() ?? 'Classic';
          final desc = doc['description']?.toString() ??
              'Full-length feature film streamed via Internet Archive API.';

          return MovieItem(
            id: id,
            title: title,
            category: 'Cinema',
            year: year,
            rating: 8.1,
            posterUrl: 'https://archive.org/services/img/$id',
            description: desc,
            dubStreams: {}, // Resolved dynamically when opened
            isLiveArchiveItem: true,
          );
        }).toList();

        setState(() {
          _liveSearchResults = results;
        });
      }
    } catch (_) {
      // Ignore network errors cleanly
    } finally {
      if (mounted) {
        setState(() => _isSearchingApi = false);
      }
    }
  }

  void _onSearchChanged(String value) {
    setState(() {});
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    if (_useLiveArchiveSearch && value.trim().length >= 2) {
      _debounce = Timer(const Duration(milliseconds: 500), () {
        _searchInternetArchive(value);
      });
    } else {
      setState(() => _liveSearchResults = []);
    }
  }

  List<MovieItem> get _displayedMovies {
    final query = _searchController.text.trim().toLowerCase();
    final combined = [
      ..._catalog.where((m) {
        final matchesQuery =
            query.isEmpty || m.title.toLowerCase().contains(query);
        final matchesCategory =
            _selectedCategory == 'All' || m.category == _selectedCategory;
        final matchesDub = _selectedDubFilter == 'All Dubs' ||
            m.dubStreams.keys.any(
              (k) => k.toLowerCase().contains(_selectedDubFilter.toLowerCase()),
            );
        return matchesQuery && matchesCategory && matchesDub;
      }),
      ..._liveSearchResults,
    ];
    return combined;
  }

  void _openProviderDialog() async {
    final prefs = await SharedPreferences.getInstance();
    final controller = TextEditingController(
      text: prefs.getString('custom_provider_url') ?? '',
    );

    if (!mounted) return;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF16181E),
        title: const Row(
          children: [
            Icon(Icons.extension, color: Color(0xFF00E676)),
            SizedBox(width: 8),
            Text('Provider / Stream Injector', style: TextStyle(fontSize: 17)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Paste a remote JSON catalog URL (GitHub Raw / Netlify) or a direct .m3u8 / .mp4 stream link:',
              style: TextStyle(fontSize: 13, color: Colors.white70),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              decoration: InputDecoration(
                hintText: 'https://.../catalog.json or stream.m3u8',
                filled: true,
                fillColor: const Color(0xFF0B0C10),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFE50914),
            ),
            onPressed: () async {
              final url = controller.text.trim();
              await prefs.setString('custom_provider_url', url);
              if (ctx.mounted) Navigator.pop(ctx);
              await _fetchCustomProviderUrl(url);
            },
            child: const Text('Load Provider'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF16181E),
        elevation: 0,
        title: const Row(
          children: [
            Icon(Icons.movie_filter, color: Color(0xFFE50914), size: 28),
            SizedBox(width: 8),
            Text(
              'StreamBox',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 19),
            ),
            SizedBox(width: 6),
            Chip(
              label: Text(
                'PRO ENGINE',
                style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold),
              ),
              backgroundColor: Color(0xFFE50914),
              visualDensity: VisualDensity.compact,
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Add Custom Provider or M3U8 URL',
            icon: const Icon(Icons.extension, color: Color(0xFF00E676)),
            onPressed: _openProviderDialog,
          ),
        ],
      ),
      body: Column(
        children: [
          // Search Bar + Live API Switch
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 6),
            child: Column(
              children: [
                TextField(
                  controller: _searchController,
                  onChanged: _onSearchChanged,
                  decoration: InputDecoration(
                    hintText:
                        'Search built-in dubs or live global cinema API...',
                    prefixIcon: const Icon(Icons.search, color: Colors.white54),
                    suffixIcon: _searchController.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear, size: 18),
                            onPressed: () {
                              _searchController.clear();
                              _onSearchChanged('');
                            },
                          )
                        : null,
                    filled: true,
                    fillColor: const Color(0xFF16181E),
                    contentPadding: const EdgeInsets.symmetric(vertical: 0),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.cloud_sync,
                            size: 15, color: Color(0xFF00E676)),
                        const SizedBox(width: 6),
                        const Text(
                          'Live Public Cinema API Search',
                          style: TextStyle(fontSize: 12, color: Colors.white70),
                        ),
                      ],
                    ),
                    Switch(
                      value: _useLiveArchiveSearch,
                      activeColor: const Color(0xFF00E676),
                      onChanged: (val) {
                        setState(() => _useLiveArchiveSearch = val);
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Dub Language Filter Bar
          SizedBox(
            height: 38,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              itemCount: _dubFilters.length,
              itemBuilder: (context, index) {
                final dub = _dubFilters[index];
                final selected = _selectedDubFilter == dub;
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: ChoiceChip(
                    label: Text(dub, style: const TextStyle(fontSize: 12)),
                    selected: selected,
                    selectedColor: const Color(0xFFE50914),
                    backgroundColor: const Color(0xFF16181E),
                    onSelected: (_) => setState(() => _selectedDubFilter = dub),
                  ),
                );
              },
            ),
          ),

          // Category Row
          SizedBox(
            height: 36,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              itemCount: _categories.length,
              itemBuilder: (context, index) {
                final cat = _categories[index];
                final selected = _selectedCategory == cat;
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: TextButton(
                    onPressed: () => setState(() => _selectedCategory = cat),
                    child: Text(
                      cat,
                      style: TextStyle(
                        fontSize: 13,
                        color: selected
                            ? const Color(0xFF00E676)
                            : Colors.white54,
                        fontWeight:
                            selected ? FontWeight.bold : FontWeight.normal,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),

          if (_isSearchingApi)
            const LinearProgressIndicator(
              color: Color(0xFFE50914),
              minHeight: 2,
            ),

          // Movie Grid
          Expanded(
            child: GridView.builder(
              padding: const EdgeInsets.all(14),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                childAspectRatio: 0.64,
                crossAxisSpacing: 14,
                mainAxisSpacing: 14,
              ),
              itemCount: _displayedMovies.length,
              itemBuilder: (context, index) {
                final movie = _displayedMovies[index];
                return _ProMovieCard(movie: movie);
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _ProMovieCard extends StatelessWidget {
  final MovieItem movie;
  const _ProMovieCard({required this.movie});

  @override
  Widget build(BuildContext context) {
    final badgeText = movie.isLiveArchiveItem
        ? 'LIVE API'
        : '${movie.dubStreams.length} DUBS';
    final badgeColor = movie.isLiveArchiveItem
        ? const Color(0xFF00C853)
        : const Color(0xFFE50914);

    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => ProPlayerScreen(movie: movie),
          ),
        );
      },
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF16181E),
          borderRadius: BorderRadius.circular(12),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Image.network(
                    movie.posterUrl,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Container(
                      color: Colors.grey[900],
                      child: const Icon(Icons.local_movies, size: 48),
                    ),
                  ),
                  Positioned(
                    top: 8,
                    left: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 3),
                      decoration: BoxDecoration(
                        color: badgeColor,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        badgeText,
                        style: const TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    top: 8,
                    right: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 3),
                      decoration: BoxDecoration(
                        color: Colors.black87,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.star, color: Colors.amber, size: 12),
                          const SizedBox(width: 3),
                          Text(
                            movie.rating.toStringAsFixed(1),
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    movie.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    movie.isLiveArchiveItem
                        ? '${movie.year} • Auto-Resolves Stream'
                        : '${movie.year} • ${movie.dubStreams.keys.join(", ")}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
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
// PRO VIDEO PLAYER WITH STREAM RESOLVER, DOUBLE-TAP SEEK & FULLSCREEN
// ============================================================================

class ProPlayerScreen extends StatefulWidget {
  final MovieItem movie;
  const ProPlayerScreen({super.key, required this.movie});

  @override
  State<ProPlayerScreen> createState() => _ProPlayerScreenState();
}

class _ProPlayerScreenState extends State<ProPlayerScreen> {
  VideoPlayerController? _controller;
  Map<String, String> _dubStreams = {};
  String _currentLanguage = '';
  String _activeSubtitle = 'Off';
  double _playbackSpeed = 1.0;
  bool _isResolving = true;
  bool _isFullscreen = false;
  String? _seekFeedback;

  @override
  void initState() {
    super.initState();
    _prepareStreamsAndPlay();
  }

  Future<void> _prepareStreamsAndPlay() async {
    setState(() => _isResolving = true);

    Map<String, String> resolvedStreams = Map.from(widget.movie.dubStreams);

    // 1. If it's a Live Internet Archive item, resolve its .mp4 stream dynamically
    if (widget.movie.isLiveArchiveItem && resolvedStreams.isEmpty) {
      try {
        final metaUrl = 'https://archive.org/metadata/${widget.movie.id}';
        final res = await http.get(Uri.parse(metaUrl));
        if (res.statusCode == 200) {
          final data = json.decode(res.body);
          final List files = data['files'] ?? [];
          for (final f in files) {
            final name = f['name']?.toString() ?? '';
            if (name.endsWith('.mp4')) {
              final streamUrl =
                  'https://archive.org/download/${widget.movie.id}/${Uri.encodeComponent(name)}';
              resolvedStreams['Original Track (${f['format'] ?? 'MP4'})'] =
                  streamUrl;
              resolvedStreams['Hindi Dub Slot (Mirror)'] = streamUrl;
              resolvedStreams['Bengali Dub Slot (Mirror)'] = streamUrl;
              break;
            }
          }
        }
      } catch (_) {}
    }

    // 2. If the primary URL is an HLS .m3u8 master playlist, inspect for #EXT-X-MEDIA audio tracks
    if (resolvedStreams.isNotEmpty) {
      final firstUrl = resolvedStreams.values.first;
      if (firstUrl.endsWith('.m3u8')) {
        final hlsTracks = await HlsManifestParser.extractAudioTracks(firstUrl);
        resolvedStreams.addAll(hlsTracks);
      }
    }

    if (resolvedStreams.isEmpty) {
      resolvedStreams['Fallback Open Stream'] =
          'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/TearsOfSteel.mp4';
    }

    _dubStreams = resolvedStreams;
    _currentLanguage = _dubStreams.keys.first;
    await _initializeStream(_currentLanguage);
  }

  Future<void> _initializeStream(String language, {Duration? resumeAt}) async {
    setState(() => _isResolving = true);

    final oldController = _controller;
    final streamUrl = _dubStreams[language]!;
    final newController =
        VideoPlayerController.networkUrl(Uri.parse(streamUrl));

    try {
      await newController.initialize();
      await newController.setPlaybackSpeed(_playbackSpeed);
      if (resumeAt != null) {
        await newController.seekTo(resumeAt);
      }
      await newController.play();

      if (mounted) {
        setState(() {
          _controller = newController;
          _currentLanguage = language;
          _isResolving = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _isResolving = false);
      }
    }

    await oldController?.dispose();
  }

  Future<void> _switchDubLanguage(String newLang) async {
    if (newLang == _currentLanguage) return;
    final pos = await _controller?.position ?? Duration.zero;
    await _initializeStream(newLang, resumeAt: pos);
  }

  void _seekRelative(int seconds) async {
    if (_controller == null || !_controller!.value.isInitialized) return;
    final current = await _controller!.position ?? Duration.zero;
    final target = current + Duration(seconds: seconds);
    await _controller!.seekTo(target);
    setState(() {
      _seekFeedback = seconds > 0 ? '+${seconds}s ⏩' : '${seconds}s ⏪';
    });
    Future.delayed(const Duration(milliseconds: 650), () {
      if (mounted) setState(() => _seekFeedback = null);
    });
  }

  void _toggleFullscreen() {
    setState(() => _isFullscreen = !_isFullscreen);
    if (_isFullscreen) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
    } else {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
      SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    super.dispose();
  }

  Widget _buildVideoSurface() {
    return Container(
      color: Colors.black,
      child: _isResolving || _controller == null
          ? const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(color: Color(0xFFE50914)),
                  SizedBox(height: 10),
                  Text('Resolving multi-audio stream...',
                      style: TextStyle(fontSize: 12, color: Colors.white70)),
                ],
              ),
            )
          : Stack(
              alignment: Alignment.bottomCenter,
              children: [
                Center(
                  child: AspectRatio(
                    aspectRatio: _controller!.value.aspectRatio,
                    child: VideoPlayer(_controller!),
                  ),
                ),

                // Double-tap left/right seek zones + tap to pause
                Row(
                  children: [
                    Expanded(
                      child: GestureDetector(
                        behavior: HitTestBehavior.translucent,
                        onDoubleTap: () => _seekRelative(-10),
                        onTap: () {
                          setState(() {
                            _controller!.value.isPlaying
                                ? _controller!.pause()
                                : _controller!.play();
                          });
                        },
                      ),
                    ),
                    Expanded(
                      child: GestureDetector(
                        behavior: HitTestBehavior.translucent,
                        onDoubleTap: () => _seekRelative(10),
                        onTap: () {
                          setState(() {
                            _controller!.value.isPlaying
                                ? _controller!.pause()
                                : _controller!.play();
                          });
                        },
                      ),
                    ),
                  ],
                ),

                // Center Play Icon or Seek Ripple Feedback
                if (_seekFeedback != null)
                  Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 18, vertical: 10),
                      decoration: BoxDecoration(
                        color: Colors.black87,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        _seekFeedback!,
                        style: const TextStyle(
                            fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                    ),
                  )
                else if (!_controller!.value.isPlaying)
                  IgnorePointer(
                    child: Center(
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: const BoxDecoration(
                          color: Colors.black54,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.play_arrow,
                            color: Colors.white, size: 54),
                      ),
                    ),
                  ),

                // Active Subtitle / CC Overlay
                if (_activeSubtitle != 'Off' &&
                    widget.movie.subtitles.containsKey(_activeSubtitle))
                  Positioned(
                    bottom: 34,
                    left: 24,
                    right: 24,
                    child: IgnorePointer(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.black87,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          widget.movie.subtitles[_activeSubtitle]!,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Colors.yellowAccent,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ),

                // Top Player Bar: Audio Track, Speed & Fullscreen
                Positioned(
                  top: 8,
                  right: 8,
                  left: 8,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      // Speed button
                      PopupMenuButton<double>(
                        initialValue: _playbackSpeed,
                        color: const Color(0xFF16181E),
                        onSelected: (speed) {
                          setState(() => _playbackSpeed = speed);
                          _controller?.setPlaybackSpeed(speed);
                        },
                        itemBuilder: (_) => [0.5, 1.0, 1.25, 1.5, 2.0]
                            .map(
                              (s) => PopupMenuItem(
                                value: s,
                                child: Text('${s}x Speed'),
                              ),
                            )
                            .toList(),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: Colors.black87,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text('${_playbackSpeed}x',
                              style: const TextStyle(
                                  fontSize: 12, fontWeight: FontWeight.bold)),
                        ),
                      ),
                      const SizedBox(width: 8),

                      // Dub Switcher Pill
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFE50914),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 6),
                        ),
                        icon: const Icon(Icons.audiotrack, size: 15),
                        label: Text(
                          _currentLanguage,
                          style: const TextStyle(fontSize: 12),
                        ),
                        onPressed: () {
                          showModalBottomSheet(
                            context: context,
                            backgroundColor: const Color(0xFF16181E),
                            builder: (_) => ListView(
                              shrinkWrap: true,
                              children: [
                                const Padding(
                                  padding: EdgeInsets.all(16),
                                  child: Text(
                                    'Select Audio / Dub Track',
                                    style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 16),
                                  ),
                                ),
                                ..._dubStreams.keys.map(
                                  (lang) => ListTile(
                                    leading: Icon(
                                      lang == _currentLanguage
                                          ? Icons.check_circle
                                          : Icons.radio_button_unchecked,
                                      color: const Color(0xFF00E676),
                                    ),
                                    title: Text(lang),
                                    onTap: () {
                                      Navigator.pop(context);
                                      _switchDubLanguage(lang);
                                    },
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                      const SizedBox(width: 8),

                      // Fullscreen toggle
                      IconButton(
                        style: IconButton.styleFrom(
                          backgroundColor: Colors.black87,
                        ),
                        icon: Icon(
                          _isFullscreen
                              ? Icons.fullscreen_exit
                              : Icons.fullscreen,
                          color: Colors.white,
                        ),
                        onPressed: _toggleFullscreen,
                      ),
                    ],
                  ),
                ),

                VideoProgressIndicator(
                  _controller!,
                  allowScrubbing: true,
                  colors: const VideoProgressColors(
                    playedColor: Color(0xFFE50914),
                    bufferedColor: Colors.white38,
                    backgroundColor: Colors.white12,
                  ),
                ),
              ],
            ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isFullscreen) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: Center(child: _buildVideoSurface()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF16181E),
        title: Text(widget.movie.title),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AspectRatio(
            aspectRatio: 16 / 9,
            child: _buildVideoSurface(),
          ),

          // Multi-Dub & Subtitle Track Selector Bar
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            color: const Color(0xFF16181E),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'AVAILABLE AUDIO / DUB TRACKS (TAP TO SWITCH LIVE):',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF00E676),
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: _dubStreams.keys.map((lang) {
                    final selected = lang == _currentLanguage;
                    return ChoiceChip(
                      label: Text(lang, style: const TextStyle(fontSize: 12)),
                      selected: selected,
                      selectedColor: const Color(0xFFE50914),
                      onSelected: (_) => _switchDubLanguage(lang),
                    );
                  }).toList(),
                ),
                if (widget.movie.subtitles.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  const Text(
                    'SUBTITLES / CC:',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: Colors.white70,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 8,
                    children: ['Off', ...widget.movie.subtitles.keys].map((sub) {
                      return ChoiceChip(
                        label: Text(sub, style: const TextStyle(fontSize: 12)),
                        selected: _activeSubtitle == sub,
                        selectedColor: Colors.blueAccent,
                        onSelected: (_) => setState(() => _activeSubtitle = sub),
                      );
                    }).toList(),
                  ),
                ],
              ],
            ),
          ),

          // Movie Synopsis & Metadata
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.movie.title,
                    style: const TextStyle(
                      fontSize: 21,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '${widget.movie.year} • ${widget.movie.category} • ★ ${widget.movie.rating}',
                    style: const TextStyle(color: Colors.white60),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Tip: Double-tap the left or right side of the video player to seek 10 seconds backward or forward.',
                    style: TextStyle(fontSize: 12, color: Color(0xFF00E676)),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    widget.movie.description,
                    style: const TextStyle(fontSize: 14, height: 1.5),
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
