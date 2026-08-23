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
- A persisted GitHub connection flow with encrypted renewable OAuth credentials
- Provider-independent external identities plus GitHub connection and daily-contribution tables
- Manual GitHub contribution-calendar synchronization with authoritative daily upserts
- Automatic encrypted GitHub credential rotation before synchronization
- An authenticated homepage heatmap rendered from saved GitHub daily totals
- Automated controller, model, job, mailer, and service tests

The GitHub connection flow saves identity and encrypted credentials. Before synchronization, Gridfolio reuses a valid access token or atomically exchanges the refresh token for a new encrypted credential pair. A manually invoked synchronization service persists official daily totals from the connection date forward, and the homepage renders those cached records. Background jobs, automatic sync triggers, and manual browser synchronization remain later checkpoints.

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
