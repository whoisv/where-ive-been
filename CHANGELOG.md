# Changelog

Releases of Where I've Been. Each release is one production deploy; the version shows in the map's bottom-right corner.

## Pending release (on `preview`, not yet live)
- v1.22: The third map is called "National Parks" (switcher, Profile and Help), not "Parks".
- v1.22 preview 2: Photos. Up to 10 per place (country, state or national park), added from the place's page. Shrunk on your device before upload (about 1600 px, usually 150–400 KB, plus a small thumbnail). Your first photo becomes the page's banner. Click to view full size, add a caption, step through, or delete. Private by default; Profile has "Share my photos with the traveler community" (needs community membership), and shared photos appear to other members under "From other travelers" with the screen name. Deleting your account deletes your photos. Requires add-photos.sql.
- v1.22 preview 3: The photo viewer fills the screen (full screen on phones).

## v1.21 · Nov 20, 2026 (live)
Includes v1.19 and v1.20.
- Share my map opens as a pop-up over the page (full screen on phones) instead of below the panel, with the preview on the left and size, look and Share/Download on the right. Close with ✕, Esc or a click outside.
- Admin "Give access" button (also opens from any "Not confirmed" tag in the traveler list). Type an email; it checks for an account, then sends the right email through the site's email service: a sign-in link that creates the account (new people), the confirmation email again (never confirmed), or a password reset link (confirmed). Backup: set a temporary password and send it yourself by email, text or copy. People set up this way choose their own password right after signing in. Requires admin-access.sql.
- States, a second map. Switch with Countries | States at the top of the panel. The 50 states, grouped by region (Midwest, Northeast, South, West). Washington, D.C. is shown but not counted. Same chips, double-click, year first visited, trips and notes, plus a simple state page (flag, region, Wikipedia description). Profile has "Open the app on: Countries / States". A US home state is marked as visited automatically. Import a list and Copy my list work with states. State leaderboards (most states, this year, each region, from your home country or state) and a state rank tile, community members only. State badges come later. Requires add-states.sql, then add-state-leaderboards.sql.
- National parks, a third map ("Parks"). The 64 US national parks (only parks designated "National Park", including Chiricahua, the newest, from Oct 20, 2026; not monuments or historic sites), shown as dots on the US map, grouped by region (Alaska, East, Midwest, Mountain, Pacific, South, Territories). Same chips, double-click, year, trips and notes, park pages with Wikipedia photo and description, Import and Copy, park leaderboards and rank, and "National parks" as a default view. Requires add-parks.sql.

## v1.18 · Nov 15, 2026
- Share my map. A "Share my map" button next to your country count makes an image of your map with visited countries in their continent colors, your screen name, home, "traveling since", country count, share of the world and continents, plus "Made with Where I've Been · whereihavebeen.com" at the bottom. Three sizes (Square for posts, Story with continent counts and flags, Wide for Facebook/X/link previews), light or dark. On phones it opens the share sheet; on computers it downloads a PNG. Never shows email, trips or notes.
- Admin console at /admin.html (admins only): total sign-ups, new and active this week/month, sign-ups per day or week with a running total, most-visited and home countries, and a searchable, sortable list of every traveler (email, sign-up date, last sign-in, last change, email confirmed, sign-in method, home, community member, countries, continents, trips, notes) with CSV download. An "Admin" link appears in the panel for admins only. Requires admin.sql (put your email in it first).

## v1.16 · Nov 13, 2026
- Help & About page (Help link in the panel and on the sign-in screen; shareable at whereihavebeen.com/#help) with how-to, badges and community, common questions, privacy and contact (help@whereihavebeen.com).
- Removed the "Other" group (including Northern Cyprus and Somaliland) and Kosovo: shown as plain land, not counted.
- Continents listed in alphabetical order (panel bars, Check off countries, leaderboard choices).

## v1.15 · Nov 13, 2026
- Badges. 22 badges in five groups (countries, continents, collections, trips, notes), a badge row on the panel, a full badge page with progress bars, and a "New badge!" pop-up.
- "Year first visited" on each country page; trips and notes move under an optional "Add trip details and notes" section. The year counts toward "since", countries this year, the Big year badge and the this-year leaderboard. Requires add-first-year.sql.
- Name line at the top of the panel: home-country flag, screen name, home, and "traveling since" once a year is entered.
- Your home country is marked as visited automatically.
- "Days on the road" and "countries this year" tiles only appear once you've entered years or dated trips.
- "Check off countries" redesigned: continents fold open, and countries are flag chips you tap to mark visited.
- Territories outside the country count (Cayman Islands, Turks and Caicos, Bermuda, Martinique, Puerto Rico and others) no longer show as dots or colored shapes.
- French Guiana is its own entry (South America), no longer part of France.
- Headline no longer shows the logged-trip count ("1 trip"), which read as if only one trip had been taken.
- Fix: after setting a new password, go straight to the map instead of staying on the reset screen.

## v1.14 · Nov 13, 2026
- Clear message when an email link has expired or was already used (v1.13).
- Signing in to an unconfirmed account opens "Check your email" with Resend ready.

## v1.12 · Nov 12, 2026
- French Polynesia is its own entry.
- Greenland is its own entry (v1.6).
- "Join the traveler community" opt-in at sign-up and in Profile (v1.8–v1.9).
- Delete my account in Profile (v1.10). Requires delete-account.sql.
- Fix: Profile save error "pendingCodes is not defined" (v1.11).
- "Check your email" screen after sign-up, with resend (v1.7).
- United States first in the home country list (v1.5).
- Leaderboards, percentile, version tag (v1.3–v1.4).
