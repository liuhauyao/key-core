import 'package:url_launcher/url_launcher.dart';

class UrlLauncherService {
  Future<bool> openUrl(String url) async {
    try {
      final uri = Uri.parse(url);
      if (await canLaunchUrl(uri)) {
        return await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
      return false;
    } catch (e) {
      return false;
    }
  }

  Future<bool> openManagementUrl(String url) async {
    if (url.isEmpty) return false;
    return await openUrl(url);
  }

  Future<bool> openApiEndpoint(String url) async {
    if (url.isEmpty) return false;
    return await openUrl(url);
  }

  bool isValidUrl(String url) {
    try {
      final uri = Uri.parse(url);
      return uri.hasScheme && (uri.scheme == 'http' || uri.scheme == 'https');
    } catch (e) {
      return false;
    }
  }
}
