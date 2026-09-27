import fs from "fs";
import path from "path";
import os from "os";
import http from "http";

const brainDir = path.join(os.homedir(), ".gemini/antigravity/brain");
const fileCache = new Map();
let allMemories = [];

function parseLogFile(filePath, convId) {
  if (!fs.existsSync(filePath)) return [];
  const content = fs.readFileSync(filePath, "utf-8");
  const lines = content.split("\n").filter(Boolean);
  const memories = [];

  for (const line of lines) {
    try {
      const entry = JSON.parse(line);
      
      // Basic Metadata we extract:
      const meta = {
        conversation_id: convId,
        step_index: entry.step_index,
        timestamp: entry.created_at
      };

      if (entry.type === "USER_INPUT") {
        memories.push({
          id: entry.step_index + "-" + convId + "-user",
          content: entry.content || (entry.truncated_fields ? "[Truncated Content]" : ""),
          source: { type: "conversation_excerpt", platform: "antigravity", label: "User Prompt" },
          metadata: meta,
          createdAt: entry.created_at || new Date().toISOString()
        });
      } else if (entry.type === "PLANNER_RESPONSE" && entry.content) {
        
        // Extract Tool Call Metadata (What the AI actually did!)
        let toolsUsed = [];
        if (entry.tool_calls && entry.tool_calls.length > 0) {
           toolsUsed = entry.tool_calls.map(tc => tc.function?.name || "tool_call");
        }

        memories.push({
          id: entry.step_index + "-" + convId + "-ai",
          content: entry.content,
          source: { type: "conversation_excerpt", platform: "antigravity", label: "Antigravity Output" },
          metadata: { ...meta, tools_used: toolsUsed },
          createdAt: entry.created_at || new Date().toISOString()
        });
      }
    } catch (e) {
      // Ignore
    }
  }
  return memories;
}

function processAllLogs() {
  if (!fs.existsSync(brainDir)) return;
  const dirs = fs.readdirSync(brainDir, { withFileTypes: true });
  
  let anyUpdates = false;

  for (const dirent of dirs) {
    if (!dirent.isDirectory()) continue;
    const convId = dirent.name;
    const convPath = path.join(brainDir, convId);
    const transcriptPath = path.join(convPath, ".system_generated/logs/transcript.jsonl");
    
    if (!fs.existsSync(transcriptPath)) continue;

    const stat = fs.statSync(transcriptPath);
    const cached = fileCache.get(transcriptPath);

    if (!cached || stat.size !== cached.size) {
      // Parse main conversation
      const memories = parseLogFile(transcriptPath, convId);
      
      // BONUS: Collect Artifacts!
      const convFiles = fs.readdirSync(convPath);
      for (const file of convFiles) {
        // Artifacts are stored as .md files directly in the conversation root
        if (file.endsWith(".md")) {
           const artStat = fs.statSync(path.join(convPath, file));
           memories.push({
             id: convId + "-artifact-" + file,
             content: fs.readFileSync(path.join(convPath, file), "utf-8"),
             source: { type: "artifact", platform: "antigravity", label: `Artifact: ${file}` },
             metadata: { conversation_id: convId },
             createdAt: artStat.mtime.toISOString()
           });
        }
      }

      fileCache.set(transcriptPath, { size: stat.size, memories });
      anyUpdates = true;
    }
  }

  if (anyUpdates) {
    let combined = [];
    for (const [_, data] of fileCache.entries()) {
      combined = combined.concat(data.memories);
    }
    combined.sort((a, b) => new Date(b.createdAt).getTime() - new Date(a.createdAt).getTime());
    allMemories = combined;
    console.log(`[Auto-Scraper] Scraped ${allMemories.length} memories & artifacts.`);
  }
}

// Initial sweep
processAllLogs();

setInterval(processAllLogs, 1000);

http.createServer((req, res) => {
  res.setHeader("Access-Control-Allow-Origin", "*");
  res.writeHead(200, { "Content-Type": "application/json" });
  res.end(JSON.stringify(allMemories));
}).listen(3001);
