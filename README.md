# Find your team

A student collaboration board matching Attendly and BuyNsell's mint/forest-green design. React, Vite, Supabase, and Vercel. Public browsing, no-account posts, eligibility and skills filters, saved posts, management-key backup/restore, direct email contact, sharing, expiry, reports, light/dark themes, and original static guides/policies.

## Run

Copy `.env.example` to `.env.local` and supply the Supabase project URL and publishable key. Never use a service-role key in VITE variables. Run `npm ci`, `npm run dev`, or `npm run build`. `npm run check` validates the generated site and anonymous database boundaries. Production uses `https://findyourteam-ten.vercel.app` as its canonical origin; update `scripts/pages.mjs` if changing domains.

## Database and ownership

With owner approval, this site uses isolated `public.team_posts` and `team_private` objects in the existing BuyNsell Supabase project because the account has reached the two-free-project limit. The original marketplace tables are not changed. `database/schema.sql` documents the initial schema. Apply it only once to a fresh namespace.

Public reads use RLS. Direct writes are revoked. Public invoker RPCs call narrowly scoped private definer routines with a fixed empty search path. A 256-bit browser-generated capability is required for each post mutation; only its SHA-256 digest is stored privately. No Supabase Auth login or service-role key is used. A lost management key cannot be recovered; owners can back up and restore their keys. Imported backups are validated. Treat them like passwords.

Requests are rate-limited by a hash of provider-supplied forwarded-IP headers, plus a key bucket for creation. If the header is absent, requests share a fallback bucket. This reduces casual abuse but is not bot-proof; add a server-verified challenge if abuse warrants it. Hidden posts cannot be reopened by their posters.

## Owner moderation

Review reports using the authenticated Supabase SQL editor:

```sql
select r.id, r.post_id, r.reason, r.created_at, r.reviewed, p.title
from team_private.reports r left join public.team_posts p on p.id=r.post_id
order by r.created_at desc;
-- After verifying a report, hide a post:
-- update public.team_posts set status='hidden',updated_at=now() where id='<verified-post-id>';
-- update team_private.reports set reviewed=true where id='<reviewed-report-id>';
```

Reports never automatically hide a post. There are no ads on user-generated content. Periodically remove old rate buckets and resolved reports according to your retention needs:

```sql
delete from team_private.rate_limits where started_at < now()-interval '48 hours';
```

## AdSense readiness

Original static editorial guides, navigation, About/contact, privacy, terms, safety, sitemap, robots, metadata, accessible forms, responsive layout, HTTPS, and content reporting are included. The account's ownership meta tag (`ca-pub-2851684575995607`) and exact authorized seller entry in `public/ads.txt` are configured for AdSense verification. No tracking or ad scripts are enabled. Approval is Google's decision, not a test this repository can guarantee.

Before enabling ads: secure AdSense approval for your owned domain, use the real publisher ID and authorized ads.txt line from Google, configure Google's required certified consent platform where applicable, update privacy disclosures, and restrict ads to reviewed editorial pages. Do not serve ads on unreviewed recruitment posts, report forms, empty/error views, or management screens. Do not ask users to click ads. Manual moderation must be actively operated by the owner.

Contact: public GitHub issues for general technical feedback; in-site private reports for opportunity/privacy issues. Never put private information in a public issue.
