import 'id_token.dart';
import 'logto_storage_strategy.dart';

class _TokenStorageKeys {
  static const accessTokenKey = 'logto_access_token';
  static const refreshTokenKey = 'logto_refresh_token';
  static const idTokenKey = 'logto_id_token';
}

class TokenStorage {
  IdToken? _idToken;
  String? _accessToken;
  String? _refreshToken;

  late final LogtoStorageStrategy _storage;

  static TokenStorage? loaded;

  TokenStorage({
    required IdToken? idToken,
    required String? accessToken,
    required String? refreshToken,
    LogtoStorageStrategy? storageStrategy,
  }) {
    _storage = storageStrategy ?? SecureStorageStrategy();
    _idToken = idToken;
    _accessToken = accessToken;
    _refreshToken = refreshToken;
  }

  static Future<TokenStorage> fromPersistence({
    LogtoStorageStrategy? storageStrategy,
  }) async {
    final storage = storageStrategy ?? SecureStorageStrategy();
    final values = await Future.wait<String?>([
      storage.read(key: _TokenStorageKeys.accessTokenKey),
      storage.read(key: _TokenStorageKeys.refreshTokenKey),
      storage.read(key: _TokenStorageKeys.idTokenKey),
    ]);
    return TokenStorage(
      idToken: _decodeIdToken(values[2]),
      accessToken: values[0],
      refreshToken: values[1],
    );
  }

  Future<void> save() async {
    await Future.wait([
      setAccessToken(_accessToken),
      setIdToken(_idToken),
      setRefreshToken(_refreshToken),
    ]);
  }

  static IdToken? _decodeIdToken(String? encoded) {
    if (encoded == null) return null;
    return IdToken.unverified(encoded);
  }

  static String? _encodeIdToken(IdToken? token) {
    return token?.toCompactSerialization();
  }

  IdToken? get idToken => _idToken;

  String? get accessToken => _accessToken;

  String? get refreshToken => _refreshToken;

  Future<void> setIdToken(IdToken? idToken) async {
    _idToken = idToken;
    await _storage.write(
      key: _TokenStorageKeys.idTokenKey,
      value: _encodeIdToken(idToken),
    );
  }

  Future<void> setAccessToken(String? accessToken) async {
    _accessToken = accessToken;
    await _storage.write(
      key: _TokenStorageKeys.accessTokenKey,
      value: accessToken,
    );
  }

  Future<void> setRefreshToken(String? refreshToken) async {
    _refreshToken = refreshToken;
    await _storage.write(
      key: _TokenStorageKeys.refreshTokenKey,
      value: refreshToken,
    );
  }

  Future<void> clear() async {
    _accessToken = null;
    _refreshToken = null;
    _idToken = null;
    await Future.wait<void>([
      _storage.delete(key: _TokenStorageKeys.accessTokenKey),
      _storage.delete(key: _TokenStorageKeys.refreshTokenKey),
      _storage.delete(key: _TokenStorageKeys.idTokenKey),
    ]);
  }
}
