#!/usr/bin/env bash
# Builds the Flutter web app for the Playwright suite into ../build/web.
#
# E2E=true turns the semantics tree on at startup (lib/core/e2e_semantics.dart)
# so Flutter web renders the flt-semantics DOM Playwright drives; a normal
# build leaves it off. The Supabase URL and key point at the local stack
# (`supabase start`); the key is the standard public local-dev anon key, and
# both can be overridden from the environment.
set -euo pipefail

SUPABASE_URL="${SUPABASE_URL:-http://127.0.0.1:54321}"
SUPABASE_ANON_KEY="${SUPABASE_ANON_KEY:-eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0}"

cd "$(dirname "$0")/.."
flutter build web --release \
  --dart-define=E2E=true \
  --dart-define=SUPABASE_URL="$SUPABASE_URL" \
  --dart-define=SUPABASE_ANON_KEY="$SUPABASE_ANON_KEY"
