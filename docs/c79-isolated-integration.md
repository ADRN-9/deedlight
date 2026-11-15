# C79 — isolated DeedLight integration candidate

This branch is isolated from shared application branches. It starts at PR #10 commit
`c983e2ed8b93c935139c935343261570ecea6978` and reproduces the published
C73 -> C74 -> C75 -> C76 application tree, without reapplying the incorporated C72 patch.

| Patch | Source evidence | SHA-256 | Expected tree |
| --- | --- | --- | --- |
| C73 | `a25a43a85d74a5a5b9d05309ad0840df8ddcd8cf` | `864c3fae8df6b3c60fbcf17f0189e633ae1b1de54a01dde01738c545f53dc8d9` | `dd4f8593fdb1b3032eb6cddd5f39e50ea9cb7682` |
| C74 | `4b913640c16c1113d9f559b26e7d930a432f4ccb` | `71412f3345a34ba3e7ad1246cbfd0165b6d765fdbd719c97d045a6fae265a1fc` | `a9981c2672b316a07904ad7f6b498cd22f206a5b` |
| C75 | `df1150dcee7c54a4e5bc2af1225afbc57c722309` | `166c8834d48d3caaada8f766408a07b247a262ff5e042eb375be8bf5ae37484a` | `3ffedca10b5f38b375b08350ea7090e5a0a000d8` |
| C76 | `d786f5640c9702a82b2b0f34c67e30d8d62115b1` | `88c57e35489b4c7b5b806be02612dff67ef3ffd401cd884976e1d76982251672` | `5b9fa485c0dcc67beb5b82e9623e5dff4e93260b` |

Migration order: the PR #10 chain 019–024, then 025, 026, 027, 028,
029 (global provider registry), 030 (fail-closed cutover), 031 (legacy
lifecycle guard), 032 (conflict-hold repair), 033 (bounce and suppression).

C77 regression fixtures are copied byte-for-byte from evidence commit
`135a2dae0723df808c9bf2c9a473f53041a42063` into `scripts/`.
The C76 real two-session claim fixture is copied from commit
`d786f5640c9702a82b2b0f34c67e30d8d62115b1`.

The PR #11 `security/audit-deedlight` subtree and audit workflow are copied
unchanged from `aed588d771dc04fda5e5c18d8611239ac926a513`.
The separate `scripts/c79-run-pr11-audit-fixtures.sh` adapter changes only
the original test-runner's source checkout pin, branch gate, and relative root
to permit the **same synthetic safeguards** on this specific CI commit.
The original PR #11 runner and SHA-256 manifest remain intact.

The PR #11 metadata checks are historically pinned to PR #10's 019–024
schema. Passing these legacy fixtures does not by itself attest migration
025–033 catalog expectations. A separate catalog-only audit on the
post-033 disposable schema and independent Reviewer disposition are required.

All CI tests use disposable PostgreSQL 16, synthetic provider transport and
`DELIVERY_ENABLED=false`. Do not execute fixtures against Production.
No credential, Production migration, Cron activation, delivery send, deploy,
PR merge, or completion tag is authorized by this branch.

OPEN: general PR Validation, independent security review, nine moderate
glob/minimatch advisories, complete post-033 audit expectations, Production
migration history and staged Production release benchmarks.
