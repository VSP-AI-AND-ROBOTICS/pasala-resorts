# Subscription auto-billing (Razorpay)

ResortHub can charge each resort's plan (Starter, Pro, Enterprise) monthly
through Razorpay Subscriptions. Until the steps below are done, nothing
changes: the platform admin keeps setting plans and paid-until dates by
hand on the platform console, and owners see no payment button.

Design: `docs/superpowers/specs/2026-09-25-p8-subscription-auto-billing-design.md`.

## 1. Create the plans in Razorpay

In the Razorpay Dashboard (Subscriptions → Plans), create one plan per
tier you want to bill online:

- Billing frequency: every 1 month.
- Amount: the same monthly price as the console's **Plan prices** dialog
  (MRR on the console uses the console's price, not Razorpay's).

Copy each plan's id (`plan_…`).

## 2. Paste the plan ids

On the platform console, open **Plan prices** and fill in
"<Plan> Razorpay plan id" for each tier. Leave a tier blank to keep it
billed by hand.

## 3. Set the secrets

```bash
supabase secrets set \
  RAZORPAY_KEY_ID=rzp_live_xxxxxxxx \
  RAZORPAY_KEY_SECRET=xxxxxxxxxxxxxxxx \
  RAZORPAY_BILLING_WEBHOOK_SECRET=choose-a-long-random-string
```

If you already set `RAZORPAY_WEBHOOK_SECRET` for online booking payments
(P6), you can reuse it: the billing webhook falls back to it when
`RAZORPAY_BILLING_WEBHOOK_SECRET` is unset. Never put these values in the
app, in the database or in git.

## 4. Deploy the functions

```bash
supabase functions deploy billing-subscribe
supabase functions deploy billing-webhook
```

## 5. Add the webhook in Razorpay

Razorpay Dashboard → Settings → Webhooks → Add:

- URL: `https://<project-ref>.supabase.co/functions/v1/billing-webhook`
- Secret: the value of `RAZORPAY_BILLING_WEBHOOK_SECRET`
- Events: `subscription.authenticated`, `subscription.activated`,
  `subscription.charged`, `subscription.pending`, `subscription.halted`,
  `subscription.cancelled`, `subscription.completed`,
  `subscription.paused`, `subscription.resumed`, `subscription.updated`.

## What happens then

- The owner sees **Auto-pay** under their plan in Settings, picks a plan,
  and authorises auto-pay on Razorpay's page. The first charge is on the
  day after their current trial or paid period ends (or at once if there
  is none).
- Every successful charge moves the plan's paid-until date to the end of
  the charged month and records a payment the owner sees in the sheet;
  the console shows "Auto-pay: On · Last payment …".
- If Razorpay gives up after failed retries, the plan shows Lapsed (it
  still locks nothing). Cancelling auto-pay keeps the plan paid until the
  end of the period.
- The platform admin can still change any plan by hand; the next Razorpay
  event applies on top.

## Checking it without a real account

The automated tests never call Razorpay. To try the webhook locally,
see Task 10 of `docs/superpowers/plans/2026-09-25-p8-subscription-auto-billing.md`
(a signed fixture event posted to `supabase functions serve`).
