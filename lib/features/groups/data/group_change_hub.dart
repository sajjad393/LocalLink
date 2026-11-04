import 'dart:async';

/// Bundle G2: "this group changed" (info, members, photo, my state). The
/// group service says it; the Chats list, the group chat and Group info
/// read it again.
class GroupChangeHub {
  GroupChangeHub._();

  static final GroupChangeHub instance = GroupChangeHub._();

  final StreamController<String> _changes = StreamController<String>.broadcast();

  Stream<String> get changes => _changes.stream;

  void changed(String groupId) {
    if (groupId.isNotEmpty) _changes.add(groupId);
  }
}
