import { readFileSync } from "node:fs";
import { pathToFileURL } from "node:url";

export const AUDIT_SEVERITIES = Object.freeze(["info", "low", "moderate", "high", "critical"]);
const COUNT_FIELDS = Object.freeze([...AUDIT_SEVERITIES, "total"]);

function isRecord(value) {
  return value !== null && typeof value === "object" && !Array.isArray(value);
}

function assertCount(value, field) {
  if (!Number.isSafeInteger(value) || value < 0) {
    throw new Error(`npm audit report is incomplete: metadata.vulnerabilities.${field} must be a non-negative safe integer.`);
  }
}

export function validateNpmAuditReport(report) {
  if (!isRecord(report)) throw new Error("npm audit report must be a JSON object.");
  if (report.auditReportVersion !== 2) {
    throw new Error("npm audit report has an unsupported or missing auditReportVersion; expected version 2.");
  }

  const counts = report.metadata?.vulnerabilities;
  if (!isRecord(counts)) throw new Error("npm audit report is incomplete: metadata.vulnerabilities is missing.");

  for (const field of COUNT_FIELDS) {
    if (!Object.hasOwn(counts, field)) {
      throw new Error(`npm audit report is incomplete: metadata.vulnerabilities.${field} is missing.`);
    }
    assertCount(counts[field], field);
  }

  const severityTotal = AUDIT_SEVERITIES.reduce((sum, severity) => sum + counts[severity], 0);
  if (counts.total !== severityTotal) {
    throw new Error(`npm audit report is inconsistent: total ${counts.total} does not equal severity sum ${severityTotal}.`);
  }

  const vulnerabilities = report.vulnerabilities;
  if (!isRecord(vulnerabilities)) {
    throw new Error("npm audit report is incomplete: vulnerabilities must be an object.");
  }

  const observed = Object.fromEntries(AUDIT_SEVERITIES.map((severity) => [severity, 0]));
  const packages = [];

  for (const [name, item] of Object.entries(vulnerabilities)) {
    if (!isRecord(item)) {
      throw new Error(`npm audit report is incomplete: vulnerabilities[${JSON.stringify(name)}] must be an object.`);
    }
    if (!AUDIT_SEVERITIES.includes(item.severity)) {
      throw new Error(`npm audit report contains an invalid severity for ${name}.`);
    }
    if (typeof item.isDirect !== "boolean") {
      throw new Error(`npm audit report is incomplete: ${name}.isDirect must be boolean.`);
    }
    if (typeof item.range !== "string" || item.range.length === 0) {
      throw new Error(`npm audit report is incomplete: ${name}.range must be a non-empty string.`);
    }
    if (!Array.isArray(item.nodes) || item.nodes.length === 0 || item.nodes.some((node) => typeof node !== "string" || node.length === 0)) {
      throw new Error(`npm audit report is incomplete: ${name}.nodes must contain dependency paths.`);
    }
    if (!Array.isArray(item.via) || item.via.length === 0) {
      throw new Error(`npm audit report is incomplete: ${name}.via must contain advisory or dependency references.`);
    }
    for (const reference of item.via) {
      if (typeof reference === "string" && reference.length > 0) continue;
      if (!isRecord(reference) || !AUDIT_SEVERITIES.includes(reference.severity)) {
        throw new Error(`npm audit report contains an invalid advisory severity for ${name}.`);
      }
    }
    if (!(typeof item.fixAvailable === "boolean" || isRecord(item.fixAvailable))) {
      throw new Error(`npm audit report is incomplete: ${name}.fixAvailable must be boolean or an object.`);
    }

    observed[item.severity] += 1;
    packages.push({
      name,
      severity: item.severity,
      direct: item.isDirect,
      range: item.range,
      paths: item.nodes,
      fixAvailable: item.fixAvailable,
    });
  }

  if (Object.keys(vulnerabilities).length !== counts.total) {
    throw new Error(`npm audit report is inconsistent: ${Object.keys(vulnerabilities).length} package entries do not match total ${counts.total}.`);
  }

  for (const severity of AUDIT_SEVERITIES) {
    if (observed[severity] !== counts[severity]) {
      throw new Error(`npm audit report is inconsistent: ${severity} package entries ${observed[severity]} do not match metadata count ${counts[severity]}.`);
    }
  }

  if (counts.total !== 0) {
    const summary = AUDIT_SEVERITIES.map((severity) => `${severity}=${counts[severity]}`).join(", ");
    throw new Error(`Dependency audit must be clean across every severity; found total=${counts.total} (${summary}).`);
  }

  return { counts: { ...counts }, packages };
}

export function parseNpmAuditJson(text) {
  if (typeof text !== "string" || text.trim().length === 0) {
    throw new Error("npm audit returned an empty report.");
  }

  let report;
  try {
    report = JSON.parse(text);
  } catch (error) {
    throw new Error("npm audit returned malformed JSON.", { cause: error });
  }

  return validateNpmAuditReport(report);
}

function main() {
  const reportPath = process.argv[2];
  const rawAuditExitCode = process.argv[3];

  if (
    !reportPath ||
    rawAuditExitCode === undefined ||
    !/^(0|[1-9]\d*)$/.test(rawAuditExitCode)
  ) {
    throw new Error("Usage: node scripts/verify-npm-audit.mjs <report.json> <npm-audit-exit-code>");
  }

  const auditExitCode = Number(rawAuditExitCode);
  if (!Number.isSafeInteger(auditExitCode)) {
    throw new Error("npm audit exit status must be a non-negative safe integer.");
  }

  const report = parseNpmAuditJson(readFileSync(reportPath, "utf8"));
  if (auditExitCode !== 0) {
    throw new Error(`npm audit exited with status ${auditExitCode} despite a zero-finding report.`);
  }

  console.log(JSON.stringify({ audit: "PASS", ...report }, null, 2));
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) main();
