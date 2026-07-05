import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:encrypt/encrypt.dart' as enc;
import 'package:pointycastle/key_derivators/api.dart';
import 'package:pointycastle/key_derivators/pbkdf2.dart';
import 'package:pointycastle/macs/hmac.dart';
import 'package:pointycastle/digests/sha256.dart';

class KeyDerivationService {
  KeyDerivationService._();

  static String _getAppSecret() {
    final p1 = String.fromCharCodes([77, 110, 100, 80, 108, 97, 121]);
    final p2 = "TemplSecret";
    final p3 = String.fromCharCodes([75, 101, 121, 48, 49]);
    return "$p1-$p2\_$p3";
  }

  static Uint8List _deriveKeys(Uint8List salt) {
    final secret = _getAppSecret();
    final derivator = PBKDF2KeyDerivator(HMac(SHA256Digest(), 64));

    const iterations = 15000;
    const keyLength = 64;

    derivator.init(Pbkdf2Parameters(salt, iterations, keyLength));

    return derivator.process(Uint8List.fromList(utf8.encode(secret)));
  }

  static String generateConfigSignature(String questId, bool isReadOnly) {
    final secret = _getAppSecret();
    final dataToSign = "${questId}_readOnly:$isReadOnly";

    final hmac = Hmac(sha256, utf8.encode(secret));
    final digest = hmac.convert(utf8.encode(dataToSign));
    return digest.toString();
  }

  static bool verifyConfigSignature(
    String questId,
    bool isReadOnly,
    String? signature,
  ) {
    if (signature == null || signature.isEmpty) return false;
    final expected = generateConfigSignature(questId, isReadOnly);
    return expected == signature;
  }

  static Uint8List encryptProtectedQuestData(Uint8List questData) {
    final random = Random.secure();

    final salt = Uint8List(16);
    for (var i = 0; i < 16; i++) {
      salt[i] = random.nextInt(256);
    }

    final ivBytes = Uint8List(16);
    for (var i = 0; i < 16; i++) {
      ivBytes[i] = random.nextInt(256);
    }
    final iv = enc.IV(ivBytes);

    final derived = _deriveKeys(salt);
    final aesKey = enc.Key(derived.sublist(0, 32));
    final hmacKey = derived.sublist(32, 64);

    final encrypter = enc.Encrypter(enc.AES(aesKey, mode: enc.AESMode.cbc));
    final encrypted = encrypter.encryptBytes(questData, iv: iv);
    final cipherText = Uint8List.fromList(encrypted.bytes);

    final hmac = Hmac(sha256, hmacKey);
    final hmacInput = BytesBuilder();
    hmacInput.add(ivBytes);
    hmacInput.add(cipherText);
    final mac = hmac.convert(hmacInput.toBytes()).bytes;

    final result = BytesBuilder();
    result.add(salt);
    result.add(ivBytes);
    result.add(mac);
    result.add(cipherText);

    return result.toBytes();
  }

  static Uint8List decryptProtectedQuestData(Uint8List payload) {
    if (payload.length < 16 + 16 + 32) {
      throw Exception("Неверный формат защищенного файла (слишком короткий)");
    }

    final salt = payload.sublist(0, 16);
    final ivBytes = payload.sublist(16, 32);
    final providedMac = payload.sublist(32, 64);
    final cipherText = payload.sublist(64);

    final derived = _deriveKeys(salt);
    final aesKey = enc.Key(derived.sublist(0, 32));
    final hmacKey = derived.sublist(32, 64);

    final hmac = Hmac(sha256, hmacKey);
    final hmacInput = BytesBuilder();
    hmacInput.add(ivBytes);
    hmacInput.add(cipherText);
    final expectedMac = hmac.convert(hmacInput.toBytes()).bytes;

    var macsEqual = true;
    for (var i = 0; i < 32; i++) {
      if (providedMac[i] != expectedMac[i]) {
        macsEqual = false;
      }
    }

    if (!macsEqual) {
      throw Exception(
        "Ошибка целостности данных: файл был модифицирован (HMAC не совпадает)",
      );
    }

    final iv = enc.IV(ivBytes);
    final encrypter = enc.Encrypter(enc.AES(aesKey, mode: enc.AESMode.cbc));

    try {
      final decrypted = encrypter.decryptBytes(
        enc.Encrypted(cipherText),
        iv: iv,
      );
      return Uint8List.fromList(decrypted);
    } catch (e) {
      throw Exception("Не удалось расшифровать данные файла: $e");
    }
  }

  static final enc.IV _legacyIv = enc.IV.fromUtf8("MndPlayerQuestIV");

  static Uint8List decryptLegacyQuestData(Uint8List encryptedData) {
    throw Exception("Legacy encryption format no longer supported.");
  }
}
