# Flex Node

A small Windows 11 Home health reporter and phone-readable status page.
No dependencies, frameworks, or build step. Windows PowerShell 5.1 is enough.
The reporter runs every 10 minutes while the task's user is signed in.
The page refreshes every minute and marks reports older than 30 minutes OFFLINE.

## Install on the spare laptop

Run these three commands in an elevated PowerShell window on the spare laptop:

```powershell
winget install -e --id Git.Git
git clone https://github.com/jaithechai/flex-node.git C:\flex-node
powershell -ExecutionPolicy Bypass -File C:\flex-node\setup.ps1
```

After Git installs, reopen elevated PowerShell if `git` is not found.
Setup keeps AC sleep and hibernate off and makes lid close do nothing on AC.
Battery power settings stay as they are. Setup installs Tailscale and Chrome
Remote Desktop Host. Pass `-SkipApps` to skip those installations.
Setup replaces the scheduled task on each run and creates `.env` only if missing.
It does not change Windows Update, Defender, or auto-login.
Keep this Windows user signed in; locking the screen is fine.

## Finish by hand

1. Create a fine-grained GitHub token limited to this repository with
   **Contents: Read and write**. Paste it into `GITHUB_TOKEN` in `C:\flex-node\.env`.
2. Create a healthchecks.io check with a 10 minute period and 20 minute grace.
   Paste its ping URL into `HEALTHCHECK_URL` in `.env` and configure alerts there.
3. Sign in to Tailscale.
4. Set a Chrome Remote Desktop PIN through its remote access setup.
5. Turn on Conservation Mode in Lenovo Vantage.
6. Check the actual process names with `Get-Process` and adjust `WATCH` in `.env`.
   Use names without `.exe`. Leave `WATCH` empty to disable process watching.
7. Run `Get-ScheduledTaskInfo flex-node-status` after ten minutes.
   `LastTaskResult` should be `0`.
8. Open `https://jaithechai.github.io/flex-node/` on your phone.
   GitHub Pages already serves it from the main branch's `/docs` folder.

The repository must already contain its main branch before reporting starts.
The reporter creates the `status` branch on its first successful upload.
Each report replaces that branch with one parentless commit containing only
`status.json`. GitHub may retain unreachable older objects after replacement.
The token must allow writes to `status`; branch protection can prevent updates.

## Published data and secrets

Public data: report and boot timestamps, AC status, battery percentage, CPU and
RAM percentages, system-drive free GB, and watched process names/running states.
No hostname, username, IP address, or filesystem path is included in status data.
Use only process names you are comfortable making public.
The token and healthcheck URL stay in ignored `.env`; never commit that file.
Failed watched processes send the status JSON to the private healthcheck `/fail`
endpoint. Successful checks send a plain GET. Upload and ping fail independently.

Fine-grained tokens expire. Renew the token in `.env` before expiry.
If it expires, the page becomes OFFLINE after 30 minutes while healthchecks
still pings, provided the reporter and network are working.

## Check locally

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\test.ps1
.\status.ps1 -DryRun
```

DryRun skips `.env`, uses an empty watch list, and does not access the network.
Serve `docs` with any local static server and open
`index.html?src=status.sample.json` to test the page. The fixed sample will show
OFFLINE once its timestamp is old. On Pages the source URL is derived from the
owner and repository in the page URL. Custom domains need a `?src=` override.

## Remove

```powershell
Unregister-ScheduledTask flex-node-status
```

## Earning apps

Bandwidth-sharing apps pay per GB of other people's traffic that leaves through
your home IP address. The IP earns, not the hardware, so more apps on one
connection mostly split the same demand. Expect a few dollars a month per home
connection. That figure is an estimate, not a measurement.

Before installing any of them:

1. Get a yes from the person who holds the internet account.
2. Read the provider's terms. Some residential plans ban proxy services and resale.
3. Never run them on a university, employer, or other shared network.
4. Put the laptop on the router's guest Wi-Fi so it cannot reach other devices.
5. Use a separate local Windows account with no personal sign-ins.
6. Create the app accounts and payout details on a different device.

Then install two or three from their official sites only, for example
[Honeygain](https://www.honeygain.com/), [EarnApp](https://earnapp.com/) and
[Pawns](https://pawns.app/). Turn on start with Windows in each, and add each
process name to `WATCH`. Log real payouts for 30 days, then keep or remove them.

No crypto miner: on a laptop CPU it earns about a dollar a month.
