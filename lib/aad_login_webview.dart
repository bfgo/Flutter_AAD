import 'dart:async';
import 'dart:io';

import 'package:aad_oauth/model/config.dart';
import 'package:aad_oauth/model/token.dart';
import 'package:aad_oauth/request/authorization_request.dart';
import 'package:aad_oauth/request_token.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'helper/auth_storage.dart';
import 'helper/token_exception.dart';

typedef AsyncTokenGetter = void Function(Future<Token> future);

class AadLoginWebview extends StatefulWidget {
  /// function to retrieve the Token response
  final AsyncTokenGetter onTokenCreated;

  /// Optional callback invoked when a web view is first created.
  /// [controller] is the [WebViewController] for the created web view.
  final WebViewCreatedCallback? onWebViewCreated;

  /// Aad Configuration [Config]
  final Config config;

  /// Optional widget to show to use while loading.
  /// If not provided it will use a SizedBox
  final Widget? loader;

  /// A delegate function that decides how to handle navigation actions.
  /// When a navigation is initiated by the WebView (e.g when a user clicks a link)
  /// this delegate is called and has to decide how to proceed with the navigation.
  ///
  /// If the link contains an error or the correct code of the AadOAuth it will not call this delegate.
  final NavigationDelegate navigationDelegate;

  final bool refreshIfAvailable;

  const AadLoginWebview({
    Key? key,
    required this.config,
    required this.onTokenCreated,
    this.navigationDelegate = _delegate,
    this.onWebViewCreated,
    this.loader,
    this.refreshIfAvailable = false,
  }) : super(key: key);

  static FutureOr<NavigationDecision> _delegate(NavigationRequest navigation) =>
      NavigationDecision.navigate;

  @override
  State<AadLoginWebview> createState() => _AadLoginWebviewState();
}

class _AadLoginWebviewState extends State<AadLoginWebview> {
  late AuthStorage authStorage;
  final CookieManager cookieManager = CookieManager();
  Completer<Token>? _completer;
  String? initialUrl;
  bool performWebFlow = false;

  @override
  void initState() {
    super.initState();
    final authorizationRequest = AuthorizationRequest(widget.config);
    authStorage = AuthStorage(
      tokenIdentifier: widget.config.tokenIdentifier,
      aOptions: widget.config.aOptions,
    );
    initialUrl = _calculateUrl(authorizationRequest);
    Future.microtask(() => login(widget.refreshIfAvailable));
  }

  @override
  void didUpdateWidget(AadLoginWebview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.config != oldWidget.config) {
      final authorizationRequest = AuthorizationRequest(widget.config);
      authStorage = AuthStorage(
        tokenIdentifier: widget.config.tokenIdentifier,
        aOptions: widget.config.aOptions,
      );
      initialUrl = _calculateUrl(authorizationRequest);
    }
  }

  FutureOr<NavigationDecision> _navigationDelegate(NavigationRequest request) {
    final uri = Uri.parse(request.url);
    widget.config.updatePolicyTokenUrl(uri);

    if (uri.queryParameters['error'] != null) {
      final error = uri.queryParameters['error']!;
      final description = uri.queryParameters['error_description'];
      _completer = null;
      _completer = Completer<Token>()
        ..completeError(TokenException.error(error, description));
      widget.onTokenCreated(_completer!.future);
      return NavigationDecision.navigate;
    }

    if (uri.queryParameters['code'] != null) {
      final code = uri.queryParameters['code'];
      _authorize(code);
      return NavigationDecision.navigate;
    }

    return widget.navigationDelegate(request);
  }

  Future<void> login(bool refreshIfAvailable) async {
    try {
      await _removeOldTokenOnFirstLogin();
      final token =
          await _authorization(refreshIfAvailable: refreshIfAvailable);
      if (token != null) {
        _completer = Completer<Token>()..complete(token);
        widget.onTokenCreated(_completer!.future);
      }
    } catch (e) {
      if (e is SocketException) {
        _completer = Completer<Token>()..completeError(e);
        widget.onTokenCreated(_completer!.future);
      } else {
        /// Fix when token is already old and need to reenter credentials:
        /// Error during token request: invalid_grant: AADB2C90080:
        /// The provided grant has expired. Please re-authenticate and try again.
        await logout();
      }
    }
    if (mounted && _completer == null) setState(() => performWebFlow = true);
  }

  Future<void> _removeOldTokenOnFirstLogin() async {
    var prefs = await SharedPreferences.getInstance();
    final _keyFreshInstall = 'freshInstall';
    if (!prefs.getKeys().contains(_keyFreshInstall)) {
      await logout();
      await prefs.setBool(_keyFreshInstall, false);
    }
  }

  Future<void> logout() async {
    await authStorage.clear();
    await cookieManager.clearCookies();
  }

  Future<Token?> _authorization({bool refreshIfAvailable = false}) async {
    var token = await authStorage.loadTokenFromCache();

    if (!refreshIfAvailable && token.hasValidAccessToken()) {
      return token;
    } else if (refreshIfAvailable && token.hasRefreshToken()) {
      final requestToken = RequestToken(widget.config);
      token = await requestToken.requestRefreshToken(token.refreshToken!);
    }

    if (!token.hasValidAccessToken()) {
      return null;
    }

    await authStorage.saveTokenToCache(token);
    return token;
  }

  String? _calculateUrl(AuthorizationRequest request) {
    return Uri.tryParse(request.url)
        ?.replace(queryParameters: request.parameters)
        .toString();
  }

  Future<void> _authorize(String? code) async {
    if (code == null) {
      _completer = null;
      _completer = Completer<Token>()
        ..completeError(Exception('Access denied or authentication canceled.'));
      widget.onTokenCreated(_completer!.future);
      return;
    } else if (_completer != null && !_completer!.isCompleted) {
      widget.onTokenCreated(_completer!.future);
    }
    _completer = null;
    _completer = Completer<Token>();
    try {
      final requestToken = RequestToken(widget.config);
      final token = await requestToken.requestToken(code);
      await authStorage.saveTokenToCache(token);
      _completer!.complete(token);
    } catch (e) {
      _completer!.completeError(e);
    }
    widget.onTokenCreated(_completer!.future);
  }

  @override
  Widget build(BuildContext context) {
    if (!performWebFlow) {
      return widget.loader ?? const SizedBox();
    }

    return WebView(
      key: ValueKey<String?>(initialUrl),
      onWebViewCreated: widget.onWebViewCreated,
      gestureNavigationEnabled: true,
      userAgent: widget.config.userAgent,
      initialUrl: initialUrl,
      javascriptMode: JavascriptMode.unrestricted,
      navigationDelegate: _navigationDelegate,
    );
  }
}
