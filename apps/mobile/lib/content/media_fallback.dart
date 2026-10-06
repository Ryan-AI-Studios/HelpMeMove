enum MediaFallback { video, rive, still, text, unavailable }

MediaFallback resolveMediaFallback({
  required bool video,
  required bool rive,
  required bool still,
  required bool text,
}) {
  if (video) {
    return MediaFallback.video;
  }
  if (rive) {
    return MediaFallback.rive;
  }
  if (still) {
    return MediaFallback.still;
  }
  if (text) {
    return MediaFallback.text;
  }
  return MediaFallback.unavailable;
}
