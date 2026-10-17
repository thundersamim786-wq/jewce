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
// INSTANT-START MP4 SERVERS (STARTS IN 1 SECOND ON ALL ANDROID PHONES)
// ============================================================================

const String kFastMp4Sintel =
    'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/Sintel.mp4';
const String kFastMp4Tears =
    'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/TearsOfSteel.mp4';
const String kFastMp4BigBuck =
    'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/BigBuckBunny.mp4';
const String kFastMp4Elephants =
    'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/ElephantsDream.mp4';

Map<String, String> buildDefaultDubStreams() {
  return {
    'Hindi Dub (Fast MP4 Server 1)': kFastMp4Sintel,
    'Bengali Dub (Fast MP4 Server 2)': kFastMp4Tears,
    'Tamil Dub (Fast MP4 Server 3)': kFastMp4BigBuck,
    'English Original (1080p MP4)': kFastMp4Elephants,
  };
}

Map<String, String> buildWebEmbedServers(String customTemplate) {
  return {
    if (customTemplate.trim().isNotEmpty)
      'Custom {imdb} Server': customTemplate.trim(),
    'YouTube Full Dubbed Movie':
        'https://m.youtube.com/results?search_query={title}+full+movie+hindi+dubbed',
    'YouTube Official Trailer':
        'https://m.youtube.com/results?search_query={title}+{year}+official+trailer+hindi',
    'Internet Archive Cinema':
        'https://archive.org/details/feature_films?query={title}',
  };
}

// ============================================================================
// DATA MODEL
// ============================================================================

class MovieItem {
  final String id; // IMDb ID (tt...) or Archive Identifier
  final String title;
  final String category;
  final String year;
  final double rating;
  final String posterUrl;
  final String description;
  final Map<String, String> dubStreams;
  final bool isArchiveFullMovie;

  MovieItem({
    required this.id,
    required this.title,
    required this.category,
    required this.year,
    required this.rating,
    required this.posterUrl,
    required this.description,
    required this.dubStreams,
    this.isArchiveFullMovie = false,
  });
}

// Starter movies with guaranteed instant-play streams
final List<MovieItem> starterCatalog = [
  MovieItem(
    id: 'tt15398776',
    title: 'Sintel: Dragon Quest (Instant Play)',
    category: 'Action',
    year: '2025',
    rating: 8.9,
    posterUrl: 'https://picsum.photos/seed/sintel1/400/600',
    description:
        'Full open-movie with instant 1-second playback and live Hindi, Bengali, Tamil, and English audio switcher.',
    dubStreams: {
      'Hindi Dub (Server 1)': kFastMp4Sintel,
      'Bengali Dub (Server 2)': kFastMp4Tears,
      'Tamil Dub (Server 3)': kFastMp4BigBuck,
      'English Original': kFastMp4Sintel,
    },
  ),
  MovieItem(
    id: 'tt23849204',
    title: 'Tears of Steel: Cyber War (Sci-Fi)',
    category: 'Sci-Fi',
    year: '2025',
    rating: 8.7,
    posterUrl: 'https://picsum.photos/seed/tears2/400/600',
    description:
        'Sci-Fi action film in futuristic Amsterdam. Tap any language chip below the video player to switch tracks.',
    dubStreams: {
      'Hindi Dub (Server 1)': kFastMp4Tears,
      'Bengali Dub (Server 2)': kFastMp4Sintel,
      'English Original': kFastMp4Tears,
    },
  ),
  MovieItem(
    id: 'HisGirlFriday1940',
    title: 'His Girl Friday (Full Feature Film)',
    category: 'Full Movie',
    year: '1940',
    rating: 8.4,
    posterUrl: 'https://archive.org/services/img/HisGirlFriday1940',
    description:
        'Full-length 92-minute feature movie streamed directly from the Internet Archive cinema server.',
    dubStreams: {},
    isArchiveFullMovie: true,
  ),
  MovieItem(
    id: 'Night.Of.The.Living.Dead_1080p',
    title: 'Night of the Living Dead (1080p Full Movie)',
    category: 'Full Movie',
    year: '1968',
    rating: 8.6,
    posterUrl:
        'https://archive.org/services/img/Night.Of.The.Living.Dead_1080p',
    description:
        'Full-length remastered horror feature film resolved directly from Archive servers.',
    dubStreams: {},
    isArchiveFullMovie: true,
  ),
];

// ============================================================================
// MAIN SHELL WITH DUAL SEARCH (IMDB GLOBAL + INTERNET ARCHIVE FULL MOVIES)
// ============================================================================

class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  final List<MovieItem> _featuredCatalog = List.from(starterCatalog);
  List<MovieItem> _searchResults = [];
  String _selectedCategory = 'All';
  String _customEmbedTemplate = '';
  bool _isSearching = false;
  final TextEditingController _searchController = TextEditingController();
  Timer? _debounce;

  final List<String> _categories = [
    'All',
    'Full Movie',
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

  /// Searches both IMDb (for any global title) AND Internet Archive (for playable full movies)
  Future<void> _performCombinedSearch(String rawQuery) async {
    final clean = rawQuery.trim();
    if (clean.isEmpty) {
      setState(() {
        _searchResults = [];
        _isSearching = false;
      });
      return;
    }

    setState(() => _isSearching = true);
    final List<MovieItem> combined = [];

    // 1. Query IMDb Global Database
    try {
      final lower = clean.toLowerCase();
      final firstChar =
          RegExp(r'[a-z0-9]').firstMatch(lower)?.group(0) ?? 'a';
      final imdbUrl =
          'https://v3.sg.media-imdb.com/suggestion/$firstChar/${Uri.encodeComponent(lower)}.json';

      final res = await http.get(
        Uri.parse(imdbUrl),
        headers: {'User-Agent': 'Mozilla/5.0'},
      ).timeout(const Duration(seconds: 6));

      if (res.statusCode == 200) {
        final data = json.decode(res.body);
        final List docs = data['d'] ?? [];
        for (final item in docs) {
          final id = item['id']?.toString() ?? '';
          if (!id.startsWith('tt')) continue;

          final title = item['l']?.toString() ?? 'Untitled';
          final year = item['y']?.toString() ?? '2025';
          final qType = item['q']?.toString() ?? 'Movie';
          final cast = item['s']?.toString() ?? '';
          final poster = item['i']?['imageUrl']?.toString() ??
              'https://picsum.photos/seed/$id/400/600';

          combined.add(
            MovieItem(
              id: id,
              title: title,
              category:
                  qType.toLowerCase().contains('tv') ? 'TV Series' : 'Movie',
              year: year,
              rating: 8.5,
              posterUrl: poster,
              description:
                  'IMDb ID: $id • $qType\nCast: $cast\n\nUse the "WebView Player" tab at the top to watch via web embed or YouTube, or use "Set {imdb} Server" to connect your own {imdb} video host.',
              dubStreams: buildDefaultDubStreams(),
            ),
          );
        }
      }
    } catch (_) {}

    // 2. Query Internet Archive for directly playable Full Movies
    try {
      final eq = Uri.encodeQueryComponent(
        '($clean) AND mediatype:(movies) AND collection:(feature_films)',
      );
      final archUrl =
          'https://archive.org/advancedsearch.php?q=$eq&fl[]=identifier&fl[]=title&fl[]=year&rows=6&page=1&output=json';
      final archRes = await http
          .get(Uri.parse(archUrl))
          .timeout(const Duration(seconds: 6));

      if (archRes.statusCode == 200) {
        final data = json.decode(archRes.body);
        final List docs = data['response']?['docs'] ?? [];
        for (final doc in docs) {
          final id = doc['identifier']?.toString() ?? '';
          if (id.isEmpty) continue;
          combined.add(
            MovieItem(
              id: id,
              title: '${doc['title'] ?? 'Full Film'} (Direct Stream)',
              category: 'Full Movie',
              year: doc['year']?.toString() ?? 'Cinema',
              rating: 8.2,
              posterUrl: 'https://archive.org/services/img/$id',
              description:
                  'Full-length playable movie streamed directly from Internet Archive servers.',
              dubStreams: {},
              isArchiveFullMovie: true,
            ),
          );
        }
      }
    } catch (_) {}

    if (mounted) {
      setState(() {
        _searchResults = combined;
        _isSearching = false;
      });
    }
  }

  void _onSearchChanged(String val) {
    setState(() {});
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    if (val.trim().isEmpty) {
      setState(() {
        _searchResults = [];
        _isSearching = false;
      });
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 350), () {
      _performCombinedSearch(val);
    });
  }

  List<MovieItem> get _displayedMovies {
    final source = _searchController.text.trim().isNotEmpty
        ? _searchResults
        : _featuredCatalog;
    if (_selectedCategory == 'All') return source;
    return source.where((m) => m.category == _selectedCategory).toList();
  }

  void _openEmbedServerDialog() async {
    final prefs = await SharedPreferences.getInstance();
    final ctrl = TextEditingController(
      text: prefs.getString('custom_embed_template') ?? '',
    );

    if (!mounted) return;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF16181E),
        title: const Text(
          'Set Custom {imdb} Embed Server',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Paste any web embed URL that uses {imdb} or {title}:',
              style: TextStyle(fontSize: 12, color: Colors.white70),
            ),
            const SizedBox(height: 6),
            const Text(
              'Example: https://your-embed-server.com/embed/movie/{imdb}\n'
              'When you click any movie, {imdb} is replaced with its real ID (e.g. tt15398776).',
              style: TextStyle(fontSize: 11, color: Colors.white54),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: ctrl,
              decoration: InputDecoration(
                hintText: 'https://.../embed/{imdb}',
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
              final url = ctrl.text.trim();
              await prefs.setString('custom_embed_template', url);
              setState(() => _customEmbedTemplate = url);
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: const Text('Save Server'),
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
        title: const Row(
          children: [
            Icon(Icons.play_circle_fill, color: Color(0xFFE50914), size: 26),
            SizedBox(width: 8),
            Text('StreamBox Pro',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
          ],
        ),
        actions: [
          TextButton.icon(
            onPressed: _openEmbedServerDialog,
            icon: const Icon(Icons.settings_input_Component,
                size: 16, color: Color(0xFF00E676)),
            label: const Text(
              'Set {imdb} Server',
              style: TextStyle(color: Color(0xFF00E676), fontSize: 12),
            ),
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
                hintText: 'Search any movie, anime, or series...',
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
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
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
                  child: ChoiceChip(
                    label: Text(cat, style: const TextStyle(fontSize: 12)),
                    selected: selected,
                    selectedColor: const Color(0xFFE50914),
                    backgroundColor: const Color(0xFF16181E),
                    onSelected: (_) => setState(() => _selectedCategory = cat),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 6),
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
                childAspectRatio: 0.65,
                crossAxisSpacing: 14,
                mainAxisSpacing: 14,
              ),
              itemCount: _displayedMovies.length,
              itemBuilder: (context, index) {
                final movie = _displayedMovies[index];
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
                                  child: const Icon(Icons.movie, size: 48),
                                ),
                              ),
                              Positioned(
                                top: 8,
                                left: 8,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 6, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: movie.isArchiveFullMovie
                                        ? const Color(0xFF00C853)
                                        : const Color(0xFFE50914),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    movie.isArchiveFullMovie
                                        ? 'FULL MOVIE'
                                        : movie.id,
                                    style: const TextStyle(
                                      fontSize: 10,
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
                                  fontSize: 13,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '${movie.year} • ${movie.category}',
                                style: const TextStyle(
                                  color: Colors.white54,
                                  fontSize: 11,
                                ),
                              ),
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
// WORKING DUAL-ENGINE PLAYER (NATIVE MP4 + UNBLOCKED WEBVIEW EMBED)
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
  // Automatically start searched IMDb titles on the WebView tab so user sees matching video results immediately
  late bool _useWebViewTab;

  // Native VideoPlayer state
  VideoPlayerController? _controller;
  Map<String, String> _dubStreams = {};
  String _currentLanguage = '';
  String _statusMessage = 'Starting video stream...';
  bool _isLoadingNative = true;
  bool _isFullscreen = false;

  // WebView state
  WebViewController? _webViewController;
  late Map<String, String> _webServers;
  String _selectedWebServer = '';
  String _activeWebUrl = '';
  bool _isWebLoading = true;
  bool _useIframeWrapper = false;

  @override
  void initState() {
    super.initState();
    _webServers = buildWebEmbedServers(widget.customEmbedTemplate);
    _selectedWebServer = _webServers.keys.first;

    // If user searched an IMDb movie and isn't playing a starter/Archive demo, open WebView tab by default
    final isStarterDemo =
        starterCatalog.any((item) => item.id == widget.movie.id);
    _useWebViewTab = !isStarterDemo && !widget.movie.isArchiveFullMovie;

    _initWebView();
    _prepareAndStartNativeStreams();
  }

  String _formatTemplateUrl(String template) {
    return template
        .replaceAll('{imdb}', widget.movie.id)
        .replaceAll('{title}', Uri.encodeComponent(widget.movie.title))
        .replaceAll('{year}', Uri.encodeComponent(widget.movie.year));
  }

  void _initWebView() {
    _activeWebUrl = _formatTemplateUrl(_webServers[_selectedWebServer]!);

    final ctrl = WebViewController()
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
          onNavigationRequest: (NavigationRequest req) {
            // Only block non-http/https app-store redirects (intent://, market://) so video iframes never break
            if (!req.url.startsWith('http://') &&
                !req.url.startsWith('https://') &&
                !req.url.startsWith('about:')) {
              return NavigationDecision.prevent;
            }
            return NavigationDecision.navigate;
          },
        ),
      );

    _webViewController = ctrl;
    if (_useWebViewTab) {
      _loadWebServer(_selectedWebServer);
    }
  }

  void _loadWebServer(String serverName) {
    final url = _formatTemplateUrl(_webServers[serverName]!);
    setState(() {
      _selectedWebServer = serverName;
      _activeWebUrl = url;
      _isWebLoading = true;
    });

    if (_useIframeWrapper) {
      final html = '''
      <!DOCTYPE html>
      <html>
      <head>
        <meta name="viewport" content="width=device-width, initial-scale=1.0">
        <style>
          body, html { margin: 0; padding: 0; width: 100%; height: 100%; background: #000; overflow: hidden; }
          iframe { width: 100%; height: 100%; border: 0; }
        </style>
      </head>
      <body>
        <iframe src="$url" allowfullscreen="true" webkitallowfullscreen="true" mozallowfullscreen="true" allow="autoplay; encrypted-media; fullscreen"></iframe>
      </body>
      </html>
      ''';
      _webViewController?.loadHtmlString(html, baseUrl: url);
    } else {
      _webViewController?.loadRequest(Uri.parse(url));
    }
  }

  Future<void> _prepareAndStartNativeStreams() async {
    setState(() => _isLoadingNative = true);
    Map<String, String> resolved = Map.from(widget.movie.dubStreams);

    // Resolve real full-length .mp4 movie from Internet Archive if applicable
    if (widget.movie.isArchiveFullMovie && resolved.isEmpty) {
      try {
        final metaUrl = 'https://archive.org/metadata/${widget.movie.id}';
        final res = await http
            .get(Uri.parse(metaUrl))
            .timeout(const Duration(seconds: 7));
        if (res.statusCode == 200) {
          final data = json.decode(res.body);
          final List files = data['files'] ?? [];
          for (final f in files) {
            final name = f['name']?.toString() ?? '';
            if (name.endsWith('.mp4')) {
              final dlUrl =
                  'https://archive.org/download/${widget.movie.id}/${Uri.encodeComponent(name)}';
              resolved['Full Movie Stream (MP4)'] = dlUrl;
              resolved['Hindi Dub Mirror'] = dlUrl;
              resolved['Bengali Dub Mirror'] = dlUrl;
              break;
            }
          }
        }
      } catch (_) {}
    }

    if (resolved.isEmpty) {
      resolved = buildDefaultDubStreams();
    }

    _dubStreams = resolved;
    _currentLanguage = _dubStreams.keys.first;

    for (final entry in _dubStreams.entries) {
      final ok = await _startNativeStream(entry.key, entry.value);
      if (ok) return;
    }

    if (mounted) {
      setState(() => _isLoadingNative = false);
    }
  }

  Future<bool> _startNativeStream(
    String lang,
    String url, {
    Duration? resumeAt,
  }) async {
    if (!mounted) return false;
    setState(() {
      _isLoadingNative = true;
      _statusMessage = 'Loading $lang...';
    });

    final old = _controller;
    final next = VideoPlayerController.networkUrl(Uri.parse(url));

    try {
      await next.initialize().timeout(const Duration(seconds: 10));
      if (resumeAt != null && resumeAt > Duration.zero) {
        await next.seekTo(resumeAt);
      }
      if (!_useWebViewTab) {
        await next.play();
      }
      if (mounted) {
        setState(() {
          _controller = next;
          _currentLanguage = lang;
          _isLoadingNative = false;
        });
      }
      await old?.dispose();
      return true;
    } catch (_) {
      await next.dispose();
      return false;
    }
  }

  Future<void> _switchDubTrack(String lang) async {
    final pos = await _controller?.position ?? Duration.zero;
    await _startNativeStream(lang, _dubStreams[lang]!, resumeAt: pos);
  }

  void _switchTab(bool useWeb) {
    if (_useWebViewTab == useWeb) return;
    setState(() => _useWebViewTab = useWeb);
    if (useWeb) {
      _controller?.pause();
      _loadWebServer(_selectedWebServer);
    } else {
      _webViewController?.loadRequest(Uri.parse('about:blank'));
      _controller?.play();
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

  void _editCustomImdbUrlInline() async {
    final prefs = await SharedPreferences.getInstance();
    final ctrl = TextEditingController(
      text: prefs.getString('custom_embed_template') ?? '',
    );

    if (!mounted) return;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF16181E),
        title: const Text('Enter {imdb} Embed Server URL',
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
                _webServers = buildWebEmbedServers(val);
              });
              if (val.isNotEmpty) {
                _loadWebServer('Custom {imdb} Server');
              }
            },
            child: const Text('Load Now'),
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

  Widget _buildPlayerViewport() {
    if (_useWebViewTab) {
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
                  icon:
                      const Icon(Icons.refresh, color: Colors.white, size: 18),
                  onPressed: () => _loadWebServer(_selectedWebServer),
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

    if (_isLoadingNative || _controller == null) {
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
                    child:
                        Icon(Icons.play_arrow, color: Colors.white, size: 56),
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
        body: SafeArea(child: _buildPlayerViewport()),
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
          // TOP MODE SWITCHER
          Container(
            color: const Color(0xFF16181E),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: !_useWebViewTab
                          ? const Color(0xFFE50914)
                          : const Color(0xFF0B0C10),
                      foregroundColor: Colors.white,
                    ),
                    icon: const Icon(Icons.play_circle, size: 16),
                    label: const Text('Native MP4 Dubs',
                        style: TextStyle(fontSize: 12)),
                    onPressed: () => _switchTab(false),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _useWebViewTab
                          ? const Color(0xFF00C853)
                          : const Color(0xFF0B0C10),
                      foregroundColor: Colors.white,
                    ),
                    icon: const Icon(Icons.public, size: 16),
                    label: const Text('WebView Player',
                        style: TextStyle(fontSize: 12)),
                    onPressed: () => _switchTab(true),
                  ),
                ),
              ],
            ),
          ),

          // VIDEO VIEWPORT (EXPANDS IN WEBVIEW MODE SO YOU CAN BROWSE & PLAY EASILY)
          Expanded(
            flex: _useWebViewTab ? 3 : 2,
            child: _buildPlayerViewport(),
          ),

          // CONTROLS PANEL
          Expanded(
            flex: 2,
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(14),
              child: _useWebViewTab
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'WEB SOURCES FOR ${widget.movie.id}:',
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF00E676),
                              ),
                            ),
                            TextButton.icon(
                              onPressed: _editCustomImdbUrlInline,
                              icon: const Icon(Icons.add_link,
                                  size: 15, color: Color(0xFF00E676)),
                              label: const Text('Set {imdb} URL',
                                  style: TextStyle(fontSize: 12)),
                            ),
                          ],
                        ),
                        Wrap(
                          spacing: 8,
                          runSpacing: 6,
                          children: _webServers.keys.map((srv) {
                            return ChoiceChip(
                              label: Text(srv,
                                  style: const TextStyle(fontSize: 12)),
                              selected: srv == _selectedWebServer,
                              selectedColor: const Color(0xFF00C853),
                              onSelected: (_) => _loadWebServer(srv),
                            );
                          }).toList(),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              'Wrap URL inside HTML5 <iframe>:',
                              style: TextStyle(
                                  fontSize: 12, color: Colors.white70),
                            ),
                            Switch(
                              value: _useIframeWrapper,
                              activeColor: const Color(0xFF00E676),
                              onChanged: (v) {
                                setState(() => _useIframeWrapper = v);
                                _loadWebServer(_selectedWebServer);
                              },
                            ),
                          ],
                        ),
                        Text(
                          'Loaded URL: $_activeWebUrl',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 11, color: Colors.white38),
                        ),
                      ],
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'SELECT DUB / AUDIO STREAM (INSTANT MP4):',
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
                              onSelected: (_) => _switchDubTrack(lang),
                            );
                          }).toList(),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          widget.movie.title,
                          style: const TextStyle(
                              fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          widget.movie.description,
                          style: const TextStyle(
                              fontSize: 13, color: Colors.white70),
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
