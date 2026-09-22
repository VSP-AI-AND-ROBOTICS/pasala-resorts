/// Non-web fallback: there is no filesystem this app can safely write a
/// user-facing file to without another package. Returns `false` so the
/// caller can tell the user honestly, rather than pretending to succeed.
bool downloadCsv(String filename, String csv) => false;
