# Speakance Web

Small Next.js site for:

- landing page (`/`)
- support page (`/support`)
- Privacy Policy (`/privacy`)
- Terms (`/terms`)
- Supabase email confirmation landing (`/auth/confirmed`)
- Supabase password reset page (`/auth/reset`)

## Local development

```bash
cd /Users/andresguerra/Documents/Non-Work/Apps/TalkSpend/ios/Speakance/web
npm install
npm run dev
```

Open [http://localhost:3000](http://localhost:3000).

## Environment variables (for `/auth/reset`)

Copy `.env.example` to `.env.local` and fill in your Supabase public values:

```bash
cp .env.example .env.local
```

## Deployment

Recommended: Vercel.

This site is intentionally lightweight so it can be used for App Store Connect URLs and Supabase Auth redirects.
