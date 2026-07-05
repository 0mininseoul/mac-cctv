# Mac CCTV landing page

Single static page, no build step. `index.html` is deploy-ready as-is.

## Live

**https://mac-cctv.vercel.app** — deployed via `vercel` CLI under the `0minseouls-projects` team (Hobby plan). Lighthouse: Accessibility/Best Practices/SEO/Agentic Browsing all 100 on the live URL.

## Redeploy after editing `index.html`

```
cd web
vercel --yes --prod --scope 0minseouls-projects
```

`.vercel/project.json` (gitignored) already links this directory to the `mac-cctv` project, so no re-linking is needed.

## Before going live

- Swap the two "Coming Soon" App Store badge `href="#"` links for the real App Store / Mac App Store listing URLs once approved (`web/index.html`, both `store-badge` occurrences — hero and final CTA)
- Optional: replace the CSS phone mockup with a real demo video/GIF once one exists
