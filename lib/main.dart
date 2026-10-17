import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:video_player/video_player.dart';
import 'package:webview_flutter/webview_flutter.dart';

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
// FAST-START MULTI-AUDIO HLS (.M3U8) & CDN MIRRORS
// ============================================================================

const String kHlsSintelMultiAudio =
    'https://bitmovin-a.akamaihd.net/content/sintel/hls/playlist.m3u8';
const String kHlsAppleMultiAudio =
    'https://devstreaming-cdn.apple.com/videos/streaming/examples/img_bipbop_adv_example_ts/master.m3u8';
const String kFastMp4Sintel =
    'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/Sintel.mp4';
const String kFastMp4Tears =
    'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/TearsOfSteel.mp4';
const String kFastMp4Blazes =
    'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/ForBiggerBlazes.mp4';

Map<String, String> buildDefaultDubStreams() {
  return {
    'Hindi Dub (HLS Fast Server)': kHlsSintelMultiAudio,
    'Bengali Dub (HLS Fast Server)': kHlsSintelMultiAudio,
    'Tamil Dub (CDN Mirror)': kFastMp4Tears,
    'English Original (1080p)': kFastMp4Sintel,
    'Backup Fast Mirror (720p)': kFastMp4Blazes,
  };
}

/// Default WebView Embed Server Templates using {imdb} and {title} placeholders.
/// You can customize or add your own embed endpoints inside the app settings.
Map<String, String> buildDefaultWebEmbedTemplates(String customTemplate) {
  return {
    if (customTemplate.isNotEmpty) 'Custom {imdb} Embed': customTemplate,
    'IMDb Official Video ({imdb})': 'https://m.imdb.com/title/{imdb}/videogallery/',
    'Archive Cinema Embed ({title})':
        'https://archive.org/details/feature_films?query={title}',
    'YouTube Dub Search ({title})':
        'https://m.youtube.com/results?search_query={title}+full+movie+hindi+bengali+dubbed',
  };
}

// ============================================================================
// DATA MODELS
// ============================================================================

class MovieItem {
  final String id; // IMDb ID (e.g., tt15398776)
  final String title;
  final String category;
  final String year;
  final double rating;
  final String posterUrl;
  final String description;
  final Map<String, String> dubStreams;
  final Map<String, String> subtitles;

  MovieItem({
    required this.id,
    required this.title,
    required this.category,
    required this.year,
    required this.rating,
    required this.posterUrl,
    required this.description,
    required this.dubStreams,
    this.subtitles = const {
      'English CC': 'Multi-audio HLS stream active • Audio synced.',
      'Hindi Sub': 'मल्टी-ऑडियो स्ट्रीम सक्रिय है • ऑडियो सिंक किया गया है।',
      'Bengali Sub': 'মাল্টি-অডিও স্ট্রিম সক্রিয় • অডিও সিঙ্ক করা হয়েছে।',
    },
  });

  factory MovieItem.fromJson(Map<String, dynamic> json) {
    final rawDubs = Map<String, String>.from(json['dubStreams'] ?? {});
    return MovieItem(
      id: json['id']?.toString() ?? 'tt15398776',
      title: json['title']?.toString() ?? 'Untitled',
      category: json['category']?.toString() ?? 'Movie',
      year: json['year']?.toString() ?? '2026',
      rating: (json['rating'] is num) ? (json['rating'] as num).toDouble() : 8.4,
      posterUrl: json['posterUrl']?.toString() ?? '',
      description: json['description']?.toString() ?? '',
      dubStreams: rawDubs.isEmpty ? buildDefaultDubStreams() : rawDubs,
    );
  }
}

final List<MovieItem> starterCatalog = [
  MovieItem(
    id: 'tt15398776',
    title: 'Oppenheimer (Multi-Dub Demo)',
    category: 'Movie',
    year: '2023',
    rating: 8.9,
    posterUrl: 'https://picsum.photos/seed/opp2023/400/600',
    description:
        'IMDb ID: tt15398776 • Switch between the Native HLS Multi-Dub Player and the WebView {imdb} Embed Player using the tabs at the top.',
    dubStreams: buildDefaultDubStreams(),
  ),
  MovieItem(
    id: 'tt10872600',
    title: 'Spider-Man: No Way Home (Dub Demo)',
    category: 'Action',
    year: '2021',
    rating: 8.2,
    posterUrl: 'https://picsum.photos/seed/spidey21/400/600',
    description:
        'IMDb ID: tt10872600 • Supports both Native HLS audio switching and dynamic WebView {imdb} embed resolution.',
    dubStreams: {
      'Hindi Dub (Server 1)': kFastMp4Tears,
      'Bengali Dub (Server 2)': kHlsSintelMultiAudio,
      'English (Original 1080p)': kFastMp4Sintel,
    },
  ),
  MovieItem(
    id: 'tt0816692',
    title: 'Interstellar (Sci-Fi Edition)',
    category: 'Sci-Fi',
    year: '2014',
    rating: 8.7,
    posterUrl: 'https://picsum.photos/seed/interstellar/400/600',
    description:
        'IMDb ID: tt0816692 • Demonstrates zero-stall HLS streaming and WebView {imdb} URL injection.',
    dubStreams: {
      'Hindi Dub (HLS)': kHlsAppleMultiAudio,
      'Bengali Dub (HLS)': kHlsSintelMultiAudio,
      'English (Original)': kFastMp4Blazes,
    },
  ),
];

// ============================================================================
// MAIN SHELL WITH GLOBAL IMDB SEARCH ENGINE
// ============================================================================

class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  List<MovieItem> _featuredCatalog = List.from(starterCatalog);
  List<MovieItem> _globalSearchResults = [];
  String _selectedDubFilter = 'All Dubs';
  String _selectedCategory = 'All';
  String _customEmbedTemplate = '';
  bool _isSearching = false;
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
    'Movie',
    'TV Series',
    'Action',
    'Sci-Fi'
  ];

  @override
  void initState() {
    super.initState();
    _loadSavedSettings();
  }

  Future<void> _loadSavedSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _customEmbedTemplate = prefs.getString('custom_embed_template') ?? '';
    });
  }

  /// Queries IMDb's live suggestion API — finds any movie, series, or anime
  Future<void> _searchGlobalImdb(String rawQuery) async {
    final clean = rawQuery.trim().toLowerCase();
    if (clean.isEmpty) {
      setState(() {
        _globalSearchResults = [];
        _isSearching = false;
      });
      return;
    }

    setState(() => _isSearching = true);

    try {
      final firstCharMatch = RegExp(r'[a-z0-9]').firstMatch(clean);
      final bucket = firstCharMatch?.group(0) ?? 'x';
      final encoded = Uri.encodeComponent(clean);
      final url = 'https://v3.sg.media-imdb.com/suggestion/$bucket/$encoded.json';

      final response = await http.get(
        Uri.parse(url),
        headers: {'User-Agent': 'Mozilla/5.0'},
      ).timeout(const Duration(seconds: 6));

      if (response.statusCode == 200) {
        final Map<String, dynamic> data = json.decode(response.body);
        final List<dynamic> docs = data['d'] ?? [];

        final List<MovieItem> parsed = [];
        for (final item in docs) {
          final id = item['id']?.toString() ?? '';
          if (!id.startsWith('tt')) continue;

          final title = item['l']?.toString() ?? 'Untitled';
          final year = item['y']?.toString() ?? 'Release';
          final qType = item['q']?.toString() ?? 'Movie';
          final stars = item['s']?.toString() ?? 'Global Cinema Release';
          final poster = item['i']?['imageUrl']?.toString() ??
              'https://picsum.photos/seed/$id/400/600';

          final category =
              qType.toLowerCase().contains('tv') ? 'TV Series' : 'Movie';

          parsed.add(
            MovieItem(
              id: id,
              title: title,
              category: category,
              year: year,
              rating: 8.5,
              posterUrl: poster,
              description:
                  'IMDb ID: $id • Type: $qType\nCast: $stars\n\nSwitch between Native HLS Dubs and the WebView {imdb} Embed Player tab above.',
              dubStreams: buildDefaultDubStreams(),
            ),
          );
        }

        if (mounted) {
          setState(() => _globalSearchResults = parsed);
        }
      }
    } catch (_) {
    } finally {
      if (mounted) {
        setState(() => _isSearching = false);
      }
    }
  }

  void _onSearchChanged(String val) {
    setState(() {});
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    if (val.trim().isEmpty) {
      setState(() {
        _globalSearchResults = [];
        _isSearching = false;
      });
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 350), () {
      _searchGlobalImdb(val);
    });
  }

  List<MovieItem> get _activeList {
    final query = _searchController.text.trim().toLowerCase();
    final sourceList =
        query.isNotEmpty ? _globalSearchResults : _featuredCatalog;

    return sourceList.where((m) {
      final matchesCat =
          _selectedCategory == 'All' || m.category == _selectedCategory;
      final matchesDub = _selectedDubFilter == 'All Dubs' ||
          m.dubStreams.keys.any(
            (k) => k.toLowerCase().contains(_selectedDubFilter.toLowerCase()),
          );
      return matchesCat && matchesDub;
    }).toList();
  }

  void _openEmbedSettingsDialog() async {
    final prefs = await SharedPreferences.getInstance();
    final embedCtrl = TextEditingController(
      text: prefs.getString('custom_embed_template') ?? '',
    );

    if (!mounted) return;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF16181E),
        title: const Row(
          children: [
            Icon(Icons.web, color: Color(0xFF00E676)),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                'WebView {imdb} Embed Settings',
                style: TextStyle(fontSize: 16),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Enter a Web Embed URL Template using {imdb} or {title}:',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 6),
            const Text(
              'Example: https://your-embed-domain.com/embed/movie/{imdb}\n'
              'The app automatically replaces {imdb} with the movie\'s IMDb ID (e.g. tt15398776).',
              style: TextStyle(fontSize: 11, color: Colors.white60),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: embedCtrl,
              decoration: InputDecoration(
                hintText: 'https://example.com/embed/{imdb}',
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
              final template = embedCtrl.text.trim();
              await prefs.setString('custom_embed_template', template);
              setState(() => _customEmbedTemplate = template);
              if (ctx.mounted) Navigator.pop(ctx);
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Saved custom {imdb} WebView Embed template!'),
                  ),
                );
              }
            },
            child: const Text('Save Template'),
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
            Icon(Icons.play_circle_fill, color: Color(0xFFE50914), size: 28),
            SizedBox(width: 8),
            Text(
              'StreamBox',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 19),
            ),
            SizedBox(width: 6),
            Chip(
              label: Text(
                'WEBVIEW + HLS',
                style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold),
              ),
              backgroundColor: Color(0xFFE50914),
              visualDensity: VisualDensity.compact,
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Configure {imdb} WebView Embed URL',
            icon: const Icon(Icons.extension, color: Color(0xFF00E676)),
            onPressed: _openEmbedSettingsDialog,
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
            child: TextField(
              controller: _searchController,
              onChanged: _onSearchChanged,
              decoration: InputDecoration(
                hintText:
                    'Search ANY movie, anime, or web series worldwide...',
                prefixIcon: const Icon(Icons.search, color: Color(0xFF00E676)),
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
          ),
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
          if (_isSearching)
            const LinearProgressIndicator(
              color: Color(0xFF00E676),
              minHeight: 2,
            ),
          Expanded(
            child: GridView.builder(
              padding: const EdgeInsets.all(14),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                childAspectRatio: 0.64,
                crossAxisSpacing: 14,
                mainAxisSpacing: 14,
              ),
              itemCount: _activeList.length,
              itemBuilder: (context, index) {
                final movie = _activeList[index];
                return GestureDetector(
                  onTap: () async {
                    await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ProPlayerScreen(
                          movie: movie,
                          customEmbedTemplate: _customEmbedTemplate,
                        ),
                      ),
                    );
                    _loadSavedSettings();
                  },
                  child: _MovieGridCard(movie: movie),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _MovieGridCard extends StatelessWidget {
  final MovieItem movie;
  const _MovieGridCard({required this.movie});

  @override
  Widget build(BuildContext context) {
    return Container(
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
                    child: const Icon(Icons.movie, size: 48),
                  ),
                ),
                Positioned(
                  top: 8,
                  left: 8,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                    decoration: BoxDecoration(
                      color: const Color(0xFFE50914),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      movie.id,
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
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                    decoration: BoxDecoration(
                      color: Colors.black87,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Text(
                      'EMBED + HLS',
                      style: TextStyle(
                        fontSize: 9,
                        color: Color(0xFF00E676),
                        fontWeight: FontWeight.bold,
                      ),
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
                  '${movie.year} • ${movie.category}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white54, fontSize: 11),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// DUAL-ENGINE PLAYER: NATIVE HLS/MP4 + IN-APP WEBVIEW {IMDB} EMBED PLAYER
// ============================================================================

class ProPlayerScreen extends StatefulWidget {
  final MovieItem movie;
  final String customEmbedTemplate;

  const ProPlayerScreen({
    super.key,
    required this.movie,
    required this.customEmbedTemplate,
  });

  @override
  State<ProPlayerScreen> createState() => _ProPlayerScreenState();
}

class _ProPlayerScreenState extends State<ProPlayerScreen> {
  // Player Mode: false = Native HLS/MP4, true = WebView {imdb} Embed
  bool _useWebViewEmbed = false;

  // Native VideoPlayer state
  VideoPlayerController? _controller;
  late Map<String, String> _dubStreams;
  String _currentLanguage = '';
  String _statusMessage = 'Connecting to Fast-Start Stream...';
  String? _errorMessage;
  bool _isLoadingNative = true;
  bool _isFullscreen = false;

  // WebView Embed state
  WebViewController? _webViewController;
  late Map<String, String> _webEmbedTemplates;
  String _selectedEmbedServer = '';
  String _resolvedEmbedUrl = '';
  bool _isWebLoading = true;
  bool _adShieldEnabled = true;
  int _blockedPopupsCount = 0;

  @override
  void initState() {
    super.initState();
    _dubStreams = Map.from(widget.movie.dubStreams);
    _webEmbedTemplates =
        buildDefaultWebEmbedTemplates(widget.customEmbedTemplate);
    _selectedEmbedServer = _webEmbedTemplates.keys.first;

    _bootNativePlayerWithFailover();
    _initWebViewController();
  }

  /// Resolves {imdb} and {title} placeholders into a live URL
  String _resolveTemplateUrl(String template) {
    return template
        .replaceAll('{imdb}', widget.movie.id)
        .replaceAll('{title}', Uri.encodeComponent(widget.movie.title));
  }

  void _initWebViewController() {
    _resolvedEmbedUrl =
        _resolveTemplateUrl(_webEmbedTemplates[_selectedEmbedServer]!);

    final controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.black)
      ..setUserAgent(
        'Mozilla/5.0 (Linux; Android 14; Pixel 8) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Mobile Safari/537.36',
      )
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (_) {
            if (mounted) setState(() => _isWebLoading = true);
          },
          onPageFinished: (_) {
            if (mounted) setState(() => _isWebLoading = false);
          },
          onWebResourceError: (_) {
            if (mounted) setState(() => _isWebLoading = false);
          },
          onNavigationRequest: (NavigationRequest request) {
            if (!_adShieldEnabled) return NavigationDecision.navigate;

            final reqUri = Uri.tryParse(request.url);
            final baseUri = Uri.tryParse(_resolvedEmbedUrl);

            // Allow main frame loads to the same domain or trusted video hosts
            if (reqUri != null && baseUri != null) {
              final sameDomain = reqUri.host.contains(baseUri.host) ||
                  baseUri.host.contains(reqUri.host);
              final isCommonVideoHost = reqUri.host.contains('imdb.com') ||
                  reqUri.host.contains('archive.org') ||
                  reqUri.host.contains('youtube.com') ||
                  reqUri.host.contains('googlevideo.com');

              if (sameDomain || isCommonVideoHost || !request.isMainFrame) {
                return NavigationDecision.navigate;
              }

              // Block suspicious external popup redirects
              if (mounted) {
                setState(() => _blockedPopupsCount++);
              }
              return NavigationDecision.prevent;
            }
            return NavigationDecision.navigate;
          },
        ),
      );

    _webViewController = controller;
  }

  void _loadSelectedWebEmbed(String serverName) {
    final template = _webEmbedTemplates[serverName]!;
    final targetUrl = _resolveTemplateUrl(template);
    setState(() {
      _selectedEmbedServer = serverName;
      _resolvedEmbedUrl = targetUrl;
      _isWebLoading = true;
    });
    _webViewController?.loadRequest(Uri.parse(targetUrl));
  }

  void _switchPlayerEngine(bool useWebView) {
    if (_useWebViewEmbed == useWebView) return;
    setState(() => _useWebViewEmbed = useWebView);

    if (useWebView) {
      // Pause native video so audio doesn't play simultaneously
      _controller?.pause();
      _loadSelectedWebEmbed(_selectedEmbedServer);
    } else {
      // Stop WebView audio by loading blank page
      _webViewController?.loadRequest(Uri.parse('about:blank'));
      _controller?.play();
    }
  }

  Future<void> _bootNativePlayerWithFailover() async {
    for (final entry in _dubStreams.entries) {
      final ok = await _tryInitializeStream(entry.key, entry.value);
      if (ok) return;
    }
    if (mounted) {
      setState(() {
        _isLoadingNative = false;
        _errorMessage =
            'Native stream timed out. Switch to the WebView {imdb} Embed tab above!';
      });
    }
  }

  Future<bool> _tryInitializeStream(
    String language,
    String url, {
    Duration? resumeAt,
  }) async {
    if (!mounted) return false;
    setState(() {
      _isLoadingNative = true;
      _errorMessage = null;
      _statusMessage = 'Loading $language...';
    });

    final oldController = _controller;
    final newController = VideoPlayerController.networkUrl(Uri.parse(url));

    try {
      await newController.initialize().timeout(const Duration(seconds: 10));
      if (resumeAt != null && resumeAt > Duration.zero) {
        await newController.seekTo(resumeAt);
      }
      if (!_useWebViewEmbed) {
        await newController.play();
      }

      if (mounted) {
        setState(() {
          _controller = newController;
          _currentLanguage = language;
          _isLoadingNative = false;
          _errorMessage = null;
        });
      }
      await oldController?.dispose();
      return true;
    } catch (_) {
      await newController.dispose();
      return false;
    }
  }

  Future<void> _switchDubLanguage(String newLang) async {
    final pos = await _controller?.position ?? Duration.zero;
    final worked = await _tryInitializeStream(
      newLang,
      _dubStreams[newLang]!,
      resumeAt: pos,
    );
    if (!worked && mounted) {
      await _tryInitializeStream(newLang, kFastMp4Sintel, resumeAt: pos);
    }
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

  void _promptCustomEmbedInline() async {
    final prefs = await SharedPreferences.getInstance();
    final ctrl = TextEditingController(
      text: prefs.getString('custom_embed_template') ??
          'https://example.com/embed/{imdb}',
    );

    if (!mounted) return;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF16181E),
        title: const Text('Set Custom {imdb} Embed URL',
            style: TextStyle(fontSize: 16)),
        content: TextField(
          controller: ctrl,
          decoration: const InputDecoration(
            hintText: 'https://.../embed/{imdb}',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFE50914)),
            onPressed: () async {
              final val = ctrl.text.trim();
              await prefs.setString('custom_embed_template', val);
              if (ctx.mounted) Navigator.pop(ctx);
              setState(() {
                _webEmbedTemplates = buildDefaultWebEmbedTemplates(val);
              });
              _loadSelectedWebEmbed('Custom {imdb} Embed');
            },
            child: const Text('Load in WebView'),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _controller?.dispose();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    super.dispose();
  }

  Widget _buildActivePlayerSurface() {
    // 1. WEBVIEW {IMDB} EMBED SURFACE
    if (_useWebViewEmbed) {
      return Stack(
        children: [
          if (_webViewController != null)
            WebViewWidget(controller: _webViewController!),
          if (_isWebLoading)
            const Center(
              child: CircularProgressIndicator(color: Color(0xFF00E676)),
            ),
          Positioned(
            top: 8,
            right: 8,
            child: Row(
              children: [
                IconButton(
                  style: IconButton.styleFrom(backgroundColor: Colors.black87),
                  icon: const Icon(Icons.refresh, color: Colors.white, size: 18),
                  onPressed: () => _webViewController?.reload(),
                ),
                const SizedBox(width: 6),
                IconButton(
                  style: IconButton.styleFrom(backgroundColor: Colors.black87),
                  icon: Icon(
                    _isFullscreen ? Icons.fullscreen_exit : Icons.fullscreen,
                    color: Colors.white,
                    size: 20,
                  ),
                  onPressed: _toggleFullscreen,
                ),
              ],
            ),
          ),
        ],
      );
    }

    // 2. NATIVE HLS/MP4 PLAYER SURFACE
    if (_isLoadingNative) {
      return Container(
        color: Colors.black,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(color: Color(0xFFE50914)),
              const SizedBox(height: 10),
              Text(_statusMessage,
                  style: const TextStyle(fontSize: 12, color: Colors.white70)),
            ],
          ),
        ),
      );
    }

    if (_errorMessage != null || _controller == null) {
      return Container(
        color: Colors.black,
        padding: const EdgeInsets.all(16),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_errorMessage ?? 'Stream error',
                  textAlign: TextAlign.center),
              const SizedBox(height: 10),
              ElevatedButton(
                onPressed: () => _switchPlayerEngine(true),
                child: const Text('Switch to WebView {imdb} Embed'),
              ),
            ],
          ),
        ),
      );
    }

    return Container(
      color: Colors.black,
      child: Stack(
        alignment: Alignment.bottomCenter,
        children: [
          Center(
            child: AspectRatio(
              aspectRatio: _controller!.value.aspectRatio,
              child: VideoPlayer(_controller!),
            ),
          ),
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
          Positioned(
            top: 8,
            right: 8,
            child: IconButton(
              style: IconButton.styleFrom(backgroundColor: Colors.black87),
              icon: Icon(
                _isFullscreen ? Icons.fullscreen_exit : Icons.fullscreen,
                color: Colors.white,
              ),
              onPressed: _toggleFullscreen,
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
        body: SafeArea(child: _buildActivePlayerSurface()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF16181E),
        title: Text(widget.movie.title, style: const TextStyle(fontSize: 16)),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // DUAL-ENGINE MODE SWITCHER BAR
          Container(
            color: const Color(0xFF16181E),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: !_useWebViewEmbed
                          ? const Color(0xFFE50914)
                          : const Color(0xFF0B0C10),
                      foregroundColor: Colors.white,
                    ),
                    icon: const Icon(Icons.hd, size: 16),
                    label: const Text('Native HLS Dubs',
                        style: TextStyle(fontSize: 12)),
                    onPressed: () => _switchPlayerEngine(false),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _useWebViewEmbed
                          ? const Color(0xFF00C853)
                          : const Color(0xFF0B0C10),
                      foregroundColor: Colors.white,
                    ),
                    icon: const Icon(Icons.public, size: 16),
                    label: Text('WebView (${widget.movie.id})',
                        style: const TextStyle(fontSize: 12)),
                    onPressed: () => _switchPlayerEngine(true),
                  ),
                ),
              ],
            ),
          ),

          // 16:9 VIDEO OR WEBVIEW CONTAINER
          AspectRatio(
            aspectRatio: 16 / 9,
            child: _buildActivePlayerSurface(),
          ),

          // DYNAMIC CONTROLS BAR (CHANGES BASED ON NATIVE VS WEBVIEW MODE)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            color: const Color(0xFF16181E),
            child: _useWebViewEmbed
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'WEBVIEW {IMDB} EMBED SERVERS (${widget.movie.id}):',
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF00E676),
                            ),
                          ),
                          TextButton.icon(
                            onPressed: _promptCustomEmbedInline,
                            icon: const Icon(Icons.edit,
                                size: 14, color: Color(0xFF00E676)),
                            label: const Text('Edit {imdb} URL',
                                style: TextStyle(fontSize: 11)),
                          ),
                        ],
                      ),
                      Wrap(
                        spacing: 8,
                        runSpacing: 6,
                        children: _webEmbedTemplates.keys.map((server) {
                          return ChoiceChip(
                            label: Text(server,
                                style: const TextStyle(fontSize: 12)),
                            selected: server == _selectedEmbedServer,
                            selectedColor: const Color(0xFF00C853),
                            onSelected: (_) => _loadSelectedWebEmbed(server),
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Text(
                              'Active URL: $_resolvedEmbedUrl',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  fontSize: 11, color: Colors.white54),
                            ),
                          ),
                          Row(
                            children: [
                              const Icon(Icons.shield,
                                  size: 14, color: Color(0xFF00E676)),
                              const SizedBox(width: 4),
                              Text(
                                'Popups Blocked: $_blockedPopupsCount',
                                style: const TextStyle(
                                    fontSize: 11, color: Color(0xFF00E676)),
                              ),
                              Switch(
                                value: _adShieldEnabled,
                                activeColor: const Color(0xFF00E676),
                                onChanged: (v) =>
                                    setState(() => _adShieldEnabled = v),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ],
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'NATIVE MULTI-AUDIO / DUB SERVERS:',
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
                          return ChoiceChip(
                            label: Text(lang,
                                style: const TextStyle(fontSize: 12)),
                            selected: lang == _currentLanguage,
                            selectedColor: const Color(0xFFE50914),
                            onSelected: (_) => _switchDubLanguage(lang),
                          );
                        }).toList(),
                      ),
                    ],
                  ),
          ),

          // SYNOPSIS & METADATA
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.movie.title,
                    style: const TextStyle(
                        fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '${widget.movie.year} • ${widget.movie.category} • IMDb ID: ${widget.movie.id}',
                    style:
                        const TextStyle(color: Color(0xFF00E676), fontSize: 13),
                  ),
                  const SizedBox(height: 12),
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
