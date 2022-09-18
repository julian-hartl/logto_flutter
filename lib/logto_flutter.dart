import 'package:logto_dart_sdk/src/utilities/logto_storage_strategy.dart';
import 'package:logto_dart_sdk/src/utilities/token_storage.dart';

abstract class LogtoFlutter {
  static Future<void> initialize(
      {LogtoStorageStrategy? storageStrategy}) async {
    final storage = await TokenStorage.fromPersistence(
      storageStrategy: storageStrategy,
    );
    TokenStorage.loaded = storage;
  }
}
