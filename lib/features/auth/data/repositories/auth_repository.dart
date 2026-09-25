import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:wallet/core/constants/app_strings.dart';
import 'package:wallet/core/security/secure_storage_service.dart';
import 'package:wallet/core/utils/logger.dart';
import 'package:wallet/features/auth/data/models/user_model.dart';

class AuthRepository {
  final SecureStorageServiceImpl _storage = SecureStorageServiceImpl();

  FirebaseAuth? get _firebaseAuth {
    try {
      return FirebaseAuth.instance;
    } catch (_) {
      return null;
    }
  }

  Future<UserModel?> login({
    required String email,
    required String password,
  }) async {
    try {
      final auth = _firebaseAuth;
      if (auth == null) {
        throw Exception('Firebase Auth is not initialized');
      }

      final userCredential = await auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );

      final user = userCredential.user;
      if (user != null) {
        final idToken = await user.getIdToken();
        await _storage.write(AppStrings.credentialsKey, idToken ?? user.uid);
        await _storage.write(AppStrings.savedEmailKey, email);

        // Fetch user profile from backend
        final uri = Uri.parse('${AppStrings.baseUrl}api/admin/profile');
        final response = await http.get(uri, headers: {
          'Authorization': 'Bearer $idToken',
        }).timeout(const Duration(seconds: 8));

        if (response.statusCode == 200) {
          final jsonMap = json.decode(response.body) as Map<String, dynamic>;
          return UserModel.fromJson(jsonMap);
        }

        return UserModel(
          uid: user.uid,
          email: user.email ?? email,
          name: user.displayName ?? email.split('@').first.toUpperCase(),
        );
      }
    } catch (e) {
      AppLogger.e('Firebase authentication error', e);
      rethrow;
    }
    return null;
  }

  Future<void> signOut() async {
    try {
      await _firebaseAuth?.signOut();
      await _storage.delete(AppStrings.credentialsKey);
    } catch (e) {
      AppLogger.e('Sign out error', e);
    }
  }
}
