import 'dart:convert';

/// Every deliberately reported OpenAlias parsing or selection failure.
///
/// Messages are developer diagnostics; map the leaf types to user-facing text.
sealed class OpenAliasException implements Exception {
  final String message;
  final Object? cause;
  final StackTrace? causeStackTrace;
  const OpenAliasException(this.message, {this.cause, this.causeStackTrace});

  @override
  String toString() => '$runtimeType: $message';
}

/// The alias is not a valid ASCII DNS name.
final class OpenAliasInvalidNameException extends OpenAliasException {
  const OpenAliasInvalidNameException(super.message,
      {super.cause, super.causeStackTrace});
}

/// A matching record is malformed or not UTF-8.
final class OpenAliasInvalidRecordException extends OpenAliasException {
  const OpenAliasInvalidRecordException(super.message,
      {super.cause, super.causeStackTrace});
}

/// A matching record repeats a field key.
final class OpenAliasDuplicateFieldException extends OpenAliasException {
  const OpenAliasDuplicateFieldException(super.message,
      {super.cause, super.causeStackTrace});
}

/// The only matching record has no address or `validateAddress` rejects it.
final class OpenAliasInvalidAddressException extends OpenAliasException {
  const OpenAliasInvalidAddressException(super.message,
      {super.cause, super.causeStackTrace});
}

/// A record has `tx_payment_id` and `allowPaymentId` is false.
final class OpenAliasUnsupportedFieldException extends OpenAliasException {
  const OpenAliasUnsupportedFieldException(super.message,
      {super.cause, super.causeStackTrace});
}

/// No record carries the `oa1:<application>` prefix.
final class OpenAliasNoRecordException extends OpenAliasException {
  const OpenAliasNoRecordException(super.message,
      {super.cause, super.causeStackTrace});
}

/// Matching records name more than one address or disagree for one address.
final class OpenAliasAmbiguousException extends OpenAliasException {
  const OpenAliasAmbiguousException(super.message,
      {super.cause, super.causeStackTrace});
}

/// A record over 4096 code units or more than 64 records.
final class OpenAliasLimitExceededException extends OpenAliasException {
  final int? maximum;
  final int? actual;
  const OpenAliasLimitExceededException(super.message,
      {this.maximum, this.actual, super.cause, super.causeStackTrace});

  @override
  String toString() =>
      '$runtimeType(maximum: $maximum, actual: $actual): $message';
}

final _label = RegExp(r'^[a-z0-9_](?:[a-z0-9_-]{0,61}[a-z0-9_])?$');
final _tld = RegExp(r'^[a-z](?:[a-z0-9-]{0,61}[a-z0-9])?$');
const _specialUseTlds = {
  'alt',
  'exit',
  'i2p',
  'invalid',
  'local',
  'localhost',
  'onion',
};

String normalizeOpenAlias(String input) {
  if (input.length > 1024) {
    throw const OpenAliasInvalidNameException(
        'Invalid OpenAlias name: longer than 1024 characters');
  }
  // Before trim(): it also strips U+00A0, U+FEFF, U+2028 and similar.
  if (input.codeUnits.any((code) => code > 0x7f)) {
    throw const OpenAliasInvalidNameException(
        'Invalid OpenAlias name: non-ASCII input');
  }
  if (input.codeUnits.any((code) => code < 0x20 || code == 0x7f)) {
    throw const OpenAliasInvalidNameException(
        'Invalid OpenAlias name: control character');
  }
  var name = input.trim().toLowerCase();
  if (name.split('@').length > 2) {
    throw const OpenAliasInvalidNameException(
        'Invalid OpenAlias name: more than one @');
  }
  name = name.replaceAll('@', '.');
  if (name.endsWith('.')) name = name.substring(0, name.length - 1);
  final labels = name.split('.');
  if (name.length > 253 ||
      labels.length < 2 ||
      !labels.every(_label.hasMatch) ||
      !_tld.hasMatch(labels.last) ||
      _specialUseTlds.contains(labels.last)) {
    throw const OpenAliasInvalidNameException(
        'Invalid OpenAlias name: not a valid domain');
  }
  return name;
}

/// One parsed `oa1:` record: its application tag and fields.
class OpenAliasRecord {
  final String application;

  /// `checksum` and `address_signature` are carried but not verified;
  /// `recipient_name` and `tx_description` are untrusted display text.
  final Map<String, String> fields;
  OpenAliasRecord(this.application, Map<String, String> fields)
      : fields = Map.unmodifiable(fields);
  String? get address => fields['recipient_address'];
  String? get paymentId => fields['tx_payment_id'];
}

/// The recipient chosen by [selectOpenAliasRecipient].
class OpenAliasRecipient {
  final String domain;
  final String address;
  final String application;
  final OpenAliasRecord record;
  const OpenAliasRecipient(
      {required this.domain,
      required this.address,
      required this.application,
      required this.record});
}

final _key = RegExp(r'^[A-Za-z0-9_]+$');
const _standardKeys = {
  'recipient_address',
  'recipient_name',
  'tx_description',
  'tx_amount',
  'tx_payment_id',
  'address_signature',
  'checksum',
};
const _tab = 0x09, _space = 0x20, _quote = 0x22, _semi = 0x3b, _eq = 0x3d;
const _backslash = 0x5c;

bool _blank(int c) => c == _space || c == _tab;

bool _tagChar(int c, {bool first = false}) =>
    (c >= 0x61 && c <= 0x7a) ||
    (c >= 0x30 && c <= 0x39) ||
    (!first && (c == 0x5f || c == 0x2d));

// End of the `oa1:<application>` tag in [units] (UTF-16 or UTF-8), or -1.
// The tag is followed by a space, a tab or the end of the record.
int _tagEnd(List<int> units, String? application) {
  const oa1 = [0x6f, 0x61, 0x31, 0x3a];
  final n = units.length;
  if (n < 5) return -1;
  for (var i = 0; i < 4; i++) {
    if (units[i] != oa1[i]) return -1;
  }
  if (!_tagChar(units[4], first: true)) return -1;
  var i = 5;
  while (i < n && _tagChar(units[i])) {
    i++;
  }
  if (i < n && !_blank(units[i])) return -1;
  if (application != null) {
    if (i - 4 != application.length) return -1;
    for (var k = 0; k < application.length; k++) {
      if (units[4 + k] != application.codeUnitAt(k)) return -1;
    }
  }
  return i;
}

// C0/C1 controls, line separators, zero-width and bidi format characters.
bool _forbidden(int c) =>
    (c < 0x20 && c != _tab) ||
    (c >= 0x7f && c <= 0x9f) ||
    c == 0x061c ||
    c == 0x180e ||
    (c >= 0x200b && c <= 0x200f) ||
    (c >= 0x2028 && c <= 0x202e) ||
    (c >= 0x2060 && c <= 0x2069) ||
    c == 0xfeff ||
    (c >= 0xfff9 && c <= 0xfffb);

// OpenAlias spec: ';' only in a fully quoted value; other quotes are literal.
int _wrapEnd(String s, int open) {
  for (var j = open + 1; j < s.length; j++) {
    final c = s.codeUnitAt(j);
    if (c == _backslash) {
      j++;
    } else if (c == _quote) {
      var k = j + 1;
      while (k < s.length && _blank(s.codeUnitAt(k))) {
        k++;
      }
      if (k == s.length ||
          s.codeUnitAt(k) == _semi ||
          (s.codeUnitAt(k) == _backslash &&
              k + 1 < s.length &&
              s.codeUnitAt(k + 1) == _semi)) {
        return j;
      }
    }
  }
  return -1;
}

// OpenAlias spec: DNS libraries may escape the pair-ending ';' as '\;'.
OpenAliasRecord? parseOpenAliasRecord(String record, {String? application}) {
  final tagEnd = _tagEnd(record.codeUnits, application);
  if (tagEnd < 0) return null;
  if (record.length > 4096) {
    throw OpenAliasLimitExceededException('OpenAlias record too large',
        maximum: 4096, actual: record.length);
  }
  const malformed =
      OpenAliasInvalidRecordException('Malformed OpenAlias record');
  if (record.codeUnits.any(_forbidden)) throw malformed;
  final n = record.length;
  final fields = <String, String>{};
  final seen = <String>{};
  var i = tagEnd;
  while (true) {
    while (i < n) {
      final c = record.codeUnitAt(i);
      if (_blank(c) || c == _semi) {
        i++;
      } else if (c == _backslash &&
          i + 1 < n &&
          record.codeUnitAt(i + 1) == _semi) {
        i += 2;
      } else {
        break;
      }
    }
    if (i == n) break;
    final start = i;
    while (i < n &&
        record.codeUnitAt(i) != _eq &&
        record.codeUnitAt(i) != _semi &&
        record.codeUnitAt(i) != _backslash) {
      i++;
    }
    if (i == n || record.codeUnitAt(i) != _eq) throw malformed;
    final key = _trimBlanks(record.substring(start, i));
    if (!_key.hasMatch(key) ||
        (key != key.toLowerCase() &&
            _standardKeys.contains(key.toLowerCase()))) {
      throw malformed;
    }
    if (!seen.add(key.toLowerCase())) {
      throw const OpenAliasDuplicateFieldException(
          'Duplicate field in OpenAlias record');
    }
    i++;
    while (i < n && _blank(record.codeUnitAt(i))) {
      i++;
    }
    final close =
        i < n && record.codeUnitAt(i) == _quote ? _wrapEnd(record, i) : -1;
    final wrapped = close >= 0;
    final end = wrapped ? close : n;
    final units = <int>[];
    final escaped = <bool>[];
    var j = wrapped ? i + 1 : i;
    while (j < end) {
      final c = record.codeUnitAt(j);
      if (c == _backslash) {
        if (j + 1 >= end) throw malformed;
        final next = record.codeUnitAt(j + 1);
        j += 2;
        if (next == _semi && !wrapped) break;
        if (next != _space &&
            next != _quote &&
            next != _backslash &&
            next != _semi) {
          throw malformed;
        }
        units.add(next);
        escaped.add(true);
      } else {
        j++;
        if (c == _semi && !wrapped) break;
        units.add(c);
        escaped.add(false);
      }
    }
    if (wrapped) {
      j = close + 1;
      while (j < n && _blank(record.codeUnitAt(j))) {
        j++;
      }
      if (j < n) j += record.codeUnitAt(j) == _semi ? 1 : 2;
    }
    i = j;
    var first = 0;
    var last = units.length;
    while (first < last && !escaped[first] && _blank(units[first])) {
      first++;
    }
    while (last > first && !escaped[last - 1] && _blank(units[last - 1])) {
      last--;
    }
    fields[key] = String.fromCharCodes(units.sublist(first, last));
  }
  return OpenAliasRecord(record.substring(4, tagEnd), fields);
}

String _trimBlanks(String s) {
  var a = 0;
  var b = s.length;
  while (a < b && _blank(s.codeUnitAt(a))) {
    a++;
  }
  while (b > a && _blank(s.codeUnitAt(b - 1))) {
    b--;
  }
  return s.substring(a, b);
}

/// Whether every matching record must agree or the first one wins.
enum OpenAliasSelection { uniqueAddress, first }

/// Extra record checks; throw to reject the record.
typedef OpenAliasFieldValidator = void Function(OpenAliasRecord record);

/// Whether [application] can follow `oa1:` in a record: lowercase letters,
/// digits, `_` or `-`, not starting with `_` or `-`.
bool isOpenAliasApplication(String application) {
  final units = application.codeUnits;
  return units.isNotEmpty &&
      _tagChar(units.first, first: true) &&
      units.every(_tagChar);
}

void _checkApplication(String application) {
  if (!isOpenAliasApplication(application)) {
    throw ArgumentError.value(application, 'application');
  }
}

bool _sameFields(OpenAliasRecord a, OpenAliasRecord b) =>
    a.fields.length == b.fields.length &&
    a.fields.entries.every((e) => b.fields[e.key] == e.value);

/// Selects the recipient from raw TXT [records] for [domain], each record's
/// character-strings already concatenated.
///
/// Records of other applications are ignored without being decoded; a
/// matching record that is not UTF-8 is an [OpenAliasInvalidRecordException].
/// The caller is responsible for the origin of [records].
OpenAliasRecipient selectOpenAliasRecipient(
    {required String domain,
    required List<List<int>> records,
    required String application,
    required bool Function(String) validateAddress,
    OpenAliasFieldValidator? validateRecord,
    OpenAliasSelection selection = OpenAliasSelection.uniqueAddress,
    bool allowPaymentId = false}) {
  _checkApplication(application);
  if (records.length > 64) {
    throw OpenAliasLimitExceededException('Too many OpenAlias records',
        maximum: 64, actual: records.length);
  }
  final parsed = <OpenAliasRecord>[];
  for (final bytes in records) {
    if (_tagEnd(bytes, application) < 0) continue;
    final String text;
    try {
      text = utf8.decode(bytes);
    } on FormatException catch (e, st) {
      throw OpenAliasInvalidRecordException('OpenAlias record is not UTF-8',
          cause: e, causeStackTrace: st);
    }
    parsed.add(parseOpenAliasRecord(text, application: application)!);
  }
  final candidates = <String, OpenAliasRecord>{};
  for (final record in parsed) {
    if (!allowPaymentId && (record.paymentId?.isNotEmpty ?? false)) {
      throw const OpenAliasUnsupportedFieldException(
          'Unsupported field: tx_payment_id');
    }
    validateRecord?.call(record);
    final address = record.address;
    if (address == null || address.isEmpty || !validateAddress(address)) {
      // A publisher may also list another network's address under this app.
      if (parsed.length > 1) {
        throw const OpenAliasAmbiguousException('Multiple recipient addresses');
      }
      throw const OpenAliasInvalidAddressException(
          'Recipient address rejected by validateAddress');
    }
    final previous = candidates.putIfAbsent(address, () => record);
    if (!_sameFields(previous, record)) {
      throw const OpenAliasAmbiguousException(
          'Conflicting records for one recipient address');
    }
    if (selection == OpenAliasSelection.first) break;
  }
  if (candidates.isEmpty) {
    throw const OpenAliasNoRecordException('No matching OpenAlias record');
  }
  if (candidates.length != 1) {
    throw const OpenAliasAmbiguousException('Multiple recipient addresses');
  }
  return OpenAliasRecipient(
      domain: domain,
      address: candidates.keys.single,
      application: application,
      record: candidates.values.single);
}
