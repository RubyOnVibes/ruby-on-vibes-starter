# Sending Transactional Emails

By default, mounted vibes apps use [mailbin](https://github.com/excid3/mailbin) to simulate sending emails.

You may send real emails by setting up a provider and verifying a custom domain.

## Resend

[Resend](https://resend.com/pricing) is one of the simpler email providers to use.

To enable Resend, sign up, verify your domain, and add a valid `RESEND_API_KEY` secret to your app.

Other providers may be used used instead, if desired.