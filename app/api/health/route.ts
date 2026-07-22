export async function GET() {
  return Response.json({
    ok: true,
    siteUrlSet: Boolean(process.env.NEXT_PUBLIC_SITE_URL),
    supabaseUrlSet: Boolean(process.env.NEXT_PUBLIC_SUPABASE_URL),
    supabaseAnonKeySet: Boolean(process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY),
    serviceRoleKeySet: Boolean(process.env.SUPABASE_SERVICE_ROLE_KEY),
    siteUrl: process.env.NEXT_PUBLIC_SITE_URL ?? null,
    runtime: "cloudflare-workers-opennext"
  });
}
