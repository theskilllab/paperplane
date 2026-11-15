import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart'
    show FutureProviderFamily, NotifierProviderFamily;
import 'package:paperplane/api/api_error.dart';
import 'package:paperplane/api/models/approval.dart';
import 'package:paperplane/app/providers.dart';
import 'package:paperplane/core/submit_controller.dart';
import 'package:paperplane/features/inbox/company_providers.dart';

/// Everything S4 shows for one approval.
@immutable
class ApprovalDetail {
  /// Creates the detail.
  const new({
    required this.approval,
    this.linkedIssues = const [],
    this.requesterName,
  });

  /// The approval itself.
  final Approval approval;

  /// Issues the approval points at.
  final List<LinkedIssue> linkedIssues;

  /// Display name of the requesting agent, when known.
  final String? requesterName;
}

/// Loads one approval, its linked issues and the requester's name.
///
/// A failed agent-list or linked-issue call does not hide the approval: the
/// screen still shows and decides it, without the optional names or links.
final FutureProviderFamily<ApprovalDetail, String> approvalDetailProvider =
    FutureProvider.autoDispose.family<ApprovalDetail, String>((ref, id) async {
      final repository = ref.watch(approvalRepositoryProvider);
      final inboxRepository = ref.read(inboxRepositoryProvider);
      final company = ref.read(activeCompanyProvider);
      final approval = await repository.fetch(id);
      final linked = _tolerant(
        () => repository.linkedIssues(id),
        const <LinkedIssue>[],
      );
      final names = company == null
          ? Future.value(const <String, String>{})
          : _tolerant(
              () => inboxRepository.agentNames(company.id),
              const <String, String>{},
            );
      final agentId = approval.requestedByAgentId;
      return ApprovalDetail(
        approval: approval,
        linkedIssues: await linked,
        requesterName: agentId == null ? null : (await names)[agentId],
      );
    });

/// One shared in-flight state for both decision buttons (PRD G6).
class ApprovalDecision extends SubmitController<Approval> {
  /// Creates the controller for [approvalId].
  new(this.approvalId);

  /// Approval this decision belongs to.
  final String approvalId;
}

/// The decision state of one approval.
final NotifierProviderFamily<ApprovalDecision, SubmitState<Approval>, String>
approvalDecisionProvider = NotifierProvider.autoDispose
    .family<ApprovalDecision, SubmitState<Approval>, String>(
      ApprovalDecision.new,
    );

Future<T> _tolerant<T>(Future<T> Function() call, T fallback) async {
  try {
    return await call();
  } on ApiError {
    return fallback;
  }
}
