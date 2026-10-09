import 'dart:async';
import 'dart:io';

/// 全局测试配置：默认禁止测试访问外网。
///
/// - 单元/组件测试一律用 MockClient / 本地文件，不得依赖网络；
/// - 需要真实网络的集成测试打 `@Tags(['network'])`，并在运行时设置
///   `KEYCORE_NETWORK_TESTS=1`（见 dart_test.yaml 与 test/integration/README）。
///   未设置时，这里的 HttpOverrides 会让任何真实连接立即失败，
///   从而把“偷偷联网”的测试暴露出来。
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  if (Platform.environment['KEYCORE_NETWORK_TESTS'] != '1') {
    HttpOverrides.global = _NoNetworkHttpOverrides();
  }
  await testMain();
}

class _NoNetworkHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    final client = super.createHttpClient(context);
    client.connectionFactory = (uri, proxyHost, proxyPort) {
      final host = uri.host;
      if (host == 'localhost' || host == '127.0.0.1' || host == '::1') {
        return Socket.startConnect(host, uri.port);
      }
      stderr.writeln('NETWORK-BLOCKED: $uri');
      throw StateError(
        'Network access is disabled in tests (attempted $uri). '
        'Use MockClient, or tag the test with @Tags([\'network\']) '
        'and run with KEYCORE_NETWORK_TESTS=1.',
      );
    };
    return client;
  }
}
