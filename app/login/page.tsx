import { LoginForm } from "./login-form";

export const dynamic = "force-dynamic";

export default function LoginPage() {
  return (
    <section className="mx-auto max-w-md px-4 py-16 sm:px-6">
      <LoginForm />
    </section>
  );
}
