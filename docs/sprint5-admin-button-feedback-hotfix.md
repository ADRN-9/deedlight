# Deedlight Sprint 5 Admin Button Feedback Hotfix

This hotfix adds visible click/pending feedback for admin moderation buttons so the admin can tell that actions were submitted.

## 1. Add the new component

Copy:

```text
components/ui/pending-submit-button.tsx
```

into your project.

## 2. Update `app/admin/offerings/[id]/page.tsx`

Add this import near the top:

```tsx
import { PendingSubmitButton } from "@/components/ui/pending-submit-button";
```

Then replace admin action submit buttons inside their forms.

### Approve saved version

Before:

```tsx
<button type="submit" className="...">
  Approve saved version
</button>
```

After:

```tsx
<PendingSubmitButton className="..." pendingText="Approving..." clickedText="Approving...">
  Approve saved version
</PendingSubmitButton>
```

### Request edit

```tsx
<PendingSubmitButton className="..." pendingText="Sending request..." clickedText="Requesting edit...">
  Request edit
</PendingSubmitButton>
```

### Reject

```tsx
<PendingSubmitButton className="..." pendingText="Rejecting..." clickedText="Rejecting...">
  Reject
</PendingSubmitButton>
```

### Hide saved Offering from public

```tsx
<PendingSubmitButton className="..." pendingText="Hiding..." clickedText="Hiding...">
  Hide saved Offering from public
</PendingSubmitButton>
```

### Save edits only

```tsx
<PendingSubmitButton className="..." pendingText="Saving edits..." clickedText="Saving...">
  Save edits only
</PendingSubmitButton>
```

### Save edits and keep public / publish

```tsx
<PendingSubmitButton className="..." pendingText="Saving and publishing..." clickedText="Publishing...">
  Save edits and keep public
</PendingSubmitButton>
```

## 3. Commit and push

```bash
git add components/ui/pending-submit-button.tsx app/admin/offerings/[id]/page.tsx
git commit -m "Add admin moderation button feedback"
git push
```

## Expected result

When you click an admin action button:

- the button briefly changes text immediately;
- during submit, it shows a spinner and action-specific text;
- the button is disabled while submitting;
- the button gets an active press effect;
- after redirect, the URL/status banner confirms the action.
