import 'package:aad_oauth/model/token.dart';

class TokenException implements Exception {
  final Token? token;
  final String? _error;
  final String? _description;

  const TokenException(this.token)
      : _error = null,
        _description = null;

  const TokenException.error(this._error, this._description) : token = null;

  factory TokenException.fromMap(Map<String, dynamic> map) {
    return TokenException.error(map['error'], map['error_description']);
  }

  @override
  String toString() {
    if (_error != null) {
      return 'TokenException: Error during token request: $_error: $_description';
    }

    if (token == null) return 'TokenException: not token available';
    if (token!.hasValidAccessToken()) return 'not valid access token';
    return 'TokenException: invalid token';
  }
}
