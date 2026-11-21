#!/usr/bin/env python3
import sys
import os
import json
import re
import datetime
import fcntl

STATE_DIR = os.path.expanduser("~/.local/state/omarchy/dagyr.desktop-widgets")
DATA_FILE = os.path.join(STATE_DIR, "notes.json")
MD_FILE = os.path.join(STATE_DIR, "notes.md")

DEFAULT_DATA = {
    "todos": [
        {"id": 1, "text": "Set up desktop widgets repository", "done": True, "tag": "#work"},
        {"id": 2, "text": "Build QuickNotesWidget proof of concept", "done": False, "tag": "#todo"},
        {"id": 3, "text": "Test custom widget import pipeline", "done": False, "tag": "#idea"},
        {"id": 4, "text": "Design Circular Pomodoro Timer", "done": False, "tag": "#idea"}
    ],
    "scratchpad": "# Desktop Scratchpad\n\nQuick notes synced to markdown.\n- High-performance Omarchy UI\n- Quickshell QML & Hyprland\n",
    "commands": [
        {"id": 1, "name": "Restart Shell", "cmd": "omarchy-restart-shell", "desc": "Reload Quickshell desktop environment"},
        {"id": 2, "name": "Git Status", "cmd": "git status", "desc": "Inspect current repository status"},
        {"id": 3, "name": "System Info", "cmd": "fastfetch", "desc": "Show system and hardware overview"}
    ]
}

DEFAULT_TAGS = [
    {"name": "#todo", "color": "foreground"},
    {"name": "#work", "color": "accent"},
    {"name": "#idea", "color": "#ffcc40"},
    {"name": "#bug", "color": "urgent"}
]

def clean_tag_name(raw):
    """#word form: no whitespace (it would split the tag in Markdown), one
    leading #, at most 32 characters."""
    name = re.sub(r"\s+", "-", str(raw).strip()).lstrip("#")[:31]
    return ("#" + name) if name else ""

def clean_tags(raw):
    """Keep only well-formed {name, color} entries with unique names."""
    out, seen = [], set()
    if not isinstance(raw, list):
        return out
    for t in raw:
        if not isinstance(t, dict):
            continue
        name = clean_tag_name(t.get("name", ""))
        if not name:
            continue
        if name in seen:
            continue
        color = str(t.get("color", "accent")).strip()[:16]
        if color not in ("accent", "urgent", "foreground") and not re.fullmatch(r"#[0-9a-fA-F]{6}", color):
            color = "accent"
        seen.add(name)
        out.append({"name": name, "color": color})
    return out

DEFAULT_LOGGING = {
    "obsidian_enabled": False,
    "obsidian_folder": "~/Documents/Obsidian/Timeline/Timeline",
    "event_log_enabled": False
}
TASKS_NOTE = "Quick Notes Tasks.md"
LOG_NOTE = "Quick Notes Log.md"
EVENT_LOG = os.path.join(STATE_DIR, "tasks.log")   # fallback when no folder is set

def clean_logging(raw):
    out = dict(DEFAULT_LOGGING)
    if isinstance(raw, dict):
        out["obsidian_enabled"] = bool(raw.get("obsidian_enabled", False))
        out["event_log_enabled"] = bool(raw.get("event_log_enabled", False))
        folder = str(raw.get("obsidian_folder", "")).strip()[:512]
        if folder and "\n" not in folder:
            out["obsidian_folder"] = folder.rstrip("/") or "/"
    return out

def obsidian_folder(cfg):
    return os.path.expanduser(cfg.get("obsidian_folder", "")) if cfg.get("obsidian_folder") else ""

def today():
    return datetime.date.today().isoformat()

# Marks the note as ours (frontmatter, shown by Obsidian as a property); the
# old H1 is still accepted so notes written before this change keep syncing.
TASKS_NOTE_FRONTMATTER = "---\nsource: omarchy-quick-notes\n---\n"
TASKS_NOTE_HEADER = "# Quick Notes Tasks"
TASK_LINE_RE = re.compile(r"^\s*[-*+]\s+\[(.)\]\s*(.*)$")
# Obsidian Tasks field markers; a field is the marker plus its value
FIELD_RE = re.compile(r"\s*(➕|✅|🆔|📅|⏳|🛫|🔁|❌|⏫|🔼|🔽|🔺|⏬)\s*(\S+)")

def task_line(t):
    """One task in the Obsidian Tasks dialect. The 🆔 ties the line back to
    the task so edits made in Obsidian can be matched up again."""
    mark = "x" if t.get("done") else " "
    line = f"- [{mark}] {t.get('text', '')}"
    if t.get("tag"):
        line += f" {t['tag']}"
    if t.get("created"):
        line += f" ➕ {t['created']}"
    if t.get("done") and t.get("completed"):
        line += f" ✅ {t['completed']}"
    line += f" 🆔 {t.get('id')}"
    return line

def render_obsidian(data):
    lines = [TASKS_NOTE_FRONTMATTER, "\n"]
    for t in data.get("todos", []):
        lines.append(task_line(t) + "\n")
    return "".join(lines)

def obsidian_note_path(data):
    cfg = clean_logging(data.get("logging"))
    if not cfg["obsidian_enabled"]:
        return ""
    folder = obsidian_folder(cfg)
    return os.path.join(folder, TASKS_NOTE) if folder else ""

def write_obsidian(data):
    """Rewrite the task note, only when its content would change, so the
    widget's file watcher is not poked for nothing."""
    path = obsidian_note_path(data)
    if not path:
        return
    try:
        content = render_obsidian(data)
        if os.path.exists(path):
            with open(path, "r", encoding="utf-8") as f:
                if f.read() == content:
                    return
        os.makedirs(os.path.dirname(path), exist_ok=True)
        tmp = path + ".tmp"
        with open(tmp, "w", encoding="utf-8") as f:
            f.write(content)
        os.replace(tmp, path)
    except Exception as e:
        sys.stderr.write(f"Error writing Obsidian tasks: {e}\n")

def parse_task_line(line, known_tags):
    """-> {id|None, text, tag, done, created, completed} or None."""
    m = TASK_LINE_RE.match(line)
    if not m:
        return None
    done = m.group(1).strip().lower() in ("x", "✓")
    body = m.group(2).strip()
    fields = {}
    def take(fm):
        fields.setdefault(fm.group(1), fm.group(2))
        return ""
    body = FIELD_RE.sub(take, body).strip()
    tag = ""
    tm = re.search(r"(?:^|\s)(#[^\s#]+)$", body)
    if tm:
        tag = tm.group(1)
        body = body[:tm.start()].strip()
    elif known_tags:
        # a tag anywhere in the line, if it is one of ours
        for kt in known_tags:
            if re.search(r"(?:^|\s)" + re.escape(kt) + r"(?=\s|$)", body):
                tag = kt
                body = re.sub(r"\s*" + re.escape(kt) + r"(?=\s|$)", "", body).strip()
                break
    todo_id = None
    if "🆔" in fields and fields["🆔"].isdigit():
        todo_id = int(fields["🆔"])
    def date_or_none(v):
        return v if v and re.fullmatch(r"\d{4}-\d{2}-\d{2}", v) else None
    return {
        "id": todo_id,
        "text": body,
        "tag": tag,
        "done": done,
        "created": date_or_none(fields.get("➕")),
        "completed": date_or_none(fields.get("✅")),
    }

def import_obsidian(data):
    """Read the task note back: ticks, edits, new lines and removed lines made
    in Obsidian are applied to the todos. Returns True when anything changed."""
    path = obsidian_note_path(data)
    if not path or not os.path.exists(path):
        return False
    try:
        with open(path, "r", encoding="utf-8") as f:
            content = f.read()
    except Exception:
        return False
    if "source: omarchy-quick-notes" not in content and TASKS_NOTE_HEADER not in content:
        # Not our note (or half written): never wipe the list on that basis.
        return False

    tags = clean_tags(data.get("tags")) or list(DEFAULT_TAGS)
    known = [t["name"] for t in tags]
    parsed = []
    for line in content.splitlines():
        pt = parse_task_line(line, known)
        if pt and (pt["text"] or pt["id"] is not None):
            parsed.append(pt)

    todos = data.get("todos", [])
    by_id = {t.get("id"): t for t in todos}
    next_id = max([t.get("id", 0) for t in todos], default=0) + 1
    seen = set()
    new_list = []
    changed = False
    src = "from Obsidian"

    for pt in parsed:
        t = by_id.get(pt["id"]) if pt["id"] is not None else None
        if t is not None and pt["id"] not in seen:
            seen.add(pt["id"])
            if pt["text"] and pt["text"] != t.get("text", ""):
                log_event(data, "edited", {**t, "text": pt["text"]}, "was " + json.dumps(t.get("text", ""), ensure_ascii=False) + ", " + src)
                t["text"] = pt["text"]
                changed = True
            if pt["tag"] and pt["tag"] != t.get("tag", ""):
                log_event(data, "retagged", {**t, "tag": pt["tag"]}, "was " + t.get("tag", "") + ", " + src)
                t["tag"] = pt["tag"]
                changed = True
            if pt["done"] != bool(t.get("done")):
                t["done"] = pt["done"]
                if pt["done"]:
                    t["completed"] = pt["completed"] or today()
                else:
                    t.pop("completed", None)
                log_event(data, "done" if pt["done"] else "reopened", t, src)
                changed = True
            elif pt["done"] and pt["completed"] and pt["completed"] != t.get("completed"):
                t["completed"] = pt["completed"]
                changed = True
            if pt["created"] and pt["created"] != t.get("created"):
                t["created"] = pt["created"]
                changed = True
            new_list.append(t)
        elif pt["text"]:
            t = {"id": next_id, "text": pt["text"], "done": pt["done"], "tag": pt["tag"] or (known[0] if known else ""), "created": pt["created"] or today()}
            if pt["done"]:
                t["completed"] = pt["completed"] or today()
            next_id += 1
            seen.add(t["id"])
            new_list.append(t)
            log_event(data, "added", t, src)
            changed = True

    for t in todos:
        if t.get("id") not in seen:
            log_event(data, "deleted", t, src)
            changed = True

    if [t.get("id") for t in new_list] != [t.get("id") for t in todos]:
        changed = True

    # Tags typed in Obsidian that we do not know yet get added, accent coloured
    for t in new_list:
        if t.get("tag") and t["tag"] not in known:
            cleaned = clean_tag_name(t["tag"])
            t["tag"] = cleaned
            if cleaned and cleaned not in known:
                tags.append({"name": cleaned, "color": "accent"})
                known.append(cleaned)
                changed = True

    if changed:
        data["todos"] = new_list
        data["tags"] = tags
    return changed

def log_event(data, kind, todo, extra=""):
    """Append-only audit line per change, when enabled. With an Obsidian
    folder set it goes into a Markdown note there under a heading per day;
    otherwise into the plain tasks.log in the state directory."""
    cfg = clean_logging(data.get("logging"))
    if not cfg["event_log_enabled"]:
        return
    try:
        now = datetime.datetime.now()
        text = json.dumps(todo.get("text", ""), ensure_ascii=False)
        tag = todo.get("tag", "")
        suffix = f" ({extra})" if extra else ""
        folder = obsidian_folder(cfg)
        if folder:
            os.makedirs(folder, exist_ok=True)
            path = os.path.join(folder, LOG_NOTE)
            day = now.strftime("%Y-%m-%d")
            existing = ""
            if os.path.exists(path):
                with open(path, "r", encoding="utf-8") as f:
                    existing = f.read()
            with open(path, "a", encoding="utf-8") as f:
                if f"\n## {day}\n" not in existing and not existing.startswith(f"## {day}\n") and not existing.endswith(f"## {day}\n"):
                    f.write(("\n" if existing else "") + f"## {day}\n")
                f.write(f"- {now.strftime('%H:%M')} {kind} {text} {tag}{suffix}\n")
        else:
            os.makedirs(STATE_DIR, exist_ok=True)
            with open(EVENT_LOG, "a", encoding="utf-8") as f:
                f.write(f"{now.isoformat(timespec='seconds')} {kind} id={todo.get('id')} {text} {tag}{suffix}\n")
    except Exception:
        pass

def load_data():
    os.makedirs(STATE_DIR, exist_ok=True)
    if os.path.exists(DATA_FILE):
        try:
            with open(DATA_FILE, "r", encoding="utf-8") as f:
                data = json.load(f)
                if "todos" not in data: data["todos"] = DEFAULT_DATA["todos"]
                if "scratchpad" not in data: data["scratchpad"] = DEFAULT_DATA["scratchpad"]
                if "commands" not in data: data["commands"] = DEFAULT_DATA["commands"]
                if not clean_tags(data.get("tags")): data["tags"] = list(DEFAULT_TAGS)
                
                # Ensure all commands have an ID
                needs_save = False
                cmds = data.get("commands", [])
                max_id = 0
                for c in cmds:
                    if isinstance(c.get("id"), int) and c["id"] > max_id:
                        max_id = c["id"]
                for c in cmds:
                    if "id" not in c or not isinstance(c.get("id"), int):
                        max_id += 1
                        c["id"] = max_id
                        needs_save = True
                data["commands"] = cmds
                if needs_save:
                    save_data(data)
                return data
        except Exception:
            pass
    # Legacy migration check
    legacy_file = os.path.join(os.path.dirname(os.path.abspath(__file__)), "notes.json")
    if os.path.exists(legacy_file):
        try:
            with open(legacy_file, "r", encoding="utf-8") as f:
                data = json.load(f)
                save_data(data)
                return data
        except Exception:
            pass
    save_data(DEFAULT_DATA)
    return DEFAULT_DATA

def sync_markdown(data):
    try:
        os.makedirs(STATE_DIR, exist_ok=True)
        lines = ["# Quick Notes & Tasks\n", "## Tasks\n"]
        for t in data.get("todos", []):
            mark = "x" if t.get("done") else " "
            tag = f" `{t.get('tag')}`" if t.get("tag") else ""
            lines.append(f"- [{mark}] {t.get('text', '')}{tag}\n")
        lines.append("\n## Scratchpad\n\n")
        lines.append(data.get("scratchpad", ""))
        lines.append("\n")
        lines.append("\n## Snippets\n\n")
        for c in data.get("commands", []):
            lines.append(f"- **{c.get('name', '')}**: `{c.get('cmd', '')}`\n")
        with open(MD_FILE, "w", encoding="utf-8") as f:
            f.writelines(lines)
    except Exception:
        pass

def save_data(data):
    try:
        os.makedirs(STATE_DIR, exist_ok=True)
        # Write to a temp file and rename so a killed process can never leave
        # a half-written notes.json behind.
        tmp = DATA_FILE + ".tmp"
        with open(tmp, "w", encoding="utf-8") as f:
            json.dump(data, f, indent=2, ensure_ascii=False)
            f.flush()
            os.fsync(f.fileno())
        os.replace(tmp, DATA_FILE)
        sync_markdown(data)
        write_obsidian(data)
    except Exception as e:
        sys.stderr.write(f"Error saving data: {e}\n")

# Actions that never touch todos skip the Obsidian import
DIALOG_FREE_ACTIONS = {"save_scratchpad", "add_command", "edit_command", "delete_command", "save_logging", "save_tags"}

LOCK_FILE = os.path.join(STATE_DIR, "notes.lock")

def main():
    action = sys.argv[1] if len(sys.argv) > 1 else "load"
    # The widget runs once per monitor and every copy drives this script, so
    # runs are serialized: the second copy then reloads the data the first one
    # just wrote and finds nothing left to do (no duplicate imports or log lines).
    os.makedirs(STATE_DIR, exist_ok=True)
    lock = open(LOCK_FILE, "w")
    fcntl.flock(lock, fcntl.LOCK_EX)
    data = load_data()

    # Two-way sync: pick up anything changed in the Obsidian note before
    # acting, so an action never overwrites an edit made there.
    if action in ("load", "import_obsidian") or action not in DIALOG_FREE_ACTIONS:
        if import_obsidian(data):
            save_data(data)
    if action == "import_obsidian":
        print(json.dumps({"status": "imported", "todos": data.get("todos", []), "tags": clean_tags(data.get("tags")) or DEFAULT_TAGS}))
        return

    if action == "add_todo" and len(sys.argv) >= 3:
        text = sys.argv[2].strip()
        tag = sys.argv[3].strip() if len(sys.argv) >= 4 else "#todo"
        if text:
            todos = data.get("todos", [])
            new_id = max([t.get("id", 0) for t in todos], default=0) + 1
            todo = {"id": new_id, "text": text, "done": False, "tag": tag, "created": today()}
            todos.insert(0, todo)
            data["todos"] = todos
            log_event(data, "added", todo)
            save_data(data)
            print(json.dumps({"status": "added", "todos": todos}))
            return

    elif action == "toggle_todo" and len(sys.argv) >= 3:
        try:
            todo_id = int(sys.argv[2])
            todos = data.get("todos", [])
            for t in todos:
                if t.get("id") == todo_id:
                    t["done"] = not t.get("done", False)
                    if t["done"]:
                        t["completed"] = today()
                    else:
                        t.pop("completed", None)
                    log_event(data, "done" if t["done"] else "reopened", t)
                    break
            data["todos"] = todos
            save_data(data)
            print(json.dumps({"status": "toggled", "todos": todos}))
            return
        except Exception as e:
            print(json.dumps({"status": "error", "error": str(e)}))
            return

    elif action == "delete_todo" and len(sys.argv) >= 3:
        try:
            todo_id = int(sys.argv[2])
            for t in data.get("todos", []):
                if t.get("id") == todo_id:
                    log_event(data, "deleted", t)
            todos = [t for t in data.get("todos", []) if t.get("id") != todo_id]
            data["todos"] = todos
            save_data(data)
            print(json.dumps({"status": "deleted", "todos": todos}))
            return
        except Exception as e:
            print(json.dumps({"status": "error", "error": str(e)}))
            return

    elif action == "edit_todo" and len(sys.argv) >= 4:
        try:
            todo_id = int(sys.argv[2])
            text = sys.argv[3].strip()
            todos = data.get("todos", [])
            if text:
                for t in todos:
                    if t.get("id") == todo_id:
                        old_text = t.get("text", "")
                        t["text"] = text
                        log_event(data, "edited", t, "was " + json.dumps(old_text, ensure_ascii=False))
                        break
                data["todos"] = todos
                save_data(data)
            print(json.dumps({"status": "edited", "todos": todos}))
            return
        except Exception as e:
            print(json.dumps({"status": "error", "error": str(e)}))
            return

    elif action == "reorder_todos" and len(sys.argv) >= 3:
        try:
            order = [int(i) for i in json.loads(sys.argv[2])]
            todos = data.get("todos", [])
            by_id = {t.get("id"): t for t in todos}
            reordered = [by_id[i] for i in order if i in by_id]
            reordered += [t for t in todos if t.get("id") not in order]
            data["todos"] = reordered
            save_data(data)
            print(json.dumps({"status": "reordered", "todos": reordered}))
            return
        except Exception as e:
            print(json.dumps({"status": "error", "error": str(e)}))
            return

    elif action == "set_tag" and len(sys.argv) >= 4:
        try:
            todo_id = int(sys.argv[2])
            tag = sys.argv[3].strip()
            todos = data.get("todos", [])
            for t in todos:
                if t.get("id") == todo_id:
                    old_tag = t.get("tag", "")
                    t["tag"] = tag
                    log_event(data, "retagged", t, "was " + old_tag)
                    break
            data["todos"] = todos
            save_data(data)
            print(json.dumps({"status": "tagged", "todos": todos}))
            return
        except Exception as e:
            print(json.dumps({"status": "error", "error": str(e)}))
            return

    elif action == "save_tags" and len(sys.argv) >= 3:
        try:
            tags = clean_tags(json.loads(sys.argv[2]))
        except Exception:
            tags = []
        if tags:
            data["tags"] = tags
            save_data(data)
        print(json.dumps({"status": "tags_saved", "tags": data.get("tags", DEFAULT_TAGS)}))
        return

    elif action == "rename_tag" and len(sys.argv) >= 4:
        old_name = sys.argv[2].strip()
        new_name = clean_tag_name(sys.argv[3])
        tags = clean_tags(data.get("tags")) or list(DEFAULT_TAGS)
        names = [t["name"] for t in tags]
        if new_name and old_name in names and new_name not in names:
            for t in tags:
                if t["name"] == old_name:
                    t["name"] = new_name
            todos = data.get("todos", [])
            for t in todos:
                if t.get("tag") == old_name:
                    t["tag"] = new_name
            data["tags"] = tags
            data["todos"] = todos
            save_data(data)
        print(json.dumps({"status": "tag_renamed", "tags": data.get("tags", DEFAULT_TAGS), "todos": data.get("todos", [])}))
        return

    elif action == "delete_tag" and len(sys.argv) >= 3:
        name = sys.argv[2].strip()
        tags = clean_tags(data.get("tags")) or list(DEFAULT_TAGS)
        remaining = [t for t in tags if t["name"] != name]
        if remaining and len(remaining) < len(tags):
            fallback = remaining[0]["name"]
            todos = data.get("todos", [])
            for t in todos:
                if t.get("tag") == name:
                    t["tag"] = fallback
                    log_event(data, "retagged", t, "was " + name + ", tag deleted")
            data["tags"] = remaining
            data["todos"] = todos
            save_data(data)
        print(json.dumps({"status": "tag_deleted", "tags": data.get("tags", DEFAULT_TAGS), "todos": data.get("todos", [])}))
        return

    elif action == "save_logging" and len(sys.argv) >= 3:
        try:
            cfg = clean_logging(json.loads(sys.argv[2]))
        except Exception:
            cfg = clean_logging(data.get("logging"))
        data["logging"] = cfg
        save_data(data)
        print(json.dumps({"status": "logging_saved", "logging": cfg}))
        return

    elif action == "clear_completed":
        for t in data.get("todos", []):
            if t.get("done"):
                log_event(data, "deleted", t, "cleared")
        todos = [t for t in data.get("todos", []) if not t.get("done")]
        data["todos"] = todos
        save_data(data)
        print(json.dumps({"status": "cleared", "todos": todos}))
        return

    elif action == "save_scratchpad" and len(sys.argv) >= 3:
        content = sys.argv[2]
        data["scratchpad"] = content
        save_data(data)
        print(json.dumps({"status": "saved_scratchpad"}))
        return

    elif action == "add_command" and len(sys.argv) >= 4:
        name = sys.argv[2].strip()
        cmd = sys.argv[3].strip()
        desc = sys.argv[4].strip() if len(sys.argv) >= 5 else ""
        if name and cmd:
            commands = data.get("commands", [])
            new_id = max([c.get("id", 0) for c in commands], default=0) + 1
            commands.append({"id": new_id, "name": name, "cmd": cmd, "desc": desc})
            data["commands"] = commands
            save_data(data)
            print(json.dumps({"status": "added_command", "commands": commands}))
            return

    elif action == "edit_command" and len(sys.argv) >= 5:
        try:
            cmd_id = int(sys.argv[2])
            name = sys.argv[3].strip()
            cmd = sys.argv[4].strip()
            desc = sys.argv[5].strip() if len(sys.argv) >= 6 else ""
            commands = data.get("commands", [])
            for c in commands:
                if c.get("id") == cmd_id:
                    c["name"] = name
                    c["cmd"] = cmd
                    if desc:
                        c["desc"] = desc
                    break
            data["commands"] = commands
            save_data(data)
            print(json.dumps({"status": "edited_command", "commands": commands}))
            return
        except Exception as e:
            print(json.dumps({"status": "error", "error": str(e)}))
            return

    elif action == "delete_command" and len(sys.argv) >= 3:
        try:
            cmd_id = int(sys.argv[2])
            commands = [c for c in data.get("commands", []) if c.get("id") != cmd_id]
            data["commands"] = commands
            save_data(data)
            print(json.dumps({"status": "deleted_command", "commands": commands}))
            return
        except Exception as e:
            print(json.dumps({"status": "error", "error": str(e)}))
            return

    # Default: output all data
    print(json.dumps({
        "status": "ok",
        "todos": data.get("todos", []),
        "scratchpad": data.get("scratchpad", ""),
        "commands": data.get("commands", []),
        "tags": clean_tags(data.get("tags")) or DEFAULT_TAGS,
        "logging": clean_logging(data.get("logging")),
        "tasks_note": TASKS_NOTE,
        "log_note": LOG_NOTE
    }))

if __name__ == "__main__":
    main()
