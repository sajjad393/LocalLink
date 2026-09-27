import 'package:locallink/core/models/account.dart';
import 'package:locallink/core/models/attachment.dart';
import 'package:locallink/core/models/call.dart';
import 'package:locallink/core/models/device.dart';
import 'package:locallink/core/models/group.dart';
import 'package:locallink/core/models/message.dart';
import 'package:locallink/core/models/profile.dart';

class AccountRestoreManifest {
  final int version;
  final LocalAccount account;
  final LocalProfile profile;
  final List<Device> devices;
  final Map<String, int> counts;
  final bool cryptoBackupAvailable;
  final String cryptoBackupUpdatedAt;
  final int historicalIdentityKeys;
  final String generatedAt;

  const AccountRestoreManifest({
    required this.version,
    required this.account,
    required this.profile,
    required this.devices,
    required this.counts,
    required this.cryptoBackupAvailable,
    required this.cryptoBackupUpdatedAt,
    required this.historicalIdentityKeys,
    required this.generatedAt,
  });

  factory AccountRestoreManifest.fromJson(Map<String, dynamic> json) => AccountRestoreManifest(
        version: int.tryParse(json['version']?.toString() ?? '') ?? 1,
        account: LocalAccount.fromJson(Map<String, dynamic>.from(json['account'] as Map)),
        profile: LocalProfile.fromJson(Map<String, dynamic>.from(json['profile'] as Map)),
        devices: (json['devices'] as List? ?? []).map((e) => Device.fromJson(Map<String, dynamic>.from(e as Map))).toList(),
        counts: (json['counts'] as Map? ?? {}).map((key, value) => MapEntry(key.toString(), int.tryParse(value.toString()) ?? 0)),
        cryptoBackupAvailable: json['crypto_backup_available'] == true,
        cryptoBackupUpdatedAt: json['crypto_backup_updated_at']?.toString() ?? '',
        historicalIdentityKeys: int.tryParse(json['historical_identity_keys']?.toString() ?? '') ?? 0,
        generatedAt: json['generated_at']?.toString() ?? '',
      );
}

class AccountRestorePage {
  final String scope;
  final LocalAccount? account;
  final LocalProfile? profile;
  final List<Device> devices;
  final List<LocalGroup> groups;
  final List<GroupMember> groupMembers;
  final List<Message> messages;
  final List<GroupMessage> groupMessages;
  final List<CallRecord> calls;
  final List<Attachment> files;
  final String nextCursor;
  final bool hasMore;

  const AccountRestorePage({
    required this.scope,
    required this.account,
    required this.profile,
    required this.devices,
    required this.groups,
    required this.groupMembers,
    required this.messages,
    required this.groupMessages,
    required this.calls,
    required this.files,
    required this.nextCursor,
    required this.hasMore,
  });

  factory AccountRestorePage.fromJson(String scope, Map<String, dynamic> json) => AccountRestorePage(
        scope: scope,
        account: json['account'] is Map ? LocalAccount.fromJson(Map<String, dynamic>.from(json['account'] as Map)) : null,
        profile: json['profile'] is Map ? LocalProfile.fromJson(Map<String, dynamic>.from(json['profile'] as Map)) : null,
        devices: (json['devices'] as List? ?? []).map((e) => Device.fromJson(Map<String, dynamic>.from(e as Map))).toList(),
        groups: (json['groups'] as List? ?? []).map((e) => LocalGroup.fromJson(Map<String, dynamic>.from(e as Map))).toList(),
        groupMembers: (json['group_members'] as List? ?? []).map((e) => GroupMember.fromJson(Map<String, dynamic>.from(e as Map))).toList(),
        messages: (json['messages'] as List? ?? []).map((e) => Message.fromJson(Map<String, dynamic>.from(e as Map))).toList(),
        groupMessages: (json['group_messages'] as List? ?? []).map((e) => GroupMessage.fromJson(Map<String, dynamic>.from(e as Map))).toList(),
        calls: (json['calls'] as List? ?? []).map((e) => CallRecord.fromJson(Map<String, dynamic>.from(e as Map))).toList(),
        files: (json['files'] as List? ?? []).map((e) => Attachment.fromJson(Map<String, dynamic>.from(e as Map))).toList(),
        nextCursor: json['next_cursor']?.toString() ?? '',
        hasMore: json['has_more'] == true,
      );
}

class CryptoBackupEnvelope {
  final bool available;
  final String envelope;
  final int size;
  final String createdAt;
  final String updatedAt;

  const CryptoBackupEnvelope({required this.available, required this.envelope, required this.size, required this.createdAt, required this.updatedAt});

  factory CryptoBackupEnvelope.fromJson(Map<String, dynamic> json) => CryptoBackupEnvelope(
        available: json['available'] == true,
        envelope: json['envelope']?.toString() ?? '',
        size: int.tryParse(json['size']?.toString() ?? '') ?? 0,
        createdAt: json['created_at']?.toString() ?? '',
        updatedAt: json['updated_at']?.toString() ?? '',
      );
}
