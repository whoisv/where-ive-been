# Project notes for Claude

Where I've Been: a static travel-map app (index.html + config.js + countries-data.js), Supabase back end, deployed by Netlify from this repo's `main` branch. Live at https://whereihavebeen.com (domain at Squarespace, DNS records point to Netlify; HTTPS by Let's Encrypt). Preview: https://preview--whereihavebeen.netlify.app.

## Owner's decisions (keep these on every change)
- Greenland (GL) is its own country, not folded into Denmark.
- French Polynesia (PF) is its own entry, not folded into France.
- French Guiana (GF) is its own entry, cut out of France's outline when the map data draws them together (`splitTerritory`).
- Palestine (PS) and Kosovo (XK) are excluded from the checklist and counts (`EXCLUDE`); their shapes stay as plain, unclickable land. Northern Cyprus and Somaliland are not countries in this app either.
- Rule: only places in the country count appear on the map. Anything without a continent in `CONTINENTS` (disputed or unrecognised regions in the map data) is plain land too. Other territories (see `PARENT` in index.html) get no dot, and their shapes are plain, unclickable land. Every sovereign country in the count must stay on the map: small ones have backup dots in `SMALL`, drawn only when the map data lacks an outline. A visit to one still counts toward the parent country (Import a list maps "Hong Kong" → China, "Puerto Rico" → US).
- United States is listed first in the home-country dropdown.
- Antarctica is included as its own continent.
- States map (second category, "States"): the 50 states only, for now (owner's choice; territories may be added later). Washington, D.C. and anything else in the map data that isn't one of the 50 is plain land and not counted. Regions follow the Census: Midwest, Northeast, South, West. State visits live in their own table, `state_visits` (codes like US-CA), so country leaderboards, rankings and the admin console stay countries-only. Profile has a default view (`profiles.default_view`).
- National Parks map (third category; always call it "National Parks", never just "Parks"): only the parks officially designated "National Park" (64 as of Oct 20, 2026, when Chiricahua became the newest); no monuments, landmarks or historic sites. Data in `NATIONAL_PARKS`; visits in `park_visits` (codes like NP-YOSE); regions in `park_regions`. When Congress adds a park, add it to `NATIONAL_PARKS` and to add-parks.sql's region list.
- Photos: up to 10 per person per place (any country, state or park code), shrunk in the browser to about 1600 px JPEG plus a `_t.jpg` thumbnail, stored in the private `photos` bucket at `<user id>/<place code>/<uuid>.jpg`; rows in `photos` (add-photos.sql). Private by default; `profiles.share_photos` shares them only when `is_public` is also on, shown under the screen name. The first photo is the place's banner. Account deletion removes the files from the app first, then the rows.
- Each map's settings live in `VIEW_CFG` in index.html (list, table, leaderboard and rank functions, SQL file).
- One opt-in switch, "Join the traveler community" (`profiles.is_public`, off by default), gates every feature that shows a user to others: leaderboards now, comparisons and similar later. Members appear by screen name only; never email, trips or notes.

## Release process (owner's request: bundle releases, deploys cost credits)
- Never push app changes straight to `main`. Work on the `preview` branch; collect several changes into one release.
- When a batch is ready, push `preview` (Netlify branch deploy at preview--whereihavebeen.netlify.app), list what's in it, and wait for the owner to test.
- Only on the owner's "ship it": merge `preview` into `main` in one push = one production deploy. Bump `APP_VERSION` once per release and add a CHANGELOG.md entry.
- Fixes found during preview go into the same batch.
- Docs/notes-only commits to `main` include `[skip netlify]` in the commit message so they don't deploy.
- Urgent live fixes only with the owner's explicit OK.

## Working rules
- Bump `APP_VERSION` in index.html on every change; the owner checks the map corner to confirm a deploy.
- Never overwrite `config.js` (it holds the owner's live Supabase URL and anon key). Fetch from GitHub before editing.
- Database changes ship as `.sql` files the owner runs in Supabase's SQL Editor.
