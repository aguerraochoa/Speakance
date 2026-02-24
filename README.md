# Speakance iOS App (SwiftUI Skeleton)

This folder contains a SwiftUI v1 foundation with:

- Core tab navigation
- Voice-first capture screen (mocked capture flow)
- Review/edit sheet
- Expense feed
- Insights
- Settings
- Offline queue state model + mock sync behavior

## Generate Xcode Project

This repo uses an `XcodeGen` spec to avoid hand-editing `.xcodeproj` files.

1. Install XcodeGen (example: `brew install xcodegen`)
2. From this folder, run `xcodegen generate`
3. Open `Speakance.xcodeproj` in Xcode

## What Is Mocked Right Now

- Audio recording service (UI state only)
- Network monitor (manual toggle in Settings)
- Backend API parsing/saving (mock client)

The code is structured so you can replace the mocks with real Supabase/OpenAI integrations.

