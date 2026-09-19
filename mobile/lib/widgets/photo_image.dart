import 'package:flutter/widgets.dart';

import '../demo/demo_client.dart';

/// Resolves an attachment URL to an image.
///
/// Photos normally come from object storage over HTTP. In demo mode there is
/// no storage, so an upload keeps its bytes in memory under a `demo:` URL and
/// they are shown straight from there.
ImageProvider photoImage(String url) {
  if (url.startsWith('demo:')) {
    final bytes = demoBackend.images[url];
    if (bytes != null) return MemoryImage(bytes);
  }
  return NetworkImage(url);
}

/// True when the URL is a demo upload, which no browser can open.
bool isDemoPhoto(String url) => url.startsWith('demo:');
