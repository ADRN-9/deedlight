"use client";

import type { ReactNode } from "react";
import { useFormStatus } from "react-dom";

type PendingOwnerActionButtonProps = {
  children: ReactNode;
  pendingText: string;
  className?: string;
  confirmMessage?: string;
};

export function PendingOwnerActionButton({
  children,
  pendingText,
  className = "",
  confirmMessage,
}: PendingOwnerActionButtonProps) {
  const { pending } = useFormStatus();

  return (
    <button
      type="submit"
      disabled={pending}
      aria-disabled={pending}
      aria-busy={pending}
      className={className}
      onClick={(event) => {
        if (
          !pending &&
          confirmMessage &&
          typeof window !== "undefined" &&
          !window.confirm(confirmMessage)
        ) {
          event.preventDefault();
        }
      }}
    >
      {pending ? pendingText : children}
    </button>
  );
}
