// 304 (H3): the app's words moved to lib/l10n/app_en.arb. Old tests that
// read English words in a source file read the same file with each
// `L.t.word` put back as its English text (the words did not change).
import 'dart:convert';
import 'dart:io';

Map<String, String>? _en;

Map<String, String> _english() => _en ??= {
      for (final e in (jsonDecode(File('lib/l10n/app_en.arb').readAsStringSync()) as Map<String, dynamic>).entries)
        if (!e.key.startsWith('@')) e.key: e.value as String,
    };

List<String> _names(String key) {
  final raw = jsonDecode(File('lib/l10n/app_en.arb').readAsStringSync()) as Map<String, dynamic>;
  final meta = raw['@$key'];
  if (meta is Map && meta['placeholders'] is Map) {
    return (meta['placeholders'] as Map).keys.cast<String>().toList();
  }
  return RegExp(r'\{(\w+)\}').allMatches(_english()[key] ?? '').map((m) => m.group(1)!).toSet().toList();
}

String _quote(String s) {
  final body = s.replaceAll(r'\', r'\\').replaceAll('\n', r'\n');
  if (!body.contains("'")) return "'$body'";
  return '"${body.replaceAll('"', r'\"')}"';
}

/// Splits "a, b(c, d), 'e, f'" at top-level commas.
List<String> _args(String s) {
  final out = <String>[];
  var depth = 0;
  String? q;
  var start = 0;
  for (var i = 0; i < s.length; i++) {
    final c = s[i];
    if (q != null) {
      if (c == r'\') {
        i++;
      } else if (c == q) {
        q = null;
      }
      continue;
    }
    if (c == "'" || c == '"') {
      q = c;
    } else if ('([{'.contains(c)) {
      depth++;
    } else if (')]}'.contains(c)) {
      depth--;
    } else if (c == ',' && depth == 0) {
      out.add(s.substring(start, i).trim());
      start = i + 1;
    }
  }
  final last = s.substring(start).trim();
  if (last.isNotEmpty) out.add(last);
  return out;
}

/// [src] with `L.t.word` -> 'English words', `L.t.word(a, b)` -> 'words $a ${b.c}'
/// and `L.en('X')` -> 'X'.
String english304(String src) {
  final en = _english();
  final buf = StringBuffer();
  final re = RegExp(r'L\.t\.(\w+)');
  var i = 0;
  for (final m in re.allMatches(src)) {
    if (m.start < i) continue;
    final key = m.group(1)!;
    final text = en[key];
    if (text == null) continue;
    buf.write(src.substring(i, m.start));
    var end = m.end;
    if (end < src.length && src[end] == '(') {
      var depth = 0;
      var j = end;
      String? q;
      for (; j < src.length; j++) {
        final c = src[j];
        if (q != null) {
          if (c == r'\') {
            j++;
          } else if (c == q) {
            q = null;
          }
          continue;
        }
        if (c == "'" || c == '"') {
          q = c;
        } else if (c == '(') {
          depth++;
        } else if (c == ')') {
          depth--;
          if (depth == 0) break;
        }
      }
      final args = _args(src.substring(end + 1, j));
      final names = _names(key);
      var out = text;
      for (var k = 0; k < names.length && k < args.length; k++) {
        final a = args[k];
        final v = RegExp(r'^[A-Za-z_]\w*$').hasMatch(a) ? '\$$a' : '\${$a}';
        out = out.replaceAll('{${names[k]}}', v);
      }
      buf.write(_quote(out));
      end = j + 1;
    } else {
      buf.write(_quote(text));
    }
    i = end;
  }
  buf.write(src.substring(i));
  return buf.toString().replaceAllMapped(RegExp(r"L\.en\(('[^']*'|" r'"[^"]*")\)'), (m) => m.group(1)!);
}

/// Reads a source file with the English words put back.
String readEnglish304(String path) => english304(File(path).readAsStringSync());
