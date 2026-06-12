# Org Second Brain via Claude Haiku -- Implementation Plan

## Goal

An interactive query interface for your org notes, powered by Claude Haiku,
accessible via an Emacs `M-x` command (and optionally a Fish CLI fallback).
Responses cite source files as clickable `[[file:path][heading]]` org-links.

---

## Phase 1 -- Fish CLI (Foundation)

Build the base query tool first. Validate prompt + output quality before
wiring up Emacs.

- [ ] Write `orq` Fish function that:
  - Globs all `.org` files from your notes dir
  - Injects each file's absolute path as a header above its content so Claude
    knows which file each section belongs to
  - Passes the annotated corpus + query to Claude Haiku via `claude --print`
  - Prints the response to stdout
- [ ] Test against your real notes corpus
- [ ] Tune the system prompt to:
  - Instruct Claude to always cite using the format:
    `[[file:/absolute/path/to/file.org][* Heading Text]]`
  - Cover your 3 use cases: quick lookup, cross-note connections, summarization

---

## Phase 2 -- Emacs Integration (Core)

Wire the CLI into Emacs as a proper interactive command.

- [ ] Create `~/.config/doom/org-brain.el`
- [ ] Write `org-brain-query` interactive function that:
  - Prompts for a query string via the minibuffer
  - Calls the claude CLI directly as an async subprocess via `make-process`
    (non-blocking -- won't freeze Emacs)
  - Streams stdout into a `*org-brain*` buffer as it arrives
- [ ] `*org-brain*` buffer behavior:
  - Opens in `org-mode` so `[[file:...][...]]` links are rendered and clickable
  - Evil normal-mode keybindings active
  - Read-only (use `org-brain-minor-mode` for custom bindings on top)
  - `RET` on a citation link jumps to that file + heading directly (native
    org-mode behavior, free)

---

## Phase 3 -- Citation Prompt Engineering

This is the key phase that makes references actually useful.

- [ ] Each org file passed to Claude is prefixed with a metadata block:
      --- FILE: /absolute/path/to/file.org
      So Claude can reconstruct the path in citations reliably.

- [ ] System prompt instructs Claude to:

  - Always ground claims in a specific file + heading
  - Emit citations inline as `[[file:/path/to/file.org][* Heading]]`
  - For cross-note connections, cite both sides of the link
  - Never fabricate headings -- only cite headings that exist in the corpus

- [ ] Validate citation accuracy against known notes before moving to Phase 4

---

## Phase 4 -- Doom Config Wiring

Plug `org-brain.el` cleanly into your existing Doom setup.

- [ ] Load `org-brain.el` from `config.el` via `(load! "org-brain")`
- [ ] Bind `org-brain-query` under Doom's notes prefix:
  - `SPC n q` -- query your second brain
- [ ] Local bindings inside `*org-brain*` buffer:
  - `q` -- quit/close buffer
  - `r` -- re-run last query
  - `y` -- yank full response to clipboard
  - `RET` -- follow org-link citation (already native)

---

## Phase 5 -- UX Polish (Optional)

- [ ] Show a "Querying your second brain..." message in the minibuffer while
      waiting for Haiku to respond
- [ ] Persist last N queries as a ring buffer, accessible via `SPC n Q`
      (query history picker via Consult/Vertico)
- [ ] `org-brain-query-at-point` -- uses the heading or word at cursor as the
      query, bound to `SPC n w`
- [ ] Prepend a timestamp + query string as a header in the `*org-brain*`
      buffer so you can track what you asked

---

## File Layout

~/.config/doom/
├── config.el # add (load! "org-brain") here
├── packages.el # likely no new packages needed
└── org-brain.el # all implementation lives here

~/.config/fish/functions/
└── orq.fish # CLI fallback, also used for manual testing

---

## Key Technical Decisions (Resolved)

| Decision               | Choice                                      |
| ---------------------- | ------------------------------------------- |
| Output format          | org-mode (enables native clickable links)   |
| Citation style         | `[[file:abs/path][* Heading]]` inline       |
| Emacs subprocess model | Async via `make-process` (non-blocking)     |
| Doom elisp loading     | Flat file `org-brain.el` + `(load!)`        |
| Scope of file scan     | Configurable var, defaults to all org files |
