# Integrating with Stripe

Pay automatically checks environment variables for API keys:

To enable Stripe subscriptions

1) Add `STRIPE_PUBLIC_KEY` and `STRIPE_PRIVATE_KEY` secrets using your Stripe API keys.

2) `STRIPE_SIGNING_SECRET` after setting up a webhook to `<YOUR_APP_URL>/webhooks/stripe`

### NOTE:

* The "Update Payment Method" button will not work when your app is embedded in an iframe — open your app in its own tab instead.