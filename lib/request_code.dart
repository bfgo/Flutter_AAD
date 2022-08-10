import 'dart:async';
import 'package:flutter/material.dart';

import 'request/authorization_request.dart';
import 'model/config.dart';
import 'package:webview_flutter/webview_flutter.dart';

class RequestCode {
  final Config _config;
  final AuthorizationRequest _authorizationRequest;

  String? _code;

  RequestCode(Config config)
      : _config = config,
        _authorizationRequest = AuthorizationRequest(config);
  Future<String?> requestCode() async {
    _code = null;
    final urlParams = _constructUrlParams();
    var webView = WebView(
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
    var uri = Uri.parse(request.url);

      if (_config.otherPolicies.isNotEmpty && _config.isB2C) {
        for (var policy in _config.otherPolicies) {
          if (uri.pathSegments.contains('authorize')) {
            if (uri.pathSegments.contains(policy)) {
              _config.updatePolicyTokenUrl(policy);
              break;
            }
          }
        }
      }

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
