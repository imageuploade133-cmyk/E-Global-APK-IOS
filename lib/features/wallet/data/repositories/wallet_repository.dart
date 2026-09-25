import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:wallet/core/constants/app_strings.dart';
import 'package:wallet/core/security/secure_storage_service.dart';
import 'package:wallet/core/storage/local_cache_service.dart';
import 'package:wallet/core/utils/logger.dart';
import 'package:wallet/features/auth/data/models/user_model.dart';
import 'package:wallet/features/wallet/data/models/wallet_model.dart';
import 'package:wallet/features/wallet/data/models/transaction_model.dart';

class WalletRepository {
  final LocalCacheService _cacheService = LocalCacheService();
  final SecureStorageServiceImpl _secureStorage = SecureStorageServiceImpl();
  static const String _walletCacheKey = 'cached_user_wallet_v1';
  static const String _transactionsCacheKey = 'cached_user_transactions_v1';
  static const String _userCacheKey = 'cached_user_profile_v1';

  Future<String?> _resolveIdToken() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        return await user.getIdToken();
      }
      return await _secureStorage.read(AppStrings.credentialsKey);
    } catch (_) {
      return await _secureStorage.read(AppStrings.credentialsKey);
    }
  }

  Future<UserModel?> getCachedUser() async {
    final cached = await _cacheService.read(_userCacheKey);
    if (cached != null) {
      return UserModel.fromJson(cached);
    }
    return null;
  }

  Future<UserModel?> fetchUserProfileFromApi() async {
    try {
      final token = await _resolveIdToken();
      if (token == null || token.isEmpty) return await getCachedUser();

      final uri = Uri.parse('${AppStrings.baseUrl}api/admin/profile');
      final response = await http.get(uri, headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      }).timeout(const Duration(seconds: 8));

      if (response.statusCode >= 200 && response.statusCode < 300) {
        final jsonMap = json.decode(response.body) as Map<String, dynamic>;
        final user = UserModel.fromJson(jsonMap);
        await _cacheService.save(_userCacheKey, user.toJson());
        return user;
      }
    } catch (e) {
      AppLogger.e('Error fetching user profile', e);
    }
    return await getCachedUser();
  }

  Future<WalletModel?> getCachedWallet() async {
    final cached = await _cacheService.read(_walletCacheKey);
    if (cached != null) {
      return WalletModel.fromJson(cached);
    }
    return null;
  }

  Future<WalletModel?> fetchWalletFromApi([String? explicitToken]) async {
    try {
      final token = explicitToken ?? await _resolveIdToken();
      final uri = Uri.parse('${AppStrings.baseUrl}api/wallets');
      final headers = <String, String>{
        'Content-Type': 'application/json',
      };
      if (token != null && token.isNotEmpty) {
        headers['Authorization'] = 'Bearer $token';
      }

      final response = await http.get(uri, headers: headers).timeout(const Duration(seconds: 8));
      if (response.statusCode >= 200 && response.statusCode < 300) {
        final jsonMap = json.decode(response.body) as Map<String, dynamic>;
        if (jsonMap['success'] == true) {
          final wallet = WalletModel.fromJson(jsonMap);
          await _cacheService.save(_walletCacheKey, wallet.toJson());
          return wallet;
        }
      }
    } catch (e) {
      AppLogger.e('Error fetching wallet from API', e);
    }
    return await getCachedWallet();
  }

  Future<List<TransactionModel>> getCachedTransactions() async {
    final cached = await _cacheService.read(_transactionsCacheKey);
    if (cached != null && cached['transactions'] is List) {
      final list = cached['transactions'] as List;
      return list.map((e) => TransactionModel.fromJson(e as Map<String, dynamic>)).toList();
    }
    return [];
  }

  Future<List<TransactionModel>> fetchTransactionsFromApi() async {
    try {
      final token = await _resolveIdToken();
      if (token == null || token.isEmpty) return await getCachedTransactions();

      final uri = Uri.parse('${AppStrings.baseUrl}api/wallets');
      final response = await http.get(uri, headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      }).timeout(const Duration(seconds: 8));

      if (response.statusCode >= 200 && response.statusCode < 300) {
        final jsonMap = json.decode(response.body) as Map<String, dynamic>;
        if (jsonMap['transactions'] is List) {
          final rawList = jsonMap['transactions'] as List;
          final txs = rawList.map((e) => TransactionModel.fromJson(e as Map<String, dynamic>)).toList();
          await _cacheService.save(_transactionsCacheKey, {'transactions': rawList});
          return txs;
        }
      }
    } catch (e) {
      AppLogger.e('Error fetching transactions from API', e);
    }
    return await getCachedTransactions();
  }
}
