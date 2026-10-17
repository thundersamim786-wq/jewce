import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:video_player/video_player.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const AutoStreamApp());
}

class AutoStreamApp extends StatelessWidget {
  const AutoStreamApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Auto Stream Native',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF0B0C10),
        primaryColor: const Color(0xFFE50914),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFFE50914),
          surface: Color(0xFF16181E),
        ),
      ),
      home: const AutoCatalogScreen(),
    );
  }
}

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
}

// ============================================================================
// AUTOMATED SEARCH & MEDIA RESOLVER
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

  // Automated search across millions of open video archives
  Future<void> _executeAutoSearch(String query) async {
    final clean = query.trim();
    if (clean.isEmpty) {
      setState(() => _results = []);
      return;
    }

    setState(() => _isLoading = true);

    try {
      // 1. Query the open archive catalog for video media matching the title
      final uri = Uri.parse(
        'https://archive.org/advancedsearch.php?q=${Uri.encodeComponent(clean)}+AND+mediatype:movies&fl[]=identifier,title,description,year&rows=20&output=json',
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
            year: doc['year']?.toString() ?? 'Archive',
            description: doc['description']?.toString() ?? 'Public domain media stream.',
            // High-resolution automated thumbnail directly from Archive CDN
            posterUrl: 'https://archive.org/services/img/$id',
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

    if (mounted) {
      setState(() => _isLoading = false);
    }
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
        title: const Text('Auto Stream Engine', style: TextStyle(fontWeight: FontWeight.bold)),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              controller: _searchCtrl,
              onChanged: _onSearchChanged,
              decoration: InputDecoration(
                hintText: 'Search any title (e.g. Superman, Night of the Living Dead)...',
                prefixIcon: const Icon(Icons.search, color: Color(0xFF00E676)),
                suffixIcon: _searchCtrl.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchCtrl.clear();
                          setState(() => _results = []);
                        },
                      )
                    : null,
                filled: true,
                fillColor: const Color(0xFF16181E),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          if (_isLoading) const LinearProgressIndicator(color: Color(0xFF00E676), minHeight: 2),
          Expanded(
            child: _results.isEmpty && !_isLoading
                ? const Center(
                    child: Text('Type a title to automatically discover and play videos.',
                        style: TextStyle(color: Colors.white54)),
                  )
                : GridView.builder(
                    padding: const EdgeInsets.all(12),
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      childAspectRatio: 0.65,
                      crossAxisSpacing: 12,
                      mainAxisSpacing: 12,
                    ),
                    itemCount: _results.length,
                    itemBuilder: (context, idx) {
                      final item = _results[idx];
                      return GestureDetector(
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => AutoPlayerScreen(media: item),
                            ),
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
                                  item.posterUrl,
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
                                      item.title,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                                    ),
                                    const SizedBox(height: 3),
                                    Text(
                                      item.year,
                                      style: const TextStyle(color: Colors.white54, fontSize: 11),
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
// AUTOMATIC STREAM RESOLVER & NATIVE PLAYER
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
  String? _directStreamUrl;

  @override
  void initState() {
    super.initState();
    _resolveAndPlay();
  }

  // Automatically fetches file structure and resolves the direct video stream URL
  Future<void> _resolveAndPlay() async {
    setState(() {
      _isResolving = true;
      _statusMessage = 'Locating playable video file...';
    });

    try {
      // 1. Fetch metadata container to discover the raw MP4 file
      final metaUri = Uri.parse('https://archive.org/metadata/${widget.media.identifier}');
      final response = await http.get(metaUri).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final List files = data['files'] ?? [];

        // 2. Automatically find the best progressive .mp4 stream
        String? targetFile;
        for (final f in files) {
          final name = (f['name'] ?? '').toString();
          final format = (f['format'] ?? '').toString().toLowerCase();

          if (name.endsWith('.mp4') || format.contains('mp4') || format.contains('h.264')) {
            targetFile = name;
            break;
          }
        }

        if (targetFile != null) {
          // 3. Construct direct streaming URL
          final streamUrl = 'https://archive.org/download/${widget.media.identifier}/$targetFile';
          setState(() {
            _directStreamUrl = streamUrl;
            _statusMessage = 'Buffering native player...';
          });

          // 4. Mount video player
          _controller = VideoPlayerController.networkUrl(
            Uri.parse(streamUrl),
            httpHeaders: {'User-Agent': 'Mozilla/5.0 (Android; Mobile)'},
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

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF16181E),
        title: Text(widget.media.title, style: const TextStyle(fontSize: 16)),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AspectRatio(
            aspectRatio: 16 / 9,
            child: Container(
              color: Colors.black,
              child: _controller != null && _controller!.value.isInitialized
                  ? Stack(
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
                                  child: Icon(Icons.play_arrow, color: Colors.white, size: 54),
                                )
                              : const SizedBox.expand(),
                        ),
                        VideoProgressIndicator(
                          _controller!,
                          allowScrubbing: true,
                          colors: const VideoProgressColors(
                            playedColor: Color(0xFFE50914),
                            bufferedColor: Colors.white24,
                            backgroundColor: Colors.white10,
                          ),
                        ),
                      ],
                    )
                  : Center(
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (_isResolving)
                              const CircularProgressIndicator(color: Color(0xFFE50914)),
                            const SizedBox(height: 12),
                            Text(
                              _statusMessage ?? 'Preparing video...',
                              textAlign: TextAlign.center,
                              style: const TextStyle(color: Colors.white70, fontSize: 13),
                            ),
                          ],
                        ),
                      ),
                    ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(widget.media.title,
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                Text(
                  'Resolved URL: ${_directStreamUrl ?? "Analyzing..."}',
                  style: const TextStyle(fontSize: 11, color: Color(0xFF00E676)),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 12),
                Text(
                  widget.media.description,
                  style: const TextStyle(fontSize: 13, color: Colors.white70),
                  maxLines: 4,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
