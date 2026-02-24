# iOS Vault + Git Flow (Current)

## Scope
This document covers the iOS flow only:
- app launch and mandatory vault selection
- vault navigation (Apple Notes style folders)
- Git setup (OAuth PKCE + origin + clone)
- sync actions (add/commit/pull/push)
- diagnostics and common failure states

## 1) Launch and Vault Onboarding
Entry points:
- `FSNotes iOS/ViewController.swift` (`showGitVaultOnboardingIfNeeded`)
- `FSNotes iOS/ViewController+More.swift` (`openGitSettings`, `GitVaultPickerViewController`)

Behavior:
1. On first launch (or when no sidebar vault exists), onboarding is forced.
2. User must choose an existing folder as vault (no auto-created vault).
3. Optionally user can start from GitHub: enter repository URL -> pick target folder.
4. Picked folder is stored via security-scoped bookmark.
5. Only one vault is supported. Choosing a new vault replaces the previous one.

## 2) Folder UX (Apple Notes style)
Entry points:
- `FSNotes iOS/FolderViewController.swift`

Behavior:
1. Sidebar root shows folder list.
2. Opening a folder shows its direct child folders first, then notes.
3. Opening a subfolder does not repeat parent folder as content item.

## 3) Git Settings and OAuth (PKCE)
Entry points:
- `FSNotes iOS/Preferences/GitViewController.swift`
- `FSNotes iOS/SceneDelegate.swift` (OAuth callback routing)

Behavior:
1. Git settings binds to git root project (`getGitProject() ?? project`).
2. OAuth uses browser-based GitHub authorization (PKCE).
3. Callback is handled by custom URL scheme (`fsnotes://oauth/callback`).
4. Code exchange goes through backend endpoint from Info.plist.
5. Access token is persisted in keychain; auth mode set to oauth.

## 4) Origin Resolution Strategy
Core implementation:
- `FSNotesCore/Extensions/Project+Git.swift`

`getGitOrigin()` fallback order:
1. `project.settings.gitOrigin`
2. global `UserDefaultsManagement.gitOrigin`
3. inherited origin from parent project chain
4. read from local repository remotes / `.git/config`

Recovered origin is saved back to both project settings and global defaults.

## 5) Repository Discovery Strategy
Core implementation:
- `FSNotesCore/Extensions/Project+Git.swift`

Lookup candidates include:
1. inline repo at `<vault>/.git`
2. iCloud git storage repo at `<settingsKey prefix>.git`
3. legacy names (`<key> - <label>.git`, hashed key variants)
4. fallback scan by reading each repo's `core.worktree` and matching current vault path

## 6) Sync Action Semantics
Core implementation:
- `FSNotesCore/Extensions/Project+Git.swift` (`gitDo`, `saveRevision`)

UI entry points:
- `FSNotes iOS/View/NotesTableView.swift` (`Git Add/commit/push`)
- `FSNotes iOS/FolderViewController.swift` (`Git Sync`)
- `FSNotes iOS/Preferences/GitViewController.swift` (main action button)

Behavior:
1. All sync actions resolve to git root project first.
2. Success always shows user-visible confirmation.
3. Error message mapping is centralized in `Project.gitSyncErrorMessage(_:)`.

## 7) Diagnostics
Entry point:
- `FSNotes iOS/Preferences/GitViewController.swift` (`runDiagnosticsIfNeeded`)

Status line includes:
- vault
- settingsKey prefix
- repo found/missing
- repository candidates
- gitStorage repository count
- global origin present/empty
- remotes summary
- origin source (settings/auto/none)

This is the primary source for debugging misconfigured vault/git state.

## 8) Known Critical Signals
- `repo=missing` + `gitStorageCount=0`:
  local repo does not exist yet (needs init/clone path)
- `origin=empty` + `originSource=none`:
  origin not configured anywhere (vault/global/parent/local config)
- `Operation not permitted`:
  security-scoped folder access lost; re-pick folder
