import 'package:flutter/widgets.dart';

import '../demo/demo_client.dart';

/// Shows an attachment from storage, or from memory for `demo:` URLs.
ImageProvider photoImage(String url) {
  if (url.startsWith('demo:')) {
    final bytes = demoBackend.images[url];
    if (bytes != null) return MemoryImage(bytes);
  }
  return NetworkImage(url);
}

/// True when the URL is a demo upload, which no browser can open.
bool isDemoPhoto(String url) => url.startsWith('demo:');
