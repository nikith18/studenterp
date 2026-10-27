# Attendly — Student Attendance Management System

A Flutter Android semester project starter with a role-based demonstration UI and Android local persistence. It currently runs in **local demo mode**: the role picker is not secure authentication, student/faculty records are demonstration fixtures, and attendance history is stored on the device using Android SharedPreferences. Advanced workflow actions and their sample repositories run in memory for the current app process. Firebase Authentication and Firestore are **not connected**; the source does not claim cloud sync, multi-user access, or Firebase-backed account security.

## Run

1. Install Flutter (Dart SDK constraint: `^3.13.5`) and Android Studio with an Android SDK.
2. Open this folder in Android Studio or VS Code.
3. Run `flutter pub get` and launch on an Android emulator/device.
4. Sign in with any syntactically valid email and a password of at least four characters, then choose Student, Faculty, or Admin. This is a UI demonstration selector, not authentication.

The app has three role-specific navigation flows. Faculty can select a subject, update each student's status (Present, Absent, On Duty), mark everyone present, and save a dated summary. Saved summaries survive app restarts on that Android device. Students see attendance summaries, subject cards, below-threshold styling, and saved history. Admin sees a searchable directory view. Theme selection and sign-out are functional.

## Download Android APK

[Download the latest Android APK](https://github.com/nikith18/studenterp/releases/latest/download/app-release.apk). A GitHub Actions workflow builds the release APK and attaches it to GitHub Releases whenever a `v*` version tag is pushed. The APK runs in local demo mode and does not sync attendance to Firebase.

## Firebase setup required for production

1. Create a Firebase project and Android app matching `com.example.studenterp` (or update the package consistently).
2. Install FlutterFire CLI and run `flutterfire configure`; add generated `firebase_options.dart` and initialize Firebase before `runApp`.
3. Add `firebase_core`, `firebase_auth`, and `cloud_firestore`; replace `LocalStore` and demo role selection with repository/service implementations backed by Firebase Auth and Firestore. Resolve the authenticated user's role from a server-managed `users/{uid}` document; never trust a role supplied by the client.
4. Enable the required Firebase Auth provider, create users through a trusted admin flow, deploy `firestore.rules`, and create the needed indexes. Do not commit service-account keys or private credentials.
5. Model attendance using deterministic session IDs (`classId_subjectId_yyyyMMdd`) and records keyed by student ID beneath the session. Use a transaction/batch and server timestamps to reject duplicate sessions and validate edits. Compute percentages from sessions and records.
6. Replace the demo fixtures and static student subject percentages with actual assigned classes and query results. Add rules emulator tests for every role before deployment.

## Firestore collection proposal

- `users/{uid}`: `role`, `displayName`, `email`, `active`, timestamps.
- `students/{uid}`: `rollNumber`, `departmentId`, `semester`, `classId`.
- `faculty/{uid}`: `facultyId`, `departmentId`, `assignedClassIds`, `assignedSubjectIds`.
- `subjects/{subjectId}`: `name`, `code`, `departmentId`, `semester`.
- `classes/{classId}`: `name`, `departmentId`, `semester`, `studentIds`, `facultyIds`, `subjectIds`.
- `attendanceSessions/{sessionId}`: `classId`, `subjectId`, `date`, `facultyId`, timestamps, `locked`.
- `attendanceSessions/{sessionId}/records/{studentId}`: `studentId`, `subjectId`, `classId`, `date`, `status` (`present`, `absent`, `onDuty`), `facultyId`, `createdAt`, `updatedAt`.
- `notifications/{notificationId}`: `recipientId`, `title`, `body`, `read`, `createdAt`.

## Security

`firestore.rules` is a starting policy template, not deployed or production-certified. It assumes administrator role claims are assigned by a trusted server, and validates student ownership and faculty assignment. Adapt and emulator-test it against your actual data schema before deployment. The Android demo currently has no network backend.

## Verification and limitations

- No Firebase configuration is present in this workspace, so Firebase login, Firestore writes, push notifications, and cross-device reports are unavailable.
- Attendance history persistence currently stores saved summaries only; editable student statuses and demo accounts reset when the app process restarts.
- Student dashboard percentages are illustrative UI fixtures, not calculated from a live session ledger. Replace them with calculations from valid sessions and records before using real attendance.
- The admin directory is illustrative; its add action reports that the local demo directory is read-only.

## Demonstration test checklist

1. **Login validation:** leave email invalid or password shorter than four characters; the form should block sign-in. Then sign in with valid demo-shaped input.
2. **Role navigation:** select each role before sign-in and verify its overview and second navigation destination.
3. **Attendance entry:** as Faculty, open Attendance, change at least one student's status, use All present, and save. The saved summary should reflect the present count.
4. **Duplicate protection:** save twice for the same subject on the same date. The second save updates that date/subject summary instead of adding another history item.
5. **Persistence:** close and reopen the Android app, sign in again, and confirm the saved summary remains in History.
6. **Theme and logout:** switch appearance, sign out, and sign back in.
7. **Role security:** this build has no secure role authorization. Before Firebase integration, verify with Firebase Emulator rules tests that a student cannot read another student's records, faculty cannot edit unassigned classes, and only trusted admin claims can manage accounts.

The widget smoke test covers student login and dashboard rendering. `flutter analyze` completed successfully in the supplied workspace. The Flutter test and APK build commands did not return results in this tool session, so those outcomes remain unverified.

## Phase 4 — Live classroom attendance monitor

The server-side session lifecycle is implemented in `functions/src/attendance_sessions.ts`. `openAttendanceSession` checks the caller's faculty role and class/subject assignments, then creates one deterministic `attendanceSessions/{sessionId}` for the class, subject, and day. `sessionDurationMinutes` is read from `institutionSettings/default` (5–240 minutes; defaults to 60). `closeAttendanceSession` permits the owning faculty member or an admin and finalizes status counts. A scheduled function closes expired sessions every minute. Firestore client rules deny session creation and updates; attendance records use top-level deterministic IDs `attendanceRecords/{sessionId}_{studentId}` and writes require the owner faculty, assignment, open/unexpired session, and roster membership.

The Flutter monitor has pure models, a repository interface, a controller that disposes snapshot subscriptions, and a responsive screen with assignment selection, live count tiles, timer, search, status controls, mark-all, close confirmation, and error/offline states. It is wired to an in-memory sample repository in local demo mode; opening and marking a session works only within the running app process and does not synchronize across devices. This is not the Firebase-backed live monitor.

Phase 4 changed the attendance record path from the earlier nested proposal to top-level `attendanceRecords`; migrate any existing nested records before using real data. The existing notification trigger and indexes now use the top-level records. Add `sessionDurationMinutes` to the admin settings document and deploy updated rules/indexes/functions with `firebase deploy --only firestore:rules,firestore:indexes,functions`. The expiry query requires the status/expiry composite index included in `firestore/firestore.indexes.json`. Scheduled Functions and callable deployment require a configured Firebase project and billing-enabled plan.

Run `flutter test test/live_attendance_models_test.dart`, `flutter analyze`, `npm run test:rules`, and `npm run test:functions` after installing dependencies and starting emulators through the scripts. The Functions emulator suite includes a two-client snapshot synchronization check with a two-second bound. No Firebase emulator, FlutterFire configuration, or live project is available in this workspace, so cross-device sync and server rejection behavior remain unverified here.

## Advanced workflows and guardian access

Firestore rules now support student-owned OD/leave request creation and attendance dispute creation against the student's own deterministic record. Both collections are client read-only after submission; clients cannot approve requests, resolve disputes, or edit attendance. Cloud Functions in `functions/src/advanced_workflows.ts` validate reviewer claims and assignments, record review identity/reason/history, and send deduplicated in-app decision notifications. Dispute corrections run only through the trusted callable and append an audit entry to the record before changing its status.

Guardian links live at `guardianLinks/{guardianUid}/students/{studentUid}`. Guardian accounts require a trusted `guardian` role claim; clients cannot create or modify links. The guardian requests access, the student approves or rejects it, and either party can revoke an active link. Guardian reads of a linked student's profile and records require approved consent. Low-attendance alerts are also sent to approved linked guardians.

The Flutter demo now uses explicitly labeled, in-memory sample repositories for prediction, notifications, and live attendance. Advanced request submission, review decisions, and guardian consent are interactive local simulations; changes last for the current app process and do not modify Firestore or actual attendance. They are for classroom demonstration only. Firebase Auth/Firestore adapters, real guardian login, and evidence upload remain unconfigured/not implemented. The trusted Functions and rules remain available for a future Firebase integration; run `npm run test:rules` and `npm run test:functions` before any deployment.
## Firebase emulator foundations (Phase 1)

This repository currently has no Firebase project configuration, generated FlutterFire options, or connected Firebase backend. The emulator setup uses the reserved `demo-student-attendance` project ID and does not contact or deploy to a real project.

### Run the emulators and Firestore rules tests

1. Install Node.js 20 and Java 11 or newer.
2. From the project root run `npm install` to install the Firebase CLI, Firebase JS SDK, and rules test library.
3. Run `npm run test:rules`. This starts Auth, Firestore, and Storage emulators, runs `@firebase/rules-unit-testing`, then shuts the emulators down.
4. To start the full local suite interactively, run `npx firebase emulators:start`; open the Emulator UI at `http://127.0.0.1:4000`.
5. Install the Functions dependencies with `npm --prefix functions install`; run `npm --prefix functions run build` to type-check the minimal TypeScript entry point.

The `institutionSettings/default` document uses whole percentage points: `defaultAttendanceThreshold: 75`, `warningBuffer: 5`, and `countApprovedOdAsPresent: false`. Clients can read settings; only an admin custom claim can create/update a validated settings document. Client role writes are blocked in Firestore rules; role claims must be provisioned by trusted server code.

### Real project setup and deployment

After creating a Firebase project, run `firebase use --add` and replace the demo alias with your real project ID. Add platform apps with FlutterFire CLI when the Firebase integration phase begins. Deploy with `firebase deploy --only firestore:rules,firestore:indexes,storage` after reviewing rules against the real schema. Deploy server functions separately with `firebase deploy --only functions`; Functions deployment requires the Blaze plan. The demo alias and emulator configuration are not evidence of a configured production project.

## Phase 2 — Smart attendance predictor

The predictor is pure Dart and calculates every displayed value from session counts. Thresholds and warning buffers are percentage points in `InstitutionSettings`; the calculation layer converts them to fractions. Approved On Duty sessions count only when `countApprovedOdAsPresent` is enabled. For zero conducted sessions, current attendance is 0 and one attended future class is shown as the first meaningful recovery step (except a 100% threshold, which follows the specified not-recoverable rule).

The UI includes a projection control, a separate Historical attendance section, threshold selection restricted to 50–100, and loading/empty/error/offline states. The local dashboard now uses labeled sample session counts and computes predictions from those counts; it does not use a Firebase user, Firestore stream, or stored percentage. The sample threshold and records are in-memory demonstration values.

When Firebase is configured, provide an `AttendancePredictionRepository` that streams each student's raw session counts, the `institutionSettings/default` document, and `users/{uid}.personalAttendanceThreshold`. Each record must identify its subject, status, and session; approved OD count must reflect the actual approval state. Persist the student's threshold only to `users/{uid}.personalAttendanceThreshold`. The Firestore rule permits that field alone, only for the authenticated student's own profile, with an integer value from 50 through 100. It does not permit role changes.

Run the pure/widget tests with `flutter test`; run the Firestore rule tests with `npm run test:rules` after installing the root npm dependencies and starting the configured emulators. No live-stream update can be verified until a Firebase project and repository adapter are connected.

## Phase 3 — Smart notifications

Trusted Functions now expose `createNotification`, which uses Firestore `DocumentReference.create()` so duplicate dedupe keys become no-ops. The attendance record write trigger reads institutional and personal thresholds, recalculates subject attendance from raw records, applies the approved-OD policy, creates one daily low-attendance/warning notification per student and subject, and creates a correction notification when modification/audit version data changes. The correction and request/dispute/report notification types are supported by the shared helper; only attendance record writes are wired in this phase. The records collection-group query has a composite index.

Notification client rules permit recipients to read their own documents and only set `isRead` plus `readAt`; all client creates and deletes are denied, including admin clients. Admin SDK Functions bypass those client rules. The Flutter screen groups notifications by day, marks items read on tap, supports mark-all, and derives the dashboard badge from the repository stream. FCM is not enabled.

The Flutter demo uses labeled sample notifications in memory, and marking one or all read updates the current demo stream. These are not delivered by Cloud Functions and reset when the app process closes. The Functions and rule files are separate and are not connected to this demo. Approved OD is counted only when the attendance record carries `odApproved: true` and the institution setting enables it.

Install dependencies with `npm install` at the root and `npm --prefix functions install`. Run `npm run test:rules` and `npm run test:functions` against the emulators. Deploy the checked rules/indexes and Functions with `firebase deploy --only firestore:rules,firestore:indexes,functions` after selecting a real project. Functions deployment requires the Blaze plan. No FCM permission or token UI is included.

## Phase 3 — Smart notifications

Cloud Functions now contain a shared `createNotification` helper that uses Firestore `DocumentReference.create()` semantics. The attendance record write trigger counts the student's valid subject records, applies their personal or institution threshold and warning buffer, and creates at most one low-attendance warning per student/subject/UTC day. It emits a separate deterministic correction notification when trusted `modifiedAt`, `auditVersion`, or `audit` data changes. Future notification types are supported by the helper but no OD/leave, dispute, or report triggers are wired until those features exist.

Notifications are created only by Admin SDK code. Firestore rules allow recipients to read their own notifications and change only `isRead`/`readAt`; all client creates and deletes are denied. The same rules prevent clients from writing the server-only attendance fields `odApproved`, `modifiedAt`, `auditVersion`, and `audit`. The attendance aggregation query has a collection-group index.

The Flutter notification controller and screen support repository streams, unread counts, day grouping, mark-one/mark-all actions, and loading/empty/error/offline states. In the app, it uses sample notifications from the in-memory demo repository, and the dashboard bell reflects the unread sample count. Firebase notifications and FCM are not connected. The UI exposes an optional related-screen callback; no notification destination screen is wired because this local demo has no matching detail routes.

To run emulator checks after installing dependencies, use `npm install`, `npm --prefix functions install`, `npm run test:rules`, and `npm run test:functions`. The latter builds TypeScript and starts Firestore and Functions emulators; it verifies the helper's create-once behavior and a low-attendance trigger dedupe flow. Select a real project only for deployment, then run `firebase deploy --only firestore:rules,firestore:indexes,functions`. Functions deployment requires Blaze. These emulator checks have not run in this workspace because the Firebase CLI and npm dependencies are not installed.
