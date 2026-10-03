# HelpMeMove

An adaptive movement coach: assessment → movement → measurement → adaptation → fitness.

> **Status: scaffold only.** Flutter and Rust build, test, and CI exist.
> Product features are not implemented. Planning, scope, and track governance
> live in the workspace directories described below, not here.

## Workspace layout

The product checkout is this directory (`Repo`). Planning and governance live alongside it in the
workspace root and are **not** part of this repository:

| Location | Contents |
| --- | --- |
| `Repo/` | This repository — the application checkout. All Git/build/test commands run here. |
| `../Planning-Docs/` | Product vision, design, architecture, research, and product risk/launch docs. |
| `../Conductor/` | Track specs, plans, reviews, evidence, and the track registry. |
| `../Frontend-Assets/` | Original design references. |
| `../.agents/` | Agent instructions and skills. Never part of this repository. |

Agent instructions for the workspace are in `../AGENTS.md`.

## Intended stack

Per the workspace planning docs:

- **Flutter** — presentation layer.
- **Rust** — deterministic decision logic, with typed errors (no production `unwrap`/`expect`).
- **Swift / Kotlin** — high-frequency hardware and ML responsibilities on their platforms.

Clinical thresholds are not invented by this project, and safety logic is never overridden by an LLM.

## Prerequisites

- Rust 1.99.0, selected by `rust-toolchain.toml` in this repository (edition 2024).
- Flutter 3.47.6 and Dart 3.13.5.

Product features are still absent. The smoke screen only shows `HelpMeMove` and a `Scaffold check` button.

## Local tool state

`.env` and `.ledgerful/` are local, machine-specific tool state and are **gitignored**. They are never
committed. See `../AGENTS.md` for the operational rules around Ledgerful and AI-Brains.

## License

Not yet determined.
