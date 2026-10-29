# Privacy of this public snapshot

This repository is an independent portfolio copy of a personal app. It is built for the author's private use and is not associated with Opel or Stellantis.

## What is included

- Application source, original interface work and generated vehicle renders.
- Deterministic demo fixtures with an obviously synthetic VIN.
- Public-place route fixtures around Rüsselsheim; these are not a personal trip export.
- A curated gallery from the demo, with no account screen or real server address.
- Example bundle identifiers (`com.example.betteropel`) and a matching example App Group.

## What is excluded

No personal signing-team ID, account credentials, server activity logs, live vehicle database, private server hostname, device provisioning profile, local Xcode user state, or original Git history is intentionally included. The public repository starts with a new history and a GitHub no-reply commit identity.

`.gitignore` excludes common local configuration, signing files, logs, databases and personal captures. `scripts/privacy_check.py` checks tracked files for common secret patterns, unexpected vehicle identifiers, private hostnames, personal paths and signing settings. It reports file names and rule names rather than printing matching values.

Automated pattern matching cannot prove the absence of all private information. Images and contextual demo data also require human review. The supplied gallery was visually reviewed before this snapshot was published.

## Runtime data stays local to your installation

The app can store a server address, VIN and cached vehicle readings in its App Group. A fresh installation starts in demo mode. Connecting to an owner-hosted server is an explicit action in Settings. The app does not contain an analytics or advertising SDK; MapKit, place lookup and an explicitly configured server can use the network.

The optional server manages MyOpel authentication separately. Its configuration, tokens, logs and databases must stay outside the repository. It is not installed or started by the demo build.

## Safe captures

The `shot.sh` and `record.sh` helpers launch with `-server none -resetDemo`, returning the public app to demo mode before capture. Use these only with the public example app, and visually inspect the result. Do not pass live `-server`, `-vin` or `-scheduler` arguments during a public capture. `captures/` is ignored by Git.

Run the repository guard before committing:

```bash
python3 scripts/privacy_check.py
```

If sensitive data ever reaches a remote, removing the current file alone does not remove it from history. Revoke exposed credentials and remediate the history before continuing to share it.
