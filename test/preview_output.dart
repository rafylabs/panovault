import 'dart:io';

/// Portable screenshot output directory for preview / e2e visual tests.
///
/// Resolution order:
/// 1. `PANOVAULT_PREVIEW_DIR` env var (CI or local override)
/// 2. `$HOME/Pictures/panovault-previews` when HOME exists
/// 3. `Directory.systemTemp/panovault-previews`
///
/// The directory is created on demand, so tests never fail on a missing path.
Directory previewDir() {
  final envDir = Platform.environment['PANOVAULT_PREVIEW_DIR'];
  final home = Platform.environment['HOME'];

  final base = (envDir != null && envDir.trim().isNotEmpty)
      ? envDir.trim()
      : (home != null && home.trim().isNotEmpty)
          ? '$home/Pictures/panovault-previews'
          : '${Directory.systemTemp.path}/panovault-previews';

  final dir = Directory(base);
  if (!dir.existsSync()) dir.createSync(recursive: true);
  return dir;
}

/// Absolute file path inside [previewDir] for [name].
File previewFile(String name) => File('${previewDir().path}/$name');
