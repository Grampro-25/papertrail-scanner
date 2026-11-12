# Papertrail document scanner

The original scanner-only Android app, version 1.0.0.

## Features
- Capture pages using the phone camera or import photos.
- Crop and rotate images, with original, clean, grayscale, and black-and-white filters.
- Create multipage scanned documents and reorder or remove pages.
- Rename, search, star, and organize scans into Personal, Work, and Receipts categories.
- Generate and share multipage PDF files from scanned images.
- Store scans privately on the device without an account.

This repository contains the first version only. The later PDF reader, PDF importing, annotations, signatures, OCR, and Word-export features are not included. No APKs or other packaged app releases are included.

## Requirements
- Flutter 3.35.7 and Dart 3.9.2 or a compatible SDK
- JDK 17
- Android SDK 36 and NDK 27.0.12077973
- Android 7.0 or later for the app

## Run and test
```sh
flutter pub get
flutter analyze
flutter test
flutter run
```

To build locally, run `flutter build apk --debug`. Build output is ignored by Git. Configure your own release signing key before publishing to Google Play. No signing keys are included.

## Storage
Scans are stored in the app's private files. Export important documents before uninstalling, which removes the library. PDF exports are flattened page images; this is a scanner, not a general PDF editor.

## Source
`lib/main.dart` contains the original scanner UI, document storage, page management, and filters. `android/app/src/main/kotlin/com/papertrail/papertrail/MainActivity.kt` creates multipage PDFs using Android's PdfDocument API. Tests cover metadata persistence, ordered rapid saves, cropping/rotation, grayscale output, and import resizing.
