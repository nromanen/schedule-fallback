# Deployment and maintenance

Playbook for the schedule fallback page. What the page is and how it works: [README.md](README.md).

How it fits together: the page is hosted on GitHub Pages; a script on mathserver exports
the schedule from the main app every 30 minutes and pushes the JSON files to this repository.
If mathserver goes down, the page keeps working with the last exported data.

## 1. GitHub

1. The repository must be public (on the free plan, Pages only works with public repositories).
   The schedule is public anyway, but never put secrets here.
2. In the repository root: `index.html`, `README.md`, `DEPLOY.md`, `export-schedule.sh`
   and an empty `.nojekyll` (so GitHub does not run the site through Jekyll).
3. Settings → Pages → Source: **Deploy from a branch**, branch `main`, folder **/ (root)**.
   URL: `https://<owner>.github.io/<repo>/`.

## 2. Access from mathserver (deploy key)

No admin rights needed; everything runs as your own user.

```bash
# a separate key just for this repo, without a passphrase (cron can't type one)
ssh-keygen -t ed25519 -N "" -C "mathserver schedule-fallback" -f ~/.ssh/schedule_fallback

cat >> ~/.ssh/config <<'EOF'
Host github-fallback
  HostName github.com
  User git
  IdentityFile ~/.ssh/schedule_fallback
  IdentitiesOnly yes
EOF
chmod 700 ~/.ssh && chmod 600 ~/.ssh/schedule_fallback ~/.ssh/config

cat ~/.ssh/schedule_fallback.pub
```

Add the public key on GitHub: repository → Settings → Deploy keys → Add deploy key,
with **Allow write access** checked.

Check:

```bash
ssh -T git@github-fallback      # "You've successfully authenticated"
```

`github-fallback` is an SSH alias: it connects to github.com using this key only.
If the connection hangs, port 22 is blocked: in the `github-fallback` block replace
`HostName github.com` with `HostName ssh.github.com` and add `Port 443`.

## 3. Clone and first run

```bash
git clone git@github-fallback:<owner>/<repo>.git ~/schedule-fallback
cd ~/schedule-fallback
git config user.name "schedule-bot"
git config user.email "schedule-bot@localhost"

./export-schedule.sh
ls *.json                        # semesters.json, full-<id>.json for every running semester
git log -1                       # "Schedule snapshot ..."
```

The Pages site should now list the semesters, and the banner should show the snapshot time.

Requires `curl`, `jq`, `git`. If `jq` is missing: `sudo apt install jq` (or ask the admin).

## 4. Cron

`crontab -e`:

```
*/30 * * * * $HOME/schedule-fallback/export-schedule.sh >> $HOME/export-schedule.log 2>&1
```

Next day, check `tail ~/export-schedule.log` and the commit history on GitHub.
A commit only appears when the schedule has actually changed.

## How `export-schedule.sh` works

0. `git pull --rebase` — picks up page changes pushed from elsewhere.
1. `GET /public/semesters` → `semesters.json`.
2. For every semester with `disable: false` that has not ended yet:
   `GET /schedules/full/semester?semesterId=<id>` → `full-<id>.json`.
3. Commit and push, only if something changed.

A file is replaced only by a valid response (it has `semester` and either `schedule` or `items`).
If the app is down or a schedule is unpublished (the API then answers 200 with a status
instead of a schedule), the previous copy stays and the log gets
`semester <id>: export failed, keeping the previous file`.
Files of semesters that have ended are not deleted; they simply drop out of the list.

Environment variables:

| Variable | Default | Meaning |
|---|---|---|
| `API` | `http://localhost:8080` | address of the main app |
| `REPO` | `~/schedule-fallback` | clone of this repository |

## Updating the page

Edit `index.html` locally, commit and push. The cron job on the server pulls the change
before its next export (`git pull --rebase`). Do not rewrite commits that are already pushed
(`--amend`, `--force`): the server clone pushes to `main` too.

## Troubleshooting

| Symptom | Cause and fix |
|---|---|
| `Permission denied (publickey)` | The remote points to `git@github.com:…` instead of the alias: `git remote set-url origin git@github-fallback:<owner>/<repo>.git`. If `ssh -T git@github-fallback` fails as well, check `~/.ssh/config`, `600` permissions on the key, and that the deploy key is added to this repository. |
| `ssh -T` works, `git push` does not | The deploy key does not have **Allow write access**. |
| `The current branch main has no upstream branch` | Run `git push -u origin main` once. |
| `rejected … fetch first` | GitHub has commits you don't have locally: `git pull --rebase origin main`, then `git push`. |
| `ssh` hangs | Port 22 is blocked → use `ssh.github.com:443` (see section 2). |
| The page says «Для семестру … немає резервної копії» ("no backup for this semester") | `full-<id>.json` is missing: the semester was not exported (see the log), or the page is opened from disk (`file://`). |
| The banner shows an old date | Cron is not running or not pushing: `tail ~/export-schedule.log`, `crontab -l`, `git -C ~/schedule-fallback status`. During a mathserver outage this is expected — the page shows the last snapshot. |
| A semester is missing from the list | It has ended or has `disable: true`; a direct link `?semester=<id>` still opens it if the file exists. |
