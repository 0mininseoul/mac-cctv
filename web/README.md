# Mac CCTV landing page

Single static page, no build step. `index.html` is deploy-ready as-is.

## Deploy to Vercel (manual — one-time, human step)

1. `vercel login` (or connect the GitHub repo in the Vercel dashboard)
2. From this directory: `vercel --prod` (or import the repo in the Vercel dashboard and set **Root Directory** to `web/`)
3. Vercel auto-detects a static site (no framework, no build command needed)
4. Free tier (Hobby plan) is fine as long as the app stays free — see PRD §9/§14 for when Pro ($20/mo) becomes necessary

## Before going live

- Swap the two "Coming Soon" App Store badge `href="#"` links for the real App Store / Mac App Store listing URLs once approved (`web/index.html`, both `store-badge` occurrences — hero and final CTA)
- Optional: replace the CSS phone mockup with a real demo video/GIF once one exists
