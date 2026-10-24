# Contributing

How work reaches `main` and the live site. Commands are PowerShell, run from the repo root unless a step says otherwise.

## Who does what

- **Padmanand** owns `main`: he tests every PR and says when it merges. He and Claude design each feature before anyone builds it.
- **Sudarshana** builds the money paths (registration, payment, refunds, check-in, sign-in) and fixes bugs.
- **Rakshith** builds front-end features, such as Q&A.

Designs, plans and the ops guides are in the team's private Drive folder, not here. Ask Padmanand for access.

## The rules

1. **Design first.** Build only what has been designed and agreed ("go"). If something comes up mid-build that needs a decision, stop and ask; don't decide it in the code.
2. **One step, one branch, one PR**, from the latest `main`. Name the branch after the feature (`refund-policy`, `questions-in-advance`). Internal plan labels never go in code, comments, branch names, PR titles or commit messages.
3. **Nobody commits to `main`.** PRs are **squash-merged**, so each PR is one commit on `main` titled `What it does (#123)`, and easy to revert.
4. **Keep it simple.** A volunteer organisation runs this. Simple events stay simple: a feature for big events must not add a step or a field to a simple event's setup.
5. **A backend merge is a production deploy.** Beta and live share one API and one database, and Cloud Build redeploys the API on every merge that touches `backend/`. The live app is deployed from `main` only.
6. **Database changes are Padmanand's.** The PR includes the migration file (`backend/migrations/events_db/`, next free number), tested on a scratch database. Padmanand backs up and runs it on the live database **before** the merge. Nobody else runs SQL on the live database.
7. **Testing, in proportion:**
   - every PR: app tests and server tests for what it changes;
   - **money paths** (registration, payment, refunds, check-in, sign-in): the full backend suite, plus the ~10-minute smoke test on beta, before merging;
   - a UI change: every page that shares the pattern, side by side, in light and dark, on a phone and a computer.
8. **A new public field** on an event must be added to the allow-list in `backend/tests/test_admin_auth_unification.py`.

## Code rules

- **UI:** follow [`docs/UI_PATTERNS.md`](docs/UI_PATTERNS.md) and use the shared pieces it lists. If a PR changes a pattern, it updates that guide too.
- **Colours** come from the theme (`context.palette`), never `Color(0x…)`. `frontend/tool/check_colors.sh` checks this (it's a bash script: run it from Git Bash or WSL).
- `flutter analyze` and `flutter test` pass; commit a changed `pubspec.lock`.
- **The server works out every amount;** the app never sends one.
- **Personal details never go in a page address** or a log.
- Never commit `.env*` (except `.env.example`), `build/`, `.dart_tool/` or any secret. Secrets live in Secret Manager.

## The loop

```powershell
git fetch origin; git checkout main; git pull
git checkout -b <feature-name>
# work, commit
git push -u origin <feature-name>
# open a PR into main
```

If `main` moves on and the PR conflicts, the branch owner rebases: `git fetch origin; git rebase origin/main`, then `git push --force-with-lease`.

## Test and deploy to beta

From `frontend/` on the branch:

```powershell
flutter pub get
flutter analyze; flutter test
flutter build web --release --dart-define=BACKEND_BASE_URL=https://nitksaa-events-api-246773894709.asia-south1.run.app
firebase deploy --only hosting:beta
```

- Only failures from the tests: `flutter test 2>&1 | Select-String -Pattern "\[E\]|Expected:|Actual:|Which:|Some tests|All tests" -Context 2,6`.
- Open beta (`nitksaa-events-beta.web.app`) in a private window, or press **Ctrl+Shift+R**: the service worker caches hard.
- There's one beta site, so the last deploy wins. Say so in the team chat if two of you need it.
- **A PR that changes both the server and the app:** the server part can't be tried on beta before merging (beta uses the live API). Check the app parts on beta, merge (that deploys the server), then check the rest. A server change that only adds things (a new route or field) doesn't affect the live app in between.

Backend tests: set-up and how to run them are in [`backend/README.md`](backend/README.md).

## After a merge

```powershell
git checkout main; git pull
git push origin --delete <feature-name>
git branch -D <feature-name>
git fetch --prune
```

**Live app release** (Padmanand), from `main`:

```powershell
cd frontend
flutter pub get; flutter test
flutter build web --release --dart-define=BACKEND_BASE_URL=https://nitksaa-events-api-246773894709.asia-south1.run.app
firebase deploy --only hosting:events
```

Then check sign-in, the Events page, one event page and My Events on `events.nitkalumni.in`.

## Roll back

- **App:** Firebase console › Hosting › the site › Release history › ⋮ on the previous release › Rollback.
- **API:** Cloud Run › `nitksaa-events-api` › Revisions › send traffic to the previous revision; then revert the PR.
- A rollback doesn't undo a migration. Migrations that only add (new tables, nullable columns) leave older revisions working, which is why they're preferred.
- Fallback points are tagged `stable-<date>` on `main`.
