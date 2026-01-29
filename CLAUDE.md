## Constraints when making plans 
Do:

Consider performance such as roundtrips, N+1 anti patterns, covering indexes.
Handle security such as proper API secret handling, rate limiting, input validation
Consider impact of change on the existing architecture, does it fit?
Handle logging & tracing for prod debugging purposes, ideally using an OpenTelemetry provider like Sentry.io
Pause and propose options if you encounter any of these:

Adding a new runtime dependency
Changing a public API / exported interface
Schema migrations / irreversible data changes
Broad refactors across unrelated modules
Any uncertainty that you think could cause the wrong architecture choice. 

Do not:

Perform unsolicited unrelated refactors (no renames, reorganizing, style-only changes, “cleanup” drive-bys).
Write "thinking out loud" code comments for obvious or self-explanatory code. Treat comments as a way to explain things you guess might be confusing to future readers.
Leave TODOs or examples in your diffs. Only write production ready finished implementations.
