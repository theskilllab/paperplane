# lib/features

One folder per product feature (`connect/` for S1, `inbox/` for S2/S3,
`approvals/` for S4, `account/` for sign out; later PRs add questions,
issues and new issue). Features use
`lib/api/` for data and `lib/ui/` for components, and never import a UI
package directly.
