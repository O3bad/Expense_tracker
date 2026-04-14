# Spendly — Expense Tracker App

A Flutter mobile app for tracking personal expenses with Firebase authentication and cloud storage.

---

## Overview

Spendly is a clean, minimalist expense tracker that lets users log, categorize, edit, and delete their spending. Each user's expenses are stored privately in Cloud Firestore under their own account, so data is secure and synced across devices.

---

## Features

- **Authentication** — Email/password sign-up and login with Firebase Auth, with animated transitions and inline validation
- **Expense Management** — Add, edit, and delete expenses with title, amount, date, category, and notes
- **Categories** — 7 built-in categories: General, Grocery, Car Repairs, Gym Requirements, Entertainment, Utilities, Healthcare — each with a distinct color
- **Cloud Sync** — Expenses are stored in Firestore per user (`users/{uid}/expenses`) with real-time updates; `date` is stored as a Firestore `Timestamp` for correct ordering and queries
- **Splash Screen** — Branded gradient splash with Flutter animations (scale, fade, slide)
- **Insights** — Bar chart of this month’s spending by category (`fl_chart`)
- **Search** — Filter the list by title or notes
- **Export** — Share expenses as CSV (`csv` + `share_plus`)
- **Monthly budget** — Optional budget on the user profile with a progress bar on the header card (tap the card to set or clear)
- **Dark mode** — Light and dark themes following system setting (`ThemeMode.system`)
- **Portrait Lock** — Fixed portrait orientation for a consistent UI

---

## Tech Stack

| Layer | Technology |
|---|---|
| Framework | Flutter (Dart SDK ≥ 3.10.7) |
| Auth | Firebase Auth |
| Database | Cloud Firestore |
| Charts | fl_chart |
| Export | csv, share_plus |
| Fonts | google_fonts (Nunito) |

---

## Project Structure

```
lib/
├── main.dart                  # App entry, Firebase init, MaterialApp
├── firebase_options.dart      # Firebase config
├── theme/
│   └── app_theme.dart         # Light & dark themes, color tokens
├── auth/
│   ├── auth_gate.dart         # Auth stream → Expenses or login
│   └── auth_screen.dart       # Login & sign-up screen
├── models/
│   └── expense_model.dart     # Expense model (DateTime + Firestore Timestamp)
├── screens/
│   ├── splash_screen.dart     # Animated splash → AuthGate
│   ├── expense_screen.dart    # Main list, search, insights, export
│   └── add_edit_expense_screen.dart
└── services/
    ├── api_handler.dart       # Abstract API interface
    └── firestore_db.dart      # Firestore implementation
```

---

## Getting Started

### Prerequisites

- Flutter SDK ≥ 3.10.7
- A Firebase project with **Authentication** (Email/Password) and **Cloud Firestore** enabled

### Setup

1. **Clone the repository**
   ```bash
   git clone <repo-url>
   cd expense_tracker
   ```

2. **Install dependencies**
   ```bash
   flutter pub get
   ```

3. **Configure Firebase**
   - Create a Firebase project at [console.firebase.google.com](https://console.firebase.google.com)
   - Enable Email/Password authentication
   - Enable Cloud Firestore
   - Run `flutterfire configure` to generate `lib/firebase_options.dart`

4. **Deploy security rules**
   - Use `firestore.rules` in this repo (users can only read/write their own `users/{uid}` document and `users/{uid}/expenses` subcollection).
   - Deploy with the Firebase CLI: `firebase deploy --only firestore:rules`

5. **Run the app**
   ```bash
   flutter run
   ```

---

## Data Model

```dart
Expense {
  id?       : String   // Firestore document ID
  title     : String
  amount    : double
  date      : DateTime // Stored in Firestore as Timestamp (legacy ISO strings still read)
  category  : String
  notes     : String
}
```

User profile (`users/{uid}`) may include:

- `monthlyBudget` — optional number used for the header progress bar

Firestore path: `users/{uid}/expenses/{expenseId}`

---

## App Theme

The app uses `AppTheme` in `lib/theme/app_theme.dart` with Material 3:

| Token | Light | Notes |
|---|---|---|
| Primary | `#6C63FF` | Purple |
| Secondary | `#03DAC6` | Teal |
| Surface | `#F8F7FF` | Light lavender |
| Dark surface | `#121218` | Dark mode scaffold |

Font: Nunito (via google_fonts).
