class LocalAccount {
  final String id;
  final String username;
  final String createdAt;

  const LocalAccount({required this.id, required this.username, required this.createdAt});

  factory LocalAccount.fromJson(Map<String, dynamic> json) => LocalAccount(
        id: json['id']?.toString() ?? '',
        username: json['username']?.toString() ?? '',
        createdAt: json['created_at']?.toString() ?? '',
      );
}
