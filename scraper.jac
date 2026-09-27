import os;
import json;
import time;
import datetime;

with entry {
    brain_dir = os.path.join(os.path.expanduser("~"), ".gemini/antigravity/brain");
    claude_projects_dir = os.path.join(os.path.expanduser("~"), ".claude/projects");
    codex_sessions_dir = os.path.join(os.path.expanduser("~"), ".codex/sessions");
    out_file = os.path.join(os.path.expanduser("~"), ".sherry", "scraped_data.json");
    os.makedirs(os.path.dirname(out_file), exist_ok=True);
    
    print("Starting Comprehensive Agent Scraper (Antigravity + Claude + Codex)...");
    
    while True {
        all_mems = [];
        
        # ── 1. ANTIGRAVITY ──
        if os.path.exists(brain_dir) {
            for conv_id in os.listdir(brain_dir) {
                conv_path = os.path.join(brain_dir, conv_id);
                if os.path.isdir(conv_path) {
                    t_path = os.path.join(conv_path, ".system_generated/logs/transcript.jsonl");
                    if os.path.exists(t_path) {
                        with open(t_path, "r") as f {
                            for line in f {
                                line = line.strip();
                                if not line { continue; }
                                try {
                                    data = json.loads(line);
                                    t = data.get("type");
                                    c = data.get("content");
                                    ts = data.get("created_at", "");
                                    if t == "USER_INPUT" and c {
                                        if "<USER_REQUEST>" in c and "</USER_REQUEST>" in c {
                                            c = c.split("<USER_REQUEST>")[1].split("</USER_REQUEST>")[0].strip();
                                        }
                                        all_mems.append({"id": str(data.get("step_index")) + "-" + conv_id + "-user", "content": c, "source": {"type": "conversation_excerpt", "platform": "antigravity", "label": "User"}, "createdAt": ts});
                                    } elif t == "PLANNER_RESPONSE" and c {
                                        all_mems.append({"id": str(data.get("step_index")) + "-" + conv_id + "-ai", "content": c, "source": {"type": "conversation_excerpt", "platform": "antigravity", "label": "Antigravity"}, "createdAt": ts});
                                    }
                                } except Exception as e {
                                    continue;
                                }
                            }
                        }
                    }
                }
            }
        }
        
        # ── 2. CLAUDE (Desktop + CLI) ──
        if os.path.exists(claude_projects_dir) {
            for project_dir in os.listdir(claude_projects_dir) {
                project_path = os.path.join(claude_projects_dir, project_dir);
                if not os.path.isdir(project_path) { continue; }
                for fname in os.listdir(project_path) {
                    if not fname.endswith(".jsonl") { continue; }
                    fpath = os.path.join(project_path, fname);
                    session_id = fname.replace(".jsonl", "");
                    try {
                        with open(fpath, "r") as f {
                            line_idx = 0;
                            for line in f {
                                line = line.strip();
                                if not line { continue; }
                                try {
                                    data = json.loads(line);
                                    t = data.get("type", "");
                                    ts = data.get("timestamp", "");
                                    
                                    if t == "user" {
                                        msg = data.get("message", {}).get("content", "");
                                        if isinstance(msg, str) and msg and not msg.startswith("<local-command") and not msg.startswith("<command-name") {
                                            all_mems.append({
                                                "id": "claude-" + session_id + "-" + str(line_idx),
                                                "content": msg,
                                                "source": {"type": "conversation_excerpt", "platform": "claude", "label": "User"},
                                                "createdAt": ts
                                            });
                                        }
                                    } elif t == "assistant" {
                                        msg = data.get("message", {}).get("content", "");
                                        text = "";
                                        if isinstance(msg, list) {
                                            for block in msg {
                                                if isinstance(block, dict) and block.get("type") == "text" {
                                                    text = block.get("text", "");
                                                    break;
                                                }
                                            }
                                        } elif isinstance(msg, str) {
                                            text = msg;
                                        }
                                        if text and not text.startswith("API Error") {
                                            all_mems.append({
                                                "id": "claude-" + session_id + "-" + str(line_idx),
                                                "content": text,
                                                "source": {"type": "conversation_excerpt", "platform": "claude", "label": "Claude"},
                                                "createdAt": ts
                                            });
                                        }
                                    }
                                } except Exception as e {
                                    continue;
                                }
                                line_idx = line_idx + 1;
                            }
                        }
                    } except Exception as e {
                        continue;
                    }
                }
            }
        }
        
        # ── 3. CODEX (Desktop + CLI) ──
        if os.path.exists(codex_sessions_dir) {
            for year_dir in os.listdir(codex_sessions_dir) {
                year_path = os.path.join(codex_sessions_dir, year_dir);
                if not os.path.isdir(year_path) { continue; }
                for month_dir in os.listdir(year_path) {
                    month_path = os.path.join(year_path, month_dir);
                    if not os.path.isdir(month_path) { continue; }
                    for day_dir in os.listdir(month_path) {
                        day_path = os.path.join(month_path, day_dir);
                        if not os.path.isdir(day_path) { continue; }
                        for fname in os.listdir(day_path) {
                            if not fname.endswith(".jsonl") { continue; }
                            fpath = os.path.join(day_path, fname);
                            session_id = fname.replace(".jsonl", "")[:30];
                            try {
                                with open(fpath, "r") as f {
                                    line_idx = 0;
                                    for line in f {
                                        line = line.strip();
                                        if not line { continue; }
                                        try {
                                            data = json.loads(line);
                                            dtype = data.get("type", "");
                                            ts = data.get("timestamp", "");
                                            
                                            if dtype == "response_item" {
                                                payload = data.get("payload", {});
                                                ptype = payload.get("type", "");
                                                role = payload.get("role", "");
                                                content = payload.get("content", []);
                                                
                                                if ptype == "message" and isinstance(content, list) {
                                                    for block in content {
                                                        if isinstance(block, dict) {
                                                            btype = block.get("type", "");
                                                            text = block.get("text", "");
                                                            if not text { continue; }
                                                            if len(text) < 10 { continue; }
                                                            if text.startswith("<app-context") { continue; }
                                                            if text.startswith("<recommended_plugins") { continue; }
                                                            
                                                            if btype == "input_text" and role == "user" {
                                                                if "tool exec result" in text or "tool exec call" in text or "RETAINED USER INSTRUCTIONS" in text or "TRANSCRIPT DELTA" in text or "The following is the Codex agent history" in text { continue; }
                                                                if text.startswith("user: ") { text = text.replace("user: ", "", 1); }
                                                                all_mems.append({
                                                                    "id": "codex-" + session_id + "-" + str(line_idx),
                                                                    "content": text,
                                                                    "source": {"type": "conversation_excerpt", "platform": "codex", "label": "User"},
                                                                    "createdAt": ts
                                                                });
                                                            } elif btype == "output_text" and role == "assistant" {
                                                                if "tool exec result" in text or "tool exec call" in text or "RETAINED USER INSTRUCTIONS" in text or "TRANSCRIPT DELTA" in text { continue; }
                                                                all_mems.append({
                                                                    "id": "codex-" + session_id + "-" + str(line_idx),
                                                                    "content": text,
                                                                    "source": {"type": "conversation_excerpt", "platform": "codex", "label": "Codex"},
                                                                    "createdAt": ts
                                                                });
                                                            }
                                                        }
                                                    }
                                                }
                                            }
                                        } except Exception as e {
                                            continue;
                                        }
                                        line_idx = line_idx + 1;
                                    }
                                }
                            } except Exception as e {
                                continue;
                            }
                        }
                    }
                }
            }
        }
        
        all_mems.sort(key=lambda m: m.get("createdAt", ""), reverse=True);
        capped = all_mems[:200];
        with open(out_file, "w") as f {
            json.dump(capped, f, indent=2);
        }
        print(f"[Jaclang Auto-Scraper] {len(all_mems)} total, showing latest 200.");
        time.sleep(2);
    }
}
