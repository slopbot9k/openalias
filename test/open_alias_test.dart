import 'dart:convert';

import 'package:test/test.dart';
import 'package:openalias/openalias.dart';

List<List<int>> bytes(List<String> records) => [...records.map(utf8.encode)];

OpenAliasRecipient select(List<String> records) => selectOpenAliasRecipient(
      domain: 'alice.example',
      application: 'xmr',
      validateRecord: rejectPaymentId,
      records: bytes(records),
      validateAddress: (s) => s == 'valid' || s == 'second',
    );

void rejectPaymentId(OpenAliasRecord record) {
  if (record.fields['tx_payment_id']?.isNotEmpty ?? false) {
    throw const OpenAliasUnsupportedFieldException(
        'Separate payment IDs are unsupported');
  }
}

void main() {
  parserTests();
  selectorTests();
  test('normalizes email aliases, case and root dot', () {
    expect(normalizeOpenAlias(' Alice@Example. '), 'alice.example');
    expect(normalizeOpenAlias(' alice.example'), 'alice.example');
    expect(normalizeOpenAlias('alice.example '), 'alice.example');
    expect(
      normalizeOpenAlias('xn--bcher-kva.example'),
      'xn--bcher-kva.example',
    );
    expect(normalizeOpenAlias('Dan_M@_Pay.Example'), 'dan_m._pay.example');
    expect(normalizeOpenAlias('pay.xn--p1ai'), 'pay.xn--p1ai');
    final long = '${'a' * 63}.${'b' * 63}.${'c' * 63}.${'d' * 57}.org';
    expect(long.length, 253);
    expect(normalizeOpenAlias('$long.'), long);
  });
  for (final name in [
    'example',
    'https://example.org',
    'a@@b.org',
    'a..org',
    'a.org/path',
    '-a.org',
    'ü.example',
    'K.example',
    '127.0.0.1',
    'a.onion',
    'a.org\u0000',
    '\ufeffalice.example',
    '\u00a0alice.example',
    'alice.example\u2028',
    'alice.example\u3000',
    '\talice.example',
    'alice.example\n',
    'alice.exam\u007fple',
    'alice@',
    '@example.org',
    'a.org..',
    'a b.org',
    'a\u3002org',
    '[::1]',
    '1.2.3.4.',
    'example.123',
    'alice.b_c',
    'x.onion.',
    'alice@pay.localhost',
    'printer.local',
    'a.i2p',
    'a.exit',
    'a.alt',
    'a.invalid',
    '${'a' * 64}.org',
    '${'a' * 63}.${'b' * 63}.${'c' * 63}.${'d' * 58}.org',
    '${'a.' * 600}org',
  ]) {
    test('rejects invalid alias ${name.length > 40 ? name.length : name}', () {
      expect(
        () => normalizeOpenAlias(name),
        throwsA(isA<OpenAliasException>()),
      );
    });
  }
  test(
    'parses semicolon fields and quoted values without requiring spaces',
    () {
      expect(
        select([
          'oa1:xmr recipient_name="Alice; Example";recipient_address="valid";',
        ]).address,
        'valid',
      );
    },
  );
  test('ignores other coins and nonmatching currency prefixes', () {
    expect(
      select([
        'oa1:btc recipient_address=bad;',
        'oa1:xmrfoo recipient_address=bad;',
        'oa1:xmr recipient_address=valid;',
      ]).address,
      'valid',
    );
  });
  for (final records in [
    <String>[],
    ['oa1:xmr recipient_address=wrong-network;'],
    ['oa1:xmr recipient_address=valid;recipient_address=second;'],
    ['oa1:xmr recipient_address=valid;', 'oa1:xmr recipient_address=second;'],
    ['oa1:xmr recipient_address=valid;tx_payment_id=0123456789abcdef;'],
    ['oa1:xmr recipient_address="valid;'],
  ]) {
    test(
      'rejects missing, invalid or ambiguous payment instructions $records',
      () {
        expect(() => select(records), throwsA(isA<OpenAliasException>()));
      },
    );
  }
  test('blames the alias only when its single address is invalid', () {
    Object? failure(List<String> records) {
      try {
        select(records);
      } on OpenAliasException catch (e) {
        return e;
      }
      fail('expected an exception');
    }

    expect(failure(['oa1:xmr recipient_address=wrong-network;']),
        isA<OpenAliasInvalidAddressException>());
    expect(
        failure([
          'oa1:xmr recipient_address=valid;',
          'oa1:xmr recipient_address=wrong-network;',
        ]),
        isA<OpenAliasAmbiguousException>());
    expect(
        failure([
          'oa1:xmr recipient_address=wrong-network;',
          'oa1:xmr recipient_address=valid;',
        ]),
        isA<OpenAliasAmbiguousException>());
  });
  test('does not apply suggested amounts or names to recipient', () {
    final result = select([
      'oa1:xmr recipient_address=valid;tx_amount=999;recipient_name=Someone;',
    ]);
    expect(result.domain, 'alice.example');
    expect(result.address, 'valid');
  });
}

Map<String, String> fields(String record) =>
    parseOpenAliasRecord(record, application: 'xmr')!.fields;

void parserTests() {
  group('record parser', () {
    test('keeps quotes that do not wrap the whole value', () {
      expect(
        fields('oa1:xmr recipient_address=a; '
            'recipient_name=Alice "Vendor" Smith;')['recipient_name'],
        'Alice "Vendor" Smith',
      );
      expect(fields('oa1:xmr recipient_name=O"Brien;')['recipient_name'],
          'O"Brien');
      expect(fields('oa1:xmr recipient_name="O"Brien";')['recipient_name'],
          'O"Brien');
      expect(
          fields('oa1:xmr recipient_name="Alice" Smith; recipient_address=a;'),
          {'recipient_name': '"Alice" Smith', 'recipient_address': 'a'});
      expect(fields('oa1:xmr recipient_name="Bob; recipient_address=a;'),
          {'recipient_name': '"Bob', 'recipient_address': 'a'});
    });
    test('allows semicolons only in fully wrapped values', () {
      expect(
          fields('oa1:xmr recipient_name = "  Alice; Bob  " ; '
              'recipient_address="a"'),
          {'recipient_name': 'Alice; Bob', 'recipient_address': 'a'});
      expect(fields('oa1:xmr tx_description="a;b;c";recipient_address=a;'),
          {'tx_description': 'a;b;c', 'recipient_address': 'a'});
      expect(() => fields('oa1:xmr recipient_name=Alice; Smith;'),
          throwsA(isA<OpenAliasException>()));
      expect(() => fields('oa1:xmr recipient_name=Alice "a;b" Smith;'),
          throwsA(isA<OpenAliasException>()));
    });
    test('accepts backslash-escaped pair separators', () {
      expect(fields(r'oa1:xmr recipient_address=a\; recipient_name=b\;'),
          {'recipient_address': 'a', 'recipient_name': 'b'});
      expect(fields(r'oa1:xmr recipient_name="x\;y" \; recipient_address=a\;'),
          {'recipient_name': 'x;y', 'recipient_address': 'a'});
    });
    test('escapes, trimming, empty values and keys', () {
      expect(
          fields('oa1:xmr\trecipient_address=\ta\t; Custom_1=; e="";'
              r' q=\"x\"; b=a\\b; s=\ \ '),
          {
            'recipient_address': 'a',
            'Custom_1': '',
            'e': '',
            'q': '"x"',
            'b': r'a\b',
            's': '  ',
          });
      expect(fields('oa1:xmr recipient_name=Zoë 山田 😀;')['recipient_name'],
          'Zoë 山田 😀');
    });
    for (final (i, record) in [
      'oa1:xmr recipient_address=a;Recipient_Address=b;',
      r'oa1:xmr recipient_name=a\nb;',
      r'oa1:xmr recipient_name=a\',
      'oa1:xmr recipient_name=a\u202eb;',
      'oa1:xmr recipient_name=a\u2067b;',
      'oa1:xmr recipient_name=a\u0085b;',
      'oa1:xmr recipient_name=a\u200bb;',
      'oa1:xmr recipient_name=a\u200fb;',
      'oa1:xmr recipient_name=a\u061cb;',
      'oa1:xmr recipient_name=a\u2060b;',
      'oa1:xmr recipient_name=a\u2064b;',
      'oa1:xmr recipient_name=a\ufeffb;',
      'oa1:xmr recipient_name=a\ufff9b;',
      'oa1:xmr recipient_name=a\u180eb;',
      'oa1:xmr recipient_address=\u200ba;',
      'oa1:xmr tx_description="a\u202ab";',
      'oa1:xmr recipient_name=a\rb;',
      'oa1:xmr recipient address=a;',
      'oa1:xmr recipient_address=a; junk;',
      'oa1:xmr =a;',
      'oa1:xmr "recipient_address"=a;',
      r'oa1:xmr recipient\_address=a;',
      'oa1:xmr recipient_address=${'a' * 4096}',
    ].indexed) {
      test('rejects malformed record $i', () {
        expect(() => fields(record), throwsA(isA<OpenAliasException>()));
      });
    }
    test('ignores other records without inspecting them', () {
      for (final record in [
        'oa1:xmrfoo recipient_address=a;',
        'OA1:xmr recipient_address=a;',
        ' oa1:xmr recipient_address=a;',
        'oa1:xmr;recipient_address=a;',
        'v=spf1 -all',
        'oa1:btc recipient_address=\u0000${'a' * 70000}',
        'x' * 70000,
      ]) {
        expect(parseOpenAliasRecord(record, application: 'xmr'), isNull);
      }
    });
    test('errors do not echo record contents', () {
      try {
        fields('oa1:xmr recipient_address=secret;recipient_address=secret2;');
        fail('expected an exception');
      } on OpenAliasException catch (e) {
        expect(e.toString(), isNot(contains('secret')));
      }
    });
  });
}

OpenAliasRecipient selectWith(List<String> records,
        {String application = 'xmr',
        bool allowPaymentId = false,
        OpenAliasSelection selection = OpenAliasSelection.uniqueAddress}) =>
    selectOpenAliasRecipient(
        domain: 'alice.example',
        application: application,
        records: bytes(records),
        validateAddress: (a) => a == 'valid' || a == 'second' || a == 'bitcoin',
        allowPaymentId: allowPaymentId,
        selection: selection);

void selectorTests() {
  group('selector', () {
    test('ignores records of other applications and unrelated text', () {
      final result = selectWith([
        'oa1:xmr recipient_address=monero;',
        'oa1:xmrx recipient_address=monero;',
        'v=spf1 -all',
        'oa1:btc recipient_address=bitcoin;custom_1=value;tx_amount=99;',
      ], application: 'btc');
      expect(result.address, 'bitcoin');
      expect(result.domain, 'alice.example');
      expect(result.application, 'btc');
      expect(result.record.fields['custom_1'], 'value');
      expect(() => result.record.fields['tx_amount'] = '1',
          throwsUnsupportedError);
    });
    test('ignores oversized records of other applications', () {
      expect(
          selectWith([
            'oa1:btc ${'x' * 9000}',
            'oa1:xmr recipient_address=valid;',
          ]).address,
          'valid');
    });
    test('payment IDs are rejected unless allowed', () {
      const records = ['oa1:xmr recipient_address=valid; tx_payment_id=abc;'];
      expect(() => selectWith(records),
          throwsA(isA<OpenAliasUnsupportedFieldException>()));
      expect(selectWith(records, allowPaymentId: true).record.paymentId, 'abc');
      expect(
          () => selectWith(
              ['oa1:xmr recipient_address=valid; TX_Payment_ID=abc;'],
              allowPaymentId: true),
          throwsA(isA<OpenAliasInvalidRecordException>()));
    });
    for (final second in [
      'oa1:xmr recipient_address=valid; tx_payment_id=bbb;',
      'oa1:xmr recipient_address=valid; tx_payment_id=aaa; recipient_name=Bob;',
      'oa1:xmr recipient_address=valid;',
    ]) {
      test('conflicting records for one address are ambiguous: $second', () {
        expect(
            () => selectWith([
                  'oa1:xmr recipient_address=valid; tx_payment_id=aaa;',
                  second,
                ], allowPaymentId: true),
            throwsA(isA<OpenAliasAmbiguousException>()));
      });
    }
    test('duplicate identical records are unambiguous', () {
      expect(
          selectWith([
            'oa1:xmr recipient_address=valid;',
            'oa1:xmr recipient_address=valid;',
          ]).address,
          'valid');
    });
    test('first selection differs from the strict default', () {
      const records = [
        'oa1:xmr recipient_address=valid;',
        'oa1:xmr recipient_address=second;'
      ];
      expect(selectWith(records, selection: OpenAliasSelection.first).address,
          'valid');
      expect(() => selectWith(records),
          throwsA(isA<OpenAliasAmbiguousException>()));
    });
    test('rejects more than 64 records', () {
      try {
        selectWith(List.filled(65, 'oa1:xmr recipient_address=valid;'));
        fail('expected an exception');
      } on OpenAliasLimitExceededException catch (e) {
        expect(e.maximum, 64);
        expect(e.actual, 65);
      }
      expect(
          selectWith(List.filled(64, 'oa1:xmr recipient_address=valid;'))
              .address,
          'valid');
    });
    test('no matching record', () {
      expect(() => selectWith(['oa1:btc recipient_address=bitcoin;']),
          throwsA(isA<OpenAliasNoRecordException>()));
    });
    test('decodes only records of the application', () {
      const invalid = [0xff, 0xfe];
      expect(
          selectOpenAliasRecipient(
              domain: 'alice.example',
              application: 'xmr',
              records: [
                [...utf8.encode('oa1:btc recipient_name='), ...invalid],
                [...utf8.encode('oa1:xmrx '), ...invalid],
                invalid,
                utf8.encode('oa1:xmr recipient_address=valid;'),
              ],
              validateAddress: (a) => a == 'valid').address,
          'valid');
      try {
        selectOpenAliasRecipient(
            domain: 'alice.example',
            application: 'xmr',
            records: [
              [...utf8.encode('oa1:xmr recipient_name='), ...invalid],
            ],
            validateAddress: (a) => true);
        fail('expected an exception');
      } on OpenAliasInvalidRecordException catch (e) {
        expect(e.cause, isA<FormatException>());
      }
    });
    test('checks the prefix on bytes', () {
      expect(
          selectWith(['oa1:xmr\trecipient_address=valid;']).address, 'valid');
      for (final other in [
        'oa1:xmrx recipient_address=valid;',
        'oa1:XMR recipient_address=valid;',
        ' oa1:xmr recipient_address=valid;',
        'oa1:xmr;recipient_address=valid;',
        'oa1: recipient_address=valid;',
        'oa1:xmr\rrecipient_address=valid;',
      ]) {
        expect(() => selectWith([other]),
            throwsA(isA<OpenAliasNoRecordException>()),
            reason: other);
      }
      expect(() => selectWith(['oa1:xmr']),
          throwsA(isA<OpenAliasInvalidAddressException>()));
    });
    test('rejects an invalid application name before decoding', () {
      for (final application in ['XMR', '', '-xmr', 'xmr ', 'xm\u00e9']) {
        expect(isOpenAliasApplication(application), isFalse,
            reason: application);
        expect(
            () => selectOpenAliasRecipient(
                domain: 'alice.example',
                application: application,
                records: [
                  [...utf8.encode('oa1:xmr '), 0xff],
                ],
                validateAddress: (a) => true),
            throwsArgumentError,
            reason: application);
      }
      expect(isOpenAliasApplication('x_1-'), isTrue);
      expect(
          selectWith(const ['oa1:x_1- recipient_address=valid;'],
                  application: 'x_1-')
              .address,
          'valid');
    });
  });
}
