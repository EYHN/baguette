# Security Policy

baguette drives your iOS simulators, and `baguette serve` exposes that control over HTTP and WebSocket. A way for a web page, another user or another machine to reach it is a security bug. Thank you for reporting one privately.

## Supported versions

Only the latest release gets security fixes. Update with `brew upgrade baguette`.

## Reporting a vulnerability

**Don't open a public issue.** Report it privately on GitHub: [**Report a vulnerability**](https://github.com/tddworks/baguette/security/advisories/new) (the Security tab → *Advisories*).

Please include:

- what an attacker can do, and what they need first (a page open in your browser, a local account, a plugin, network access to a `serve` port, …)
- the baguette, Xcode and macOS versions
- steps or a proof of concept that reproduce it

## What to expect

- A first reply within 7 days.
- A fix in a release, credited to you in the advisory and the [CHANGELOG](CHANGELOG.md) unless you'd rather stay anonymous.
- The advisory is published once a fixed version is out.

## Scope

In scope: the `baguette` CLI, `baguette serve` and its routes, the `Host` / `Origin` checks and plugin grants, the guest helpers and injected dylibs under `Injected/`, and the Homebrew formula.

Out of scope:

- Running `serve` with `--host 0.0.0.0` or a broad `--allowed-hosts` on an untrusted network: you have chosen to share control of the simulator ([serve routes](docs/serve.md)).
- Plugins you install yourself, which run with the permissions you grant them.
- Flaws in Xcode, CoreSimulator or the simulated apps themselves (report those to Apple).
