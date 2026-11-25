# Fork update: the agent's steps

<!-- app.fork_update sends a one-line prompt pointing here (fork_prompt in src/update.rs). Edits apply without rebuilding Herdr, even to an agent already running. -->

Update my personal Herdr fork to an official stable release. The prompt that sent you here names the version: read `<version>` below as that version (e.g. 0.1.18). Work in this checkout; docs/fork-update-copies.md explains the design. Never reset, force-push or discard work. Don't quit or restart Herdr.

First review, then merge: nothing is merged, built or installed until I've answered.

1. Run `scripts/fork-clones.sh <version>` and read .cache/fork-update-v<version>/clones.md. It previews the merge (git merge-tree) without touching the checkout: the files the merge will conflict in, with their conflict hunks, then per profile the copies of shipped mods and layouts whose original changed, and own mods using a changed API.
2. Write the review as markdown in your reply (it gets rendered) and save the same text as .cache/fork-update-v<version>/review.md. Start with a short summary: how many conflicts, copies and own mods need a decision. Then:
   - `### C1 · <file>` per conflicted file: what the fork changed there and why (`git log v<version>..HEAD --no-merges -- <file>`), what upstream changed, and how you'd resolve it (normally keep both).
   - `### A1 · <copy>` per copy whose original changed, covering every profile that has it (name them, and point out where the profiles' copies differ, e.g. cloned from another version or customized differently): each upstream change in plain words, what the copy customized, whether they overlap, and your recommendation (Keep copy as is, Drop copy and use the original, or Re-clone and reapply my changes) with why.
   - `### B1 · <own mod>` per own mod using a changed API, across profiles: the change and the edit you'd make.
   Short bullets throughout. If nothing needs a decision, say so in one line and go on to step 5.
3. Ask one question per section, its choice applying to every profile in it (I'll use the free-text answer to treat a profile differently). The question text is one line naming its section (`A1 · my-agents: see A1 above`), no explanations in it; your recommendation first. Options: for C, Resolve as proposed / Keep the fork's side / Take upstream's side; for A, the three choices; for B, Apply edit / Skip.
4. Write my answers under `## Decisions` in clones.md. Don't edit anything in the profiles yet: copies reload as soon as they're saved, and the running Herdr is still the old version.
5. Run `scripts/fork-update.sh <version>`. It merges the tag, runs the tests, installs the build into /Applications/Herdr.app and pushes, logging to .cache/fork-update-v<version>/.
   - Exit 2 (merge conflicts): resolve them as I decided, `git add` the files and re-run. Ask me only about conflicts the review didn't cover.
   - Exit 1: read the named log, fix the cause in a separate fork commit, and re-run.

Report how the conflicts were resolved, other fixes and the installed version, and ask me to restart Herdr (every open Herdr window, the personal one too); your terminal keeps running. If any decision needs edits (Re-clone, Drop or own-mod edits), say plainly that they only happen after the restart. Then, in the same turn, start `scripts/fork-wait-restart.sh` as a background job with a timeout of a day (86400000 ms; the default would stop it after minutes) and end your turn: it exits once every running Herdr started after the install, and you're woken up then, so I don't have to tell you. If I say it has restarted first, go on without waiting for it. If it exits 1 (gave up after a day), remind me that the decisions are still pending.

Once Herdr has restarted, check `herdr-app --version`, then apply the decisions:

- Keep: set `cloned_from.version` to <version>.
- Drop: delete the copy and point everything that used it (layout `content.mod`, `terminal_menu`, `openOverlay({ mod })` in other mods, the !-lines for it in ~/.config/.gitignore) back to the original.
- Re-clone: move the copy aside, `herdr-app do mod.clone` (or `layout.clone`) with the same name as `as` (`HERDR_APP_HOME` picks the profile; its window must be open, else ask me to open it), reapply my changes, delete the old copy.
- Own mods: make the edits I agreed to.

Then run `herdr-app check` on every changed mod and look at `herdr-app status` per profile, commit ~/.config with my commit skill (my-commit), and finish with each copy and own mod, the choice and the check result.

As the very last line of that final report, write exactly: Ready to rumble, Mr. Panda
