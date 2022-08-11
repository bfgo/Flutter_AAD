import 'dart:async';
import 'package:flutter/material.dart';

import 'request/authorization_request.dart';
import 'model/config.dart';
import 'package:webview_flutter/webview_flutter.dart';

class RequestCode {
  final NavigatorConfig _config;
  final AuthorizationRequest _authorizationRequest;

  String? _code;

  RequestCode(NavigatorConfig config)
      : _config = config,
        _authorizationRequest = AuthorizationRequest(config);
  Future<String?> requestCode() async {
    _code = null;
    final urlParams = _constructUrlParams();
    var webView = WebView(
      userAgent: _config.userAgent,
      initialUrl: '${_authorizationRequest.url}?$urlParams',
      javascriptMode: JavascriptMode.unrestricted,
      navigationDelegate: _navigationDelegate,
    );
    await _config.navigatorKey.currentState!.push(MaterialPageRoute(
      builder: (_) => Scaffold(body: SafeArea(child: webView)),
    ));
    return _code;
  }

  FutureOr<NavigationDecision> _navigationDelegate(NavigationRequest request) {
    final uri = Uri.parse(request.url);
    _config.updatePolicyTokenUrl(uri);

    if (uri.queryParameters['error'] != null) {
      _config.navigatorKey.currentState!.pop();
    }

    if (uri.queryParameters['code'] != null) {
      _code = uri.queryParameters['code'];
      _config.navigatorKey.currentState!.pop();
    }
    return NavigationDecision.navigate;
  }

  Future<void> clearCookies() async {
    await CookieManager().clearCookies();
  }

  String _constructUrlParams() =>
      _mapToQueryParams(_authorizationRequest.parameters);

  String _mapToQueryParams(Map<String, String> params) {
    final queryParams = <String>[];
    params.forEach((String key, String value) =>
        queryParams.add('$key=${Uri.encodeQueryComponent(value)}'));
    return queryParams.join('&');
  }
}
