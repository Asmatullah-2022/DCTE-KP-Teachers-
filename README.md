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

- **Outbound network access to `dcte.kpese.gov.pk` and `kpese.gov.pk` is
  blocked** from every build environment this project has been developed
  in (re-confirmed via both an agent web-fetch and a direct `curl`, which
  returns `CONNECT tunnel failed, response 403` for the domain), so the
  live HTML markup of those sites has never been inspected. Every selector
  in `functions/src/sources/sourceConfig.ts` carries an explicit
  `verificationStatus: 'NEEDS_LIVE_VERIFICATION'` field and is a
  conservative, best-effort default for a typical WordPress site (both
  domains run WordPress) — **not** tested against the real DOM. Verify and
  adjust them against the live pages, then flip that flag to `'VERIFIED'`,
  before relying on automatic sync in production; see the file's header
  comment for the exact steps.
- **The official semester-notification PDF has since been read.** The
  project owner uploaded the actual 24-page "Revised Notification
  Semester-wise Course Grade I-VIII" PDF (Session 2025-26) directly into
  the session, and `scripts/import_dcte_pdf.ts` was built and iterated
  against its real content (this environment still could not reach
  `dcte.kpese.gov.pk` to download it itself). `scripts/seed/subjects.json`
  (22 subjects) and `scripts/seed/curriculum.json` (1,323 records covering
  ECE through Grade 8) now contain real, extracted data — see §8 for exact
  counts and what's still rough (word order in some Urdu titles, mainly).
  Every record still carries `needsVerification: true`; nothing is
  auto-published without human review. `scripts/seed/*.schema-example.json`
  remain as field-shape references only.
- **The Flutter/Dart SDK was not available in this build environment**, so
  `flutter pub get` / `flutter build` were not run here. The code is
  written to compile against the dependency versions pinned in
  `pubspec.yaml`. A GitHub Actions workflow
  (`.github/workflows/build-apk.yml`, see §16) now builds and tests the
  app on every push and on demand, specifically so this doesn't block you
  building on a phone with no local Flutter install — but its first real
  run has not been observed yet (this repo has no CI history); watch the
  Actions tab for the first run and treat any failure there as a real bug
  to fix, the same as a local `flutter analyze`/`flutter test` failure.
- Android platform folders (`android/`) are **not included** in the repo
  — see §3, step 1, and §16 (the CI workflow generates them on the fly if
  missing). Hand-authoring a working Gradle wrapper (`gradle-wrapper.jar`
  is a binary file) is not reliable to do blind; `flutter create .`
  generates it correctly and takes 10 seconds.

Everything else — Dart source, Cloud Functions (TypeScript, verified with
`tsc --noEmit` and `npm test` in this environment), Firestore
rules/indexes, Storage rules, seed data, and the CI workflow — is complete
and real.

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
├── firebase.json                    # firestore + storage + functions + hosting (admin/)
│
├── .github/workflows/
│   └── build-apk.yml                # CI: builds & tests the app, uploads the APK — see §16
│
├── admin/                           # standalone curriculum-review dashboard — see §17
│   ├── index.html                   # the dashboard itself (vanilla JS, no build step)
│   └── firebase-config.example.js   # copy -> firebase-config.js (gitignored) with your web config
│
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
│   │   ├── sources/sourceConfig.ts          # ⚠ NEEDS_LIVE_VERIFICATION, see §1
│   │   ├── parsers/{htmlParser,pdfParser,classify}.ts
│   │   ├── sync/{checkOfficialSources,syncLogger}.ts
│   │   ├── notifications/sendFcm.ts
│   │   ├── admin/
│   │   │   ├── auth.ts                      # requireAdmin() — the one admin-claim check
│   │   │   ├── adminApi.ts                  # document/notification/source review
│   │   │   └── curriculumReview.ts          # bulk curriculum review — see §17
│   │   └── ai/extract.ts                    # askAssistant callable (stub)
│   └── test/{htmlParser,pdfParser,classify,curriculumReview}.test.ts
│
├── firebase/
│   ├── firestore.rules
│   ├── firestore.indexes.json
│   └── storage.rules
│
├── scripts/
│   ├── import_dcte_pdf.ts                   # ⚠ THE real curriculum importer — run locally, see §5
│   ├── grant_admin.ts                       # sets the admin custom claim — see §5
│   ├── jest.config.js
│   └── seed/
│       ├── import_seed.ts
│       ├── confidence.ts                    # ⚠ THE extraction-confidence/validation logic — see §17
│       ├── confidence.test.ts
│       ├── grades.json                          # real (ECE, Grade 1-8)
│       ├── academic_calendar.json               # real dates + exam weighting; verified:true
│       ├── documents.json                       # the source PDF's own metadata row
│       ├── subjects.schema-example.json         # field-shape reference only, not data
│       ├── curriculum.schema-example.json       # field-shape reference only, not data
│       ├── subjects.json                        # real — 22 subjects, from import_dcte_pdf.ts
│       └── curriculum.json                      # real — 1,323 records, from import_dcte_pdf.ts
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
there is no bundled admin UI/auth flow in this MVP (see §9), and this
claim is the *entire* admin system: every admin-only Cloud Function
(`functions/src/admin/adminApi.ts`'s `requireAdmin`) and every Firestore
rule (`firebase/firestore.rules`'s `isAdmin()`) checks exactly
`request.auth.token.admin === true` and nothing else.

**Exact steps** (full detail in `scripts/grant_admin.ts`'s header comment):

1. Create the Firebase Auth user, if you haven't already: Firebase Console
   → Authentication → Users → **Add user** (email/password is fine). Copy
   their **UID** from that same list.
2. Download a service-account key: Firebase Console → Project Settings
   (gear icon) → **Service Accounts** tab → **Generate new private key**.
   Save it *outside* this repo, e.g. `~/secrets/dcte-service-account.json`
   — **never commit it** (already covered by `.gitignore`).
3. Run:
   ```bash
   cd scripts
   npm install
   GOOGLE_APPLICATION_CREDENTIALS=~/secrets/dcte-service-account.json \
     npm run grant:admin -- <uid>
   ```
4. That user must sign out and back in (or refresh their ID token) for the
   claim to take effect — an already-issued token doesn't update
   retroactively.
5. To revoke later: same command with `--revoke` appended.

Firebase Admin credentials (the service-account key) are used **only** by
scripts you run locally with your own machine's environment variable —
they are never embedded in `lib/` (the Flutter app) or committed anywhere
in this repo.

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

`grades`, `subjects`, `curriculum`, `curriculum_pending`, `documents`,
`notifications`, `academic_calendar`, `sources`, `sync_logs`, `users`,
`app_config`.

`curriculum_pending` is **admin-only, never read by the app** — it's the
staging area every extracted/imported curriculum row lands in first (see
§8), carrying `extractionConfidence` (HIGH/MEDIUM/LOW), a `validation`
report, `verificationStatus` (`pending_review` / `verified` / `rejected`),
`reviewedBy`/`reviewedAt`, and (only if an admin edited it)
`correctedValue`/`originalExtractedValue`/`correctedBy`/`correctedAt` — see
§17 for exactly how those are computed and reviewed in bulk. A row only
ever reaches the public `curriculum` collection via `approveCurriculumRecord`
(or the bulk/selected-approve callables), and the pending copy is
**updated, never deleted**, so it stays a permanent audit trail.

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
`subjects.json` → `academic_calendar.json` → `documents.json` →
`curriculum.json`. **All five now contain real data extracted from the
actual official PDF** (session 2025-26; see "How this was produced" below)
— none of it is a placeholder or template.

- `grades.json` — ECE, Grade 1–8.
- `academic_calendar.json` — Summer/Winter × Semester I/II dates, the
  "Summer Zone follows Semester-I / Winter Zone follows Semester-II for
  2025-26 with immediate effect" policy note, and the 45%/55% examination
  weighting, all transcribed directly from page 1 of the real PDF and
  cross-checked against its extracted text — `verified: true`.
- `documents.json` — the notification's own metadata: title, full
  department name, notification number (`4411-22/SSW/Semester Breakup`),
  dated 2025-09-04, 24 pages, and the SHA-256/size of the exact file the
  project owner uploaded (see `_fileHashNote` in that file for why it's
  not yet cross-checked against a *live* download).
- **`subjects.json` — 22 subjects**, real names read from the PDF: Urdu,
  English, Mathematics, Hindko, Pashto, Seraiki, Khowar, Islamiyat,
  Nazira-e-Quran, General Knowledge, Ethics for Non-Muslims, General
  Science, Social Studies, Mutala-e-Quran, History, Geography, Computer
  Education, Home Economics, Drawing, Arabic, Introduction to
  Technologies, and one subject whose name in the source PDF is written
  entirely in Urdu (subjectId `subject-d531ee040d`, appears to be Health &
  Physical Education based on its unit titles, but the name is preserved
  verbatim rather than translated/guessed — see below).
- **`curriculum.json` — 1,323 records** spanning ECE through Grade 8,
  every one with `sourceDocumentId` / `sourcePage` / `sourceUrl` /
  `session` / `semester` / `unitNumber` / `unitTitle`, and every one
  with **`needsVerification: true`** — none of this is presented as
  final. Where the source itself has no itemized unit list (a few
  regional-language entries just say e.g. "Page No. 01 to 18"), the note
  itself is stored rather than invented per-lesson titles.

**What `npm run seed` actually does with those 1,323 rows — none of them
go straight to the public app.** `importCurriculum` (in
`scripts/seed/import_seed.ts`) checks each row's `needsVerification` flag:
a row marked `false` is written to the public `curriculum` collection; a
row marked `true` (currently **all 1,323** — none have been human-reviewed
yet) is written to `curriculum_pending` instead, an admin-only collection
the Flutter app's queries never touch (see §7). So as of this PDF import,
running `npm run seed` populates `curriculum_pending` with all 1,323 rows
and leaves the public `curriculum` collection with **0** — exactly
matching the "don't auto-publish unverified curriculum" rule. Every
pending row also gets an `extractionConfidence` rating (HIGH/MEDIUM/LOW)
and a `validation` report computed at the same time, so reviewing all
1,323 doesn't mean approving them one at a time — see §17 for the exact
breakdown and the bulk-review dashboard.

**Known quality limits — read before flipping `needsVerification` to
`false` on anything:**
- English-medium subjects (Math, English, Science, History, Geography,
  Computer Education, etc.) extracted cleanly — titles read correctly
  word-for-word in spot checks against the source pages.
- Urdu/Arabic-script subjects (Urdu, Islamiyat, Nazira-e-Quran,
  Mutala-e-Quran, Hindko/Pashto/Seraiki/Khowar's numbered entries)
  extracted with **uncorrected word order** in places, and some titles
  have stray fragments of an adjacent honorific phrase (a "ﷺ"/durood
  formula rendered as many separate diacritic glyphs) bled in from a
  neighboring line. This is a known, documented limitation — see
  `scripts/import_dcte_pdf.ts`'s "URDU/ARABIC-SCRIPT TEXT" header comment
  for why it isn't auto-corrected — not silently hidden. Every affected
  row is still traceable to its exact `sourcePage`.
- Re-run the importer with `--debug` (see below) any time to see the raw
  reconstructed text next to what it parsed, if you want to manually
  clean up a specific subject/grade.

**How this was produced (re-run this if the notification is revised):**

```bash
# 1. Get the PDF onto a machine that can reach dcte.kpese.gov.pk (your own
#    laptop/browser is enough — download it like any other file):
#      https://dcte.kpese.gov.pk/wp-content/uploads/Revised-Notification-Semester-wise-Course-Grade-I-VIII-final-draft.pdf

# 2. Install the script's dependencies (one-time):
cd scripts
npm install

# 3. (Optional) Preview what it detects without writing files, and see the
#    raw text it reconstructed per page/column (useful if a revised PDF's
#    wording doesn't match the built-in patterns — see the script's header
#    for which regexes/constants to adjust):
npm run import:pdf -- ~/Downloads/Revised-Notification-Semester-wise-Course-Grade-I-VIII-final-draft.pdf --dry-run --debug

# 4. Run it for real — this OVERWRITES scripts/seed/subjects.json and
#    scripts/seed/curriculum.json:
npm run import:pdf -- ~/Downloads/Revised-Notification-Semester-wise-Course-Grade-I-VIII-final-draft.pdf

# 5. Review the generated files against the PDF by hand, especially any
#    Urdu-script rows (see "Known quality limits" above). Flip
#    needsVerification to false only for rows you've personally confirmed.

# 6. Import into Firestore:
GOOGLE_APPLICATION_CREDENTIALS=/path/to/serviceAccountKey.json npm run seed
```

If a future PDF turns out to be a scanned image with no text layer, the
script detects that (fewer than ~200 characters of extractable text) and
stops without writing anything — it will tell you to run OCR first (e.g.
`ocrmypdf input.pdf output-ocr.pdf`, or this project's own `pdf` skill) and
re-run against the OCR'd file, or transcribe by hand using the
`*.schema-example.json` files as a field reference. It does the same —
refuses to write anything — if it extracts text but finds no recognizable
grade/subject/unit patterns at all, so a layout change surfaces as a loud
failure rather than silently producing nothing (or garbage).

`import_seed.ts` also independently refuses to import any row that still
contains the literal placeholder text `"REPLACE WITH ..."`, so an unedited
schema-example file can never accidentally go live even if misnamed.

---

## 9. Admin panel

### 9a. Document review (notifications pipeline)

No standalone document-review UI ships in this MVP — drive these as
callable Cloud Functions (Functions shell, or the admin dashboard's
browser console) with an admin ID token:

- `getPendingDocuments({ limit? })` → the review queue: every document
  currently at `detected` / `downloaded` / `extracted` / `pending_review`,
  newest first.
- `approveDocument({ documentId, editedMetadata? })`
- `rejectDocument({ documentId, reason? })`
- `publishNotification({ documentId, category, title, titleUrdu?, summary?, notificationNumber? })`
  → also sends the FCM push.
- `setSourceActive({ sourceId, active })`
- `forceSyncSource({ sourceId })`

**Approving a new document, step by step:**
1. Wait for (or trigger via `forceSyncSource`) a sync run — it creates a
   `documents` row and drives it through `detected` → `downloaded` (PDFs
   only) → `extracted` (PDFs only — raw text preview + a curriculum
   candidate count get attached) → `pending_review`. Call
   `getPendingDocuments` to list everything sitting in the queue.
2. Review it (its `sourceUrl`, `fileHash`/`fileSize`/`rawExtractionPreview`
   if a PDF) against the live source.
3. Call `approveDocument` (optionally passing corrected `editedMetadata`)
   → sets `verified: true, status: verified`.
4. Call `publishNotification` with the category/title/summary you want
   shown → creates the public `notifications` row, flips the document to
   `status: published`, and pushes FCM to `dcte_all` + the category topic.

### 9b. Curriculum review — the bulk-review dashboard

`admin/index.html` is a real, standalone admin web page (vanilla JS,
Firebase v10 CDN modules — no build step, no Flutter needed) for reviewing
the 1,323 curriculum records extracted from the PDF **without approving
them one at a time**. See §17 for what it does and how to deploy it; the
callables it's built on:

- `getPendingCurriculum({ gradeId?, subjectId?, semester?, confidence?, verificationStatus?, limit? })`
  → the `curriculum_pending` queue, filterable any way you like.
- `getCurriculumReviewSummary()` → the dashboard header counts (total /
  HIGH / MEDIUM / LOW / verified / pending / rejected / published to app).
- `approveCurriculumRecord({ curriculumId, editedFields? })` → approve ONE
  record (any confidence level), optionally correcting its title.
- `editCurriculumPending({ curriculumId, correctedValue })` → save a
  correction WITHOUT approving/rejecting yet.
- `rejectCurriculumRecord({ curriculumId, reason? })`
- `approveSelectedCurriculum({ curriculumIds: string[] })` /
  `rejectSelectedCurriculum({ curriculumIds: string[], reason? })` → act on
  an admin-picked batch (the dashboard's checkbox selection).
- `bulkApproveHighConfidence({ gradeId?, subjectId?, semester?, dryRun? })`
  → the safe bulk action: approves every record that is BOTH
  `extractionConfidence: 'HIGH'` AND still `pending_review` — **never**
  MEDIUM or LOW, no matter how the filters are scoped. `dryRun: true`
  previews the count/list without writing anything.
- `exportCurriculumReviewReport()` → grouped counts + the full list of
  records that failed hard validation, for the dashboard's download button.

None of these delete a `curriculum_pending` document — approve/reject only
ever update its `verificationStatus`/`reviewedBy`/`reviewedAt` in place
and (for approvals) copy a record into the public `curriculum` collection,
so `curriculum_pending` stays a permanent audit trail of every decision.

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
- [x] `classifyCategory` / `parseLooseDate` — keyword categories, ISO and
      DD/MM/YYYY date parsing, "never guess" on unparseable text
- [x] `buildApprovalWrites` (curriculum review) — copies to the public
      collection with `needsVerification: false`, leaves the pending copy
      updated (not deleted), preserves `rawText`/`extractedText` untouched
      by an edit, and correctly records `correctedValue`/
      `originalExtractedValue`/`correctedBy` when a title is corrected
- [ ] `checkOfficialSources` end-to-end (new doc / duplicate / changed
      hash / failed source) — write with `firebase-functions-test` +
      a Firestore emulator once you've verified real selectors (§1); the
      function is structured so each branch (`documentsAdded` /
      `documentsUpdated` / `documentsSkipped`) is independently observable
      via the returned `sync_logs` row
- [ ] `bulkApproveHighConfidence` / `approveSelectedCurriculum` /
      `getCurriculumReviewSummary` end-to-end — these call `getFirestore()`
      directly, so they need a Firestore emulator (not available in the
      environment this was built in) rather than a pure unit test; the
      pure per-record logic they share (`buildApprovalWrites`) is covered
      above

**Scripts (`cd scripts && npm test`)**
- [x] `validateRecord` — every hard check individually (unknown grade/
      subject, invalid semester, missing sourcePage/sourceDocumentId/
      sourceUrl, empty title, duplicate key)
- [x] `isOcrSuspect` — clean English, clean short Urdu (incl. a legitimate
      single-letter word, which an earlier version of this heuristic
      false-flagged — see the test), scrambled Arabic-script text, long
      non-Urdu text
- [x] `classifyConfidence` — HIGH for clean English, MEDIUM (never HIGH)
      for clean Urdu, LOW for OCR-suspect text/failed validation/scope-note
      records
- [x] `findDuplicateKeys` — real duplicates detected; two legitimate
      scope-notes for the same subject/semester NOT flagged as duplicates

**Firestore security rules** — `firebase emulators:exec` with
`@firebase/rules-unit-testing` against `firebase/firestore.rules`:
- [ ] Anonymous read of published notification → allowed
- [ ] Anonymous read of a `pending_review` document → denied
- [ ] Non-admin write to `curriculum` → denied
- [ ] Admin (custom claim) write to `curriculum` → allowed
- [ ] Non-admin read of `curriculum_pending` → denied
- [ ] Admin read/write of `curriculum_pending` → allowed

---

## 11. Deployment checklist

- [ ] `flutterfire configure` run against your **production** Firebase
      project, `lib/config/firebase_options.dart` regenerated
- [ ] App Check activated (Play Integrity) and enforced in the Firebase
      Console for Firestore/Storage/Functions
- [ ] `firebase deploy --only firestore:rules,firestore:indexes,storage,functions`
- [ ] `sources/*` documents reviewed — `active: true`, real selectors
      verified against the live sites (§1)
- [ ] At least one admin user has the `admin` custom claim (§5 "Grant
      yourself admin")
- [ ] Seed data imported (§8) — lands `curriculum_pending` (1,323 rows,
      admin-only) and the other collections; `academic_calendar` is
      already `verified: true` (transcribed from the real PDF)
- [ ] Curriculum records reviewed via the bulk-review dashboard (§17) —
      at minimum, click **Approve High Confidence** per group you care
      about — before expecting the app's Curriculum tab to show anything;
      it queries the public `curriculum` collection only, which starts empty
- [ ] `admin/firebase-config.js` created from the `.example.js` (§17) and
      `firebase deploy --only hosting` run, if you want the review
      dashboard deployed rather than opened from disk
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
  per source, with the base/list URL, department, CSS selectors used by
  `functions/src/parsers/htmlParser.ts`, and a `verificationStatus` flag
  (`NEEDS_LIVE_VERIFICATION` out of the box — see §1).
- **The official PDF URL is also the seed source document ID's basis**:
  `functions/src/sources/sourceConfig.ts` exports
  `DCTE_SEMESTER_NOTIFICATION_PDF_URL`, and `scripts/seed/documents.json` /
  `scripts/import_dcte_pdf.ts` both default to that same URL, so every
  curriculum row's `sourceUrl` and the in-app "Documents" library entry
  resolve to the exact same government URL.
- **In the app**, every curriculum unit and document detail screen shows
  an "Official Source" panel (`lib/widgets/source_attribution.dart`) with
  an **"Open Original PDF"** link (or "View Original Source" for non-PDF
  pages) that opens `sourceUrl` directly — the Flutter client never
  scrapes these sites, it only ever links out to them.

## 13. How daily updates work

`functions/src/sync/checkOfficialSources.ts` exports a `onSchedule`
Cloud Function named **`checkOfficialSources`**, running `0 6 * * *` in
`Asia/Karachi` (once daily). It is **not** hard-coded to the one semester
PDF — it walks whatever links `functions/src/parsers/htmlParser.ts` finds
on each configured listing page (`SOURCE_CONFIGS` in
`functions/src/sources/sourceConfig.ts`, currently the DCTE homepage and
the KPESE notifications category page — both marked
`NEEDS_LIVE_VERIFICATION`, see §1), so any new post/PDF KPESE or DCTE
publishes going forward is picked up the same way. For each configured
source it:

1. Checks `robots.txt` for the source and skips (logging why) if disallowed.
2. Politely fetches the listing page — identifying User-Agent, 15s
   timeout, up to 3 retries with exponential backoff, and it treats a
   403/429/401 response as "back off, don't bypass" rather than retrying
   aggressively (see `functions/src/utils/http.ts`).
3. Extracts and normalizes candidate links, each with a best-effort
   `category` (`functions/src/parsers/classify.ts`, keyword-based —
   curriculum / assessment / teacherTraining / academicCalendar / policy
   / notification) and a best-effort `publishedDate` parsed from whatever
   date text sits near the link (left `null`, never guessed, if it can't
   be parsed confidently).
4. For each link, compares its normalized URL against existing `documents.sourceUrl` values:
   - **New URL** → creates a `documents` row at `status: 'detected'` with
     `category`, `publishedDate` (if parsed), and `documentUrl` (mirrors
     `sourceUrl` when the link is already a direct file — see the code
     comment there for the current limit: a source that links to an
     announcement *page* rather than the file itself isn't followed one
     level deeper yet), then (if it's a PDF) downloads it (`'downloaded'`),
     extracts its text with `pdf-parse` and runs the conservative
     unit-candidate scan (`'extracted'`, storing a text preview + candidate
     count — never a `curriculum` row), and finally lands it at
     `'pending_review'`.
   - **Same URL, PDF, changed SHA-256 hash** → re-runs
     downloaded→extracted→pending_review on the existing row (resets
     `verified: false`) — this is the duplicate-vs-changed detection.
   - **Same URL, same hash** → skipped (counted in `documentsSkipped`).
5. Writes one `sync_logs` document with counts (`documentsFound/Added/Updated/Skipped`)
   and any errors, and updates the matching `sources` doc's
   `lastCheckedAt` / `lastSuccessfulCheckAt` / `verificationStatus`.

An admin can also call `forceSyncSource({ sourceId })` to run this on
demand for one source (e.g. right after fixing its selectors). At no point
does this function write to the `curriculum` collection or send an FCM
push — see §14 and §9 for the human-gated steps that do.

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

---

## 16. Building an APK without installing Flutter (GitHub Actions)

`.github/workflows/build-apk.yml` builds and tests the app in the cloud —
useful since this project is being developed from a phone with no local
Flutter install. It runs automatically on every push/PR that touches
`lib/`, `test/`, `pubspec.yaml`, or `android/`, **and** supports an
on-demand manual run (one workflow covers both asks rather than two
near-duplicate files):

1. GitHub repo → **Actions** tab → **Build Android APK** (left sidebar) →
   **Run workflow** button → pick the branch → **Run workflow**.
2. Wait for it to finish (Flutter install + `flutter analyze` +
   `flutter test` + `flutter build apk --release` — a few minutes).
3. Open the finished run → **Artifacts** section at the bottom →
   download `dcte-kp-teachers-release-apk` → unzip → `app-release.apk` →
   transfer to your phone (e.g. via a cloud drive or `adb install`) and
   install it (you'll need "install unknown apps" allowed for whichever
   app you use to open it).

What it does under the hood:
- Checks out the repo, installs Java 17 + Flutter (stable channel).
- Generates `android/` on the fly with `flutter create .` **only if** it
  isn't already committed — so once you commit your own `android/` (e.g.
  after running `flutterfire configure` locally, which edits Android
  Gradle files), the workflow uses that instead of regenerating it.
- Runs `flutter pub get`, `flutter analyze --no-fatal-infos`, `flutter test`.
- Runs `flutter build apk --release` and uploads the resulting APK as a
  workflow artifact (kept 14 days).

**Important limitation:** this builds against whatever
`lib/config/firebase_options.dart` is committed — the placeholder in this
repo until you run `flutterfire configure` (§5) and commit the real one
(or wire it in as a CI secret restored by an extra workflow step, if you'd
rather not commit it to a public repo). The APK installs and runs, but
won't reach Firebase until that's real. Also note: this workflow has not
been observed running yet in this repository (no GitHub Actions history
exists here) — treat its first real run as the actual test of it, the
same as you would for the Flutter code itself.

---

## 17. Bulk curriculum review — how to clear 1,323 pending records without approving them one by one

The 1,323 curriculum records extracted from the real PDF (§8) all start in
`curriculum_pending`, every one flagged `needsVerification: true`. Nothing
here is auto-published. But approving over a thousand records one at a
time isn't realistic either, so every record gets an `extractionConfidence`
rating computed once at seed time (`scripts/seed/confidence.ts` — the only
place this logic lives; the dashboard and Cloud Functions only ever read
the result back) and a `validation` report, so the *safe* majority can be
bulk-approved in one click while anything actually uncertain still gets a
human's eyes.

### How confidence is decided

| Rating | Meaning | Eligible for bulk approval? |
|---|---|---|
| **HIGH** | Passes every hard check (known grade/subject, valid semester, real `sourcePage`/`sourceDocumentId`/`sourceUrl`, non-empty title, not a duplicate), isn't flagged as OCR-scrambled, is a real itemized unit (not a scope note), and contains **no Arabic-script text**. | Yes — the only rating `bulkApproveHighConfidence` ever touches. |
| **MEDIUM** | Passes every hard check and isn't OCR-scrambled, but the title contains Urdu text. Per the project's own rule to be conservative with Urdu, this is **never** HIGH no matter how clean it looks. | No — always requires a human read, just not page-by-page scrutiny. |
| **LOW** | Fails a hard check, OR looks OCR/glyph-scrambled (see below), OR is a non-itemized "scope note" record (e.g. "Page No. 1 to 18" instead of a real unit title). | **Never** — every LOW record must be opened individually. |

The OCR-scramble check (`isOcrSuspect` in `confidence.ts`) is a heuristic
for a real, observed failure mode: this PDF's Arabic-script text sometimes
bleeds isolated diacritic glyphs from a neighboring honorific phrase into
a title, producing many one-character "words". It flags a title as
suspect if it has more than 15 words, or (for titles with 6+ words) more
than 35% of its words are a single character — tuned so ordinary short
Urdu phrases with one legitimate single-letter word (e.g. "و", "and")
aren't flagged; see `scripts/seed/confidence.test.ts` for the exact cases
this was checked against, including one it originally got wrong.

### Real numbers for this PDF's 1,323 records

```
HIGH confidence:              535   (safe for one-click bulk approval)
MEDIUM confidence:             456   (Urdu — needs a human read, every one)
LOW confidence:                332   (OCR-suspect or a scope-note record — never bulk-approved)
Duplicate (grade/subject/semester/unit) records: 0
Records with missing/invalid required fields:      0
```
(Run `cd scripts && npx ts-node -e "..."` against `confidence.ts` yourself,
or just open the dashboard — §9b's `getCurriculumReviewSummary` shows the
live count from Firestore, which will differ slightly after you start
approving/rejecting records.)

### Using the dashboard

1. Copy `admin/firebase-config.example.js` → `admin/firebase-config.js`
   and fill in your Firebase project's **web app** config (Firebase
   Console → Project Settings → General → Your apps → Web app — add one
   if you don't have one yet; it's free and instant). This file is
   gitignored, same as the Flutter app's real `firebase_options.dart`.
2. Deploy it: `firebase deploy --only hosting` (from the repo root — the
   `admin/` folder is already wired as the Hosting public directory in
   `firebase.json`). You'll get a `https://<project-id>.web.app` URL.
3. Open that URL, sign in with an account that has the `admin` custom
   claim (§5 — if you haven't granted yourself admin yet, do that first).
4. The page loads a Grade → Subject → Semester tree on the left (with
   H/M/L badges per group) and a live summary bar at the top. Click a
   semester to see its records on the right.
5. Per record: **View Source PDF** (opens the exact page via a `#page=N`
   link most browser PDF viewers honor — "jump to page"), **Edit**
   (correct the title without approving/rejecting), **Approve**,
   **Reject**.
6. Per group or selection: check rows and click **Approve Selected** /
   **Reject Selected**, or click **Approve High Confidence** to bulk-approve
   every still-pending HIGH record in the currently selected
   grade/subject/semester in one action (it asks for confirmation first
   and shows you the count before committing).
7. **Export Review Report** downloads a JSON file (grouped counts +
   every record that failed validation) for offline triage.

**If you'd rather not deploy Hosting yet**, you can open `admin/index.html`
directly from disk in a browser (`file://...`) after filling in
`firebase-config.js` — Firebase Auth/Firestore/Functions calls work fine
from a local file, only the URL will look different. If your project has
App Check enforced on Firestore/Functions (§11), you'll need to add an App
Check provider to this page too (not wired in by default) or temporarily
allow unenforced access for the Hosting origin while you review.

**After approving records**, the Android app's Curriculum tab needs no
extra step to see them — `CurriculumRepository` uses a live Firestore
listener (`.snapshots()`) on the public `curriculum` collection, so an
approved record appears in the app automatically, in real time.
