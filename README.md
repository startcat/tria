# Lyncat Tria — engine and CLI

**Drop it in the inbox. Tria reads it, names it and files it where it belongs.**

Tria sorts your documents with AI, following rules you write in plain language (`TRIA.md`). You drop documents in an
inbox; Tria reads each one, proposes a clear name and a folder, and you decide. It never deletes or overwrites
anything, and everything can be undone.

This repository holds the engine (`TriaKit`) and the `tria` command-line tool for macOS. The CLI works with your own
Anthropic or OpenAI API key. The [Mac app](https://tria.lyn.cat) uses the same engine.

## Principles

1. **It always reads the content.** It never sorts by file name.
2. **It never deletes or overwrites.** The Trash, only if you ask for it.
3. **When in doubt, it asks.** Doubtful documents stay in the inbox, with their question.
4. **Everything is logged and can be undone** (`tria undo`).
5. **With your own key, your documents never go through Start.cat.** Text is extracted on your Mac and sent straight
   to your AI provider.

## Install

```bash
brew install startcat/tap/tria
```

Requires macOS 14 or later.

## Getting started

```bash
tria config --provider anthropic --set-key   # stored in the macOS Keychain; or --provider openai
cd ~/Documents/Business
tria init --template sl --lang es            # creates TRIA.md and PERFIL.md · or: autonomo, hogar · or --learn
# drop documents in 99-Pendiente/
tria sort                                    # proposes; you review and apply
tria undo --last                             # if something isn't right
```

The templates are for Spain: `autonomo` (freelancer), `sl` (company) and `hogar` (home), in Spanish (`--lang es`) or
Catalan (`--lang ca`). With `--learn`, Tria learns the rules from how your folder is already organized.

## Commands

| Command | What it does |
|---|---|
| `tria init` | Creates a workspace: `TRIA.md`, `PERFIL.md`, the inbox and the duplicates folder |
| `tria sort [--auto] [--dry-run] [--json] [--show-prompt] [--no-cache]` | Processes the inbox. In a terminal, with a full-screen review; `--auto` applies only high-confidence proposals and exact duplicates |
| `tria status` | Shows the inbox and the status of each document, without calling the AI |
| `tria undo [--last \| <batch>]` | Undoes the last batch or a specific one |
| `tria log [<batch>]` | History of batches and moves |
| `tria rules check \| learn \| suggestions \| ask "…"` | Validates `TRIA.md`, drafts rules from the folder, manages the rules suggested by your corrections, or asks Tria for a change in one sentence (shown before it's applied) |
| `tria config` | Provider, model and API key |
| `tria eval <folder>` | Measures accuracy against an already sorted archive, working on copies |

`tria help <command>` explains each one. `tria sort` exits with 0 when nothing is left pending, 1 when something is,
2 on error and 130 when interrupted with Ctrl-C. Ctrl-C never moves anything that hasn't been applied.

Each workspace keeps a log (`.tria/journal.jsonl`) of where every document went, with the confidence, the reason and
the model that read it.

## `TRIA.md`

The header sets what always applies; the body, in plain language, explains your folders and your naming.

```markdown
---
inbox: 99-Pendiente
duplicates: 98-Duplicados
protected:
  - "7-Facturas/20*/"          # Tria never moves anything into or out of these
new_folders: subfolders_only   # never | subfolders_only | anywhere
---
# Organización de documentos
## Carpetas
## Nomenclatura
## Casos especiales
```

`PERFIL.md` says who owns the archive (name, tax ID, partners, clients, banks…), so Tria can tell what you issue from
what you receive. `tria rules check` validates both.

## Privacy

- What goes to your provider: your rules, your profile (`PERFIL.md`), the folder tree with a few example names, the
  document's original name and dates, and an excerpt (the first 3 pages, at most 12,000 characters). Page images are
  sent only when there is no readable text.
- `tria rules ask` sends your request, `TRIA.md`, the folder tree and `PERFIL.md`; no documents.
- `tria sort --dry-run --show-prompt` prints exactly what is sent, before sending it, and moves nothing.
- No telemetry. Keys live only in the Keychain or in `ANTHROPIC_API_KEY` / `OPENAI_API_KEY`. OpenAI is called with
  `store: false`.
- The CLI never uses Tria AI, the Mac app's optional paid AI. Its client contract is in `Sources/TriaCore/TriaAPI/`,
  so you can see what the app sends when you choose it; the [privacy policy](https://tria.lyn.cat/en/privacy)
  explains what is stored and for how long.

## Languages

The CLI speaks Catalan, Spanish and English, following your system language. To choose one, set `TRIA_LANG=ca`,
`es` or `en`.

## Building from source

Requires Xcode 16 or later (Swift 6).

```bash
swift build -c release   # the binary is in .build/release/tria
swift test
```

`scripts/build-release.sh` builds the universal binary (arm64 and x86_64) in `dist/tria`.

## Documentation

The full documentation is at [tria.lyn.cat/en/docs](https://tria.lyn.cat/en/docs), also in
[Catalan](https://tria.lyn.cat/ca/docs) and [Spanish](https://tria.lyn.cat/es/docs).

## License

Apache-2.0.

---

**A [Start.cat](https://start.cat) product** · Lyncat Tria
