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
  final http.Client _httpClient;

  late PKCE _pkce;
  late String _state;

  static late TokenStorage _tokenStorage;

  OidcProviderConfig? _oidcConfig;

  LogtoClient(this.config, this._httpClient,
      [LogtoStorageStrategy? storageProvider]) {
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

  Future<OidcProviderConfig> _getOidcConfig() async {
    if (_oidcConfig != null) {
      return _oidcConfig!;
    }

    final discoveryUri = utils.appendUriPath(config.endpoint, discoveryPath);
    _oidcConfig = await logto_core.fetchOidcConfig(_httpClient, discoveryUri);

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
    _loading = true;
    _pkce = PKCE.generate();
    _state = utils.generateRandomString();
    _tokenStorage.setIdToken(null);

    final oidcConfig = await _getOidcConfig();

    final signInUri = logto_core.generateSignInUri(
      authorizationEndpoint: oidcConfig.authorizationEndpoint,
      clientId: config.appId,
      redirectUri: redirectUri,
      codeChallenge: _pkce.codeChallenge,
      state: _state,
      resources: config.resources,
      scopes: config.scopes,
    );

    // ignore: use_build_context_synchronously
    final callbackUri = await Navigator.push<String>(
      context,
      MaterialPageRoute(
        builder: (context) => LogtoWebview(
          url: signInUri,
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

    await _handleSignInCallback(callbackUri, redirectUri);

    _loading = false;
    return true;
  }

  Future _handleSignInCallback(String callbackUri, String redirectUri) async {
    final code = logto_core.verifyAndParseCodeFromCallbackUri(
      callbackUri,
      redirectUri,
      _state,
    );

    final oidcConfig = await _getOidcConfig();

    final tokenResponse = await logto_core.fetchTokenByAuthorizationCode(
      httpClient: _httpClient,
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
