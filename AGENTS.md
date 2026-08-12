# Repository Guidelines for AI Agents & Contributors

This document outlines key conventions and rules for maintaining code quality and consistency. For setup, development commands, and architecture overview, refer to [`README.md`](./README.md).

## Project Organization

- **`lib/features/<feature>/`**: Each feature is organized into `domain/`, `data/`, and `presentation/` layers.
- **`lib/core/`**: Shared UI utilities, themes, and common widgets.
- **`lib/presentation/`**: App-level UI orchestration (e.g., `main_scaffold.dart`).
- **`test/`**: Unit and widget tests.
- **`web/`**: PWA assets (manifest, icons, `index.html`).

## Naming Conventions

- **Files & Folders**: `snake_case` (e.g., `main_scaffold.dart`, `roster_provider.dart`)
- **Classes & Interfaces**: `PascalCase` (e.g., `RosterProvider`, `RosterRepository`)
- **Constants**: `camelCase` (e.g., `appTitle = 'Church Staff'`)
- **Dart Formatting**: 2 spaces indentation; use `dart format lib test` before committing.

## Testing Guidelines

- **Framework**: `flutter_test`
- **Test Location**: `test/` directory
- **Naming Convention**: `<feature>_<unit>_test.dart` (e.g., `roster_provider_test.dart`)
- **Pre-commit Check**: Run `flutter test` before submitting a PR.

## Commit & PR Guidelines

### Commit Message Format

Follow **Conventional Commits** with scopes:

```
<type>(<scope>): <description>

[optional body]
```

**Types**: `feat`, `fix`, `refactor`, `style`, `test`, `docs`, `chore`

**Scope Examples**: `roster`, `dashboard`, `auth`, `firebase`, `pwa`

**Examples**:
- `feat(roster): add color picker for special events`
- `fix(auth): handle Firebase token refresh errors`
- `refactor(core): extract theme constants into separate file`
- `docs: update README with new build instructions`

### Pull Request Checklist

Before submitting:
- [ ] All tests pass: `flutter test`
- [ ] Code analysis passes: `flutter analyze`
- [ ] Code formatted: `dart format lib test`
- [ ] Commit messages follow Conventional Commits
- [ ] No hardcoded secrets (use `--dart-define` for sensitive values)
- [ ] If UI changes: include screenshots in PR description
- [ ] If security-sensitive: update `firestore.rules` if applicable

## Security & Configuration

- **Firebase Config**: Managed in `lib/firebase_options.dart`. Never hardcode secrets.
- **Environment Variables**: Use `--dart-define` for build-time configuration (see README for examples).
- **Firestore Security**: All rule changes must be documented in PRs that modify data access patterns.
- **API Keys**: Sensitive keys (e.g., `FCM_WEB_VAPID_KEY`, `GOOGLE_CALENDAR_API_KEY`) are GitHub Secrets; never commit them.

## State Management

- Use `provider` scoped to each feature when possible.
- Global providers (e.g., auth state) should live near `lib/main.dart`.
- Avoid mixing business logic with UI; keep repositories in the `data` layer.

## Code Quality Standards

- Pass `flutter analyze` (lints from `analysis_options.yaml` and `flutter_lints`).
- Keep functions small and single-responsibility.
- Document complex logic with comments.
- Use meaningful variable and function names.

## When to Update Firestore Rules

If your PR:
- Adds a new collection or document structure
- Changes authentication/authorization logic
- Modifies data access patterns

...then update `.github/workflows/deploy-flutter-pwa.yml` or relevant Firestore rules and document the changes clearly in the PR.

## Quick Reference

| Task | Command |
|------|---------|
| Install deps | `flutter pub get` |
| Run locally | `flutter run -d chrome` |
| Analyze | `flutter analyze` |
| Test | `flutter test` |
| Format | `dart format lib test` |
| Build (dev) | `flutter build web --release --base-href /` |
| Build (prod) | See `flutter build web --release --base-href / --dart-define=...` in README |

For more details, see the [`README.md`](./README.md).
