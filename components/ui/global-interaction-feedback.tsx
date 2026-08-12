"use client";

import { useEffect } from "react";

const INTERACTIVE_SELECTOR = [
  "button",
  "a[href]",
  'input[type="submit"]',
  'input[type="button"]',
  '[role="button"]',
].join(",");

function closestInteractive(target: EventTarget | null) {
  if (!(target instanceof Element)) return null;

  const element = target.closest(INTERACTIVE_SELECTOR);
  return element instanceof HTMLElement ? element : null;
}

function isUnavailable(element: HTMLElement) {
  return (
    element.matches(":disabled") ||
    element.getAttribute("aria-disabled") === "true"
  );
}

function shouldTrackLink(element: HTMLElement) {
  if (!(element instanceof HTMLAnchorElement)) return false;
  if (element.target === "_blank" || element.hasAttribute("download")) {
    return false;
  }

  const href = element.getAttribute("href");
  if (!href || href.startsWith("#")) return false;

  try {
    const target = new URL(element.href, window.location.href);
    return (
      target.origin === window.location.origin &&
      target.href !== window.location.href
    );
  } catch {
    return false;
  }
}

export function GlobalInteractionFeedback() {
  useEffect(() => {
    let pendingElement: HTMLElement | null = null;
    let pendingForm: HTMLFormElement | null = null;
    let observer: MutationObserver | null = null;
    let timeoutId: number | null = null;

    const clearPending = () => {
      observer?.disconnect();
      observer = null;

      if (timeoutId !== null) {
        window.clearTimeout(timeoutId);
        timeoutId = null;
      }

      if (pendingElement) {
        delete pendingElement.dataset.deedPending;
        pendingElement.removeAttribute("aria-busy");
      }

      if (pendingForm) {
        delete pendingForm.dataset.deedSubmitting;
        pendingForm.removeAttribute("aria-busy");
      }

      pendingElement = null;
      pendingForm = null;
    };

    const watchForResult = () => {
      observer?.disconnect();

      observer = new MutationObserver((records) => {
        const meaningfulChange = records.some((record) => {
          if (record.type !== "attributes") return true;

          const attributeName = record.attributeName ?? "";
          const target = record.target;

          if (
            target === pendingElement &&
            (attributeName === "data-deed-pending" ||
              attributeName === "aria-busy")
          ) {
            return false;
          }

          if (
            target === pendingForm &&
            (attributeName === "data-deed-submitting" ||
              attributeName === "aria-busy")
          ) {
            return false;
          }

          return true;
        });

        if (meaningfulChange) {
          window.requestAnimationFrame(clearPending);
        }
      });

      observer.observe(document.body, {
        attributes: true,
        characterData: true,
        childList: true,
        subtree: true,
      });
    };

    const markPending = (
      element: HTMLElement,
      form: HTMLFormElement | null = null,
    ) => {
      clearPending();

      pendingElement = element;
      pendingForm = form;

      element.dataset.deedPending = "true";
      element.setAttribute("aria-busy", "true");

      if (form) {
        form.dataset.deedSubmitting = "true";
        form.setAttribute("aria-busy", "true");
      }

      watchForResult();

      timeoutId = window.setTimeout(clearPending, 30_000);
    };

    const showPressedState = (element: HTMLElement) => {
      if (isUnavailable(element)) return;

      element.dataset.deedPressed = "true";

      window.setTimeout(() => {
        delete element.dataset.deedPressed;
      }, 180);
    };

    const onPointerDown = (event: PointerEvent) => {
      const element = closestInteractive(event.target);
      if (element) showPressedState(element);
    };

    const onKeyDown = (event: KeyboardEvent) => {
      if (event.key !== "Enter" && event.key !== " ") return;

      const element = closestInteractive(event.target);
      if (element) showPressedState(element);
    };

    const onClick = (event: MouseEvent) => {
      const element = closestInteractive(event.target);
      if (!element || isUnavailable(element)) return;

      if (element.dataset.deedPending === "true") {
        event.preventDefault();
        event.stopPropagation();
        return;
      }

      if (shouldTrackLink(element)) {
        markPending(element);
      }
    };

    const onSubmit = (event: SubmitEvent) => {
      if (!(event.target instanceof HTMLFormElement)) return;

      const form = event.target;

      if (form.dataset.deedSubmitting === "true") {
        event.preventDefault();
        event.stopPropagation();
        return;
      }

      const submitter = event.submitter;
      if (!(submitter instanceof HTMLElement)) return;
      if (isUnavailable(submitter)) return;

      markPending(submitter, form);
    };

    document.addEventListener("pointerdown", onPointerDown, true);
    document.addEventListener("keydown", onKeyDown, true);
    document.addEventListener("click", onClick, true);
    document.addEventListener("submit", onSubmit, true);
    window.addEventListener("pageshow", clearPending);
    window.addEventListener("popstate", clearPending);

    return () => {
      clearPending();
      document.removeEventListener("pointerdown", onPointerDown, true);
      document.removeEventListener("keydown", onKeyDown, true);
      document.removeEventListener("click", onClick, true);
      document.removeEventListener("submit", onSubmit, true);
      window.removeEventListener("pageshow", clearPending);
      window.removeEventListener("popstate", clearPending);
    };
  }, []);

  return null;
}
