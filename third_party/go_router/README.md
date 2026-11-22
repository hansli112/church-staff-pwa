# go_router 17.5.0, patched

go_router 17.5.0 from pub.dev with two changes for a page popped twice, which
some Android phones' back does (flutter/flutter#187326, still open): upstream
throws `Bad state: Future already completed`.

- `ImperativeRouteMatch.complete` does nothing when the page has completed
  already.
- `GoRouterDelegate` pops a route once: popped again, it is left alone
  (`_popped`), not completed a second time.
`app/pubspec.yaml` uses it through `dependency_overrides`.

Once upstream has the fix, drop this folder and the override.
