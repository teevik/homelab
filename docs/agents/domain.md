# Domain Docs

How engineering skills should consume this repository’s domain documentation.

## Before exploring, read these

- `CONTEXT.md` at the repository root.
- Relevant ADRs under `docs/adr/`.

If these files do not exist, proceed silently. The domain-modeling skill creates them lazily when terminology or architectural decisions are resolved.

## File structure

This is a single-context repository:

```
/
├── CONTEXT.md
├── docs/
│   └── adr/
└── packages/
```

## Use the glossary’s vocabulary

When output names a domain concept, use the term defined in `CONTEXT.md`. Avoid synonyms that the glossary explicitly rejects.

If a required concept is absent, reconsider whether the term belongs to the project or note the gap for domain modeling.

## Flag ADR conflicts

If proposed work contradicts an existing ADR, surface the conflict explicitly rather than silently overriding it.
