# RayanSkills

An open collection of **Claude skills** for personal and company use, developed
in the open and published under the **MIT license**.

Skills are managed **monolithically** in this single repository.

## Layout

```
skills/<group>/<skill>/     # shippable skills (SKILL.md + scripts, references, templates)
docs/<group>/<skill>/       # design/build docs: adr/, specs/, TASKS.md (not shipped)
```

- Skills are organized into **groups**; each group is a directory under `skills/`.
- Each skill has its own directory named exactly as the skill; **skill names are
  unique across the whole repo**.
- Everything a skill needs to run lives in its own directory. Design artifacts
  (ADRs, specs, task backlog) live under `docs/`, mirroring the same path.

## Development

Working in this repo with Claude Code or Claude Desktop (Cowork mode) is guided by
[`CLAUDE.md`](./CLAUDE.md), which defines the folder rules, naming conventions,
and the create/modify workflow for skills.

## License

[MIT](./LICENSE)
