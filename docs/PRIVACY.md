# Privacy and notifications

Codex Pace Bar is local-first. The main pace bar, usage history, Task Monitor database, hook event file, and hook configuration stay on this Mac unless the user explicitly enables phone notifications.

## Local data

The app reads rate-limit information through the local Codex app-server and stores only the data needed for the pace bar and Task Monitor: timestamps, usage percentages, reset metadata, task status, project directory metadata, model/effort labels, and notification deduplication keys. Usage history is retained for 30 days and protected with owner-only file permissions. Task activity can be deleted from the Task Monitor UI.

## Optional ntfy delivery

Phone notifications are disabled by default and use a user-generated private ntfy topic. When enabled, the app sends generic task-ready or approval-needed status to that topic. It never sends prompts, responses, source code, terminal output, or full filesystem paths.

The separate **Phone notification details** setting is an explicit second opt-in. Only with that setting enabled may the notification include the last path component as a project name and the task duration. The project name is sanitized and truncated before transmission.

The ntfy request has a 10-second timeout, bounded retries, exponential backoff, cancellation handling, and persistent delivery keys to avoid duplicate alerts. Treat the topic like a password and regenerate it if it is exposed.

## Hook safety

When Task Monitor is enabled, Pace Bar adds only its own marked hook handlers. Before writing, it compares the configuration snapshot with the current file, saves a `.codex-pace-bar-backup` copy, and refuses to overwrite a file changed by another process.
