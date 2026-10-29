#!/usr/bin/env python3
"""pipeline-ab, multi-session mode: one project grows through features F1..Fn, each in new sessions.

The owner (simulator) gets a fresh session per feature and holds only that feature's notes; decisions
"for later" are voiced once in an early feature and never repeated. They reach later features only
through what the agent wrote down. Arms:

  S   interview -> SPEC.md -> build in the same session (the measured single-session default)
  K   S + the lab's light knowledge rules in CLAUDE.md (GLOSSARY.md on first use, ADR for decisions)
  PL  Pocock long-project flow: /grill-with-docs -> /to-spec -> /to-tickets (one context), then
      /implement per ticket in a fresh session; plugin without tdd and implement-spec
  N   the kit's root CLAUDE.md (template of KIT_COMMIT, filled as in the N/C stand); per feature the
      operator types the brief and nothing else

  drive_long.py --task L1 --arm PL --rep 1
"""
import argparse
import json
import os
import pathlib
import shutil
import subprocess
import time
import uuid

import drive
from drive import HERE, KIT_COMMIT, KIT_REPO, POCOCK_COMMIT, POCOCK_REPO, WORK, Run, deliver, git

TASKS_LONG = HERE / "tasks-long"
RESULTS = pathlib.Path(os.environ.get("PAB_RESULTS", HERE / "results-long"))

K_CLAUDE = """# CLAUDE.md

## Project knowledge

- Domain terms live in `GLOSSARY.md`: add a term the first time it is used or settled.
- Decisions that are hard to reverse, or that later work must follow — including ones the owner
  states "for later" — live in `docs/adr/NNNN-<slug>.md` (Context / Decision / Consequences).
- Read `GLOSSARY.md` and `docs/adr/` before starting new work.
"""


class LongRun(Run):
    def __init__(self, task, arm, rep):
        self.task, self.arm, self.rep = task, arm, rep
        self.tdir = TASKS_LONG / task
        self.name = f"{arm}-{rep}"
        self.out = RESULTS / task / self.name
        self.root = WORK / f"{task}-{self.name}"
        self.ws = self.root / "ws"
        self.features = sorted(p for p in (self.tdir / "features").iterdir() if p.is_dir())
        self.brief = self.notes = ""
        self.calls = 0
        self.transcript = []
        self.usersim_file = "USERSIM-long.md"
        self.fid = "setup"
        self.user_session = None
        self.meta = {"task": task, "arm": arm, "rep": rep, "mode": "long", "model": drive.MODEL,
                     "effort": drive.EFFORT, "user_model": drive.USER_MODEL, "user_mode": drive.USER_MODE,
                     "pocock_commit": POCOCK_COMMIT if arm == "PL" else None,
                     "kit_commit": KIT_COMMIT if arm == "N" else None, "stages": [], "errors": [],
                     "features": []}

    def setup(self):
        shutil.rmtree(self.root, ignore_errors=True)
        shutil.rmtree(self.out, ignore_errors=True)
        (self.out / "calls").mkdir(parents=True)
        self.root.mkdir(parents=True)
        shutil.copytree(self.tdir / "repo", self.ws)
        self.plugin = None
        if self.arm == "PL":
            self.plugin = WORK / f"pocock-{POCOCK_COMMIT}-long"
            if not self.plugin.exists():
                tmp = WORK / f"pocock-long.tmp-{os.getpid()}"
                tmp.mkdir(parents=True)
                tar = subprocess.run(["git", "-C", str(POCOCK_REPO), "archive", POCOCK_COMMIT],
                                     capture_output=True, check=True).stdout
                subprocess.run(["tar", "-x", "-C", str(tmp)], input=tar, check=True)
                manifest = tmp / ".claude-plugin/plugin.json"
                m = json.loads(manifest.read_text())
                # the long-project setup the lab recommends: no tdd (operator decision), no fan-out
                m["skills"] = [s for s in m["skills"] if not s.endswith(("/tdd", "/implement-spec"))]
                manifest.write_text(json.dumps(m, indent=2))
                try:
                    tmp.rename(self.plugin)
                except OSError:
                    shutil.rmtree(tmp, ignore_errors=True)
            self.apply_pocock_setup()
        if self.arm == "K":
            (self.ws / "CLAUDE.md").write_text(K_CLAUDE)
        if self.arm == "N":
            kit = WORK / f"harness-{KIT_COMMIT}"
            if not kit.exists():
                tmp = WORK / f"harness-{KIT_COMMIT}.tmp-{os.getpid()}"
                tmp.mkdir(parents=True)
                tar = subprocess.run(["git", "-C", str(KIT_REPO), "archive", KIT_COMMIT, "plugins/harness"],
                                     capture_output=True, check=True).stdout
                subprocess.run(["tar", "-x", "-C", str(tmp)], input=tar, check=True)
                try:
                    tmp.rename(kit)
                except OSError:
                    shutil.rmtree(tmp, ignore_errors=True)
            self.write_kit_claude_md(kit / "plugins/harness/skills/harness/templates/CLAUDE.md")
        git(self.ws, "init", "-q", "-b", "main")
        git(self.ws, "add", "-A")
        git(self.ws, "commit", "-q", "-m", "base")
        self.base = git(self.ws, "rev-parse", "HEAD")
        # settings files exactly as the single-session driver writes them
        cfg = self.root / "cfg"
        cfg.mkdir()
        from drive import DENY_OUTSIDE, DEV_ALLOW, write_settings
        ws = f"/{self.ws}"
        no_write = lambda *dirs: [f"{t}({ws}/{d}/**)" for d in dirs for t in ("Edit", "Write")] + ["Bash(chmod:*)"]
        self.s_dev = write_settings(cfg / "dev.json", DEV_ALLOW, DENY_OUTSIDE)
        self.s_plan = write_settings(cfg / "plan.json", DEV_ALLOW, DENY_OUTSIDE + no_write("src", "tests"))
        self.s_user = write_settings(cfg / "user.json", ["Read", "Glob", "Grep"],
                                     DENY_OUTSIDE + ["Write", "Edit", "NotebookEdit", "Bash", "Agent", "Skill"])

    def claude(self, prompt, *, label, role="dev", **kw):
        if role == "user":
            label = f"{self.fid}:user"
        return super().claude(prompt, label=label, role=role, **kw)

    def commit_feature(self, fid):
        git(self.ws, "add", "-A", check=False)
        git(self.ws, "commit", "-q", "-m", f"feature {fid}", check=False)

    # ---------- one feature per arm ----------
    def feature_S(self, fid):
        s = str(uuid.uuid4())
        self.stage(f"{fid}:spec+build", f"{self.brief}\n\n{self.SPEC_PROMPT} Then build it. Done means the test suite "
                                        "passes and the spec's criteria are covered; report the command and its output.",
                   session=s, resume=False, settings=self.s_dev,
                   user_desc=deliver("Scope: the interview, SPEC.md, then the build. Answer the interview questions; "
                                     "when the developer reports the feature as built, answer done."))

    feature_K = feature_S

    def feature_N(self, fid):
        """The kit's CLAUDE.md is in the repo; the operator types the brief and nothing else."""
        self.stage(f"{fid}:build", self.brief, session=str(uuid.uuid4()), resume=False, settings=self.s_dev,
                   user_desc=deliver("Scope: the whole feature. You typed your request. When the developer "
                                     "reports the feature as built, answer done."))

    def feature_PL(self, fid):
        s1 = str(uuid.uuid4())
        before = set(p.name for p in self.ws.glob(".scratch/*"))
        self.guarded(f"{fid}:grill", ["src", "tests"], f"/grill-with-docs {self.brief}", session=s1, resume=False,
                     settings=self.s_plan,
                     user_desc="Scope: the interview only, no spec file, no tickets, no code. You started by typing "
                               "/grill-with-docs with your request; afterwards you will type /to-spec, /to-tickets and "
                               "then /implement per ticket yourself. When the developer has no more questions, or "
                               "suggests the next step, answer done.")
        self.guarded(f"{fid}:to-spec", ["src", "tests"], "/to-spec", session=s1, resume=True, settings=self.s_plan,
                     user_desc="Scope: the spec only, no tickets and no code. You typed /to-spec; next you will type "
                               "/to-tickets yourself. When the spec is published and nothing is asked of you, answer done.")
        self.guarded(f"{fid}:to-tickets", ["src", "tests"], "/to-tickets", session=s1, resume=True,
                     settings=self.s_plan,
                     user_desc="Scope: the tickets only, no code; you will run /implement per ticket later in fresh "
                               "sessions. When the tickets are written and nothing is asked of you, answer done.")
        new = [d for d in self.ws.glob(".scratch/*") if d.name not in before] or list(self.ws.glob(".scratch/*"))
        feat_dir = max(new, key=lambda d: d.stat().st_mtime) if new else None
        tickets = sorted(feat_dir.glob("issues/*.md")) if feat_dir else []
        self.meta["features"][-1]["tickets"] = len(tickets)
        for t in tickets:
            rel = str(t.relative_to(self.ws))
            self.stage(f"{fid}:implement:{t.stem[:2]}", f"/implement {rel}", session=str(uuid.uuid4()), resume=False,
                       settings=self.s_dev,
                       user_desc=deliver("Scope: implementing this one ticket. You typed /implement with the ticket "
                                         "path in a fresh session. When the developer reports it done, answer done."))
        if not tickets:  # the operator would not stop here: build the spec in one go
            self.stage(f"{fid}:implement", f"/implement {feat_dir.relative_to(self.ws) if feat_dir else '.scratch/'}",
                       session=str(uuid.uuid4()), resume=False, settings=self.s_dev,
                       user_desc=deliver("Scope: implementing the spec. When the developer reports it done, answer done."))

    def go(self):
        t0 = time.time()
        self.setup()
        try:
            for f in self.features:
                fid = self.fid = f.name
                self.brief = (f / "BRIEF.md").read_text().strip()
                self.notes = (f / "NOTES.md").read_text().strip()
                self.user_session = None  # a new owner session per feature: no memory of earlier talks
                c0, t1 = self.calls, time.time()
                self.meta["features"].append({"id": fid})
                getattr(self, f"feature_{self.arm}")(fid)
                self.commit_feature(fid)
                self.meta["features"][-1].update(calls=self.calls - c0, wall_s=round(time.time() - t1, 1),
                                                 head=git(self.ws, "rev-parse", "HEAD"))
        except Exception as e:
            self.meta["errors"].append({"exception": repr(e)})
        self.finish(t0)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--task", required=True)
    ap.add_argument("--arm", required=True, choices=["S", "K", "PL", "N"])
    ap.add_argument("--rep", required=True, type=int)
    a = ap.parse_args()
    LongRun(a.task, a.arm, a.rep).go()


if __name__ == "__main__":
    main()
