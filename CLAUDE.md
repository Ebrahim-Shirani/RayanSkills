# RayanSkills — Project Guide (CLAUDE.md)

This repository is a **monolithic collection of Claude skills** for personal and
company use, developed in the open and published on GitHub as **RayanSkills**
under the **MIT license**.

An AI agent (Claude Code, or Claude Desktop in Cowork mode) working in this repo
**must read and follow this file** before doing anything. It defines how skills
are organized and the exact workflow for creating or modifying a skill.

---

## 1. Repository layout

```
<repo root>/
├── CLAUDE.md                # this file — rules & workflow (always applies)
├── LICENSE                  # MIT
├── README.md
├── .rayanskills/
│   └── state.json           # persistent agent state (active skill/session)
├── skills/                  # shippable skills, grouped
│   └── <group>/
│       └── <skill>/         # SKILL.md + all scripts, references, templates, examples
│           └── SKILL.md
└── docs/                    # design/build docs — NOT shipped inside skills
    └── <group>/
        └── <skill>/
            ├── TASKS.md     # development task backlog (with statuses)
            ├── adr/         # Architecture Decision Records
            └── specs/       # specifications (created when needed)
```

### Core rules

- **Skills live under `skills/`.** Every skill belongs to a **group**; each group
  is a directory directly under `skills/`.
- **One directory per skill**, named exactly as the skill, placed inside its
  group directory.
- **Everything the shipped skill needs** — `SKILL.md`, scripts, `reference/`,
  `templates/`, examples — lives inside that skill directory. Nothing else.
- **Design & build documentation does NOT ship inside the skill.** It lives under
  `docs/<group>/<skill>/`, mirroring the `skills/` path. This folder holds the
  authoring artifacts: `adr/`, `specs/`, and `TASKS.md`.
- We mirror the full `group/skill` path in `docs/` (not just `docs/<skill>/`) so
  the two trees stay structurally identical, even though skill names are unique
  repo-wide (see §2).

---

## 2. Naming conventions

- **Group and skill directory names are `kebab-case`** (lowercase words separated
  by hyphens, no spaces) — this is Claude's skill-naming standard.
  Example: group `linux-shared-libraries`, skill `linux-shared-library-versioning`.
- **Skill names must be unique across the entire repository**, not just within a
  group. Because of this, a skill can always be located by name alone.
- Each `SKILL.md` starts with two-field frontmatter:

  ```
  ---
  name: "Human Readable Title Case Name"
  description: "What the skill does and when to use it (triggers)."
  ---
  ```

  The `name` is a human-readable Title-Case string; the directory name is its
  `kebab-case` form.
- Reject any name containing spaces or invalid characters. If an existing folder
  violates this (e.g. a stray space), flag it — do not silently ship it.

---

## 3. TASKS.md — development tasks

Each skill's `docs/<group>/<skill>/TASKS.md` tracks development tasks. Tasks are
worked **in order** and each carries a **status** from this fixed vocabulary:

`TODO` · `IN_PROGRESS` · `DONE` · `BLOCKED` · `CANCELLED`

Task IDs are ordered: `T001`, `T002`, … Each task records at minimum its ID,
Status, driving ADR (if any), dependencies, and acceptance criteria. A task is
not started merely because it exists — only after review/approval.

---

## 4. Startup behavior (every session in this repo)

When this file is loaded, the agent first reads `.rayanskills/state.json`
(see §7). Then it asks the user:

> **Do you want to create a NEW skill, or MODIFY an existing one?**

### 4a. Create a NEW skill

1. Ask the user for the **skill name**.
2. **If a skill with that name already exists** anywhere in the repo, tell the
   user it already exists. The user then either:
   - chooses to **modify** that existing skill → go to §4b for that skill, or
   - **provides a different name** → repeat this check.
3. Once the name is new and valid, ask for the **group name** this skill belongs
   to. The group may be **existing or new**.
4. Create the skill scaffold (without overwriting anything that exists):
   - `skills/<group>/<skill>/` — create the group directory too if it is new.
   - `docs/<group>/<skill>/` with `adr/`, `specs/`, and a starting `TASKS.md`.
5. Record the active skill in `.rayanskills/state.json` (§7).
6. Proceed with authoring the skill (SKILL.md + supporting files).

### 4b. Modify an EXISTING skill

1. Show the user the **list of existing skills** (see §5 for the paginated,
   grouped display).
2. Let the user pick one — by number, by exact name, or by filtering.
3. Once selected, load that skill's paths into project context
   (`skills/<group>/<skill>/` and `docs/<group>/<skill>/`) and record it as the
   active skill in `.rayanskills/state.json`.
4. Make the user's changes **in the files/paths of the selected skill**, exactly
   as if the agent were running inside that skill's folder.

---

## 5. Listing skills (paginated & filterable)

When showing the skill list:

- Group the list **by group name**.
- **Paginate** at ~10–15 skills per page.
- Show a header like: `Page 2/5 — showing 11–20 of 47 skills`.
- Navigation commands: **`next`** and **`prev`**, wrapping **cyclically**
  (next on the last page goes to the first; prev on the first goes to the last).
- Allow **direct selection** by number or exact skill name from any page.
- Allow **filtering**: the user can type part of a group or skill name to narrow
  the list (the fast path — preferred over paging when the user knows the name).

Note: this is a text-driven list; there is no live keyboard/arrow navigation.
Selection happens by the user typing a number, a name, `next`/`prev`, or a filter.

---

## 6. Git & publishing

- A single **local git repository at the repo root** manages all skills
  **monolithically**.
- The remote is a **public GitHub repository named `RayanSkills`**; the local repo
  is connected to it.
- The project is **open source under the MIT license** (see `LICENSE`).

---

## 7. State persistence (surviving `/clear`)

`CLAUDE.md` is re-read every session, so these **rules** always survive. But the
**active skill** (which skill the user is currently building/editing) is live
context that `/clear` would otherwise wipe. To keep it:

- The agent stores the active skill and relevant paths in
  **`.rayanskills/state.json`**.
- On every session start (and after any `/clear`), the agent **reads this file**
  to restore the active skill and its paths into context.
- The agent **updates this file** whenever the active skill changes (new skill
  created, or a different existing skill selected).

Contract:

- **`/clear` must NOT lose the project's structural knowledge or the active
  skill.** After a clear, re-read `CLAUDE.md` + `.rayanskills/state.json` and
  continue where things were.
- **Only `exit` fully clears memory.** On exit, the working context is
  intentionally discarded (the persisted `state.json` may be reset/cleared).

`state.json` shape (example):

```json
{
  "active_skill": {
    "name": "linux-shared-library-versioning",
    "group": "linux-shared-libraries",
    "skill_path": "skills/linux-shared-libraries/linux-shared-library-versioning",
    "docs_path": "docs/linux-shared-libraries/linux-shared-library-versioning"
  },
  "updated_at": "2026-07-17T00:00:00Z"
}
```

---

## 8. Quick reference

- Add a skill → `skills/<group>/<skill>/` (+ mirror `docs/<group>/<skill>/`).
- Names: `kebab-case`, unique repo-wide, no spaces.
- Ship only skill artifacts in `skills/`; keep ADRs/specs/tasks in `docs/`.
- Track work in `TASKS.md` with statuses `TODO/IN_PROGRESS/DONE/BLOCKED/CANCELLED`.
- Persist the active skill in `.rayanskills/state.json`; survive `/clear`, reset on `exit`.
