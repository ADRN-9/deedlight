"use client";

import { useEffect, useState } from "react";
import { createClient } from "@/lib/supabase/client";

function readableError(error: unknown) {
  if (error instanceof Error) return error.message;
  if (typeof error === "string") return error;
  try {
    return JSON.stringify(error, null, 2);
  } catch {
    return "Unknown error";
  }
}

export default function AuthDebugPage() {
  const [result, setResult] = useState<Record<string, unknown>>({ loading: true });

  useEffect(() => {
    async function run() {
      try {
        const url = process.env.NEXT_PUBLIC_SUPABASE_URL;
        const key = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY;
        const supabase = createClient();
        const { data, error } = await supabase.auth.getSession();

        setResult({
          ok: !error,
          supabaseUrlSetInBrowser: Boolean(url),
          supabaseAnonKeySetInBrowser: Boolean(key),
          supabaseAnonKeyPrefix: key ? `${key.slice(0, 14)}...` : null,
          sessionExists: Boolean(data.session),
          userEmail: data.session?.user?.email ?? null,
          error: error ? readableError(error) : null
        });
      } catch (error) {
        setResult({
          ok: false,
          exception: readableError(error),
          supabaseUrlSetInBrowser: Boolean(process.env.NEXT_PUBLIC_SUPABASE_URL),
          supabaseAnonKeySetInBrowser: Boolean(process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY)
        });
      }
    }

    run();
  }, []);

  return (
    <section className="mx-auto max-w-3xl px-4 py-16 sm:px-6">
      <div className="deed-card p-7 sm:p-9">
        <p className="text-xs font-extrabold uppercase tracking-[0.2em] text-[#8D681D]">Diagnostics</p>
        <h1 className="mt-3 font-[var(--font-heading)] text-4xl font-semibold">Browser auth check</h1>
        <p className="mt-3 text-sm leading-6 text-[#7C715F]">
          This page does not show secret keys. It only confirms whether the browser bundle can read the public Supabase URL/key and create a Supabase client.
        </p>
        <pre className="mt-6 overflow-auto rounded-2xl bg-[#26231F] p-4 text-xs leading-6 text-[#FFF8EA]">
          {JSON.stringify(result, null, 2)}
        </pre>
      </div>
    </section>
  );
}
