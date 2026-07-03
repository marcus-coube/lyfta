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

## MVP

### Authentication

-   Login
-   Password recovery
-   Multi-tenant
-   Role permissions

### Student Management

-   Registration
-   Status
-   Goals
-   Injuries
-   Coach assignment

### Workout Module

-   Workout builder
-   Exercise library
-   Video/GIF support
-   Automatic workout rotation (A → B → C...)
-   Manual override
-   Workout execution
-   Rest timer
-   Previous load visualization
-   Load history

### Muscle Map

-   Human body visualization
-   Muscle effort percentage
-   Weekly and monthly muscle distribution

### Workout History

-   Previous workouts
-   Volume
-   Progression

### Chat

-   Student ↔ Coach
-   Push notifications

### Finance

-   Students
-   Monthly fee
-   Payment history
-   Active / Delinquent / Inactive
-   Manual payment reconciliation

### Dashboard

-   Active students
-   Delinquent students
-   Monthly revenue
-   Today's workouts

## V1

### Physical Assessment

-   Weight
-   Body fat
-   Circumferences
-   Progress photos
-   Charts

### Scheduling

-   Appointments
-   Assessments
-   Training sessions

### Notifications

-   Workout reminders
-   Payment reminders
-   Workout updates

### Gamification

-   Streaks
-   Achievements
-   Workout milestones

### Reports

-   Student evolution
-   Attendance
-   Financial reports

## Running Module (V1)

Inspired by the best ideas found across modern running platforms (such
as Nike Run Club, Strava, Runna and TrainingPeaks), while keeping the
experience integrated with strength training.

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

## V2 (AI)

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
