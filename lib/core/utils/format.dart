// Small formatting helpers shared by the UI and the report.

/// Formats a byte count the way drive makers do (decimal units): 512 GB, 1 TB.
String formatCapacity(num bytes) {
  const tb = 1e12;
  const gb = 1e9;
  if (bytes >= tb * 0.95) {
    final v = bytes / tb;
    return '${_trim(v)} TB';
  }
  if (bytes >= gb) {
    return '${(bytes / gb).round()} GB';
  }
  return '${(bytes / 1e6).round()} MB';
}

/// Formats memory in binary units, rounded to whole GB (e.g. 16 GB).
String formatRam(num bytes) => '${(bytes / (1024 * 1024 * 1024)).round()} GB';

String _trim(double v) {
  final s = v.toStringAsFixed(v >= 10 ? 0 : 1);
  return s.endsWith('.0') ? s.substring(0, s.length - 2) : s;
}

/// Total data written, e.g. "12.4 TB" or "850 GB".
String formatWritten(num bytes) {
  if (bytes >= 1e12) return '${(bytes / 1e12).toStringAsFixed(bytes >= 1e13 ? 1 : 2)} TB';
  return '${(bytes / 1e9).round()} GB';
}

/// 9000 -> "9,000".
String groupThousands(int v) =>
    v.toString().replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ',');
