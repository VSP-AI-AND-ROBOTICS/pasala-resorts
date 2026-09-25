.PHONY: db-reset db-test test functions-test run-web run-android run-ios

ANON_KEY ?= $(shell supabase status -o env 2>/dev/null | grep ANON_KEY | cut -d= -f2 | tr -d '"')

db-reset:
	supabase db reset

db-test:
	supabase test db

test:
	flutter test

functions-test:
	deno test supabase/functions/

run-web:
	flutter run -d chrome --dart-define=SUPABASE_URL=http://127.0.0.1:54321 --dart-define=SUPABASE_ANON_KEY=$(ANON_KEY)

run-android:
	flutter run -d emulator --dart-define=SUPABASE_URL=http://10.0.2.2:54321 --dart-define=SUPABASE_ANON_KEY=$(ANON_KEY)

run-ios:
	flutter run -d iPhone --dart-define=SUPABASE_URL=http://127.0.0.1:54321 --dart-define=SUPABASE_ANON_KEY=$(ANON_KEY)
