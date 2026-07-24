# Put StudyDesk on the web — anyone can open it, use it, and install it

Deploying to Render turns your `https://studydesk-xxxx.onrender.com` link into a
**public web app**. Anyone you share the link with can:

- open it in a browser and use StudyDesk straight away,
- create their **own account** (their data is private to them and syncs across
  their devices),
- **install it** to their phone or desktop ("Add to Home screen" / "Install") so
  it works like a downloaded app.

You (the owner) get an **admin panel** at `/admin` to see everyone's countdowns,
goals and streaks.

You only set this up **once** (~10 min). I've prepared all the code; these steps
need *your* accounts (I can't sign up as you).

---

## Step 1 — Put the code on GitHub (free)

1. Make a free account at <https://github.com> (skip if you have one).
2. Click **+** (top-right) → **New repository**. Name it `studydesk`, leave it
   Public or Private, click **Create repository**.
3. Click **uploading an existing file**.
4. Open `E:\PROJECTS\TO-DO BY FTA\server` and drag **everything inside it** into
   the upload box — including the **`webapp`** folder (that's the actual app) and
   `render.yaml`. **Skip** `node_modules` and any `studydesk.db` file if present.
5. Click **Commit changes**.

> No GitHub account? See **Plan B** at the bottom (no signup, but your laptop
> must stay on).

## Step 2 — Deploy on Render (free, no credit card)

1. Make a free account at <https://render.com> → **Sign in with GitHub**.
2. **New +** → **Blueprint** → pick your `studydesk` repo → **Apply**.
3. Render reads `render.yaml` and asks you to fill in two values — **set these
   now**, they protect your admin panel:
   - `ADMIN_USERNAME` — e.g. `pranav`
   - `ADMIN_PASSWORD` — a strong password you choose
4. Wait for **Live** (first build ≈ 2–3 min). Copy the URL at the top:

   ```
   https://studydesk-xxxx.onrender.com
   ```

That link **is** your public StudyDesk. 🎉

## Step 3 — Share it / let anyone use it

Just send people the link. On their device:

- **Phone (Android/iPhone):** open the link in Chrome/Safari → use it. To
  "download" it: browser menu → **Add to Home screen** (it then opens like an
  app, full-screen, with its own icon).
- **Desktop (Chrome/Edge):** open the link → click the **Install** icon in the
  address bar (or menu → *Install StudyDesk*).

Each person taps the account icon → **Create an account** and gets their own
private, synced StudyDesk. Nothing to configure — the app talks to the server it
was opened from.

## Step 4 — Connect *your* Windows app to the same account

So your desktop StudyDesk syncs with your phone:

- **Easy:** tell me your Render URL and I'll bake it in + rebuild the Windows app
  for you (one rebuild, then it just works).
- **Or yourself:** open StudyDesk on Windows → account icon → **Sign in to sync**
  → click **Server settings** → paste `https://studydesk-xxxx.onrender.com` →
  sign in with your account.

Now edit on the laptop and watch it appear on the phone within seconds (and the
other way). Offline edits sync automatically when the internet returns.

## Your admin panel

Open `https://studydesk-xxxx.onrender.com/admin` and log in with the
`ADMIN_USERNAME` / `ADMIN_PASSWORD` you set in Step 2. You'll see every user's
countdowns, goals, syllabus progress and streaks.

---

## Good to know

- **Free Render servers sleep** after ~15 min idle, so the *first* visit after a
  quiet period can take ~30–50 s to wake, then it's fast. (Paid plans stay awake;
  not needed to start.)
- **Data:** each device keeps its own local copy, and the cloud is the meeting
  point. On Render's free plan the server's disk can reset on a redeploy; when a
  device next syncs it re-uploads its data, so accounts/edits aren't lost in
  normal use. If you expect heavy public use and want bullet-proof storage, tell
  me and I'll switch the server to a free hosted database (Turso/Postgres).
- **Want a real installable Android APK** to hand out instead of the web install?
  We have a debug APK already; I can prep a shareable release build — just ask.

---

## Plan B — no signup (tunnel), your laptop must stay on

Publishes your laptop's own server with a free tunnel (no accounts). Trade-off:
only works while your laptop is on, and the link can change each run.

1. Download `cloudflared` for Windows from
   <https://github.com/cloudflare/cloudflared/releases>
   (`cloudflared-windows-amd64.exe`).
2. In `E:\PROJECTS\TO-DO BY FTA\server` run `npm install` then `npm start`
   (leave it running). This now serves the **app** at `/` too, not just the API.
3. In another window: `cloudflared tunnel --url http://localhost:4000`
4. Share the printed `https://...trycloudflare.com` link. Open it on any phone,
   and paste it into the Windows app's Server settings.
