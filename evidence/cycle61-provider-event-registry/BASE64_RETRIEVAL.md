# Text-only recovery path for the exact original Cycle 61 ZIP

The original unchanged binary is `ORIGINAL_C61_PACKAGE.zip` (35,836 bytes). The adjacent `ORIGINAL_C61_PACKAGE.zip.base64.txt` is a **derived transport encoding only**, not a new source version. It allows reviewers whose GitHub connector cannot render binary ZIP bytes to download the original through a plain UTF-8 file.

```sh
base64 --decode ORIGINAL_C61_PACKAGE.zip.base64.txt > recovered_c61.zip
printf '%s  %s\n' '7e574ba3f8c455f30f5c18c1487fda45dcf5af1d4ae5f15f8ea4745724ea0630' recovered_c61.zip | sha256sum --check
unzip -t recovered_c61.zip
unzip -q recovered_c61.zip
cd deedlight_c61_event_dedup_0871d1bf
sha256sum -c SHA256SUMS.txt
```

The original ZIP Git object ID (SHA-1) is `b16b93e0a2997a6d9d6616fc43e9a4649b02f24d`. The exact base64 file Git blob ID is `67cb2502a93dc2369e0c60930f6c8e0b95729cb1`. These were independently checked against the original local ZIP and its encoding.

**Never apply the included PostgreSQL migration to Production from this evidence-only branch.** The package's SQL is unintegrated and PostgreSQL execution is NOT TESTED.
