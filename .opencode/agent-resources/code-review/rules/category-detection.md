# Category Detection

Derive review categories from the review set (the diff for Path A/B, or the scoped
file contents for Path C). Do NOT use a fixed category list - let the changes/files
dictate the categories. The table below maps signals to suggested categories; you may
invent a category when the review set warrants one not listed.

## Signal → category hints

| Signal → primary language | Suggested category |
|---|---|
| `*.cpp`, `*.h`, `*.hpp` | `language/cpp` (split further by area only if the diff is large: battle / serialization / ui / pathfinding …) |
| `test/**`, `*Test.cpp`, `*_test.*`, `*.spec.*` | `tests` |
| `CMakeLists.txt`, `*.cmake`, `CMakePresets.json`, conan profiles | `build` |
| `.github/workflows/*`, CI config | `infra/ci` |
| `*.md`, `docs/*`, `README*`, `CHANGELOG*` | `docs` |
| `config/**` (game JSON), `scripts/**` (Lua), `Assets/**` | `game-data` |
| Translation / localization files (`translation.ts`, `*.qm`) | `i18n` |
| Content: `password`, `secret`, `token`, `apiKey`, `private key`, `eval(`, `exec(`, `system(`, auth, crypto, `BEGIN PRIVATE KEY` | `security-sensitive` |

## Rules

- **Security-sensitive is ALWAYS its own category**, regardless of file type. It
  cross-cuts languages and layers. Extract it standalone even if the file also
  matches another category.
- A file may belong to multiple categories (e.g. a battle-system change touching
  serialized state → `language/cpp` + `serialization`).
- **Collapse micro-categories.** If only one file maps to a given language or
  area, do not spawn a dedicated worker - fold it into the nearest related
  category or review it inline in the top agent.
- **Target 3–6 categories.** Fewer → review inline (no fan-out needed). More →
  fan out one worker per category.
- **Never echo secrets** into findings or the report. Reference sensitive content
  by `file:line` only.
- **Path C (static scope):** there is no diff, so signals come from the file paths
  and their current contents (content greps), not from changed lines. Review the
  whole file, not hunks.

## Output of this step

A category map for the report appendix:

```
category → [list of files]
```

This map drives the worker fan-out (Step 3) and is recorded in the final report's
"What was reviewed" appendix.
