# Project notes for Claude

Where I've Been: a static travel-map app (index.html + config.js + countries-data.js), Supabase back end, deployed by Netlify from this repo's `main` branch.

## Owner's decisions (keep these on every change)
- Greenland (GL) is its own country, not folded into Denmark.
- French Polynesia (PF) is its own entry, not folded into France.
- Palestine (PS) is excluded from the checklist and counts; its shape stays as plain, unclickable land.
- Other territories count toward their parent country (Hong Kong/Macau → China, Puerto Rico/Guam → US, etc.). See `PARENT` in index.html.
- United States is listed first in the home-country dropdown.
- Antarctica is included as its own continent.
- One opt-in switch, "Join the traveler community" (`profiles.is_public`, off by default), gates every feature that shows a user to others: leaderboards now, comparisons and similar later. Members appear by screen name only; never email, trips or notes.

## Working rules
- Bump `APP_VERSION` in index.html on every change; the owner checks the map corner to confirm a deploy.
- Never overwrite `config.js` (it holds the owner's live Supabase URL and anon key). Fetch from GitHub before editing.
- Database changes ship as `.sql` files the owner runs in Supabase's SQL Editor.
