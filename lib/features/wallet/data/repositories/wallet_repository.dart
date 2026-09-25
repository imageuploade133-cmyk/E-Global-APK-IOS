import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:wallet/core/constants/app_strings.dart';
import 'package:wallet/core/storage/local_cache_service.dart';
import 'package:wallet/core/utils/logger.dart';
import 'package:wallet/features/wallet/data/models/wallet_model.dart';
import 'package:wallet/features/wallet/data/models/transaction_model.dart';

class WalletRepository {
  final LocalCacheService _cacheService = LocalCacheService();
  static const String _walletCacheKey = 'cached_user_wallet_v1';
  static const String _transactionsCacheKey = 'cached_user_transactions_v1';

  Future<WalletModel?> getCachedWallet() async {
    final cached = await _cacheService.read(_walletCacheKey);
    if (cached != null) {
      return WalletModel.fromJson(cached);
    }
    return null;
  }

  Future<List<TransactionModel>> getCachedTransactions() async {
    final cached = await _cacheService.read(_transactionsCacheKey);
    if (cached != null && cached['transactions'] is List) {
      final list = cached['transactions'] as List;
      return list.map((e) => TransactionModel.fromJson(e as Map<String, dynamic>)).toList();
    }
    return [];
  }

  Future<WalletModel?> fetchWalletFromApi([String? idToken]) async {
    try {
      final uri = Uri.parse('${AppStrings.baseUrl}api/wallets');
      final headers = <String, String>{
        'Content-Type': 'application/json',
      };
      if (idToken != null && idToken.isNotEmpty) {
        headers['Authorization'] = 'Bearer $idToken';
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
}
