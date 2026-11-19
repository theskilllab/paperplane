import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart'
    show FutureProviderFamily, NotifierProviderFamily;
import 'package:paperplane/api/models/interaction.dart';
import 'package:paperplane/app/providers.dart';
import 'package:paperplane/core/submit_controller.dart';

/// Identifies one interaction on one issue.
@immutable
class InteractionKey {
  /// Creates the key.
  const new({required this.issueId, required this.interactionId});

  /// Issue that owns the interaction.
  final String issueId;

  /// Interaction id.
  final String interactionId;

  @override
  bool operator ==(Object other) =>
      other is InteractionKey &&
      other.issueId == issueId &&
      other.interactionId == interactionId;

  @override
  int get hashCode => Object.hash(issueId, interactionId);
}

/// Loads one interaction by re-reading the issue's list (there is no
/// get-by-id call). Null means the item is gone or already resolved away.
final FutureProviderFamily<Interaction?, InteractionKey> interactionProvider =
    FutureProvider.autoDispose.family<Interaction?, InteractionKey>(
      (ref, key) => ref
          .watch(interactionRepositoryProvider)
          .find(key.issueId, key.interactionId),
    );

/// One shared in-flight state for the sheet's answer buttons (PRD G6).
class InteractionWrite extends SubmitController<Interaction> {
  /// Creates the controller for [key].
  new(this.key);

  /// Interaction this write belongs to.
  final InteractionKey key;
}

/// The write state of one interaction.
final NotifierProviderFamily<
  InteractionWrite,
  SubmitState<Interaction>,
  InteractionKey
>
interactionWriteProvider = NotifierProvider.autoDispose
    .family<InteractionWrite, SubmitState<Interaction>, InteractionKey>(
      InteractionWrite.new,
    );
