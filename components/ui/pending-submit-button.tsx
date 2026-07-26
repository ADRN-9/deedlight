"use client";

import * as React from "react";
import { useFormStatus } from "react-dom";

type PendingSubmitButtonProps = React.ButtonHTMLAttributes<HTMLButtonElement> & {
  pendingText?: string;
  clickedText?: string;
};

export function PendingSubmitButton({
  children,
  pendingText = "Saving...",
  clickedText = "Clicked...",
  className = "",
  disabled,
  onClick,
  ...props
}: PendingSubmitButtonProps) {
  const { pending } = useFormStatus();
  const [clicked, setClicked] = React.useState(false);

  React.useEffect(() => {
    if (!clicked || pending) return;

    const timer = window.setTimeout(() => setClicked(false), 900);
    return () => window.clearTimeout(timer);
  }, [clicked, pending]);

  const isDisabled = Boolean(disabled || pending);

  return (
    <button
      {...props}
      type={props.type ?? "submit"}
      disabled={isDisabled}
      aria-busy={pending}
      data-clicked={clicked ? "true" : "false"}
      onClick={(event) => {
        setClicked(true);
        onClick?.(event);
      }}
      className={[
        className,
        "relative inline-flex items-center justify-center gap-2 transition duration-150 ease-out",
        "active:translate-y-0.5 active:scale-[0.985]",
        "focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-amber-400 focus-visible:ring-offset-2",
        isDisabled ? "cursor-wait opacity-75" : "cursor-pointer",
        clicked && !pending ? "ring-2 ring-amber-300 ring-offset-2" : "",
      ]
        .filter(Boolean)
        .join(" ")}
    >
      {pending ? (
        <>
          <span
            aria-hidden="true"
            className="h-4 w-4 animate-spin rounded-full border-2 border-current border-t-transparent"
          />
          <span>{pendingText}</span>
        </>
      ) : clicked ? (
        <span>{clickedText}</span>
      ) : (
        children
      )}
    </button>
  );
}
