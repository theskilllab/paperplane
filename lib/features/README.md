# lib/features

One folder per product feature (inbox, thread, approvals, ...). Features use
`lib/api/` for data and `lib/ui/` for components, and never import a UI
package directly.
