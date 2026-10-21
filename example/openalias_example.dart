import 'dart:convert';

import 'package:openalias/openalias.dart';

void main() {
  final recipient = selectOpenAliasRecipient(
    domain: normalizeOpenAlias('Alice@Example.com'),
    records: [
      utf8.encode(
          'oa1:xmr recipient_address=demo; recipient_name="Alice; Example";'),
    ],
    application: 'xmr',
    validateAddress: (address) => address == 'demo',
  );
  print(recipient.address);
  print(recipient.record.fields['recipient_name']);
}
