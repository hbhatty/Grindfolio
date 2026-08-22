# Gridfolio

Gridfolio is an early Rails application for tracking developer consistency across building, practicing, and applying.

## Included in this checkpoint

- Rails 8.1 with PostgreSQL, Hotwire, and Solid Queue
- Regular email/password signup with bcrypt
- Email verification and verification-email resend
- Database-backed login sessions and logout
- Session expiration and activity refresh
- Cleanup of registrations that remain unverified for seven days
- A protected account page with IANA time-zone selection
- A development-only, read-only GitHub authorization and contribution-calendar probe
- Provider-independent external identities plus GitHub connection-metadata and daily-contribution tables
- Automated controller, model, job, mailer, and service tests

The GitHub probe confirms that authorization and daily contribution retrieval work, but it does not save GitHub tokens or activity. The database structure now exists, while OAuth token storage, functional GitHub connections, synchronization jobs, and the heatmap remain later checkpoints.

## Local development

From Ubuntu under WSL:

```bash
mise install
bin/setup
bin/rails server
```

Run the project checks with:

```bash
bin/rails test
bin/rubocop
bin/rails zeitwerk:check
bundle exec brakeman -q
```
