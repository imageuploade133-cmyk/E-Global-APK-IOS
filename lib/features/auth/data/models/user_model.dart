class UserModel {
  final String uid;
  final String email;
  final String name;
  final String? firstName;
  final String? lastName;
  final String? phoneNumber;
  final String? profileImage;
  final String? accountNumber;
  final String? bankName;
  final int kycLevel;
  final bool emailVerified;
  final bool biometricEnabled;

  const UserModel({
    required this.uid,
    required this.email,
    required this.name,
    this.firstName,
    this.lastName,
    this.phoneNumber,
    this.profileImage,
    this.accountNumber,
    this.bankName,
    this.kycLevel = 1,
    this.emailVerified = false,
    this.biometricEnabled = false,
  });

  factory UserModel.fromJson(Map<String, dynamic> json) {
    return UserModel(
      uid: json['uid'] as String? ?? json['id'] as String? ?? '',
      email: json['email'] as String? ?? '',
      name: json['name'] as String? ?? json['fullName'] as String? ?? 'User',
      firstName: json['firstName'] as String?,
      lastName: json['lastName'] as String?,
      phoneNumber: json['phoneNumber'] as String? ?? json['phone'] as String?,
      profileImage: json['profileImage'] as String? ?? json['photoURL'] as String?,
      accountNumber: json['accountNumber'] as String? ?? json['virtualAccountNumber'] as String?,
      bankName: json['bankName'] as String? ?? json['virtualBankName'] as String?,
      kycLevel: json['kycLevel'] as int? ?? 1,
      emailVerified: json['emailVerified'] as bool? ?? false,
      biometricEnabled: json['biometricEnabled'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'uid': uid,
      'email': email,
      'name': name,
      'firstName': firstName,
      'lastName': lastName,
      'phoneNumber': phoneNumber,
      'profileImage': profileImage,
      'accountNumber': accountNumber,
      'bankName': bankName,
      'kycLevel': kycLevel,
      'emailVerified': emailVerified,
      'biometricEnabled': biometricEnabled,
    };
  }
}
