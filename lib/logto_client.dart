import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:jose/jose.dart';

import '/logto_core.dart' as logto_core;
import '/src/exceptions/logto_auth_exceptions.dart';
import '/src/interfaces/logto_interfaces.dart';
import '/src/utilities/constants.dart';
import '/src/utilities/id_token.dart';
import '/src/utilities/logto_storage_strategy.dart';
import '/src/utilities/pkce.dart';
import '/src/utilities/token_storage.dart';
import '/src/utilities/utils.dart' as utils;
import '/src/utilities/webview_provider.dart';

export '/src/interfaces/logto_config.dart';

// Logto SDK
class LogtoClient {
  final LogtoConfig config;

  late PKCE _pkce;
  late String _state;

  static late TokenStorage _tokenStorage;

  /// Custom [http.Client].
  ///
  /// Note that you will have to call `close()` yourself when passing a [http.Client] instance.
  final http.Client? _httpClient;

  OidcProviderConfig? _oidcConfig;

  LogtoClient(this.config,
      [LogtoStorageStrategy? storageProvider, this._httpClient]) {
    _tokenStorage = TokenStorage(storageProvider);
  }

  Future<bool> get isAuthenticated async {
    return await _tokenStorage.idToken != null;
  }

  Future<String?> get idToken async {
    final token = await _tokenStorage.idToken;
    return token?.serialization;
  }

  Future<OpenIdClaims?> get idTokenClaims async {
    final token = await _tokenStorage.idToken;
    return token?.claims;
  }

  Future<OidcProviderConfig> _getOidcConfig(http.Client httpClient) async {
    if (_oidcConfig != null) {
      return _oidcConfig!;
    }

    final discoveryUri = utils.appendUriPath(config.endpoint, discoveryPath);
    _oidcConfig = await logto_core.fetchOidcConfig(httpClient, discoveryUri);

    return _oidcConfig!;
  }

  bool _loading = false;

  Future<bool> signIn(
    BuildContext context,
    String redirectUri, {
    Color? primaryColor,
    Color? backgroundColor,
    Widget? title,
  }) async {
    if (_loading) return false;
    final httpClient = _httpClient ?? http.Client();
    try {
      _loading = true;
      _pkce = PKCE.generate();
      _state = utils.generateRandomString();
      _tokenStorage.setIdToken(null);
      // ignore: use_build_context_synchronously
      final callbackUri = await Navigator.push<String>(
        context,
        MaterialPageRoute(
          builder: (context) => LogtoWebview(
            getUrl: () async {
              final oidcConfig = await _getOidcConfig(httpClient);

              final signInUri = logto_core.generateSignInUri(
                authorizationEndpoint: oidcConfig.authorizationEndpoint,
                clientId: config.appId,
                redirectUri: redirectUri,
                codeChallenge: _pkce.codeChallenge,
                state: _state,
                resources: config.resources,
                scopes: config.scopes,
              );
              return signInUri;
            },
            signInCallbackUri: redirectUri,
            backgroundColor: backgroundColor,
            primaryColor: primaryColor,
            title: title,
          ),
        ),
      );

      if (callbackUri == null) {
        return false;
      }

      await _handleSignInCallback(callbackUri, redirectUri, httpClient);

      return true;
    } finally {
      _loading = false;
      if (_httpClient == null) httpClient.close();
    }
  }

  Future _handleSignInCallback(
      String callbackUri, String redirectUri, http.Client httpClient) async {
    final code = logto_core.verifyAndParseCodeFromCallbackUri(
      callbackUri,
      redirectUri,
      _state,
    );

    final oidcConfig = await _getOidcConfig(httpClient);

    final tokenResponse = await logto_core.fetchTokenByAuthorizationCode(
      httpClient: httpClient,
      tokenEndPoint: oidcConfig.tokenEndpoint,
      code: code,
      codeVerifier: _pkce.codeVerifier,
      clientId: config.appId,
      redirectUri: redirectUri,
    );

    final idToken = IdToken.unverified(tokenResponse.idToken);

    final keyStore = JsonWebKeyStore()
      ..addKeySetUrl(Uri.parse(oidcConfig.jwksUri));

    if (!await idToken.verify(keyStore)) {
      throw LogtoAuthException(
          LogtoAuthExceptions.idTokenValidationError, 'invalid jws signature');
    }

    final violations = idToken.claims
        .validate(issuer: Uri.parse(oidcConfig.issuer), clientId: config.appId);

    if (violations.isNotEmpty) {
      throw LogtoAuthException(
          LogtoAuthExceptions.idTokenValidationError, '$violations');
    }

    await _tokenStorage.save(
      idToken: idToken,
      accessToken: tokenResponse.accessToken,
      refreshToken: tokenResponse.refreshToken,
    );
  }
}
