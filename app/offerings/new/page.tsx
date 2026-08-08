import Link from "next/link";
import { CreateOfferingForm } from "@/components/offerings/create-offering-form";
import { createClient } from "@/lib/supabase/server";

export const dynamic = "force-dynamic";

async function getCurrentUserContext() {
  try {
    const supabase = await createClient({ allowMissingEnv: true });
    if (!supabase) return null;

    const { data, error } = await supabase.auth.getUser();
    if (error || !data.user) return null;

    const { data: profile } = await supabase
      .from("profiles")
      .select("default_offering_anonymous")
      .eq("user_id", data.user.id)
      .maybeSingle();

    return {
      defaultAnonymous: profile?.default_offering_anonymous === true,
    };
  } catch (error) {
    console.error("Offerings new auth check failed", error);
    return null;
  }
}

function SignInPrompt() {
  return (
    <main className="mx-auto max-w-5xl px-6 py-16">
      <section className="mx-auto max-w-2xl rounded-[28px] border border-[#ead7ad] bg-white/90 p-10 text-center shadow-[0_24px_70px_rgba(38,35,31,0.10)]">
        <p className="text-xs font-bold uppercase tracking-[0.35em] text-[#9a6a10]">Share an Offering</p>
        <h1 className="mt-4 text-4xl font-bold tracking-tight text-[#26231F]">Sign in to prepare a light.</h1>
        <p className="mt-4 text-[#7C715F]">
          Offerings are connected to your Goodness Journey and reviewed before they become public, so please sign in first.
        </p>
        <div className="mt-8 flex flex-wrap justify-center gap-3">
          <Link href="/login" className="rounded-full bg-[#D9A441] px-7 py-3 font-bold text-[#26231F] shadow-[0_12px_28px_rgba(217,164,65,0.28)]">
            Sign in
          </Link>
          <Link href="/signup" className="rounded-full border border-[#ead7ad] bg-white px-7 py-3 font-bold text-[#26231F]">
            Join Deedlight
          </Link>
        </div>
      </section>
    </main>
  );
}

export default async function NewOfferingPage() {
  const context = await getCurrentUserContext();

  if (!context) {
    return <SignInPrompt />;
  }

  return (
    <main className="mx-auto max-w-5xl px-6 py-10">
      <CreateOfferingForm
        defaultAnonymous={context.defaultAnonymous}
      />
    </main>
  );
}
