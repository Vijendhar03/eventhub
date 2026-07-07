# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repo is

EventHub is a full-stack ticket booking app (Next.js 14 + Express + Prisma/MySQL) that doubles as a **sandbox target for Playwright test automation practice**. A lot of the value in this repo is in `.claude/skills/` — domain knowledge and agent workflows for generating/reviewing E2E tests — not just the app itself. The Playwright suite in `tests/` runs against the **live deployed site** (`https://eventhub.rahulshettyacademy.com`), not localhost — see Testing below.

## Commands

Run from the repo root unless noted.

```bash
npm run setup       # npm install in both backend/ and frontend/
npm run dev         # runs backend + frontend concurrently (API on :3001, web on :3000)
npm run db:push     # push Prisma schema to DB, non-interactive
npm run migrate     # prisma migrate dev — interactive, creates migration files
npm run seed        # seed 10 static events (backend/prisma/seed.js)
npm run build       # next build (frontend)
npm run lint        # next lint (frontend)
```

Backend-only (from `backend/`): `npm run dev` (nodemon), `npm run prisma:studio`, `npm run prisma:generate`.

### Playwright tests

```bash
npx playwright test                                   # full suite
npx playwright test tests/<file>.spec.js --reporter=line   # single file
npx playwright test --ui                              # UI mode
npx playwright show-report                             # view last HTML report
```

- `playwright.config.ts` sets `baseURL: https://eventhub.rahulshettyacademy.com` — tests hit production, not a local dev server. Chromium only, `fullyParallel: false`, no retries.
- Only `tests/booking-management.spec.js` exists in the main tree today; more are added via the `generate-tests` skill.
- Test accounts (see `.claude/skills/eventhub-domain/user-flows.md`): `rahulshetty1@gmail.com` / `Magiclife1!` and `rahulshetty1@yahoo.com` / `Magiclife1!` (used for cross-user security tests).

## Architecture

Monorepo with two independently-run npm workspaces plus a root orchestrator (`concurrently`).

```
backend/   Express API — routes → controllers → services → repositories → Prisma
frontend/  Next.js 14 App Router — app/ pages, components/, lib/api + lib/hooks
```

Backend layering (strict, don't collapse it):
- `routes/` — Express routers, full Swagger JSDoc annotations (feeds `/api/docs`)
- `controllers/` — thin HTTP glue only, no business logic
- `services/` — business rules, validation orchestration, transactions
- `repositories/` — the only layer that touches Prisma directly
- `middleware/authMiddleware.js` — JWT bearer-token check, sets `req.user = { userId, email }`
- `utils/errors.js` — `NotFoundError` / `InsufficientSeatsError` / `ValidationError`, mapped to HTTP codes in `middleware/errorHandler.js`

Auth: JWT (7-day expiry), bcrypt-hashed passwords. `/api/auth/register` and `/api/auth/login` are open; `/api/events` and `/api/bookings` require `Authorization: Bearer <token>`. **Note:** the root `README.md` predates auth and doesn't mention `/api/auth`, `login/register` pages, or the `User` model — trust the code (`backend/src/routes/authRoutes.js`, `backend/prisma/schema.prisma`) over the README for anything auth-related.

Data model: `User 1—N Event`, `User/Event 1—N Booking` (see `backend/prisma/schema.prisma`). Key domain rules live in `.claude/skills/eventhub-domain/business-rules.md` — notably: per-user FIFO limits (max 6 events, max 9 bookings — oldest auto-deleted past the cap), static (seeded) events are shared/immutable, booking ref first letter must match the event title's first letter, and refund eligibility is frontend-only logic (single-ticket = refundable, multi-ticket = not).

### Frontend API client duplication (known state, not a bug to "fix" blindly)

`frontend/lib/api/` has **both** `.js` and `.ts` versions of the same modules (`client.js`/`client.ts`, `events.ts`/`eventsApi.js`, `bookings.ts`/`bookingsApi.js`), and different call sites import different ones:
- `useEvents.ts` → `eventsApi.js`; `useBookings.ts` → `bookingsApi.js`
- `app/bookings/page.tsx` → `bookings.ts` (via the `index.ts` barrel, which only re-exports the `.ts` versions)
- `login/register/Navbar/Footer` → `BASE_URL` from `client.ts`

Both sets are live — this is leftover churn from adding auth, not dead code. If you touch API-client behavior, check which file the specific caller actually imports before editing.

### `.claude/skills/` — read before doing test-related work

- `eventhub-domain` (not user-invocable, auto-loaded as context) — domain overview; sub-files `business-rules.md`, `api-reference.md`, `ui-selectors.md`, `user-flows.md` are the source of truth for selectors, endpoints, and rules used across the other skills
- `create-scenarios` → writes `docs/test-scenarios.md` (6-lens scenario generation: happy path, business rules, security, negative, edge case, UI state)
- `test-strategy` → reads `docs/test-scenarios.md`, writes `docs/test-strategy.md` (assigns each scenario to Unit/API/Component/E2E)
- `generate-tests` → writes `tests/<feature>.spec.js`, validates against a real browser via Playwright MCP, follows a write→run→debug→fix loop until green
- `review-tests` → reviews spec files against `playwright-best-practices`
- `playwright-best-practices` (not user-invocable) — locator priority order (testid > role > label/placeholder > id > CSS class, never XPath), assertion patterns, POM conventions (`tests/pages/`), anti-patterns

These skills chain: scenarios → strategy → generated tests → review. When asked to add test coverage, prefer following that pipeline over writing ad hoc specs.

## CI/CD (`.github/workflows/`)

- `ci.yml` — PR gate: backend (syntax check, `prisma validate`/`format`/`generate`, no DB needed), frontend (`tsc --noEmit`, `next build`), and a `schema-drift` job that SSHes into the production server to diff `schema.prisma` against the live DB (read-only). Also callable via `workflow_call` so `deploy.yml` reuses it as a pre-deploy gate.
- `deploy.yml` — on push to `main`: runs `ci.yml` as a gate, then SSHes in, writes `.env` files from secrets, pulls, rebuilds, and does a zero-downtime `pm2 reload`. **Prisma migrations are never run automatically** — if a change needs one, run `npx prisma migrate deploy` on the server manually before merging/deploying.
- `playwright.yml` — on push to `main`, runs the full Playwright suite against the live production URL and uploads the HTML report as an artifact.
