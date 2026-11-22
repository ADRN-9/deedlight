import assert from "node:assert/strict";
import { spawn, spawnSync } from "node:child_process";
import { createServer } from "node:http";
import { existsSync, readFileSync, readdirSync, rmSync, writeFileSync } from "node:fs";
import { join, relative } from "node:path";
import { setTimeout as delay } from "node:timers/promises";

const root = process.cwd();
const nextConfigPath = join(root, "next.config.ts");
const wranglerConfigPath = join(root, "wrangler.jsonc");
const smokeWranglerConfigPath = join(root, "wrangler.runtime-smoke.jsonc");
const originalNextConfig = readFileSync(nextConfigPath, "utf8");
const originalWranglerConfig = JSON.parse(readFileSync(wranglerConfigPath, "utf8"));
const authCalls = { total: 0, valid: 0 };
const memberId = "00000000-0000-4000-8000-000000000001";
const member = {
  id: memberId,
  aud: "authenticated",
  role: "authenticated",
  email: "worker-smoke@deedlight.test",
  email_confirmed_at: "2026-11-22T00:00:00.000Z",
  app_metadata: { provider: "email", providers: ["email"] },
  user_metadata: {},
  identities: [],
  created_at: "2026-11-22T00:00:00.000Z",
};
const profile = {
  user_id: memberId,
  username: "worker-smoke",
  display_name: "Worker Smoke Member",
  bio: "A local-only runtime fixture.",
  country: "Test",
  is_public: false,
  show_contribution_stats: false,
  default_offering_anonymous: true,
};
const png = Buffer.from(
  "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR4nGNgYAAAAAMAASsJTYQAAAAASUVORK5CYII=",
  "base64",
);

function json(response, status, value) {
  response.writeHead(status, { "content-type": "application/json; charset=utf-8", "cache-control": "no-store" });
  response.end(JSON.stringify(value));
}

function walk(directory) {
  const files = [];
  for (const entry of readdirSync(directory, { withFileTypes: true })) {
    const path = join(directory, entry.name);
    if (entry.isDirectory()) files.push(...walk(path));
    else if (entry.isFile()) files.push(path);
  }
  return files;
}

function run(command, args, env) {
  const result = spawnSync(command, args, { cwd: root, env, stdio: "inherit" });
  if (result.error) throw result.error;
  if (result.status !== 0) throw new Error(`${command} ${args.join(" ")} failed with status ${result.status}`);
}

async function fetchWithTimeout(url, init = {}, timeoutMs = 15_000) {
  return fetch(url, {
    ...init,
    signal: AbortSignal.timeout(timeoutMs),
  });
}

function createSupabaseMock() {
  return createServer((request, response) => {
    const url = new URL(request.url ?? "/", "http://auth.supabase.co:54321");
    const authorization = request.headers.authorization ?? "";

    if (url.pathname === "/auth/v1/user") {
      authCalls.total += 1;
      if (authorization !== "Bearer smoke-access-token") {
        return json(response, 401, { message: "Invalid JWT", code: "invalid_token" });
      }
      authCalls.valid += 1;
      return json(response, 200, member);
    }

    if (url.pathname === "/rest/v1/profiles") {
      if (authorization !== "Bearer smoke-access-token") {
        return json(response, 401, { message: "Unauthorized" });
      }
      return json(response, 200, profile);
    }

    if (url.pathname === "/rest/v1/offerings" || url.pathname === "/rest/v1/daily_reflections") {
      if (authorization !== "Bearer smoke-access-token") {
        return json(response, 401, { message: "Unauthorized" });
      }
      return json(response, 200, []);
    }

    if (url.pathname === "/storage/v1/object/public/smoke/avatar.png") {
      response.writeHead(200, {
        "content-type": "image/png",
        "content-length": png.length,
        "cache-control": "public, max-age=3600",
      });
      response.end(png);
      return;
    }

    json(response, 404, { message: "Not found", path: url.pathname });
  });
}

function startWorker(env) {
  const child = spawn(
    "npx",
    ["wrangler", "dev", "--local", "--ip", "127.0.0.1", "--port", "8787", "--config", "wrangler.runtime-smoke.jsonc", "--log-level", "error"],
    { cwd: root, env, stdio: ["ignore", "pipe", "pipe"], detached: process.platform !== "win32" },
  );
  let output = "";
  child.stdout.on("data", (chunk) => { output = (output + chunk.toString()).slice(-12000); });
  child.stderr.on("data", (chunk) => { output = (output + chunk.toString()).slice(-12000); });
  return { child, get output() { return output; } };
}

async function waitForWorker(worker) {
  const deadline = Date.now() + 90_000;
  let lastError;
  while (Date.now() < deadline) {
    if (worker.child.exitCode !== null) {
      throw new Error(`Wrangler Worker exited early (${worker.child.exitCode}).\n${worker.output}`);
    }
    try {
      const response = await fetchWithTimeout("http://127.0.0.1:8787/api/health", {}, 5_000);
      if (response.ok) return;
    } catch (error) {
      lastError = error;
    }
    await delay(500);
  }
  throw new Error(`Wrangler Worker did not become ready: ${String(lastError)}\n${worker.output}`);
}

function signalWorker(worker, signal) {
  if (process.platform !== "win32" && worker.child.pid) {
    try {
      process.kill(-worker.child.pid, signal);
      return;
    } catch {
      // Fall back to the direct child if the process group is already gone.
    }
  }
  worker.child.kill(signal);
}

async function stopWorker(worker) {
  if (worker.child.exitCode !== null || worker.child.signalCode !== null) return;
  signalWorker(worker, "SIGTERM");
  await Promise.race([
    new Promise((resolveExit) => worker.child.once("exit", resolveExit)),
    delay(10_000),
  ]);
  if (worker.child.exitCode === null && worker.child.signalCode === null) {
    signalWorker(worker, "SIGKILL");
  }
}

function createSessionCookie() {
  const session = {
    access_token: "smoke-access-token",
    refresh_token: "smoke-refresh-token",
    expires_in: 3600,
    expires_at: Math.floor(Date.now() / 1000) + 3600,
    token_type: "bearer",
    user: member,
  };
  const value = `base64-${Buffer.from(JSON.stringify(session)).toString("base64url")}`;
  return `sb-auth-auth-token=${value}`;
}

async function main() {
  const middlewareSource = readFileSync(join(root, "middleware.ts"), "utf8");
  for (const exclusion of [
    "_next/static",
    "_next/image",
    "favicon.ico",
    "manifest.webmanifest",
    "icons",
    "svg",
    "png",
    "jpg",
    "jpeg",
    "gif",
    "webp",
  ]) {
    assert.ok(middlewareSource.includes(exclusion), `middleware matcher must retain the ${exclusion} exclusion`);
  }
  assert.ok(originalWranglerConfig.compatibility_flags.includes("global_fetch_strictly_public"),
    "production Wrangler config must retain global_fetch_strictly_public");
  assert.equal(originalWranglerConfig.images?.binding, "IMAGES",
    "production Worker must bind Cloudflare Images for permitted Supabase optimization");
  assert.deepEqual(originalWranglerConfig.triggers?.crons ?? [], [],
    "runtime smoke must not activate Cron");
  assert.equal(process.env.DELIVERY_ENABLED, "false",
    "runtime smoke must keep outbound delivery disabled");

  for (const name of [
    "CLOUDFLARE_API_TOKEN",
    "CLOUDFLARE_ACCOUNT_ID",
    "SUPABASE_SERVICE_ROLE_KEY",
    "SUPABASE_ACCESS_TOKEN",
    "SUPABASE_DB_PASSWORD",
    "RESEND_API_KEY",
  ]) {
    assert.equal(process.env[name], undefined, `${name} must not be present in runtime smoke`);
  }

  const patternAnchor = 'hostname: "*.supabase.co"';
  assert.ok(originalNextConfig.includes(patternAnchor), "production config must allow HTTPS Supabase Storage hosts");
  const smokeNextConfig = originalNextConfig.replace(
    patternAnchor,
    `hostname: "*.supabase.co"
      },
      {
        protocol: "http",
        hostname: "auth.supabase.co",
        port: "54321",
        pathname: "/storage/v1/object/public/**"`,
  );
  assert.notEqual(smokeNextConfig, originalNextConfig, "local image fixture pattern must be added only for this test");

  const smokeWranglerConfig = {
    ...originalWranglerConfig,
    compatibility_flags: originalWranglerConfig.compatibility_flags.filter((flag) => flag !== "global_fetch_strictly_public"),
  };

  let mockServer;
  let worker;
  try {
    writeFileSync(nextConfigPath, smokeNextConfig);
    writeFileSync(smokeWranglerConfigPath, JSON.stringify(smokeWranglerConfig, null, 2) + "\n");

    const buildEnv = {
      ...process.env,
      NEXT_PUBLIC_SITE_URL: "http://127.0.0.1:8787",
      NEXT_PUBLIC_SUPABASE_URL: "http://auth.supabase.co:54321",
      NEXT_PUBLIC_SUPABASE_ANON_KEY: "ci-worker-smoke-anon-key",
      DELIVERY_ENABLED: "false",
    };

    run("npm", ["run", "build"], buildEnv);
    run("npx", ["opennextjs-cloudflare", "build"], buildEnv);
    run("node", ["scripts/verify-cloudflare-build-artifacts.mjs"], buildEnv);

    mockServer = createSupabaseMock();
    await new Promise((resolveListen, reject) => {
      mockServer.once("error", reject);
      mockServer.listen(54321, "127.0.0.1", resolveListen);
    });

    worker = startWorker(buildEnv);
    await waitForWorker(worker);

    const baseUrl = "http://127.0.0.1:8787";
    const cookie = createSessionCookie();

    const health = await fetchWithTimeout(`${baseUrl}/api/health`);
    assert.equal(health.status, 200, "public health route must be served by the generated Worker");
    const healthBody = await health.json();
    assert.equal(healthBody.ok, true);
    assert.equal(healthBody.runtime, "cloudflare-workers-opennext");
    assert.equal(healthBody.serviceRoleKeySet, false, "runtime must not expose a service-role key");

    const about = await fetchWithTimeout(`${baseUrl}/about`);
    assert.equal(about.status, 200, "public page must render in the Worker runtime");
    await about.text();

    const unauthenticatedProfile = await fetchWithTimeout(`${baseUrl}/settings/profile`, { redirect: "manual" });
    assert.ok([302, 303, 307, 308].includes(unauthenticatedProfile.status),
      "private profile settings must redirect without an authenticated session");
    assert.match(unauthenticatedProfile.headers.get("location") ?? "", /\/login\?next=/);
    await unauthenticatedProfile.text();

    const beforeMatchedRequest = authCalls.total;
    const matchedPublicPage = await fetchWithTimeout(`${baseUrl}/about`, { headers: { cookie } });
    assert.equal(matchedPublicPage.status, 200);
    await matchedPublicPage.text();
    assert.ok(authCalls.total > beforeMatchedRequest,
      "cookie-bearing public route must execute Supabase session middleware");

    const authenticatedProfile = await fetchWithTimeout(`${baseUrl}/settings/profile`, { headers: { cookie } });
    assert.equal(authenticatedProfile.status, 200, "authenticated private route must render");
    const profileHtml = await authenticatedProfile.text();
    assert.match(profileHtml, /Choose how your light appears/);
    assert.match(profileHtml, /Worker Smoke Member/);
    assert.ok(authCalls.valid >= 2, "middleware and server route must validate the authenticated session");

    const iconPath = join(root, ".open-next", "assets", "icons", "deedlight-192.png");
    assert.ok(existsSync(iconPath), "public icon fixture must exist in OpenNext assets");
    const beforeIcon = authCalls.total;
    const icon = await fetchWithTimeout(`${baseUrl}/icons/deedlight-192.png`, { headers: { cookie } });
    assert.equal(icon.status, 200, "public icon must be served");
    await icon.arrayBuffer();
    assert.equal(authCalls.total, beforeIcon, "icons exclusion must bypass Supabase middleware");

    for (const [path, expectedStatus] of [
      ["/manifest.webmanifest", 200],
      ["/og/deedlight-og.png", 200],
    ]) {
      const beforeRequest = authCalls.total;
      const response = await fetchWithTimeout(`${baseUrl}${path}`, { headers: { cookie } });
      assert.equal(response.status, expectedStatus, `${path} must be served with its expected static response`);
      await response.arrayBuffer();
      assert.equal(authCalls.total, beforeRequest, `${path} exclusion must bypass Supabase middleware (observed ${authCalls.total - beforeRequest} auth calls)`);
    }

    const staticRoot = join(root, ".open-next", "assets", "_next", "static");
    const staticFile = walk(staticRoot).find((file) => /\.(?:js|css)$/.test(file));
    assert.ok(staticFile, "generated Next static assets must exist");
    const staticUrl = "/" + relative(join(root, ".open-next", "assets"), staticFile).split("\\").join("/");
    const beforeStatic = authCalls.total;
    const staticResponse = await fetchWithTimeout(`${baseUrl}${staticUrl}`, { headers: { cookie } });
    assert.equal(staticResponse.status, 200, "generated Next static asset must be served");
    await staticResponse.arrayBuffer();
    assert.equal(authCalls.total, beforeStatic, "_next/static exclusion must bypass Supabase middleware");

    const imageUrl = "http://auth.supabase.co:54321/storage/v1/object/public/smoke/avatar.png";
    const imageRequestUrl = `${baseUrl}/_next/image?url=${encodeURIComponent(imageUrl)}&w=64&q=75`;
    const beforeImage = authCalls.total;
    const optimizedImage = await fetchWithTimeout(imageRequestUrl, { headers: { cookie, accept: "image/webp,image/*,*/*;q=0.8" } }, 30_000);
    const optimizedImageDiagnostic = await optimizedImage.clone().text();
    assert.equal(optimizedImage.status, 200, `permitted Supabase Storage image must pass through Worker image optimization (received ${optimizedImage.status}: ${optimizedImageDiagnostic.slice(0, 500)})`);
    assert.match(optimizedImage.headers.get("content-type") ?? "", /^image\//);
    assert.ok((await optimizedImage.arrayBuffer()).byteLength > 0);
    assert.equal(authCalls.total, beforeImage, "_next/image exclusion must bypass Supabase middleware");

    const disallowedImage = await fetchWithTimeout(
      `${baseUrl}/_next/image?url=${encodeURIComponent("https://images.example.invalid/avatar.png")}&w=64&q=75`,
    );
    assert.equal(disallowedImage.status, 400, "unlisted image hosts must remain rejected");

    console.log(JSON.stringify({
      workerRuntime: "PASS",
      routes: {
        publicHealth: health.status,
        publicPage: about.status,
        unauthenticatedPrivatePage: unauthenticatedProfile.status,
        authenticatedPrivatePage: authenticatedProfile.status,
      },
      middleware: {
        cookieBearingMatchedRouteAuthCalls: authCalls.total,
        iconExclusion: "PASS",
        faviconMatcherExclusion: "PASS",
        manifestExclusion: "PASS",
        publicImageExtensionExclusion: "PASS",
        nextStaticExclusion: "PASS",
        nextImageExclusion: "PASS",
      },
      imageOptimization: {
        permittedSupabaseStorageImage: optimizedImage.status,
        contentType: optimizedImage.headers.get("content-type"),
        disallowedHost: disallowedImage.status,
      },
      cron: "disabled",
      delivery: "disabled",
    }, null, 2));
  } finally {
    if (worker) await stopWorker(worker);
    if (mockServer) {
      mockServer.closeAllConnections();
      await new Promise((resolveClose) => mockServer.close(resolveClose));
    }
    writeFileSync(nextConfigPath, originalNextConfig);
    if (existsSync(smokeWranglerConfigPath)) rmSync(smokeWranglerConfigPath);
  }
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
