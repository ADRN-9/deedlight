# Deedlight Supabase Auth Email Templates

Use these templates in Supabase Dashboard → Authentication → Emails.

For testing, editing the templates is enough. For production, also configure Custom SMTP so the sender appears as `Deedlight <hello@deedlight.com>` instead of the default Supabase sender.

Recommended custom SMTP sender settings:

- Sender name: Deedlight
- Sender email: hello@deedlight.com
- Reply-to: hello@deedlight.com

Important Supabase variables used here:

- `{{ .ConfirmationURL }}` — the confirmation/action link
- `{{ .Email }}` — recipient email
- `{{ .SiteURL }}` — your configured Site URL

## Confirm signup

Subject:

```text
Confirm your Deedlight account
```

HTML: use `confirm-signup.html`.

## Magic link

Subject:

```text
Your Deedlight sign-in link
```

HTML: use `magic-link.html`.

## Reset password

Subject:

```text
Reset your Deedlight password
```

HTML: use `reset-password.html`.

## Change email

Subject:

```text
Confirm your Deedlight email change
```

HTML: use `change-email.html`.
