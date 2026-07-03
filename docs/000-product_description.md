# Lyfta --- Product Roadmap & Technical Planning

## Vision

Lyfta is a multi-tenant SaaS platform for gyms, personal trainers,
studios and, in the future, rehabilitation clinics. The same platform
serves different business models through permissions and feature flags.

## Stack

-   Frontend: Flutter (Android, iOS and Responsive Web)
-   Backend: Go
-   Database: PostgreSQL
-   Cache: Redis
-   Storage: S3-compatible
-   Realtime: WebSockets
-   Auth: JWT + Refresh Tokens

## Multi-tenant

Tenant - Gym - Personal Trainer - Studio

Roles - Owner/Admin - Coach - Student

A single Flutter application is used by everyone.

### Why a single app?

The application adapts itself according to the authenticated user's
permissions.

Benefits: - Single codebase - Lower maintenance cost - Shared
authentication - Users can have multiple roles (coach + student) -
Faster feature delivery

The Flutter application **must be fully responsive**, offering: -
Android - iOS - Web (desktop-first experience for gyms)

The Web version should optimize: - Student management - Workout
builder - Financial dashboard - Reports - Administrative tasks

## Delivery packs

Scope is shipped as numbered packs, prioritized by the client's brief
(athlete-first). The rationale for this ordering is recorded in
[ADR-012](adr/ADR-012-escopo-mvp-packs.md); the milestone breakdown that
implements each pack lives in [doc 014](014-plano-de-documentacao.md).

Guiding principle: **MVP 1.0 is the athlete's daily loop** — train today's
workout, track evolution, talk to the coach, offline. Everything else is
sequenced into later packs so the first release is a thin end-to-end slice,
not a broad-but-hollow one.

## MVP 1.0 --- The athlete trains, evolves and talks to the coach

The four blocks the client prioritized, plus the invisible enablers required
to make them real.

### Today's workout (execution)

-   Clean "today" screen, minimal navigation
-   Video/GIF demonstration per exercise
-   Log done load, sets and reps
-   Rest timer between sets (sound + vibration alert)
-   Works offline (execution only --- see ADR-003)

### Evolution tracking

-   Load history per exercise (progression chart)
-   Before/after progress photos
-   Body measurements + bioimpedance --- **manual entry** (device/wearable
    integration is out of scope until 3.0+)

### Communication with the coach

-   Direct chat, student ↔ coach --- **text + image only** (rich media in 3.0)
-   Workout rating / typed check-in (feedback, difficulty, pain)
-   Push notifications: pending workout, new message

### Daily practicality

-   Simple, light login + password recovery
-   Weekly visual calendar (athlete's agenda)
-   Fast startup, no jank

### Required enablers (not in the client's list, but 1.0 cannot ship without them)

-   Authentication over the multi-tenant base (login + recovery + roles)
-   **Minimal coach workout builder** + exercise library with media --- someone
    has to author "today's workout" (full builder is 2.0)
-   Backend + sync queue (the former M0 infra)
-   **Structured prescription from day one:** `prescribed_sets` is structured
    (reps, target load, rest, RPE/RIR --- ADR-004) even with the minimal
    builder, otherwise the 1.0 load chart cannot exist

## MVP 2.0 --- The coach builds and manages (makes the business viable)

-   Full workout builder: versioning, blocks (superset/circuit), automatic
    A→B→C rotation, manual override
-   Student management: registration, status, goals, injuries, coach
    assignment, LGPD consent
-   Finance (PIX / manual reconciliation first): monthly fee, payment history,
    active / delinquent / inactive --- the coach-adoption lever
-   Coach dashboard: active students, delinquents, monthly revenue, today's
    workouts

## MVP 3.0 --- Engagement and analysis

-   **Muscle map**: body visualization, muscle effort %, weekly/monthly
    distribution (our differentiator vs HubFit/Trainerize; kept here by a
    conscious client decision --- ADR-012)
-   Advanced history: PRs, estimated 1RM, best volume
-   Rich chat media (audio, video, PDF, receipts) + expanded notifications
-   Coach scheduling: appointments, assessment sessions
-   Gamification (streaks, achievements, milestones), habits, reports

## MVP 4.0 --- Running module

Full vertical, inspired by Nike Run Club, Strava, Runna and TrainingPeaks
while staying integrated with strength training.

Features: - Running plans - Coach-created running workouts - Interval
sessions - Pace targets - Heart-rate zones - Distance goals - Weekly
mileage - Running calendar - Training load - Recovery recommendations
(rule-based initially) - Manual run logging - GPS tracking - Voice
cues - Audio notifications - Route history - Personal records - 5K / 10K
/ Half / Marathon goals - Shoe management - Shoe mileage tracking -
Weather information before runs - Pace charts - Elevation charts - Split
analysis - Integration with: - Apple Health - Health Connect - Garmin -
Coros - Polar - Strava import/export

Coach tools: - Weekly planning - Workout prescription - Pace
calculator - Training zones - Athlete comments - Compliance tracking

GPS in background + wearable integrations is the single most expensive item
of the roadmap; scope is trimmed on arrival at this pack.

## V2 --- AI layer

All AI features are intentionally postponed to V2.

-   AI workout generation
-   AI running plan generation
-   AI workout review
-   AI evolution summaries
-   AI chat assistant
-   AI exercise recommendations
-   AI injury-aware suggestions
-   AI nutrition insights (future)
-   AI risk detection
-   AI coaching assistant

## Future

-   Wear OS
-   Apple Watch
-   Live workout sync
-   QR Check-in
-   NFC
-   Advanced analytics
-   Marketplace
-   Public coach profiles
-   White-label support

## Product Principles

-   Mobile-first
-   Responsive Web
-   Offline-friendly workout execution
-   Fast startup
-   Feature flags
-   Subscription-ready
-   Multi-language
-   Accessibility
-   Clean architecture
-   Domain-driven modules
