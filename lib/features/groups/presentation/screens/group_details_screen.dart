import 'package:locallink/core/widgets/link_toast.dart';
import 'package:flutter/material.dart';
import 'package:locallink/core/models/group.dart';
import 'package:locallink/features/groups/domain/group_repository_contract.dart';
import 'package:locallink/features/groups/bloc/group_members_bloc.dart';
import 'package:locallink/features/groups/presentation/widgets/group_member_tile.dart';
import 'package:locallink/core/widgets/account_avatar.dart';
import 'package:locallink/core/widgets/error_toast.dart';
import 'package:locallink/core/widgets/group_avatar.dart';
import 'package:locallink/core/widgets/local_link_bloc_builder.dart';
import 'package:locallink/core/widgets/local_link_state_view.dart';
import 'package:locallink/l10n/l10n.dart';

class GroupDetailsScreen extends StatefulWidget {
  final LocalGroup group;
  final String localDeviceId;
  final GroupRepositoryContract groups;

  const GroupDetailsScreen({
    super.key,
    required this.group,
    required this.localDeviceId,
    required this.groups,
  });

  @override
  State<GroupDetailsScreen> createState() => _GroupDetailsScreenState();
}

class _GroupDetailsScreenState extends State<GroupDetailsScreen> {
  late final GroupMembersBloc _controller;

  @override
  void initState() {
    super.initState();
    _controller = GroupMembersBloc(
      repository: widget.groups,
      group: widget.group,
      localDeviceId: widget.localDeviceId,
    );
    _controller.load();
  }


  Future<void> _addMember() async {
    if (!_controller.isOwner || _controller.isWorking) return;
    final options = _controller.addableDevices;
    if (options.isEmpty) {
      _showMessage(L.t.noOtherRegisteredDevicesAreAvailable);
      return;
    }

    final selected = await showDialog<dynamic>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(L.t.addMember),
        content: SizedBox(
          width: 380,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: options.length,
            itemBuilder: (_, index) {
              final device = options[index];
              return ListTile(
                leading: AccountAvatar(name: device.name, radius: 20, peerId: device.id),
                title: Text(device.name),
                subtitle: Text(device.platform),
                onTap: () => Navigator.pop(context, device),
              );
            },
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text(L.t.cancel)),
        ],
      ),
    );
    if (selected == null) return;

    try {
      await _controller.addMember(selected);
      _showMessage(L.t.addedToTheGroup(selected.name));
    } catch (e) {
      if (mounted) showErrorToast(context, error: e);
    }
  }

  Future<void> _removeMember(GroupMember member) async {
    if (!_controller.isOwner || _controller.isWorking || member.deviceId == widget.group.ownerId) return;
    final label = member.name.isEmpty ? member.deviceId : member.name;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(L.t.removeMember2),
        content: Text(L.t.removeFromThisGroup(label)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(L.t.cancel)),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: Text(L.t.remove),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await _controller.removeMember(member);
      _showMessage(L.t.removed2(label));
    } catch (e) {
      if (mounted) showErrorToast(context, error: e);
    }
  }

  void _showMessage(String text) {
    if (!mounted) return;
    LinkToast.show(context, text, kind: LinkToast.guess(text));
  }

  @override
  void dispose() {
    _controller.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LocalLinkBlocBuilder(bloc: _controller, builder: (context, state) => Scaffold(
      appBar: AppBar(
        title: Text(L.t.groupDetails),
        actions: [
          IconButton(
            onPressed: _controller.isLoading ? null : _controller.load,
            tooltip: L.t.refresh,
            icon: const Icon(Icons.refresh),
          ),
          if (_controller.isOwner)
            IconButton(
              onPressed: _controller.isWorking ? null : _addMember,
              tooltip: L.t.addMember,
              icon: const Icon(Icons.person_add),
            ),
        ],
      ),
      body: _controller.isLoading
          ? LocalLinkLoadingView(message: L.t.loadingMembers)
          : RefreshIndicator(
              onRefresh: _controller.load,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16),
                children: [
                  Row(
                    children: [
                      const GroupAvatar(radius: 28),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              widget.group.name,
                              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            Text(L.t.member2(_controller.members.length, _controller.members.length == 1 ? '' : 's')),
                          ],
                        ),
                      ),
                    ],
                  ),
                  if (_controller.error != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: LocalLinkInlineError(
                        message: friendlyErrorMessage(_controller.error),
                        onRetry: _controller.load,
                      ),
                    ),
                  if (_controller.isOwner)
                    FilledButton.icon(
                      onPressed: _controller.isWorking ? null : _addMember,
                      icon: const Icon(Icons.person_add),
                      label: Text(L.t.addMember),
                    ),
                  const SizedBox(height: 12),
                  ..._controller.members.map(
                    (member) => GroupMemberTile(
                      member: member,
                      isOwner: member.deviceId == widget.group.ownerId,
                      canRemove: _controller.isOwner,
                      onRemove: () => _removeMember(member),
                    ),
                  ),
                ],
              ),
            ),
    ));
  }
}
