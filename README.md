# face-recovery

Generates a daily recovery score from sleep using a face scan.

## Project scope

This project includes:

1. **Native iOS app** for taking a morning face photo and testing recovery scoring on-device.
2. **Training/data pipeline work** (same repository) to pair user photos with WHOOP recovery data for experimentation.
3. **Prompt-first image LLM scoring** as the initial baseline before iterative tuning.

## Local setup

1. Copy `.env.example` to `.env`.
2. Fill in all required values in `.env`.
3. Keep `.env` local only (it is ignored by git).

## Environment variables

See `.env.example` for all required config and secrets:

- WHOOP API OAuth credentials and endpoint
- LLM provider/model/API credentials
- App environment and local dataset/reporting paths

## Reporting notes

Use `notes/report-notes.md` during implementation and experiments.  
Add notes for each stage so they can be reused in the academic report.

## Needs Attention

You need to provide or complete:

1. **WHOOP developer credentials**
   - `WHOOP_CLIENT_ID`
   - `WHOOP_CLIENT_SECRET`
   - Confirm `WHOOP_REDIRECT_URI` that your app will use
2. **LLM credentials**
   - `LLM_API_KEY`
   - Confirm provider/model values (`LLM_PROVIDER`, `LLM_MODEL`)
3. **iOS app identifiers**
   - `IOS_BUNDLE_ID`
4. **Local paths**
   - Confirm where photos should be stored (`PHOTO_STORAGE_DIR`)
   - Confirm where paired dataset artifacts should be written (`DATASET_OUTPUT_DIR`)
5. **Manual data preparation**
   - Upload/select historical face photos you want to use for initial personal training data
   - Ensure each photo can be associated with a WHOOP recovery value for dataset pairing
6. **Device testing**
   - Build and run the app on your iPhone from Xcode on your Mac
