import { SignupForm } from "./signup-form";

export const dynamic = "force-dynamic";

export default function SignupPage() {
  return (
    <section className="mx-auto max-w-md px-4 py-16 sm:px-6">
      <SignupForm />
    </section>
  );
}
