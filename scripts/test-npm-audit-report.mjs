import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import test from "node:test";
import { mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { fileURLToPath } from "node:url";

import { AUDIT_SEVERITIES, parseNpmAuditJson, validateNpmAuditReport } from "./verify-npm-audit.mjs";

function cleanReport() {
  return {
    auditReportVersion: 2,
    vulnerabilities: {},
    metadata: {
      vulnerabilities: {
        info: 0,
        low: 0,
        moderate: 0,
        high: 0,
        critical: 0,
        total: 0,
      },
    },
  };
}

function reportWithFinding(severity) {
  const report = cleanReport();
  report.vulnerabilities.fixture = {
    name: "fixture",
    severity,
    isDirect: false,
    range: "<1.0.0",
    nodes: ["node_modules/fixture"],
    via: [{ source: 123, name: "fixture advisory", url: "https://example.invalid/advisory", severity, range: "<1.0.0" }],
    effects: [],
    fixAvailable: true,
  };
  report.metadata.vulnerabilities[severity] = 1;
  report.metadata.vulnerabilities.total = 1;
  return report;
}

test("accepts a complete zero-finding report", () => {
  const result = validateNpmAuditReport(cleanReport());
  assert.equal(result.counts.total, 0);
  assert.deepEqual(result.packages, []);
});

for (const severity of AUDIT_SEVERITIES) {
  test(`rejects any ${severity} finding`, () => {
    assert.throws(
      () => validateNpmAuditReport(reportWithFinding(severity)),
      /must be clean across every severity/,
    );
  });
}

test("requires every severity count and total", () => {
  for (const field of [...AUDIT_SEVERITIES, "total"]) {
    const report = cleanReport();
    delete report.metadata.vulnerabilities[field];
    assert.throws(() => validateNpmAuditReport(report), new RegExp(`${field} is missing`));
  }
});

test("rejects string, fractional, negative, and unsafe severity counts", () => {
  for (const invalid of ["0", 0.5, -1, Number.MAX_SAFE_INTEGER + 1]) {
    const report = cleanReport();
    report.metadata.vulnerabilities.high = invalid;
    assert.throws(() => validateNpmAuditReport(report), /non-negative safe integer/);
  }
});

test("rejects a total that does not equal the severity sum", () => {
  const report = cleanReport();
  report.metadata.vulnerabilities.total = 1;
  assert.throws(() => validateNpmAuditReport(report), /does not equal severity sum/);
});

test("rejects a package count that does not match total", () => {
  const report = reportWithFinding("low");
  report.metadata.vulnerabilities.low = 0;
  report.metadata.vulnerabilities.total = 0;
  assert.throws(() => validateNpmAuditReport(report), /package entries do not match total/);
});

test("rejects package severity counts that disagree with metadata", () => {
  const report = reportWithFinding("moderate");
  report.metadata.vulnerabilities.moderate = 0;
  report.metadata.vulnerabilities.low = 1;
  assert.throws(() => validateNpmAuditReport(report), /low package entries 0 do not match metadata count 1/);
});

test("rejects missing or malformed report sections", () => {
  assert.throws(() => validateNpmAuditReport(null), /JSON object/);
  assert.throws(() => validateNpmAuditReport({ auditReportVersion: 2, vulnerabilities: {} }), /metadata.vulnerabilities is missing/);
  assert.throws(() => validateNpmAuditReport({ auditReportVersion: 2, metadata: { vulnerabilities: cleanReport().metadata.vulnerabilities } }), /vulnerabilities must be an object/);
  assert.throws(() => parseNpmAuditJson(""), /empty report/);
  assert.throws(() => parseNpmAuditJson("{"), /malformed JSON/);
});

test("rejects malformed package entries and missing dependency paths", () => {
  const invalidSeverity = reportWithFinding("moderate");
  invalidSeverity.vulnerabilities.fixture.severity = "urgent";
  assert.throws(() => validateNpmAuditReport(invalidSeverity), /invalid severity/);

  const missingNodes = reportWithFinding("moderate");
  missingNodes.vulnerabilities.fixture.nodes = [];
  assert.throws(() => validateNpmAuditReport(missingNodes), /nodes must contain dependency paths/);

  const missingVia = reportWithFinding("moderate");
  missingVia.vulnerabilities.fixture.via = [];
  assert.throws(() => validateNpmAuditReport(missingVia), /via must contain advisory/);

  const invalidAdvisorySeverity = reportWithFinding("moderate");
  invalidAdvisorySeverity.vulnerabilities.fixture.via[0].severity = "urgent";
  assert.throws(() => validateNpmAuditReport(invalidAdvisorySeverity), /invalid advisory severity/);

  const missingDirect = reportWithFinding("moderate");
  delete missingDirect.vulnerabilities.fixture.isDirect;
  assert.throws(() => validateNpmAuditReport(missingDirect), /isDirect must be boolean/);
});


test("includes package names, dependency paths, and advisory URLs in failure diagnostics", () => {
  const report = reportWithFinding("high");
  const finding = report.vulnerabilities.fixture;
  finding.name = "@deedlight/fixture-package";
  finding.nodes = [
    "node_modules/@deedlight/fixture-package",
    "node_modules/@deedlight/fixture-package/node_modules/transitive-fixture",
  ];
  finding.via = [{
    source: 123,
    name: "GHSA-example",
    title: "Fixture advisory",
    url: "https://github.com/advisories/GHSA-example",
    severity: "high",
    range: "<1.0.0",
  }];

  assert.throws(() => validateNpmAuditReport(report), (error) => {
    assert.ok(error.message.includes("@deedlight/fixture-package"));
    assert.ok(error.message.includes("node_modules/@deedlight/fixture-package"));
    assert.ok(error.message.includes("node_modules/@deedlight/fixture-package/node_modules/transitive-fixture"));
    assert.ok(error.message.includes("https://github.com/advisories/GHSA-example"));
    return true;
  });
});

test("parses JSON text and preserves a clean report summary", () => {
  const parsed = parseNpmAuditJson(JSON.stringify(cleanReport()));
  assert.equal(parsed.counts.total, 0);
  assert.deepEqual(parsed.packages, []);
});

test("rejects missing and unsupported npm audit report versions", () => {
  for (const invalid of [undefined, 1, 3, "2", null]) {
    const report = cleanReport();
    if (invalid === undefined) {
      delete report.auditReportVersion;
    } else {
      report.auditReportVersion = invalid;
    }
    assert.throws(
      () => validateNpmAuditReport(report),
      /unsupported or missing auditReportVersion/,
    );
  }
});


test("rejects a valid zero-vulnerability report when npm audit exits nonzero", () => {
  const scriptPath = fileURLToPath(new URL("./verify-npm-audit.mjs", import.meta.url));
  const directory = mkdtempSync(join(tmpdir(), "deedlight-npm-audit-"));

  try {
    const reportPath = join(directory, "audit.json");
    writeFileSync(reportPath, JSON.stringify(cleanReport()), "utf8");

    const result = spawnSync(process.execPath, [scriptPath, reportPath, "1"], {
      encoding: "utf8",
    });

    assert.notEqual(result.status, 0);
    assert.match(
      result.stderr,
      /npm audit exited with status 1 despite a zero-finding report/,
    );
  } finally {
    rmSync(directory, { recursive: true, force: true });
  }
});

test("requires an explicit npm audit exit status argument", () => {
  const scriptPath = fileURLToPath(new URL("./verify-npm-audit.mjs", import.meta.url));
  const missingAll = spawnSync(process.execPath, [scriptPath], { encoding: "utf8" });
  assert.notEqual(missingAll.status, 0);
  assert.match(missingAll.stderr, /Usage: node scripts\/verify-npm-audit\.mjs/);

  const missingStatus = spawnSync(process.execPath, [scriptPath, "report.json"], { encoding: "utf8" });
  assert.notEqual(missingStatus.status, 0);
  assert.match(missingStatus.stderr, /Usage: node scripts\/verify-npm-audit\.mjs/);
});
