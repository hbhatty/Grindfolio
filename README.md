# Grindfolio

Grindfolio is an early Rails application for tracking developer consistency across building, practicing, and applying.

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
- User-triggered GitHub contribution-calendar synchronization through a provider-specific background job
- Automatic encrypted GitHub credential rotation before synchronization
- An authenticated homepage with focused in-place synchronization feedback and a heatmap rendered from saved GitHub daily totals
- Automated controller, model, job, mailer, and service tests

The GitHub connection flow saves identity and encrypted credentials. Before synchronization, Grindfolio reuses a valid access token or atomically exchanges the refresh token for a new encrypted credential pair. The dashboard's **Update activity** action records a durable request and enqueues provider work; focused Turbo updates render progress, cached results, retryable failure, or required reauthorization without holding the browser request open.

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
