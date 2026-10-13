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
      _showMessage('No other registered devices are available.');
      return;
    }

    final selected = await showDialog<dynamic>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add member'),
        content: SizedBox(
          width: 380,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: options.length,
            itemBuilder: (_, index) {
              final device = options[index];
              return ListTile(
                leading: AccountAvatar(name: device.name, radius: 20),
                title: Text(device.name),
                subtitle: Text(device.platform),
                onTap: () => Navigator.pop(context, device),
              );
            },
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        ],
      ),
    );
    if (selected == null) return;

    try {
      await _controller.addMember(selected);
      _showMessage('${selected.name} added to the group.');
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
        title: const Text('Remove member?'),
        content: Text('Remove $label from this group?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await _controller.removeMember(member);
      _showMessage('$label removed.');
    } catch (e) {
      if (mounted) showErrorToast(context, error: e);
    }
  }

  void _showMessage(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
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
        title: const Text('Group details'),
        actions: [
          IconButton(
            onPressed: _controller.isLoading ? null : _controller.load,
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh),
          ),
          if (_controller.isOwner)
            IconButton(
              onPressed: _controller.isWorking ? null : _addMember,
              tooltip: 'Add member',
              icon: const Icon(Icons.person_add),
            ),
        ],
      ),
      body: _controller.isLoading
          ? const LocalLinkLoadingView(message: 'Loading members…')
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
                            Text('${_controller.members.length} member${_controller.members.length == 1 ? '' : 's'}'),
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
                      label: const Text('Add member'),
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
