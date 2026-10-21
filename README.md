# openalias

Pure Dart parser and recipient selector for OpenAlias (`oa1:`) TXT records.
No networking, no dependencies.

## Usage

```dart
import 'package:openalias/openalias.dart';

final domain = normalizeOpenAlias('donate@getmonero.org');
final recipient = selectOpenAliasRecipient(
  domain: domain,
  records: txtRecords, // raw TXT bytes for [domain]
  application: 'xmr',
  validateAddress: isValidMoneroAddress,
);
print(recipient.address);
```

- `normalizeOpenAlias` lowercases an alias and turns `user@domain` into
  `user.domain`. Non-ASCII names must be given as punycode.
- `parseOpenAliasRecord` parses one record and returns null for records of
  another application.
- `selectOpenAliasRecipient` takes `records` as raw TXT bytes, each record's
  character-strings concatenated. Records without the `oa1:<application>`
  prefix are ignored undecoded; matching records must be UTF-8. It requires
  one valid address. `selection: first` stops at the first matching
  record; `tx_payment_id` is rejected unless `allowPaymentId` is set;
  `validateRecord` adds field checks. At most 64 records are accepted.
- `isOpenAliasApplication` tells whether a tag may follow `oa1:`; the selector
  throws `ArgumentError` for any other `application`.
- Failures are final leaves of sealed `OpenAliasException`. Messages are
  diagnostics; map the types to your own text.

## Trust model

`checksum` and `address_signature` are carried but not verified.
`recipient_name` and `tx_description` are untrusted display text. Fetching
TXT records and deciding whether to trust them is the caller's job.

## Development

`dart tool/check.dart`, in the repository, runs format, analyze, tests and
`pub publish --dry-run`.

## License

MIT; see `LICENSE`.
