import 'package:flutter_test/flutter_test.dart';
import 'package:locallink/core/config/app_config.dart';

void main() {
  test('AppConfig exposes stable LinkUp defaults', () {
    const config = AppConfig();
    expect(config.appName, 'LinkUp');
    expect(config.platform, 'android');
    expect(config.defaultRequestTimeout, const Duration(seconds: 8));
    expect(config.discoveryTimeout, const Duration(seconds: 3));
    expect(config.uploadTimeout, const Duration(minutes: 3));
  });
}
