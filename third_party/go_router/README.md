# go_router 17.5.0, patched

go_router 17.5.0 from pub.dev with one change: `ImperativeRouteMatch.complete`
does nothing when the page has completed already. Upstream throws
`Bad state: Future already completed` when a page is popped twice, which some
Android phones' back does (flutter/flutter#187326, still open).
`app/pubspec.yaml` uses it through `dependency_overrides`.

Once upstream has the fix, drop this folder and the override.
