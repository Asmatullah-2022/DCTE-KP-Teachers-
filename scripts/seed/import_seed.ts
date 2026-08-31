/**
 * One-time / repeatable seed importer.
 *
 * Imports grades.json, subjects.json (if present), academic_calendar.json,
 * documents.json, and curriculum.json (if present) into Firestore.
 *
 * `subjects.json` and `curriculum.json` are NOT committed to this repo by
 * default — this sandbox could not reach dcte.kpese.gov.pk to read the
 * official PDF's actual text (see README.md "Initial Content Import").
 * Generate real ones with:
 *
 *   cd scripts && npm install && npm run import:pdf -- /path/to/the-real-pdf.pdf
 *
 * which writes real seed/subjects.json + seed/curriculum.json from the
 * PDF's actual content (see ../import_dcte_pdf.ts). `subjects.schema-example.json`
 * / `curriculum.schema-example.json` in this folder are field-shape
 * references only, not data to import.
 *
 * Usage:
 *   1. Download a service-account key for your Firebase project (Firebase
 *      Console > Project Settings > Service Accounts > Generate new
 *      private key). NEVER commit this file.
 *   2. GOOGLE_APPLICATION_CREDENTIALS=/path/to/serviceAccountKey.json \
 *        npx ts-node scripts/seed/import_seed.ts
 */
import * as fs from 'fs';
import * as path from 'path';
import { initializeApp, applicationDefault } from 'firebase-admin/app';
import { getFirestore, Timestamp, FieldValue } from 'firebase-admin/firestore';

initializeApp({ credential: applicationDefault() });
const db = getFirestore();

function readJsonIfExists<T>(filename: string): T[] {
  const filePath = path.join(__dirname, filename);
  if (!fs.existsSync(filePath)) return [];
  return JSON.parse(fs.readFileSync(filePath, 'utf-8'));
}

function buildKeywords(text: string): string[] {
  return Array.from(
    new Set(
      text
        .toLowerCase()
        .replace(/[^a-z0-9؀-ۿ\s]/g, ' ')
        .split(/\s+/)
        .filter((t) => t.length > 1),
    ),
  );
}

async function importGrades() {
  const grades = readJsonIfExists<Record<string, unknown>>('grades.json');
  for (const g of grades) {
    const { gradeId, displayName, ...rest } = g as any;
    await db
      .collection('grades')
      .doc(gradeId)
      .set({ ...rest, displayName, searchKeywords: buildKeywords(displayName) }, { merge: true });
  }
  console.log(`Imported ${grades.length} grades.`);
}

async function importSubjects() {
  const subjects = readJsonIfExists<Record<string, unknown>>('subjects.json');
  for (const s of subjects) {
    const { subjectId, name, ...rest } = s as any;
    if (String(name).startsWith('REPLACE WITH')) {
      throw new Error(`subjects.json contains an unfilled template row for ${subjectId}. Fill in real data first.`);
    }
    await db
      .collection('subjects')
      .doc(subjectId)
      .set({ ...rest, name, searchKeywords: buildKeywords(name) }, { merge: true });
  }
  console.log(`Imported ${subjects.length} subjects.`);
}

async function importAcademicCalendar() {
  const rows = readJsonIfExists<Record<string, unknown>>('academic_calendar.json');
  for (const r of rows as any[]) {
    const { calendarId, startDate, endDate, ...rest } = r;
    await db
      .collection('academic_calendar')
      .doc(calendarId)
      .set(
        {
          ...rest,
          startDate: Timestamp.fromDate(new Date(startDate)),
          endDate: Timestamp.fromDate(new Date(endDate)),
        },
        { merge: true },
      );
  }
  console.log(`Imported ${rows.length} academic calendar rows.`);
}

async function importDocuments() {
  const docs = readJsonIfExists<Record<string, unknown>>('documents.json');
  for (const d of docs as any[]) {
    const { documentId, title, ...rest } = d;
    await db
      .collection('documents')
      .doc(documentId)
      .set(
        {
          ...rest,
          title,
          searchKeywords: buildKeywords(title),
          createdAt: FieldValue.serverTimestamp(),
          updatedAt: FieldValue.serverTimestamp(),
        },
        { merge: true },
      );
  }
  console.log(`Imported ${docs.length} document records.`);
}

async function importCurriculum() {
  const rows = readJsonIfExists<Record<string, unknown>>('curriculum.json');
  for (const r of rows as any[]) {
    const { curriculumId, unitTitle, ...rest } = r;
    if (String(unitTitle).startsWith('REPLACE WITH')) {
      throw new Error(`curriculum.json contains an unfilled template row for ${curriculumId}. Fill in real data first.`);
    }
    await db
      .collection('curriculum')
      .doc(curriculumId)
      .set(
        {
          ...rest,
          unitTitle,
          searchKeywords: buildKeywords(unitTitle),
          createdAt: FieldValue.serverTimestamp(),
          updatedAt: FieldValue.serverTimestamp(),
        },
        { merge: true },
      );
  }
  console.log(`Imported ${rows.length} curriculum units.`);
}

async function main() {
  await importGrades();
  await importSubjects();
  await importAcademicCalendar();
  await importDocuments();
  await importCurriculum();
  await db.collection('app_config').doc('global').set(
    { lastSyncedAt: FieldValue.serverTimestamp(), currentSession: '2025-26' },
    { merge: true },
  );
  console.log('Seed import complete.');
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
