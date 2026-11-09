# lib/core

- `SubmitController<T>`: runs one write at a time (one tap, one request) and
  keeps the screen's input on failure. Declare one provider per action; call
  `submit(action, onAlreadyHandled: refetch)`.
- `presentationFor(ApiError)`: the single mapping from errors to user copy
  (PRD G2–G5, G10). Do not write error text in screens.

For loading, error and offline states of reads, use `AsyncStateView` from
`lib/ui/`.
