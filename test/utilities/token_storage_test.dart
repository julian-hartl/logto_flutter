import 'package:flutter_test/flutter_test.dart';
import 'package:logto_dart_sdk/src/utilities/id_token.dart';
import 'package:logto_dart_sdk/src/utilities/logto_storage_strategy.dart';
import 'package:logto_dart_sdk/src/utilities/token_storage.dart';

import '../mocks/mock_storage.dart';

void main() {
  group('token storage test', () {
    late TokenStorage sut;
    const refreshToken = 'refresh_token';
    const accessToken = 'access_token';
    final idToken = IdToken.unverified(
        'eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCIsImtpZCI6IkNza2w2SDRGR3NpLXE0QkVPT1BQOWJlbHNoRGFHZjd3RXViVU5KQllwQmsifQ.eyJzdWIiOiJzV0FWNG96MHhnN1giLCJuYW1lIjoiSnVsaWFuIEhhcnRsIiwicGljdHVyZSI6Imh0dHBzOi8vYXZhdGFycy5naXRodWJ1c2VyY29udGVudC5jb20vdS85MDc5OTU2Mz92PTQiLCJ1c2VybmFtZSI6bnVsbCwicm9sZV9uYW1lcyI6W10sImF0X2hhc2giOiI4Und3Y051UFlwcHRwWUx5MjctaEFBIiwiYXVkIjoieGdTeFcwTURwVnFXMkdEdkNubE5iIiwiZXhwIjoxNjYzNTEzNDU3LCJpYXQiOjE2NjM1MDk4NTcsImlzcyI6Imh0dHBzOi8vbG9ndG8uZGV2L29pZGMifQ.U3Yn3P7Vk32lpEXjNTV9NKT9PBqM1JT8sn8jdmu0MIHLhJtdUZUxGFuiPYRDDqw7EKIsmr23VXNeKELsw7Xd7mRBTWYPLGQKDOzorVyiLmdVLuxEQYTJSEsI2qs51GZyFqYgaQHczxmOaqYKnr83RGifoNkjgBXYdIozVmAy3V67ddnHfstv7TN-f2-AgQ90zoa00RF_5HbD60_Hhl8RdDz92Y_wJ3dD5PeUp33rGpP319txxdU1DYk44cpH5AxbICunigx5dqZMYnD3Xy1B4jY5BNI6WBNMnFeDbmEQmNg9CijVAvqRN9JBzOpIEXbiznz-tb0RLOngrU3XitvAfR7NsF9YHnqp8XQrQ9itF6sI6fgALDL4FLlAOM58tlHk5M95F4G28H6KvM27n1I5TtFlUzMx1C6mR721wLbAE3l6HZoSU9heWz1liCdk_yNswhJSkFRk9rH1daieeRC_AH_6w3ufBXZ_rTOA9ziuba7C0mizp4SGQxXu57CGO8P80rkUVl-A6Z9_2IQNLfK6khlandYIwNSmpdt4OQn7DZp5eI7yXm2IIpouE304q27rgXl3wpcfHDilxniIGqKs7O-zO6uFNfZljCpvP2ZJNxzuCxizJ3eyGOqDsrLVnIONqrjpiYk2TO1MAdpzZpwKwKm2BRH3fpkDaoplwCPmqDs');
    late LogtoStorageStrategy storageStrategy;

    setUp(() {
      storageStrategy = MockStorageStrategy();
      sut = TokenStorage(
        idToken: idToken,
        accessToken: accessToken,
        refreshToken: refreshToken,
        storageStrategy: storageStrategy,
      );
    });
    tearDown(() async {
      await sut.clear();
    });
    test('should set access token locally and persist it', () async {
      await sut.setAccessToken(accessToken);

      expect(sut.accessToken, equals(accessToken));
      final persistedStorage = await TokenStorage.fromPersistence(
        storageStrategy: storageStrategy,
      );
      expect(persistedStorage.accessToken, accessToken);
    });

    test('should set refresh token locally and persist it', () async {
      await sut.setRefreshToken(refreshToken);

      expect(sut.refreshToken, equals(refreshToken));
      final persistedStorage = await TokenStorage.fromPersistence(
        storageStrategy: storageStrategy,
      );
      expect(persistedStorage.refreshToken, refreshToken);
    });

    test('should set id token locally and persist it', () async {
      await sut.setIdToken(idToken);

      expect(sut.idToken, equals(idToken));
      final persistedStorage = await TokenStorage.fromPersistence(
        storageStrategy: storageStrategy,
      );
      expect(persistedStorage.idToken, isNotNull);
    });

    test('save method should persist current state of token storage', () async {
      await sut.save();

      final persistedStorage = await TokenStorage.fromPersistence(
        storageStrategy: storageStrategy,
      );

      expect(persistedStorage.accessToken, accessToken);
      expect(persistedStorage.refreshToken, refreshToken);
      expect(persistedStorage.idToken, isNotNull);
    });

    test('clear method should delete persisted state', () async {
      await sut.save();
      await sut.clear();
      final persistedStorage = await TokenStorage.fromPersistence(
        storageStrategy: storageStrategy,
      );

      expect(persistedStorage.accessToken, null);
      expect(persistedStorage.refreshToken, null);
      expect(persistedStorage.idToken, null);
    });

    test('clear method should delete in memory state', () async {
      await sut.save();
      await sut.clear();

      expect(sut.accessToken, null);
      expect(sut.refreshToken, null);
      expect(sut.idToken, null);
    });
  });
}
