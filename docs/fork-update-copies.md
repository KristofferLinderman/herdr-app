# Fork update: review copies of shipped mods and layouts

Extends the fork's update flow (`app.fork_update`, `scripts/fork-update.sh`, commit c33a823) so that an update also checks Kristoffer's copies of shipped mods and layouts, and Kristoffer's own mods, against what changed upstream, and asks how to handle each one.

## Current flow (unchanged parts)

- Fork builds check the stable release line every hour without downloading (`check_fork` in `src/update.rs`).
- The update pill says "Herdr X is out" and has "What changed" (the release notes) and "Prepare update".
- "Prepare update" runs `app.fork_update`: opens `FORK_AGENT` (default `opencode`) in `FORK_DIR` with `fork_prompt(version)`, which runs `scripts/fork-update.sh <version>`: merge the tag, test, install into /Applications/Herdr.app, push (with gh's login when gh is signed in: the keychain helper can't prompt from the agent's terminal).

## Decisions

- **Changelog:** the pill stays as it is. "What changed" already shows the release notes before updating. Nothing about copies is added to the pill or the notes.
- **Who checks copies:** the update agent, as part of the same session that runs `fork-update.sh`.
- **When to ask, when to edit:** the agent analyzes and asks before installing (or, at the latest, before Kristoffer restarts). It applies the edits only after Kristoffer has restarted Herdr into the new build. Copies hot-reload on save, so editing them while the old app runs could load code that uses APIs the old app lacks. Terminals survive the restart (herdr-core keeps them), so the same agent session continues.
- **Ask every time:** every copy whose original changed between the two versions is brought up, even when the change looks unrelated to what the copy customized (e.g. a bug fix elsewhere in the file). No silent porting.
- **Choices per copy:**
  1. **Keep copy as is:** skip the upstream change. Set `cloned_from.version` to the new version so the same changes don't come up again next time.
  2. **Drop copy, use original:** upstream now covers what the copy did (or Kristoffer no longer wants it). Delete the copy and point everything that referenced it back to the original.
  3. **Re-clone and reapply:** take the new original fresh (`herdr-app do mod.clone` / `layout.clone`) and re-apply the copy's customizations on top. The new clone gets a fresh `cloned_from` from the app.
  - There is no "merge" choice and no "decide later" choice.
- **Own mods (not copies):** when `defaults/herdr.d.ts`, the app commands (`src/commands.rs`) or `defaults/AGENTS.md` changed an API that one of Kristoffer's own mods uses, the agent shows the API change and a proposed edit, asks, and applies it after the restart if Kristoffer agrees.
- **Profiles:** both /Users/kristoffer/.config/herdr-app and /Users/kristoffer/.config/herdr-app-personal are checked, and Kristoffer is asked separately per profile (the same copy name in both profiles is two questions).
- **Commit:** once the decisions are applied and checked, the agent commits the /Users/kristoffer/.config changes with Kristoffer's `my-commit` skill, one commit per update (e.g. `chore(herdr): review mod copies for 0.1.18`).

## What counts

| Kind | Found by | Original | Compared |
|---|---|---|---|
| Mod copy | `mods/*/mod.json` has `cloned_from: {name, version}` | `defaults/mods/<name>/` | every file in the folder except generated ones (`jsconfig.json`, `*.d.ts`) |
| Layout copy | `layouts/*.json` has `cloned_from` | `defaults/layouts/<name>.json` | the whole file |
| Own mod | any other folder in `mods/` that isn't shipped | n/a | names changed in `defaults/herdr.d.ts` and `src/commands.rs`, found as whole words in the mod's `.js` files (`gpui-kit.d.ts` isn't in this repo, so gpui-kit changes aren't covered) |

Shipped mods and layouts themselves are skipped (Herdr replaces them on start).

## Which versions get compared

- **Base:** what shipped as `cloned_from.version`. If that is the version being updated from, the fork's pre-merge HEAD (so the fork's own changes to defaults, e.g. `workspace-chrome`, are part of the base and don't show up as upstream changes). Otherwise the upstream tag `v<cloned_from.version>`: copies from older versions came from a release or a fork build near it. ("The newest fork commit at that Cargo version" was tried and rejected: upstream keeps the old version number on master until the release bump, so it hides changes made between the tag and the bump.)
- **New:** the original at the fork's HEAD after merging the new tag.
- **Copy:** the file in the profile as it is now.

A copy is "affected" when base and new differ. Whether the change touches the copy's own customizations (copy vs base) is part of the agent's analysis, not a filter.

## `scripts/fork-clones.sh <new version>`

- The agent runs it once the merge of the tag is committed (it refuses to run before that). Read-only apart from the report; safe to re-run.
- Scans both profiles, resolves base/new per the rules above.
- Writes `.cache/fork-update-v<ver>/clones.md`: per profile, per affected copy: name, original, `cloned_from.version`, the upstream diff (base → new), and the copy's own diff (base → copy). Then the own-mods section: API file diffs (old → new) and, per own mod, the changed symbols it uses.
- Unaffected copies get one line each so the report shows they were checked.
- Exit 0 always unless it cannot run (missing remote/tag): that's exit 1 with the reason. "Copies need review" is not an error.
- Copies without `cloned_from` can't be matched to an original. A mod named `my-<original>` whose `main.js` still starts like the original is listed as a warning so `cloned_from` can be added by hand.
- A copy of one of the person's own layouts or mods (e.g. `my-main-copy` from `my-main`) has nothing shipped to compare and is listed as checked.
- Own mods are compared against API changes from the profile's last run version (`update-notes.json` `last_run`) to the new one: the names on changed lines of `defaults/herdr.d.ts` and changed `cmd("…")` entries in `src/commands.rs`, matched as whole words in the mod's `.js` files. A changed `defaults/AGENTS.md` is pointed out for the agent to read.
- Works with macOS's bash 3.2 and needs `jq`.

## Agent prompt (`fork_prompt`) additions

After the merge, before restart:

1. Run `scripts/fork-clones.sh <version>` and read `clones.md`.
2. Write the review as markdown in the reply (OpenCode renders it; question text doesn't wrap or break lines well) and save it as `.cache/fork-update-v<ver>/review.md`: one `### A1 · <profile> · <copy>` section per affected copy, per profile, with short bullets (each upstream change in plain words, the copy's customizations, overlap, recommendation and why), then one `### B1 · <profile> · <own mod>` section per flagged own mod (API change, proposed edit).
3. Ask one question per section, its text a single line pointing at the section (`A1 · herdr-app · my-agents: see A1 above`), the recommended option first.
4. Write the answers under a `## Decisions` heading in `clones.md`.
5. If nothing is affected, say so in one line and continue without stopping.

After the install, the agent reports the decisions and tells Kristoffer to restart. When Kristoffer says Herdr has restarted (the agent can confirm with `herdr-app --version` / `herdr-app status`):

6. Apply the decisions:
   - Keep: set `cloned_from.version` to the new version.
   - Drop: delete the copy; repoint every reference (layout `content.mod`, `terminal_menu`, `openOverlay({ mod })` in other mods, the `.gitignore` whitelist in /Users/kristoffer/.config) to the original.
   - Re-clone: move the old copy aside, `herdr-app do mod.clone` / `layout.clone` with the same `as` name (with `HERDR_APP_HOME` set for the personal profile; that profile's window must be open), re-apply the customizations from the old copy, delete the old copy.
   - Own mods: apply the agreed edits.
7. Run `herdr-app check` on every changed mod and look at `herdr-app status` for errors, per profile.
8. Commit /Users/kristoffer/.config with `my-commit`.
9. Final report: per profile, each copy and own mod with the choice made and the result of the check.

## Edge cases

- **Personal profile window closed:** `mod.clone` needs a running window. The agent asks Kristoffer to open it (alias `hp`) or does the clone by hand (copy the folder, add `cloned_from`, rewrite `mods/<old>/` asset paths).
- **Skipped versions** (e.g. 0.1.16 → 0.1.18): base is per copy (`cloned_from.version`), so all changes since then are included.
- **Original removed upstream:** report it; "Keep" is the only safe choice offered with a note, plus "Drop" if the copy is no longer used.
- **Original renamed:** treated as removed; the agent mentions a likely new name if the diff shows one.
- **A copy whose original the fork itself edits:** covered by using the fork's commits as base and new.
- **Merge conflicts or test failures in fork-update.sh:** handled as today; the copy review runs once the merge is committed.

## Prerequisite (done)

The copies made by hand in /Users/kristoffer/.config/herdr-app-personal (`my-worktree`, `my-menu`, `my-new-menu`, `my-tabs`) got `"cloned_from": {"name": "<original>", "version": "0.1.16"}` (the version that profile last ran).
