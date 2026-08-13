"use client";

import { useFormStatus } from "react-dom";

export function PendingActionButton({
  idleLabel,
  pendingLabel,
  className,
  disabled = false,
}: {
  idleLabel: string;
  pendingLabel: string;
  className: string;
  disabled?: boolean;
}) {
  const { pending } = useFormStatus();

  return (
    <button
      type="submit"
      disabled={disabled || pending}
      aria-disabled={disabled || pending}
      className={className}
    >
      {pending ? pendingLabel : idleLabel}
    </button>
  );
}
