# Project notes for Claude

Where I've Been: a static travel-map app (index.html + config.js + countries-data.js), Supabase back end, deployed by Netlify from this repo's `main` branch. Live at https://whereihavebeen.com (domain at Squarespace, DNS records point to Netlify; HTTPS by Let's Encrypt). Preview: https://preview--whereihavebeen.netlify.app.

## Owner's decisions (keep these on every change)
- Greenland (GL) is its own country, not folded into Denmark.
- French Polynesia (PF) is its own entry, not folded into France.
- French Guiana (GF) is its own entry, cut out of France's outline when the map data draws them together (`splitTerritory`).
- Palestine (PS) is excluded from the checklist and counts; its shape stays as plain, unclickable land.
- Rule: only places in the country count appear on the map. Anything without a continent in `CONTINENTS` (disputed or unrecognised regions in the map data) is plain land too. Other territories (see `PARENT` in index.html) get no dot, and their shapes are plain, unclickable land. Every sovereign country in the count must stay on the map: small ones have backup dots in `SMALL`, drawn only when the map data lacks an outline. A visit to one still counts toward the parent country (Import a list maps "Hong Kong" → China, "Puerto Rico" → US).
- United States is listed first in the home-country dropdown.
- Antarctica is included as its own continent.
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
