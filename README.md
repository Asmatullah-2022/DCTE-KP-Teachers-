# DCTE KP Teachers

**Curriculum • Notifications • Documents • Teacher Resources**

An independent educational information app for teachers in Khyber
Pakhtunkhwa, Pakistan. It organizes official information published by:

1. Directorate of Curriculum and Teacher Education (DCTE), Khyber Pakhtunkhwa — https://dcte.kpese.gov.pk/
2. KP Elementary & Secondary Education Department (KPESE) — https://kpese.gov.pk/

> **This is NOT an official government application.** It is not affiliated
> with or endorsed by the Government of Khyber Pakhtunkhwa, DCTE, or KPESE.
> See in-app **Settings → About & Disclaimer**.

---

## 1. Status of this build — read this first

This repository is a complete, real, feature-based MVP scaffold — not a
mockup. A few things could not be done from this sandboxed build
environment and are called out explicitly rather than faked:

- **Outbound network access to `dcte.kpese.gov.pk` and `kpese.gov.pk` was
  blocked** in the environment this was built in, so the live HTML markup
  of those sites could not be inspected. `functions/src/sources/sourceConfig.ts`
  ships conservative, clearly-labeled default CSS selectors for a typical
  WordPress site (both are WordPress-based) — **verify and adjust them
  against the live pages before relying on automatic sync**, per the
  instructions in that file.
- **The actual content of the official semester-notification PDF was not
  read**, for the same reason. Per the app's own accuracy rules ("never
  invent missing unit titles," "never silently guess"), no curriculum unit
  data (subjects, unit titles) is fabricated anywhere in this repo. What
  *is* seeded (`scripts/seed/grades.json`, `academic_calendar.json`,
  `documents.json`) is data given directly in the project brief. Subjects
  and curriculum units ship only as clearly-marked
  `*_template.example.json` files — see §8 "Initial Content Import."
- **The Flutter/Dart SDK was not available in this build environment**, so
  `flutter pub get` / `flutter build` were not run here. The code is
  written to compile against the dependency versions pinned in
  `pubspec.yaml`; run the commands in §3 locally to verify and fix any
  version drift (Flutter/Firebase plugin APIs move fairly often).
- Android platform folders (`android/`) are **not included** — see §3,
  step 1. Hand-authoring a working Gradle wrapper (`gradle-wrapper.jar` is
  a binary file) is not reliable to do blind; `flutter create .` generates
  it correctly and takes 10 seconds.

Everything else — Dart source, Cloud Functions (TypeScript), Firestore
rules/indexes, Storage rules, tests, seed scripts — is complete and real.

---

## 2. Architecture

```
Flutter app (Android first)          Cloud Functions (2nd gen, Node 20/TS)
┌─────────────────────────┐          ┌──────────────────────────────────┐
│ features/*               │  reads  │ checkOfficialSources (scheduled,  │
│  home, curriculum,       │◄────────┤   Asia/Karachi, daily)            │
│  semester, notifications,│         │   → politeFetch + robots.txt      │
│  documents, search,      │         │   → extractLinks (cheerio)        │
│  resources, favorites,   │         │   → sha256 hash diff for PDFs     │
│  settings, assistant     │         │   → documents (status=pending)    │
├─────────────────────────┤         │   → sync_logs                     │
│ providers/ (Riverpod)    │         ├──────────────────────────────────┤
│ repositories/ (Firestore)│  calls  │ approveDocument / rejectDocument /│
│ services/ (FCM, cache,   │────────►│ publishNotification / setSourceActive│
│  favorites, connectivity)│callable │   → admin-only (custom claim)     │
├─────────────────────────┤         ├──────────────────────────────────┤
│ Firestore (public reads, │         │ askAssistant (callable)           │
│ admin-only writes)       │◄───────►│   → indexed-document lookup only, │
│ Firebase Storage         │         │     AI_API_KEY lives only here    │
│ Firebase Cloud Messaging │         │     (Secret Manager)              │
│ Firebase App Check       │         └──────────────────────────────────┘
└─────────────────────────┘
```

**Document pipeline** (see `functions/src/sync/checkOfficialSources.ts`):

```
DETECTED → DOWNLOADED → TEXT/PDF EXTRACTION → METADATA EXTRACTION →
RELEVANCE CLASSIFICATION → PENDING REVIEW → VERIFIED → PUBLISHED → FCM
```

Everything through **PENDING REVIEW** happens automatically on the daily
schedule. **VERIFIED → PUBLISHED → FCM** requires an explicit admin call
(`approveDocument`, then `publishNotification`) — nothing auto-extracted is
ever shown to end users without human sign-off, and AI extraction never
silently modifies official source text.

---

## 3. File tree

```
DCTE-KP-Teachers-/
├── README.md
├── .env.example
├── .gitignore
├── .firebaserc                      # placeholder — set your project id
├── firebase.json
├── pubspec.yaml
├── analysis_options.yaml
│
├── lib/
│   ├── main.dart
│   ├── config/
│   │   └── firebase_options.dart    # placeholder — run `flutterfire configure`
│   ├── core/
│   │   ├── constants/app_constants.dart
│   │   ├── theme/app_theme.dart
│   │   └── utils/semester_calculator.dart
│   ├── models/                      # Grade, Subject, Curriculum, Document,
│   │   │                            # Notification, AcademicCalendar, Source, AppConfig
│   ├── services/                    # cache, favorites, fcm, connectivity
│   ├── repositories/                # Firestore-backed reads per feature
│   ├── providers/app_providers.dart # Riverpod wiring
│   ├── routing/app_router.dart      # GoRouter routes
│   ├── widgets/                     # main_shell, offline_banner,
│   │   │                            # source_attribution, error_state_view, ...
│   └── features/
│       ├── home/            curriculum/       semester/
│       ├── notifications/   documents/        search/
│       ├── resources/       favorites/        settings/
│       └── assistant/
│
├── functions/                       # Cloud Functions v2 (TypeScript)
│   ├── package.json  tsconfig.json  jest.config.js
│   ├── src/
│   │   ├── index.ts
│   │   ├── sources/sourceConfig.ts          # ⚠ verify selectors, see §1
│   │   ├── parsers/{htmlParser,pdfParser}.ts
│   │   ├── sync/{checkOfficialSources,syncLogger}.ts
│   │   ├── notifications/sendFcm.ts
│   │   ├── admin/adminApi.ts
│   │   └── ai/extract.ts                    # askAssistant callable (stub)
│   └── test/{htmlParser,pdfParser}.test.ts
│
├── firebase/
│   ├── firestore.rules
│   ├── firestore.indexes.json
│   └── storage.rules
│
├── scripts/seed/
│   ├── import_seed.ts
│   ├── grades.json                          # real (ECE, Grade 1-8)
│   ├── academic_calendar.json               # real dates from the brief; verified:false
│   ├── documents.json                       # the source PDF's own metadata row
│   ├── subjects_template.example.json       # template — fill from the real PDF
│   └── curriculum_template.example.json     # template — fill from the real PDF
│
└── test/                                    # Flutter unit tests
    ├── semester/semester_calculator_test.dart
    └── models/{curriculum_model,notification_model}_test.dart
```

---

## 4. Setup requirements

- Flutter SDK ≥ 3.24 (Dart ≥ 3.5) — https://docs.flutter.dev/get-started/install
- Node.js 20.x (for Cloud Functions)
- A Firebase project (Blaze plan — required for Cloud Functions 2nd gen and
  outbound scheduled HTTP requests)
- Firebase CLI: `npm install -g firebase-tools`
- FlutterFire CLI: `dart pub global activate flutterfire_cli`
- Android Studio / an Android SDK for building the APK

---

## 5. Exact setup commands

```bash
# 1. Generate the Android (and optionally iOS) platform folders.
#    This project intentionally ships without android/ — flutter create
#    produces a correct, working Gradle project (including the binary
#    gradle-wrapper.jar, which cannot be hand-authored reliably).
flutter create . --org pk.gov.kp.dcte --project-name dcte_kp_teachers --platforms=android

# 2. Install Dart/Flutter dependencies.
flutter pub get

# 3. Log in to Firebase and create/select your project.
firebase login
firebase init   # choose: Firestore, Functions, Storage, Emulators
                 # point Firestore rules/indexes at firebase/firestore.rules
                 # and firebase/firestore.indexes.json (already configured
                 # in firebase.json), and Storage rules at firebase/storage.rules

# 4. Generate real Firebase config for the Flutter app (overwrites the
#    placeholder in lib/config/firebase_options.dart).
flutterfire configure --project=<your-firebase-project-id>

# 5. Add your project id to .firebaserc (or let `firebase use --add` do it).
firebase use --add

# 6. Install and build Cloud Functions.
cd functions
npm install
npm run build
cd ..

# 7. Set the AI secret (optional in v1 — askAssistant works as a stub
#    without it; required only once you wire a real model call).
firebase functions:secrets:set AI_API_KEY

# 8. Deploy Firestore rules/indexes, Storage rules, and Functions.
firebase deploy --only firestore:rules,firestore:indexes,storage,functions

# 9. Seed initial data (grades + academic calendar + the source PDF's
#    metadata row). See §8 before adding subjects/curriculum content.
cd scripts
npm install
GOOGLE_APPLICATION_CREDENTIALS=/path/to/serviceAccountKey.json npm run seed
cd ..

# 10. Run the app. (.env.example documents the official source URLs/App
#     Check debug token slot for reference — the app does not require a
#     bundled .env at runtime; those URLs are already hardcoded as public,
#     non-secret constants in lib/core/constants/app_constants.dart.)
flutter run

# 11. Build a release APK.
flutter build apk --release
```

### Grant yourself admin (for the admin-only Cloud Functions / rules)

Admin status is a custom claim (`admin: true`) on a Firebase Auth user —
there is no bundled admin UI/auth flow in this MVP (see §9). Set it with a
one-off script using the Admin SDK:

```js
// scripts/grant_admin.js (not included — small enough to paste ad hoc)
const { initializeApp, applicationDefault } = require('firebase-admin/app');
const { getAuth } = require('firebase-admin/auth');
initializeApp({ credential: applicationDefault() });
getAuth().setCustomUserClaims('<uid>', { admin: true }).then(() => process.exit(0));
```

---

## 6. Firebase configuration you must paste in yourself

| File | What to replace |
|---|---|
| `lib/config/firebase_options.dart` | Entirely regenerated by `flutterfire configure` — do not hand-edit the placeholders. |
| `.firebaserc` | `REPLACE_WITH_YOUR_FIREBASE_PROJECT_ID` |
| `.env` (copied from `.env.example`) | Optional local overrides; no secrets belong here. |
| Firebase Console → App Check | Register your Android app for Play Integrity; add a debug token for local dev devices. |
| `firebase functions:secrets:set AI_API_KEY` | Only if/when you wire `askAssistant` to a real model. |

**Never** commit: `google-services.json`, any `serviceAccountKey.json`,
`GoogleService-Info.plist`, or `.env` — all are already in `.gitignore`.

---

## 7. Firestore schema

Collections (see `lib/models/*.dart` for the Dart shape and
`firebase/firestore.rules` for access control):

`grades`, `subjects`, `curriculum`, `documents`, `notifications`,
`academic_calendar`, `sources`, `sync_logs`, `users`, `app_config`.

Public users get **read-only** access to published/verified data; all
writes require the `admin` custom claim (`sync_logs` writes are Functions
Admin-SDK-only — public/admin clients can only read them). `users` is
opt-in and self-service (a signed-in user can only read/write their own
document) — **anonymous usage works fully without signing in.**

Search relies on a `searchKeywords: string[]` field (lower-cased tokens)
maintained by the import script and Cloud Functions on write — see
`firebase/firestore.indexes.json` for the required `array-contains`
indexes, and `lib/repositories/search_repository.dart` for the client
query shape.

---

## 8. Initial content import

`scripts/seed/import_seed.ts` imports, in order: `grades.json` →
`subjects.json` (if present) → `academic_calendar.json` →
`documents.json` → `curriculum.json` (if present).

**Included and safe to import as-is:**
- `grades.json` — ECE, Grade 1–8 (from the project brief).
- `academic_calendar.json` — the Summer/Winter Semester I/II dates given in
  the project brief, session 2025-26. Seeded with **`verified: false`** —
  confirm them against the actual notification PDF before flipping to
  `true` (or edit via the admin API).
- `documents.json` — a single metadata row for the official semester
  notification PDF itself (title, URL, department), `status:
  pending_review`. This does **not** contain the PDF's internal content.

**Deliberately NOT included** (only `*_template.example.json` versions
ship): `subjects.json` and `curriculum.json`. This build could not read
the official PDF's actual text, and the app's own accuracy rule is explicit
— *never invent missing unit titles, never silently guess.* To populate
real curriculum data:

1. **Preferred:** let the daily `checkOfficialSources` function (or
   `forceSyncSource`) detect the PDF, download it, and hash it — then
   extend `functions/src/parsers/pdfParser.ts`'s
   `extractCurriculumCandidates` output into a small admin script that
   writes `curriculum` docs with `needsVerification: true`, and review them
   in the admin panel (§9) before flipping the flag.
2. **Manual fallback:** open the PDF yourself, duplicate
   `scripts/seed/subjects_template.example.json` → `subjects.json` and
   `curriculum_template.example.json` → `curriculum.json`, and transcribe
   each subject/unit **verbatim** (Urdu text included) from the source.
   Leave `needsVerification: true` on anything you're not fully certain
   of. Then re-run `npm run seed`.

`import_seed.ts` will refuse to import a row that still contains the
literal placeholder text `"REPLACE WITH ..."`, so an unedited template
can't accidentally go live.

---

## 9. Admin panel

No standalone admin web app ships in this MVP (out of scope to hand-author
reliably without a UI framework choice from you) — but the entire backend
surface it needs already exists as callable Cloud Functions, all gated on
the `admin` custom claim:

- `approveDocument({ documentId, editedMetadata? })`
- `rejectDocument({ documentId, reason? })`
- `publishNotification({ documentId, category, title, titleUrdu?, summary?, notificationNumber? })`
  → also sends the FCM push.
- `setSourceActive({ sourceId, active })`
- `forceSyncSource({ sourceId })`

The fastest way to drive these today is the Firebase Functions shell
(`cd functions && npm run shell`) or a small internal script/Postman
collection calling them as HTTPS callables with an admin ID token. A
proper web admin UI (e.g. a small React/Flutter-web app reusing these same
callables) is the natural next increment — the security model (custom
claims, rules, callable signatures) is already in place for it.

**Approving a new document, step by step:**
1. Wait for (or trigger via `forceSyncSource`) a sync run — it creates a
   `documents` row with `status: pending_review`.
2. Review it (its `sourceUrl`, and `fileHash`/`fileSize` if a PDF) against
   the live source.
3. Call `approveDocument` (optionally passing corrected `editedMetadata`)
   → sets `verified: true, status: verified`.
4. Call `publishNotification` with the category/title/summary you want
   shown → creates the public `notifications` row, flips the document to
   `status: published`, and pushes FCM to `dcte_all` + the category topic.

---

## 10. Testing checklist

**Flutter (`flutter test`)**
- [x] Semester calculation — Summer zone, both semesters, gap, boundary
      inclusivity (`test/semester/semester_calculator_test.dart`)
- [x] Semester calculation — Winter zone, both semesters, boundaries
- [x] `CurriculumModel` parsing incl. `needsVerification` defaults
- [x] `NotificationModel` category parsing incl. unknown → `other`
- [x] FCM topic list matches the required six topics
- [ ] Widget tests for offline mode / Urdu RTL rendering (add
      `flutter_test`'s `pumpWidget` + `Directionality` once you have real
      Urdu content to render — the `SubjectModel.nameUrdu` /
      `CurriculumModel.unitTitleUrdu` fields and `textDirection:
      TextDirection.rtl` usages are already wired in the unit-detail and
      subject screens)
- [ ] Search — needs the Firestore emulator (`firebase emulators:start`)
      to seed `searchKeywords` fixtures against; `SearchRepository` is a
      thin Firestore query wrapper suitable for an emulator-backed
      integration test

**Cloud Functions (`cd functions && npm test`)**
- [x] `extractLinks` — de-dup, empty-selector safety
- [x] `extractCurriculumCandidates` — unit detection, always-on
      `needsVerification`, empty input
- [ ] `checkOfficialSources` end-to-end (new doc / duplicate / changed
      hash / failed source) — write with `firebase-functions-test` +
      a Firestore emulator once you've verified real selectors (§1); the
      function is structured so each branch (`documentsAdded` /
      `documentsUpdated` / `documentsSkipped`) is independently observable
      via the returned `sync_logs` row

**Firestore security rules** — `firebase emulators:exec` with
`@firebase/rules-unit-testing` against `firebase/firestore.rules`:
- [ ] Anonymous read of published notification → allowed
- [ ] Anonymous read of a `pending_review` document → denied
- [ ] Non-admin write to `curriculum` → denied
- [ ] Admin (custom claim) write to `curriculum` → allowed

---

## 11. Deployment checklist

- [ ] `flutterfire configure` run against your **production** Firebase
      project, `lib/config/firebase_options.dart` regenerated
- [ ] App Check activated (Play Integrity) and enforced in the Firebase
      Console for Firestore/Storage/Functions
- [ ] `firebase deploy --only firestore:rules,firestore:indexes,storage,functions`
- [ ] `sources/*` documents reviewed — `active: true`, real selectors
      verified against the live sites (§1)
- [ ] At least one admin user has the `admin` custom claim
- [ ] Seed data imported (§8), `academic_calendar` rows reviewed and
      flipped to `verified: true` after manual confirmation
- [ ] `flutter build apk --release` signed with your own keystore
      (`android/key.properties` — gitignored; not included here)
- [ ] Manually verify: offline mode, Urdu RTL, FCM topic toggles, PDF
      viewer fallback to source URL on failure

---

## 12. Where the DCTE source is connected

- **Client-visible, safe URLs** live in `lib/core/constants/app_constants.dart`
  (`dcteBaseUrl`, `kpeseBaseUrl`, `kpeseNotificationsUrl`,
  `dcteSemesterNotificationPdf`) — used only for outbound "View Original
  Source" links (`lib/widgets/source_attribution.dart`) and the About
  screen. **The Flutter client never scrapes these sites directly.**
- **Server-side monitoring config** lives in
  `functions/src/sources/sourceConfig.ts` (`SOURCE_CONFIGS`) — one entry
  per source, with the base/list URL, department, and CSS selectors used
  by `functions/src/parsers/htmlParser.ts`.
- **The seeded `documents` row** (`scripts/seed/documents.json`) links the
  in-app "Documents" library entry for the notification PDF straight back
  to `sourceUrl`, so "View Original Source" always resolves to the exact
  government URL even before/without Firebase Storage mirroring.

## 13. How daily updates work

`functions/src/sync/checkOfficialSources.ts` exports a `onSchedule`
Cloud Function (`checkOfficialSources`) running `0 6 * * *` in
`Asia/Karachi` (once daily). For each configured source it: checks
`robots.txt`, politely fetches the listing page (identifying User-Agent,
15s timeout, up to 3 retries with exponential backoff — see
`functions/src/utils/http.ts`), extracts candidate links, and for each:
if the `sourceUrl` is new → creates a `documents` row (`status:
pending_review`); if it's a known PDF → re-downloads and SHA-256-hashes it,
updating the row (and resetting it to `pending_review`) only if the hash
changed, otherwise counting it as skipped. Every run writes one
`sync_logs` document with counts and any errors, and updates the
corresponding `sources` doc's `lastCheckedAt` /
`lastSuccessfulCheckAt`. An admin can also trigger `forceSyncSource`
on demand for one source.

## 14. How to manually approve a new document

See §9 above — call `approveDocument`, then `publishNotification`. Until
`publishNotification` is called, the document stays invisible to public
readers (Firestore rules only expose `status == 'published' && verified ==
true`) and no FCM push is sent.

---

## 15. Design & accessibility

Material 3, light background (`#FAFAF7`), dark-green education accent
(`#0B6E4F`, see `lib/core/theme/app_theme.dart`), rounded cards, large
readable type. English + Urdu supported via
`flutter_localizations`/`intl`; RTL is applied per-widget with
`textDirection: TextDirection.rtl` wherever Urdu text
(`nameUrdu`/`unitTitleUrdu`/`titleUrdu`) is rendered. No fake/sample data
ever renders in the production UI — every empty/loading/error state is an
explicit `ErrorStateView`, never a blank screen.
