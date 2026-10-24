# Backend (Supabase)

The app works with no backend at all: rooms, items, layouts, and the sample
catalog all run on the phone. The backend adds sign-in, the live product
catalog, and (in week 5) paid AI features, while keeping every secret key off
the phone.

```
supabase/
  migrations/      the database: tables, row level security, limits
  functions/       Edge Functions (TypeScript, run by Supabase)
    search-products, get-product   live catalog through Channel3
    delete-account                 removes the account (Apple requires it)
    generate-image, label-item,    week 5; already enforce sign-in, the kill
    scan-room                      switch, 3/day + 10/month, and the budget
    _shared/                       helpers and tests
  config.toml      settings for the Supabase CLI
```

## Costs and caps

| Service | Cost | Cap |
| --- | --- | --- |
| Supabase | Free plan, no card | Free plan can't bill. Pauses after 7 days idle; restore in the dashboard. |
| Channel3 | Free tier: 1,000 credits/month, 1 per search | We stop at 900/month (`app_config.catalog`), cache searches for 24 h, and limit each person/device to 30 searches per 10 minutes. |
| AI images (Visualize) | Model not chosen yet; prepaid credits, auto-reload off | Off until a model is chosen. Hard cap of **$5 a month** for everyone (`app_config.image_generation.monthly_budget_cents = 500`), enforced in the database (`try_spend`), plus 3 a day and 10 a month per person. |
| Item labeling, room scan | Not used in v1 | Off. Item labeling runs on the phone (free); room photo scan is "coming soon"; LiDAR phones use Apple's RoomPlan (free, on the phone). |

Change any limit in the dashboard: **Table Editor → app_config**.

## One-time setup (you do this; it needs your Supabase login)

Run these in Terminal from the project folder. Nothing here asks you to paste
a secret into chat or into a file.

1. **Log in** (opens your browser):
   ```bash
   supabase login
   ```
2. **Link this folder to your project:**
   ```bash
   supabase link --project-ref tpansxzplscfoffsscqn
   ```
   It asks for your database password (the one you chose when you created
   the project). Type it into Terminal only.
3. **Create the tables:**
   ```bash
   supabase db push
   ```
4. **Add the Channel3 key as a secret** (after you sign up at
   trychannel3.com and create an API key). In the dashboard: **Edge Functions
   → Secrets → Add new secret**, name `CHANNEL3_API_KEY`, paste the key there.
   Never put it in the app, a file, or chat.
5. **Deploy the functions:**
   ```bash
   supabase functions deploy
   ```
6. **Sign-in settings** in the dashboard, **Authentication**:
   - **Sign In / Providers → Email**: enabled, "Confirm email" on.
   - **URL Configuration**: Site URL `interiordesign://auth-callback`, and
     add `interiordesign://auth-callback` under Redirect URLs.

After step 5 the Catalog tab shows live products instead of the samples.

## Google sign-in (later)

1. In Google Cloud Console: create a project, set up the OAuth consent screen
   (basic profile and email only), and create an OAuth client ID of type
   **Web application** with the redirect URI
   `https://tpansxzplscfoffsscqn.supabase.co/auth/v1/callback`.
2. In Supabase: **Authentication → Sign In / Providers → Google**: enable it
   and paste the client ID and client secret there.
3. Set `googleSignInEnabled = true` in `InteriorDesign/Shared/Backend/BackendConfig.swift`.

## Sign in with Apple (after the Apple Developer account)

Needs the paid account to create a Services ID and key. Then enable the
Apple provider in Supabase and set `appleSignInEnabled = true`.

## Testing locally

```bash
deno test supabase/functions/_shared/     # product normalization tests
deno check supabase/functions/*/index.ts  # type check every function
```

Running the whole backend locally (`supabase start`) also needs Docker.
