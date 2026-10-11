import 'package:scout_server/util/event_search_text.dart';
import 'package:test/test.dart';

void main() {
  test('includes request body, response body, and phone', () {
    final text = eventSearchText(
      {
        'message': 'POST /orders',
        'user': {'id': 'user-9', 'phone': '+966511122233'},
        'network': {
          'url': 'https://api.test/orders',
          'method': 'POST',
          'request': {'body': '{"sku":"ORD-7781-JSON"}'},
          'response': {'body': '{"ref":"REF-4412-JSON"}'},
        },
      },
      userId: 'user-9',
    );

    expect(text, contains('ORD-7781-JSON'));
    expect(text, contains('REF-4412-JSON'));
    expect(text, contains('+966511122233'));
    expect(text, contains('user-9'));
  });

  test('caps a single body and the whole document', () {
    final text = eventSearchText({
      'network': {'request': {'body': 'x' * 20000}},
    });

    expect(text.length, lessThanOrEqualTo(eventSearchTextLimit));
    expect(text, contains('x' * eventSearchBodyLimit));
    expect(text, isNot(contains('x' * (eventSearchBodyLimit + 1))));
  });
}
