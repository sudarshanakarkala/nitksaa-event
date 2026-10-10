# Working Agreement: Branches, Beta and Releases

How Padmanand and Sudarshana work on `sudarshanakarkala/nitksaa-event` without blocking or breaking each other. The aim is speed with a few guardrails.

## Who works where

| Who | Work | Branches |
|---|---|---|
| Sudarshana | Bug fixes (`docs/issues/ISSUE-*`) | One branch per fix: `fix/issue-004`, `fix/issue-005`, … |
| Padmanand | Features (NITiKa client, performance, UI, …) | One branch per feature area: `feat/nitika`, `feat/perf`, … |

- Always branch from the latest `main`. Keep branches flat: no sub-branches.
- Nobody commits directly to `main`. Everything reaches `main` through a PR.

## The loop

```bash
# 1. Start
git checkout main && git pull
git checkout -b fix/issue-004            # or feat/perf

# 2. Work, commit, push
git push -u origin fix/issue-004

# 3. Test on beta (see "Beta" below)

# 4. Before merging: pick up main, re-test on beta
git fetch origin && git rebase origin/main
git push --force-with-lease
#    redeploy to beta, quick re-check

# 5. Open a PR into main, merge it (see "Merging")

# 6. Release to the live site from main (see "Live release")
```

## The five guardrails

### 1. Re-test after rebasing, just before merging

Your beta test ran on your branch alone, not on top of the other person's latest merges. Rebase onto `origin/main`, redeploy to beta and re-check the screens you touched. This catches changes that each work alone but break together.

Long-lived branches should also rebase once or twice a week, so the final merge stays small.

### 2. Merge through a PR, even if you merge it yourself

- A PR records what went in and makes reverting easy (`Revert` button on the PR).
- Self-merge is fine for most work once beta looks good.
- **These need the other person's approval before merging:**
  - payments, refunds or checkout;
  - auth or sign-in;
  - routing or the app shell;
  - `pubspec.yaml` dependency changes.
- Use **Create a merge commit**, not squash, so per-file history stays revertable.
- PR description: what changed, what was tested on beta, and anything the other person needs to know.

### 3. The live site only ever gets `main`

- Never deploy a branch to `events.nitkalumni.in`.
- Post one line in WhatsApp before a live deploy ("deploying main to live"), so you don't both deploy at once.
- Rollback: Firebase console → Hosting → the site → Release history → Rollback.

### 4. Don't trample each other on beta

There's one attendee beta site (`nitksaa-events-beta.web.app`), so the last deploy wins. Until each person has their own beta site:
- post "beta = `feat/perf` until 6pm" before deploying;
- when you're done, say so.

**Recommended:** give each person their own beta site. One-time setup:
1. Firebase console: create a Hosting site, e.g. `nitksaa-events-beta2`.
2. `firebase target:apply hosting beta2 nitksaa-events-beta2`, and add a `beta2` entry to `frontend/firebase.json` (same as `beta`).
3. Add `https://nitksaa-events-beta2.web.app` to the events API's `ALLOWED_ORIGINS` (Cloud Run env var).
4. Firebase console → Authentication → Settings → Authorised domains: add `nitksaa-events-beta2.web.app`.

### 5. Backend changes are the exception

Beta and the live site use the **same backend API**. A backend deploy is live for everyone immediately, so "test on beta" doesn't protect you.

For backend changes:
1. Deploy the new revision **with no traffic and a test tag**. Add these flags to your usual `gcloud run deploy`:
   ```bash
   --no-traffic --tag test
   ```
   This gives a URL like `https://test---nitksaa-events-api-….run.app`.
2. Test it: point a local build or a beta build at that URL with `--dart-define=BACKEND_BASE_URL=<test URL>`. You may need to add the beta origin to that revision's `ALLOWED_ORIGINS`.
3. Switch traffic when happy:
   ```bash
   gcloud run services update-traffic nitksaa-events-api --to-latest --region asia-south1 --project project-d22bed42-f302-4e23-8dc
   ```
4. Rollback: `update-traffic` back to the previous revision (Cloud Run console → Revisions).

Database migrations: add only (new tables and columns), never rename or drop in the same release as the code that stops using them. Take a backup before running them.

## Beta deploy (frontend)

From `frontend/` on your branch. PowerShell and bash are the same apart from paths.

```bash
flutter pub get
flutter test
flutter build web --release --dart-define=BACKEND_BASE_URL=https://nitksaa-events-api-246773894709.asia-south1.run.app
firebase deploy --only hosting:beta --project project-d22bed42-f302-4e23-8dc
```

- Open beta in a private window; the Flutter service worker caches hard.
- Afterwards, discard local `pub get` edits: `git checkout -- pubspec.lock analysis_options.yaml linux macos windows`.

## Live release

Run from `main` only, after the PR is merged:

```bash
git checkout main && git pull
cd frontend
flutter pub get && flutter test
flutter build web --release --dart-define=BACKEND_BASE_URL=https://nitksaa-events-api-246773894709.asia-south1.run.app
firebase deploy --only hosting:events --project project-d22bed42-f302-4e23-8dc
```

Then, in a private window on https://events.nitkalumni.in, check:
- sign-in;
- the events list;
- one event page;
- My Events.

Admin app: same pattern with `hosting:admin-beta` and `hosting:admin`.

## Code rules

- **Colours:** use the theme (`context.palette`, `Theme.of(context)`), never `Color(0x…)`. Run `bash frontend/tool/check_colors.sh` before committing.
- **Tests:** `flutter test` must pass before a PR merges. Bug fixes keep their test report in `docs/issues/ISSUE-xxx_*.md`.
- **Never commit:** `.env*` (except `.env.example`), `build/`, `.dart_tool/`, secrets, or your local `.firebaserc` beta targets.
- **Shared files:** if you both need the same screen file, message first.
