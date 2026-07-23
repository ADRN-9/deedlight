import { SignupForm } from "./signup-form";

export default async function SignupPage({
  searchParams
}: {
  searchParams: Promise<{ error?: string; message?: string }>;
}) {
  const params = await searchParams;

  return (
    <section className="mx-auto max-w-md px-4 py-16 sm:px-6">
      <SignupForm initialError={params.error} initialMessage={params.message} />
    </section>
  );
}
