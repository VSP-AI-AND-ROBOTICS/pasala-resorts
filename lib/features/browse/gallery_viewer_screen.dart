import 'package:flutter/material.dart';

/// A full-screen, swipeable view of a property's bundled photos, opened by
/// the "View Gallery" button over the hero image. Deliberately separate
/// from the inline [PropertyGallery] carousel in `property_screen.dart` --
/// that one is sized to sit inline in the page's scroll; this one exists
/// purely so a customer who wants to actually browse the photos has a
/// distraction-free way to do it (dark background, no page chrome besides
/// a close button and a page counter).
class GalleryViewerScreen extends StatefulWidget {
  const GalleryViewerScreen({
    super.key,
    required this.photos,
    this.initialPage = 0,
  });

  final List<String> photos;
  final int initialPage;

  @override
  State<GalleryViewerScreen> createState() => _GalleryViewerScreenState();
}

class _GalleryViewerScreenState extends State<GalleryViewerScreen> {
  late final PageController _controller =
      PageController(initialPage: widget.initialPage);
  late int _page = widget.initialPage;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            PageView.builder(
              controller: _controller,
              itemCount: widget.photos.length,
              onPageChanged: (i) => setState(() => _page = i),
              itemBuilder: (context, i) => Center(
                child: InteractiveViewer(
                  child: Image.asset(widget.photos[i], fit: BoxFit.contain),
                ),
              ),
            ),
            Positioned(
              top: 8,
              left: 8,
              child: IconButton(
                icon: const Icon(Icons.close, color: Colors.white),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ),
            Positioned(
              top: 16,
              right: 16,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '${_page + 1} / ${widget.photos.length}',
                  style: const TextStyle(color: Colors.white),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
