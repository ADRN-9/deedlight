# Sprint 10.3A interaction feedback hotfix

This hotfix makes click acknowledgement consistent across Deedlight before
Sprint 10.3A is committed.

## Interaction contract

- Every button/link receives immediate pressed feedback.
- Form submitters enter a visible pending state and ignore duplicate submits
  until the UI changes, navigation completes, or a 30 second safety timeout
  expires.
- Same-origin navigation links receive a pending state while the next view is
  loading.
- Existing component-specific pending states remain valid and are not removed.
- Keyboard activation receives the same short pressed feedback as pointer use.

## Reminder clarification

The reminder setting is an opt-in preference. Saving a time does not enable it.
The setting now has a large, persistent ON/OFF badge and the success message
explicitly says whether the preference was enabled or left off.

Sprint 10.3A still does not deliver email or push reminders. Delivery transport
is intentionally deferred to the next infrastructure step.
