import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:http/http.dart' as http;
import 'package:locallink/core/network/api_http_client.dart';

void main() {
  test('ApiHttpClient delegates a GET request to the shared client', () async {
    var called = false;
    final client = ApiHttpClient(
      client: MockClient((request) async {
        called = true;
        expect(request.method, 'GET');
        expect(request.url.path, '/api/v1/status');
        expect(request.headers['Authorization'], 'Bearer test');
        return http.Response('{"ok":true}', 200);
      }),
    );

    final response = await client.get(
      Uri.parse('http://127.0.0.1:8080/api/v1/status'),
      headers: const {'Authorization': 'Bearer test'},
    );

    expect(called, isTrue);
    expect(response.statusCode, 200);
    expect(response.body, '{"ok":true}');
    client.close();
  });

  test('ApiHttpClient supports JSON POST bodies', () async {
    final client = ApiHttpClient(
      client: MockClient((request) async {
        expect(request.method, 'POST');
        expect(request.headers['Content-Type'], 'application/json');
        expect(request.body, '{"name":"phone"}');
        return http.Response('', 201);
      }),
    );

    final response = await client.post(
      Uri.parse('http://127.0.0.1:8080/api/v1/devices'),
      headers: const {'Content-Type': 'application/json'},
      body: '{"name":"phone"}',
    );

    expect(response.statusCode, 201);
    client.close();
  });
}
