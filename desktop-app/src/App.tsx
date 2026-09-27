import { useState, useEffect } from "react";
import { invoke } from "@tauri-apps/api/core";
import "./App.css";

function PluginControlPanel() {
  const [status, setStatus] = useState("Unknown");
  const [logs, setLogs] = useState("");
  const [loading, setLoading] = useState(false);

  const runCommand = async (action: string) => {
    setLoading(true);
    try {
      const res: string = await invoke("run_pm2", { action });
      if (action === 'status') {
        setStatus(res.includes("online") ? "Active" : "Stopped");
      } else if (action === 'logs') {
        setLogs(res.trim());
      }
    } catch (e: any) {
      console.error(e);
      if (action === 'logs') setLogs("Error fetching logs: " + e);
      if (action === 'status') setStatus("Error/Stopped");
    }
    setLoading(false);
  };

  useEffect(() => {
    runCommand('status');
  }, []);

  return (
    <div className="pricing-card-featured">
      <div className="header-block">
        <h2 className="display-md">Sherry Scraper Service</h2>
        <div className="status-indicator">
          <div className={`status-dot ${status === "Active" ? "active" : "inactive"}`} />
          <span className="caption-mono">{status === "Active" ? "Online" : "Offline"}</span>
        </div>
      </div>
      
      <div className="actions-block">
        <div className="button-row">
          <button disabled={loading} onClick={() => { runCommand('start'); setTimeout(() => runCommand('status'), 1000); }} className="button-secondary-sm">
            Start
          </button>
          <button disabled={loading} onClick={() => { runCommand('stop'); setTimeout(() => runCommand('status'), 1000); }} className="button-danger-sm">
            Stop
          </button>
          <button disabled={loading} onClick={() => runCommand('logs')} className="button-secondary-sm">
            Refresh Logs
          </button>
        </div>
      </div>

      {logs && (
        <div className="code-editor-mockup code">
          {logs}
        </div>
      )}
    </div>
  );
}

function App() {
  const [autoScrapedData, setAutoScrapedData] = useState<any[]>([]);
  const [activeTab, setActiveTab] = useState<string>("All Chats");

  // Poll the Jaclang scraper JSON file
  useEffect(() => {
    const interval = setInterval(async () => {
      try {
        const res = await fetch("/scraped_data.json?t=" + Date.now());
        if (res.ok) {
          const data = await res.json();
          setAutoScrapedData(data);
        }
      } catch (e) {
        // Ignore if file doesn't exist yet
      }
    }, 2000);
    return () => clearInterval(interval);
  }, []);

  const filteredData = autoScrapedData.filter(item => {
    if (activeTab === "All Chats") return true;
    if (activeTab === "Antigravity") return item.source.platform === "antigravity";
    if (activeTab === "Codex") return item.source.platform === "codex";
    if (activeTab === "Claude") return item.source.platform === "claude";
    return true;
  });

  return (
    <div className="showcase-band-light">
      <div style={{ marginBottom: "48px" }}>
        <h1 className="display-lg" style={{ margin: "0 0 8px 0" }}>Sherry Manager.</h1>
        <p className="body-lg">Deployment dashboard for the local AI scraper.</p>
      </div>

      <PluginControlPanel />

      <div style={{ display: "flex", alignItems: "center", gap: "12px", borderBottom: "1px solid var(--hairline)", paddingBottom: "16px", marginBottom: "24px" }}>
        <h2 className="display-md" style={{ margin: 0 }}>Captured Sessions</h2>
        <span className="badge-secondary caption-mono">{filteredData.length} MEMORIES</span>
      </div>

      <div className="filters-row">
        {["All Chats", "Antigravity", "Codex", "Claude"].map(tab => (
          <button 
            key={tab} 
            className={`tab-ghost ${activeTab === tab ? "active" : ""}`}
            onClick={() => setActiveTab(tab)}
          >
            {tab}
          </button>
        ))}
      </div>
      
      <div className="sessions-grid">
        {filteredData.map((item, index) => {
          const isUser = item.source.label.toLowerCase() === "user";
          return (
            <div key={`${item.id}-${index}`} className={`card-marketing ${item.source.platform} ${isUser ? 'is-user' : 'is-ai'}`}>
              <div className="card-header" style={{ display: 'flex', alignItems: 'center', justifyContent: 'flex-start', gap: '12px' }}>
                <span className="caption-mono" style={{ fontWeight: 600, color: 'var(--ink)' }}>{item.source.label}</span>
                {isUser && (
                  <span className="badge-secondary caption-mono" style={{ fontSize: '10px', padding: '2px 8px', letterSpacing: '0.5px' }}>
                    {item.source.platform.toUpperCase()}
                  </span>
                )}
                <span className="caption-mono timestamp" style={{ marginLeft: 'auto', color: 'var(--mute)' }}>
                  {new Date(item.createdAt).toLocaleString(undefined, {
                    month: 'short', day: 'numeric', hour: 'numeric', minute: '2-digit'
                  })}
                </span>
              </div>
              <div className="card-body body-sm">
                {item.content}
              </div>
            </div>
          );
        })}
        {filteredData.length === 0 && (
          <div className="card-marketing" style={{ textAlign: "center", padding: "64px" }}>
            <span className="body-md" style={{ color: "var(--mute)" }}>No data matching this filter.</span>
          </div>
        )}
      </div>
    </div>
  );
}

export default App;
