import 'package:flutter_appauth/flutter_appauth.dart';
import 'package:http/http.dart' as http;
import 'package:jose/jose.dart';

import '/src/exceptions/logto_auth_exceptions.dart';
import '/src/interfaces/logto_interfaces.dart';
import '/src/modules/id_token.dart';
import '/src/modules/logto_storage_strategy.dart';
import '/src/modules/pkce.dart';
import '/src/modules/token_storage.dart';
import '/src/utilities/constants.dart';
import '/src/utilities/utils.dart' as utils;
import 'logto_core.dart' as logto_core;

export '/src/interfaces/logto_config.dart';

// Logto SDK
class LogtoClient {
  final LogtoConfig config;

  late PKCE _pkce;
  late String _state;

  static late TokenStorage _tokenStorage;

  /// Logto automatically enables refresh token's rotation
  ///
  /// Simultaneous access token request may be problematic
  /// Use a request cache map to avoid the race condition
  static final Map<String, Future<AccessToken?>> _accessTokenRequestCache = {};

  /// Custom [http.Client].
  ///
  /// Note that you will have to call `close()` yourself when passing a [http.Client] instance.
  late final http.Client? _httpClient;

  bool _loading = false;

  bool get loading => _loading;

  OidcProviderConfig? _oidcConfig;

  final FlutterAppAuth _appAuth;

  LogtoClient({
    required this.config,
    LogtoStorageStrategy? storageProvider,
    http.Client? httpClient,
  })  : _appAuth = const FlutterAppAuth(),
        _httpClient = httpClient {
    _tokenStorage = TokenStorage(
      storageProvider ?? SecureStorageStrategy(),
    );
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

  Future<AccessToken?> getAccessToken({String? resource}) async {
    final accessToken = await _tokenStorage.getAccessToken(resource);

    if (accessToken != null) {
      return accessToken;
    }

    // If no valid access token is found in storage, use refresh token to claim a new one
    final cacheKey = TokenStorage.buildAccessTokenKey(resource);

    // Reuse the cached request if is exist
    if (_accessTokenRequestCache[cacheKey] != null) {
      return _accessTokenRequestCache[cacheKey];
    }

    // Create new token request and add it to cache
    final newTokenRequest = _getAccessTokenByRefreshToken(resource);
    _accessTokenRequestCache[cacheKey] = newTokenRequest;

    final token = await newTokenRequest;
    // Clear the cache after response
    _accessTokenRequestCache.remove(cacheKey);

    return token;
  }

  // RBAC are not supported currently, no resource specific scopes are needed
  Future<AccessToken?> _getAccessTokenByRefreshToken(String? resource) async {
    final refreshToken = await _tokenStorage.refreshToken;

    if (refreshToken == null) {
      throw LogtoAuthException(
          LogtoAuthExceptions.authenticationError, 'not_authenticated');
    }

    final httpClient = _httpClient ?? http.Client();

    try {
      final oidcConfig = await _getOidcConfig(httpClient);

      final response = await logto_core.fetchTokenByRefreshToken(
          httpClient: httpClient,
          tokenEndPoint: oidcConfig.tokenEndpoint,
          clientId: config.appId,
          refreshToken: refreshToken,
          resource: resource,
          // RBAC are not supported currently, no resource specific scopes are needed
          scopes: resource != null ? ['offline_access'] : null);

      final scopes = response.scope.split(' ');

      await _tokenStorage.setAccessToken(response.accessToken,
          expiresIn: response.expiresIn, resource: resource, scopes: scopes);

      // renew refresh token
      await _tokenStorage.setRefreshToken(response.refreshToken);

      // verify and store id_token if not null
      if (response.idToken != null) {
        final idToken = IdToken.unverified(response.idToken!);
        await _verifyIdToken(idToken, oidcConfig);
        await _tokenStorage.setIdToken(idToken);
      }

      return await _tokenStorage.getAccessToken(resource, scopes);
    } finally {
      if (_httpClient == null) httpClient.close();
    }
  }

  Future<void> _verifyIdToken(
      IdToken idToken, OidcProviderConfig oidcConfig) async {
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
  }

  Future<void> signIn(String redirectUri) async {
    if (_loading) {
      throw LogtoAuthException(
          LogtoAuthExceptions.isLoadingError, 'Already signing in...');
    }

    final httpClient = _httpClient ?? http.Client();

    try {
      _loading = true;
      final discoveryUri = utils.appendUriPath(config.endpoint, discoveryPath);

      final tokenResponse = await _appAuth.authorizeAndExchangeCode(
        AuthorizationTokenRequest(
          config.appId,
          redirectUri,
          discoveryUrl: discoveryUri,
          scopes: (config.scopes ?? [])..addAll(reservedScopes),
          issuer: config.endpoint,
          additionalParameters: {
            for (final resource in (config.resources ?? []))
              // obviously does not work as each resource is overridden by the one after
              'resource': resource
          },
        ),
      );

      if (tokenResponse == null ||
          tokenResponse.idToken == null ||
          tokenResponse.accessToken == null ||
          tokenResponse.accessTokenExpirationDateTime == null) {
        throw LogtoAuthException(
            LogtoAuthExceptions.authenticationError, "Invalid token response.");
      }

      final idToken = IdToken.unverified(tokenResponse.idToken!);

      // await _verifyIdToken(idToken, oidcConfig);

      await _tokenStorage.save(
        idToken: idToken,
        accessToken: tokenResponse.accessToken!,
        refreshToken: tokenResponse.refreshToken,
        expiresIn:
            tokenResponse.accessTokenExpirationDateTime!.millisecondsSinceEpoch,
      );
    } finally {
      _loading = false;
      if (_httpClient == null) httpClient.close();
    }
  }

  Future<void> signOut() async {
    // Throw error is authentication status not found
    final idToken = await _tokenStorage.idToken;

    final httpClient = _httpClient ?? http.Client();

    if (idToken == null) {
      throw LogtoAuthException(
          LogtoAuthExceptions.authenticationError, 'not authenticated');
    }

    try {
      final discoveryUri = utils.appendUriPath(config.endpoint, discoveryPath);
      try {
        await _appAuth.endSession(
          EndSessionRequest(
            discoveryUrl: discoveryUri,
            issuer: config.endpoint,
            // todo: include sign out redirect uri
            postLogoutRedirectUrl: "post sign out redirect uri",
            idTokenHint: idToken.serialization,
          ),
        );
      } catch (_) {}
      final oidcConfig = await _getOidcConfig(httpClient);

      // Revoke refresh token if exist
      final refreshToken = await _tokenStorage.refreshToken;

      if (refreshToken != null) {
        try {
          await logto_core.revoke(
            httpClient: httpClient,
            revocationEndpoint: oidcConfig.authorizationEndpoint,
            clientId: config.appId,
            token: refreshToken,
          );
        } catch (e) {
          // Do Nothing silently revoke the token
        }
      }

      await _tokenStorage.clear();
    } finally {
      if (_httpClient == null) {
        httpClient.close();
      }
    }
  }
}
