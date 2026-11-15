# lib/features

One folder per product feature (`connect/` for S1, `inbox/` for S2/S3,
`account/` for sign out; later PRs add thread/approvals). Features use
`lib/api/` for data and `lib/ui/` for components, and never import a UI
package directly.
