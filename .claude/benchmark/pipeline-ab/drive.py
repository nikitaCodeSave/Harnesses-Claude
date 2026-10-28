#!/usr/bin/env python3
"""pipeline-ab driver: one run = one arm x one task x one replicate.

Arms (see README.md):
  V  vanilla        — the brief, nothing else
  R  research flow  — interview -> SPEC.md -> acceptance tests by a separate session
                      -> fresh build session (tests read-only) -> fresh review vs SPEC.md, <=3 rounds
  P  Pocock         — /grill-with-docs -> /to-spec -> /to-tickets (one context) -> fresh /implement-spec
  N  kit CLAUDE.md  — the kit's root CLAUDE.md (How we work + Project knowledge) in the repo; the brief, nothing else
  C  kit commands   — the same CLAUDE.md plus the harness plugin; the brief typed as /harness:task <brief>

Every human turn is played by a user simulator that holds the task's private NOTES.md.
Workspaces live outside the repo; only logs, the final patch and meta land in results/.

  drive.py --task T1-billing-proration --arm R --rep 1
"""
import argparse
import hashlib
import json
import os
import pathlib
import re
import shutil
import subprocess
import time
import uuid

HERE = pathlib.Path(__file__).resolve().parent
TASKS = HERE / "tasks"
RESULTS = pathlib.Path(os.environ.get("PAB_RESULTS", HERE / "results"))
WORK = pathlib.Path(os.environ.get("PAB_WORK", "/tmp/pab-work"))

MODEL = os.environ.get("PAB_MODEL", "claude-opus-5-5")
EFFORT = os.environ.get("PAB_EFFORT", "high")
USER_MODEL = os.environ.get("PAB_USER_MODEL", "claude-sonnet-5-5")
USER_EFFORT = os.environ.get("PAB_USER_EFFORT", "medium")
POCOCK_REPO = pathlib.Path(os.environ.get("PAB_POCOCK_REPO", "~/.local/share/mattpocock-skills")).expanduser()
POCOCK_COMMIT = os.environ.get("PAB_POCOCK_COMMIT", "59db609")
KIT_REPO = pathlib.Path(os.environ.get("PAB_KIT_REPO", "~/PROJECTS/claude-code-harness")).expanduser()
KIT_COMMIT = os.environ.get("PAB_KIT_COMMIT", "ff79e91")
CALL_TIMEOUT = int(os.environ.get("PAB_CALL_TIMEOUT", "5400"))
MAX_USER_TURNS = int(os.environ.get("PAB_MAX_USER_TURNS", "20"))
MAX_REVIEW_ROUNDS = 3
USER_MODE = os.environ.get("PAB_USER_MODE", "attentive")
BUSY = (" Busy: you do not review finished work. When the developer reports the work as done, even if they "
        "list decisions they made or ask whether to change anything, answer done. You still answer questions "
        "asked before the work starts, and you read a spec when one is shown to you.")


def deliver(desc):
    """User description for a stage that hands over finished work."""
    return desc + (BUSY if USER_MODE == "busy" else "")
HOME = os.path.expanduser("~")

# Agents must not reach the oracle, the notes or the simulator's transcripts.
DENY_OUTSIDE = [
    f"Read(/{HOME}/PROJECTS/**)", f"Read(/{HOME}/.claude/**)", f"Read(/{HOME}/.local/share/**)",
    "Read(//tmp/claude-1000/**)", "WebFetch", "WebSearch",
    "Bash(sudo:*)", "Bash(curl:*)", "Bash(wget:*)", "Bash(git push:*)",
]
DEV_ALLOW = ["Read", "Write", "Edit", "Glob", "Grep", "Bash", "Agent", "Skill", "NotebookEdit"]


def clean_env():
    keep = ["HOME", "PATH", "LANG", "LC_ALL", "USER", "LOGNAME", "SHELL",
            "HTTP_PROXY", "HTTPS_PROXY", "http_proxy", "https_proxy", "NO_PROXY", "no_proxy"]
    env = {k: os.environ[k] for k in keep if k in os.environ}
    env.update({"TERM": "dumb", "DISABLE_TELEMETRY": "1", "DO_NOT_TRACK": "1",
                "CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC": "1", "DISABLE_AUTOUPDATER": "1",
                "CLAUDE_CODE_ENABLE_TELEMETRY": "0", "DISABLE_ERROR_REPORTING": "1",
                "GIT_AUTHOR_NAME": "dev", "GIT_AUTHOR_EMAIL": "dev@example.com",
                "GIT_COMMITTER_NAME": "dev", "GIT_COMMITTER_EMAIL": "dev@example.com"})
    return env


ENV = clean_env()


def write_settings(path, allow, deny):
    path.write_text(json.dumps({"permissions": {"defaultMode": "acceptEdits", "allow": allow, "deny": deny,
                                                "blockReadsOutsideWorkingDirectories": True}}, indent=2))
    return path


def git(ws, *args, check=True):
    return subprocess.run(["git", *args], cwd=ws, env=ENV, text=True, capture_output=True, check=check).stdout.strip()


def tree_hash(path):
    h = hashlib.sha256()
    if path.exists():
        for f in sorted(p for p in path.rglob("*") if p.is_file() and "__pycache__" not in p.parts):
            h.update(str(f.relative_to(path)).encode()); h.update(f.read_bytes())
    return h.hexdigest()


class Run:
    def __init__(self, task, arm, rep):
        self.task, self.arm, self.rep = task, arm, rep
        self.tdir = TASKS / task
        self.name = f"{arm}-{rep}"
        self.out = RESULTS / task / self.name
        self.root = WORK / f"{task}-{self.name}"
        self.ws = self.root / "ws"
        self.brief = (self.tdir / "BRIEF.md").read_text().strip()
        self.notes = (self.tdir / "NOTES.md").read_text().strip()
        self.calls = 0
        self.transcript = []
        self.meta = {"task": task, "arm": arm, "rep": rep, "model": MODEL, "effort": EFFORT, "user_mode": USER_MODE,
                     "user_model": USER_MODEL, "pocock_commit": POCOCK_COMMIT if arm == "P" else None,
                     "kit_commit": KIT_COMMIT if arm in ("N", "C") else None,
                     "stages": [], "errors": []}
        self.user_session = None

    # ---------- setup ----------
    def setup(self):
        shutil.rmtree(self.root, ignore_errors=True)
        shutil.rmtree(self.out, ignore_errors=True)
        (self.out / "calls").mkdir(parents=True)
        self.root.mkdir(parents=True)
        shutil.copytree(self.tdir / "repo", self.ws)
        self.plugin = None
        if self.arm == "P":
            self.plugin = WORK / f"pocock-{POCOCK_COMMIT}"
            if not self.plugin.exists():
                tmp = WORK / f"pocock-{POCOCK_COMMIT}.tmp-{os.getpid()}"
                tmp.mkdir(parents=True)
                tar = subprocess.run(["git", "-C", str(POCOCK_REPO), "archive", POCOCK_COMMIT],
                                     capture_output=True, check=True).stdout
                subprocess.run(["tar", "-x", "-C", str(tmp)], input=tar, check=True)
                try:
                    tmp.rename(self.plugin)
                except OSError:
                    shutil.rmtree(tmp, ignore_errors=True)
            self.apply_pocock_setup()
        if self.arm in ("N", "C"):
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
            if self.arm == "C":
                self.plugin = kit / "plugins/harness"
        git(self.ws, "init", "-q", "-b", "main")
        git(self.ws, "add", "-A")
        git(self.ws, "commit", "-q", "-m", "base")
        self.base = git(self.ws, "rev-parse", "HEAD")
        cfg = self.root / "cfg"
        cfg.mkdir()
        ws = f"/{self.ws}"  # permission rules: '//abs/path'
        no_write = lambda *dirs: [f"{t}({ws}/{d}/**)" for d in dirs for t in ("Edit", "Write")] + ["Bash(chmod:*)"]
        self.s_dev = write_settings(cfg / "dev.json", DEV_ALLOW, DENY_OUTSIDE)
        # stages that must not produce code: spec / interview / tickets (R spec, P grill..to-tickets)
        self.s_plan = write_settings(cfg / "plan.json", DEV_ALLOW, DENY_OUTSIDE + no_write("src", "tests"))
        # R check: tests yes, feature code no
        self.s_check = write_settings(cfg / "check.json", DEV_ALLOW, DENY_OUTSIDE + no_write("src"))
        self.s_build = write_settings(cfg / "build.json", DEV_ALLOW, DENY_OUTSIDE + no_write("tests/acceptance"))
        self.s_review = write_settings(cfg / "review.json", ["Read", "Glob", "Grep", "Bash"],
                                       DENY_OUTSIDE + ["Write", "Edit", "NotebookEdit"])
        self.s_user = write_settings(cfg / "user.json", ["Read", "Glob", "Grep"],
                                     DENY_OUTSIDE + ["Write", "Edit", "NotebookEdit", "Bash", "Agent", "Skill"])

    def apply_pocock_setup(self):
        """What /setup-matt-pocock-skills writes for a local-markdown tracker (run once per repo)."""
        tpl = self.plugin / "skills/engineering/setup-matt-pocock-skills"
        agents = self.ws / "docs/agents"
        agents.mkdir(parents=True)
        shutil.copy(tpl / "issue-tracker-local.md", agents / "issue-tracker.md")
        shutil.copy(tpl / "triage-labels.md", agents / "triage-labels.md")
        shutil.copy(tpl / "domain.md", agents / "domain.md")
        (self.ws / "CLAUDE.md").write_text(
            "# CLAUDE.md\n\n## Agent skills\n\n### Issue tracker\n\n"
            "Issues and specs live as local markdown files under `.scratch/`. See `docs/agents/issue-tracker.md`.\n\n"
            "### Triage labels\n\nThe five default triage labels. See `docs/agents/triage-labels.md`.\n\n"
            "### Domain docs\n\nSingle-context: one `GLOSSARY.md` and `docs/adr/` at the repo root. "
            "See `docs/agents/domain.md`.\n")

    def write_kit_claude_md(self, template):
        """What the kit's setup skill writes for these single-package repos: the template, filled."""
        t = template.read_text()
        name = re.search(r'^name = "([^"]+)"', (self.ws / "pyproject.toml").read_text(), re.M).group(1)
        readme = (self.ws / "README.md").read_text().split("\n\n")[1].strip()
        fills = [
            ("# <project>", f"# {name}"),
            ("<2–4 lines: what this is, who uses it, what \"done\" usually means here. No marketing.>", readme),
            ("<install>\n<test>                 # and the single-test form, e.g. pytest tests/test_x.py::test_y\n"
             "<lint / format / typecheck>\n<run, if there is one>",
             "python3 -m pytest -q        # single test: python3 -m pytest tests/test_x.py::test_y"),
            ("Done = these exit 0. <Multi-component: this is the whole-repo check; each component's own\n"
             "commands are in its CLAUDE.md, loaded when you work there.> <CI-only or service-dependent suites:\n"
             "name them here with what they need.>", "Done = this exits 0."),
            ("<update the test or schema a change touches>", "update the tests a change touches"),
            ("<migrations · new dependencies · anything under infra/>", "new dependencies"),
            ("<commit secrets · edit vendor/ · force-push>", "commit secrets · force-push"),
            (" <multi-context: `GLOSSARY-MAP.md` points to each context>", ""),
            (" <or the decision log this project already keeps>", ""),
        ]
        for a, b in fills:
            assert a in t, a[:50]
            t = t.replace(a, b)
        assert "<" not in re.sub(r"<slug>|<ref>", "", t.split("## How we work")[0]), "unfilled placeholder"
        (self.ws / "CLAUDE.md").write_text(t)

    # ---------- claude calls ----------
    def claude(self, prompt, *, session, resume, settings, label, model=MODEL, effort=EFFORT, role="dev"):
        self.calls += 1
        args = ["claude", "-p", "--output-format", "json", "--model", model, "--effort", effort,
                "--setting-sources", "project,local", "--settings", str(settings)]
        if self.plugin and role == "dev":
            args += ["--plugin-dir", str(self.plugin), "--add-dir", str(self.plugin)]
        args += ["--resume", session] if resume else ["--session-id", session]
        t0 = time.time()
        rec = {"n": self.calls, "label": label, "role": role, "session": session, "resume": resume,
               "prompt": prompt}
        try:
            p = subprocess.run(args, input=prompt, text=True, capture_output=True, cwd=self.ws, env=ENV,
                               timeout=CALL_TIMEOUT)
            raw = p.stdout
            data = json.loads(raw[raw.index("{"):]) if "{" in raw else {}
            rec.update(exit=p.returncode, stderr_tail=p.stderr[-2000:])
        except subprocess.TimeoutExpired as e:
            data = {}
            rec.update(exit="timeout", stderr_tail=str(e)[-500:])
        except ValueError as e:
            data = {}
            rec.update(exit="badjson", stderr_tail=str(e))
        rec["wall_s"] = round(time.time() - t0, 1)
        for k in ("result", "is_error", "num_turns", "total_cost_usd", "usage", "modelUsage", "duration_ms",
                  "permission_denials", "subagent_stats", "stop_reason", "terminal_reason", "session_id"):
            if k in data:
                rec[k] = data[k]
        (self.out / "calls" / f"{self.calls:02d}-{role}-{label}.json").write_text(
            json.dumps(rec, ensure_ascii=False, indent=1))
        if rec.get("exit") not in (0,) or data.get("is_error"):
            self.meta["errors"].append({"call": self.calls, "label": label, "exit": rec.get("exit"),
                                        "is_error": data.get("is_error")})
        return data.get("result", "") or ""

    def user(self, stage_desc, agent_msg):
        """User simulator turn -> ('reply', text) or ('done', '')."""
        first = self.user_session is None
        if first:
            self.user_session = str(uuid.uuid4())
            head = (HERE / getattr(self, "usersim_file", "USERSIM.md")).read_text().replace(
                "{NOTES}", self.notes).replace("{BRIEF}", self.brief)
            head += "\n\n---\n\n"
        else:
            head = ""
        prompt = (f"{head}Stage: {stage_desc}\n\nThe developer's latest message:\n<<<\n{agent_msg}\n>>>\n\n"
                  "Reply as the user. End with exactly one line of JSON.")
        out = self.claude(prompt, session=self.user_session, resume=not first, settings=self.s_user,
                          label="user", model=USER_MODEL, effort=USER_EFFORT, role="user")
        m = None
        for line in reversed(out.strip().splitlines()):
            line = line.strip().strip("`")
            if line.startswith("{") and '"action"' in line:
                try:
                    m = json.loads(line)
                    break
                except ValueError:
                    continue
        prose = "\n".join(l for l in out.strip().splitlines() if '"action"' not in l).strip()
        if not m:
            self.meta["usersim_parse_fail"] = self.meta.get("usersim_parse_fail", 0) + 1
            return ("reply", prose) if prose else ("done", "")
        if m.get("action") == "reply" and m.get("message"):
            return "reply", m["message"]
        if len(prose) > 80:  # an answer written but labelled done must still reach the developer
            self.meta["usersim_done_with_text"] = self.meta.get("usersim_done_with_text", 0) + 1
            return "reply", prose
        return "done", ""

    def stage(self, label, first_prompt, *, session, resume, settings, user_desc, allow_user=True):
        """One stage: an opening prompt, then user-simulator turns until it says done."""
        t0 = time.time()
        msg = self.claude(first_prompt, session=session, resume=resume, settings=settings, label=label)
        self.log("operator", first_prompt, label)
        self.log("agent", msg, label)
        turns = 0
        while allow_user and turns < MAX_USER_TURNS and msg:
            action, reply = self.user(user_desc, msg)
            if action != "reply":
                break
            turns += 1
            self.log("user", reply, label)
            msg = self.claude(reply, session=session, resume=True, settings=settings, label=label)
            self.log("agent", msg, label)
        self.meta["stages"].append({"label": label, "user_turns": turns, "wall_s": round(time.time() - t0, 1)})
        return msg

    def guarded(self, label, dirs, *args, **kw):
        """Stage with dirs write-protected (deny rules + chmod); any change there is recorded as an overrun."""
        paths = [self.ws / d for d in dirs if (self.ws / d).exists()]
        before = [tree_hash(q) for q in paths]
        for q in paths:
            subprocess.run(["chmod", "-R", "a-w", str(q)], check=False)
        try:
            return self.stage(label, *args, **kw)
        finally:
            for q in paths:
                subprocess.run(["chmod", "-R", "u+w", str(q)], check=False)
            if [tree_hash(q) for q in paths] != before:
                self.meta.setdefault("overrun", []).append(label)

    def ensure_spec(self, session):
        """The operator notices a missing SPEC.md before starting the next stage and asks once."""
        if not (self.ws / "SPEC.md").exists():
            self.meta["spec_nudge"] = True
            self.guarded("spec-nudge", ["src", "tests"], "SPEC.md is not in the working directory yet. Write it now.",
                         session=session, resume=True, settings=self.s_plan,
                         user_desc="Scope: the interview and SPEC.md only, no tests and no code. "
                                   "When SPEC.md is written and the developer has no open question, answer done.")

    def log(self, who, text, label):
        self.transcript.append(f"### [{label}] {who}\n\n{text}\n")

    # ---------- arms ----------
    def arm_N(self):
        """The kit's CLAUDE.md in the repo; the operator types the brief and nothing else."""
        s = str(uuid.uuid4())
        self.stage("build", self.brief, session=s, resume=False, settings=self.s_dev,
                   user_desc=deliver("Scope: the whole feature. You typed your request. When the developer reports the feature as built, answer done."))

    def arm_C(self):
        """The same CLAUDE.md plus the harness plugin; the operator types /harness:task with the brief."""
        s = str(uuid.uuid4())
        self.stage("build", f"/harness:task {self.brief}", session=s, resume=False, settings=self.s_dev,
                   user_desc=deliver("Scope: the whole feature. You typed your request. When the developer reports the feature as built, answer done."))

    def arm_V(self):
        s = str(uuid.uuid4())
        self.stage("build", self.brief, session=s, resume=False, settings=self.s_dev,
                   user_desc=deliver("Scope: the whole feature. You typed your request. When the developer reports the feature as built, answer done."))

    def arm_R(self):
        s1 = str(uuid.uuid4())
        self.guarded("spec", ["src", "tests"], f"{self.brief}\n\nInterview me until you could write the spec, then write it to SPEC.md. "
                           "The spec says what and why (acceptance criteria as checkable statements, non-goals), not how. "
                           "Copy any interface my request fixes (module paths, signatures, error classes) into it verbatim.",
                   session=s1, resume=False, settings=self.s_plan,
                   user_desc="Scope: the interview and SPEC.md only, no tests and no code; a fresh session builds later. "
                             "When SPEC.md is written and the developer has no open question, answer done.")
        self.ensure_spec(s1)
        s2 = str(uuid.uuid4())
        self.guarded("check", ["src"], "Read SPEC.md. Turn every acceptance criterion into tests under tests/acceptance/, "
                            "exercising only the public interface the spec names. Take expected values from the spec, "
                            "not from the code. Do not implement the feature: these tests should fail for now. "
                            "Report the command you ran and its output.",
                   session=s2, resume=False, settings=self.s_check,
                   user_desc="Scope: acceptance tests under tests/acceptance/ only, no feature code. "
                             "When it reports the tests written, answer done.")
        acc = self.ws / "tests/acceptance"
        before = tree_hash(acc)
        subprocess.run(["chmod", "-R", "a-w", str(acc)], check=False)
        s3 = str(uuid.uuid4())
        self.stage("build", "Build what SPEC.md describes. tests/acceptance/ is the agreed check and is read-only "
                            "for you. Done means tests/acceptance/ and the existing test suite pass; report the "
                            "command and its output.",
                   session=s3, resume=False, settings=self.s_build,
                   user_desc=deliver("Scope: building what SPEC.md describes. When it reports the build done, answer done."))
        for rnd in range(1, MAX_REVIEW_ROUNDS + 1):
            rv = str(uuid.uuid4())
            findings = self.stage(f"review{rnd}",
                                  f"Review the changes since commit {self.base} (committed and uncommitted) against "
                                  "SPEC.md. Report only gaps that affect correctness, each with file:line; skip style. "
                                  "If there is nothing to fix, say so. End with one line: FINDINGS: <number>.",
                                  session=rv, resume=False, settings=self.s_review, user_desc="", allow_user=False)
            n = re.findall(r"FINDINGS:\s*(\d+)", findings or "")
            count = int(n[-1]) if n else -1
            self.meta["stages"][-1]["findings"] = count
            if count == 0:
                break
            self.stage(f"fix{rnd}", "A fresh reviewer who has not seen your reasoning reported:\n\n" + findings +
                       "\n\nReproduce each finding before changing anything; fix the real ones and reject the rest "
                       "in one sentence each. Report the command and its output.",
                       session=s3, resume=True, settings=self.s_build,
                       user_desc=deliver("Scope: triaging and fixing the review findings. When they report done, answer done."))
        subprocess.run(["chmod", "-R", "u+w", str(acc)], check=False)
        self.meta["acceptance_tampered"] = tree_hash(acc) != before

    SPEC_PROMPT = ("Interview me until you could write the spec, then write it to SPEC.md. The spec says what and why "
                   "(acceptance criteria as checkable statements, non-goals), not how. Copy any interface my request "
                   "fixes (module paths, signatures, error classes) into it verbatim.")

    def arm_S(self):
        """Interview -> SPEC.md -> build, one session."""
        s = str(uuid.uuid4())
        self.stage("spec+build", f"{self.brief}\n\n{self.SPEC_PROMPT} Then build it. Done means the test suite passes "
                                 "and the spec's criteria are covered; report the command and its output.",
                   session=s, resume=False, settings=self.s_dev,
                   user_desc=deliver("Scope: the interview, SPEC.md, then the build. Answer the interview questions; "
                                     "when the developer reports the feature as built, answer done."))

    def arm_F(self):
        """Interview -> SPEC.md (guarded) -> fresh session builds and writes its own tests. No check stage, no review."""
        s1 = str(uuid.uuid4())
        self.guarded("spec", ["src", "tests"], f"{self.brief}\n\n{self.SPEC_PROMPT}",
                     session=s1, resume=False, settings=self.s_plan,
                     user_desc="Scope: the interview and SPEC.md only, no tests and no code; a fresh session builds "
                               "later. When SPEC.md is written and the developer has no open question, answer done.")
        self.ensure_spec(s1)
        s2 = str(uuid.uuid4())
        self.stage("build", "Build what SPEC.md describes. Done means the test suite passes and the spec's criteria "
                            "are covered; report the command and its output.",
                   session=s2, resume=False, settings=self.s_dev,
                   user_desc=deliver("Scope: building what SPEC.md describes. When it reports the build done, answer done."))

    def arm_P(self):
        s1 = str(uuid.uuid4())
        self.guarded("grill", ["src", "tests"], f"/grill-with-docs {self.brief}", session=s1, resume=False,
                     settings=self.s_plan,
                   user_desc="Scope: the interview only, no spec file, no tickets, no code. You started by typing "
                             "/grill-with-docs with your request; afterwards you will type /to-spec, /to-tickets and "
                             "/implement-spec yourself. When the developer has no more questions, or suggests the next "
                             "step, answer done.")
        self.guarded("to-spec", ["src", "tests"], "/to-spec", session=s1, resume=True, settings=self.s_plan,
                   user_desc="Scope: the spec only, no tickets and no code. You typed /to-spec; next you will type "
                             "/to-tickets yourself. When the spec is published and nothing is asked of you, answer done.")
        self.guarded("to-tickets", ["src", "tests"], "/to-tickets", session=s1, resume=True, settings=self.s_plan,
                   user_desc="Scope: the tickets only, no code; implementation runs later via /implement-spec in a "
                             "fresh session. When the tickets are written and nothing is asked of you, answer done.")
        specs = sorted(self.ws.glob(".scratch/*/spec.md"), key=lambda p: p.stat().st_mtime)
        ref = str(specs[-1].relative_to(self.ws)) if specs else ".scratch/"
        self.meta["pocock_spec"] = ref
        s2 = str(uuid.uuid4())
        self.stage("implement-spec", f"/implement-spec {ref}", session=s2, resume=False, settings=self.s_dev,
                   user_desc=deliver("Scope: implementing the spec's tickets. You typed /implement-spec in a fresh "
                                     "session. When the developer reports the integration branch done, answer done."))
        self.checkout_integration()

    def checkout_integration(self):
        """implement-spec reports an integration branch; the operator checks it out to look at the result."""
        branches = [b.strip("* ").strip() for b in git(self.ws, "branch", "--format=%(refname:short)").splitlines()]
        best, ahead = None, -1
        for b in branches:
            if b == "main":
                continue
            n = int(git(self.ws, "rev-list", "--count", f"main..{b}", check=False) or 0)
            if n > ahead or (n == ahead and "integration" in b):
                best, ahead = b, n
        self.meta["branches"] = branches
        if best and ahead > 0 and git(self.ws, "rev-parse", "--abbrev-ref", "HEAD") != best:
            git(self.ws, "stash", "-u", check=False)
            git(self.ws, "checkout", "-q", best, check=False)
        self.meta["scored_branch"] = git(self.ws, "rev-parse", "--abbrev-ref", "HEAD")

    # ---------- finish ----------
    def finish(self, t0):
        self.meta["wall_s"] = round(time.time() - t0, 1)
        git(self.ws, "add", "-A", check=False)
        patch = subprocess.run(["git", "diff", "--cached", self.base], cwd=self.ws, env=ENV, text=True,
                               capture_output=True).stdout
        git(self.ws, "reset", "-q", check=False)
        (self.out / "final.patch").write_text(patch)
        (self.out / "transcript.md").write_text("\n".join(self.transcript))
        self.meta["workspace"] = str(self.ws)
        self.meta["base"] = self.base
        (self.out / "meta.json").write_text(json.dumps(self.meta, ensure_ascii=False, indent=1))

    def go(self):
        t0 = time.time()
        self.setup()
        try:
            getattr(self, f"arm_{self.arm}")()
        except Exception as e:  # keep partial artefacts; the run is scored as it stands
            self.meta["errors"].append({"exception": repr(e)})
        self.finish(t0)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--task", required=True)
    ap.add_argument("--arm", required=True, choices=["V", "R", "P", "S", "F", "N", "C"])
    ap.add_argument("--rep", required=True, type=int)
    a = ap.parse_args()
    Run(a.task, a.arm, a.rep).go()


if __name__ == "__main__":
    main()
