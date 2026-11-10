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
    generate-3d                    AI 3D model of a catalog product (Stable Fast 3D)
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
| AI 3D models of products (`generate-3d`) | Stability AI **Stable Fast 3D**: about 2 credits ($0.02) per model, prepaid credits, no auto-reload. Each product is made once, saved in Storage (`product-models` bucket), and shared. | Off until you turn on `app_config.model_3d`. Hard cap **$5 a month** (`monthly_budget_cents = 500`), plus 5 a day and 20 a month per person. Needs sign-in to make a new one; saved ones are free for everyone. |
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

## Google sign-in

Free. The app opens Google in Apple's secure browser sheet (with PKCE), then
Supabase signs the person in. The Google **client secret goes only into the
Supabase dashboard**: never into the app, a file, or a chat.

1. **Google Cloud project.** Go to console.cloud.google.com, sign in with your
   Google account, and create a project (top bar → project picker → New
   project), e.g. "Interior Design".
2. **Consent screen.** Menu → **Google Auth Platform** (or "APIs & Services →
   OAuth consent screen") → Get started. App name: your app's name; support
   email: yours; Audience: **External**; contact email: yours. Finish.
   - Data access / scopes: keep the basic ones (`openid`, `email`,
     `profile`). Add nothing else, so Google needs no review.
   - Audience: while it says **Testing**, only "test users" can sign in. Add
     your own Gmail (and any testers) under Test users.
3. **Client ID.** Google Auth Platform → **Clients** → Create client →
   Application type **Web application** (yes, web, even for an iPhone app:
   Supabase does the Google part) → under **Authorized redirect URIs** add
   `https://tpansxzplscfoffsscqn.supabase.co/auth/v1/callback` → Create. A box
   shows the **Client ID** and **Client secret**. Keep that tab open.
4. **Supabase.** Authentication → Sign In / Providers → **Google** → enable,
   paste the Client ID into **Client IDs** and the secret into **Client
   Secret (for OAuth)** → Save.
5. **Redirect URL.** Authentication → **URL Configuration** → Redirect URLs:
   make sure `interiordesign://auth-callback` is listed (add it if not).

Before the App Store: publish the consent screen (Audience → Publish app) so
anyone can sign in, not just test users.

## Sign in with Apple

The app uses Apple's native sign-in sheet (no web page), so no Services ID or
secret key is needed. The app already has the capability and
`appleSignInEnabled = true`.

In Supabase: **Authentication → Sign In / Providers → Apple** → enable it,
put `com.isabellasi.InteriorDesign` under **Client IDs**, leave the secret
key empty, and save.

Follow-up before the App Store: when an Apple user deletes their account,
Apple asks apps to also revoke the Apple sign-in. That needs a private key
from the Apple Developer site stored as a Supabase secret; not done yet.

## Testing locally

```bash
deno test supabase/functions/_shared/     # product normalization tests
deno check supabase/functions/*/index.ts  # type check every function
```

Running the whole backend locally (`supabase start`) also needs Docker.
