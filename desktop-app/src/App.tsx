import { useState, useEffect } from "react";
import { LayoutDashboard, MessageSquare, Sparkles, GitMerge, Activity, Settings, X } from "lucide-react";
import "./App.css";

const SHERRY_URL = "https://sherry.sherry-cloud.workers.dev";
const API_KEY = "shr_CL4lSPqu1n78xIUpxooKU0YSqnYvZoudaWlK9OtsX-c";

function cleanMessageText(text: string) {
  let cleaned = text;
  cleaned = cleaned.replace(/<environment_context>[\s\S]*?<\/environment_context>/g, '');
  cleaned = cleaned.replace(/Host notice:.*?authorization\./g, '');
  cleaned = cleaned.replace(/\[scraper\.err\]/g, '');
  cleaned = cleaned.replace(/Retained source order: \d+/g, '');
  return cleaned.trim();
}

export default function App() {
  const [activeTab, setActiveTab] = useState("Chat Memory");
  const [memories, setMemories] = useState<any[]>([]);
  const [loading, setLoading] = useState(false);
  const [selectedMemory, setSelectedMemory] = useState<any | null>(null);
  const [transcript, setTranscript] = useState<any[]>([]);
  const [transcriptLoading, setTranscriptLoading] = useState(false);

  // Filters
  const [platformFilter, setPlatformFilter] = useState("All platforms");
  const [deviceFilter, setDeviceFilter] = useState("All devices");
  const [dateFilter, setDateFilter] = useState("Last 30 days");

  const fetchMemories = async () => {
    setLoading(true);
    try {
      const res = await fetch(`${SHERRY_URL}/function/list_memories`, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "Authorization": `Bearer ${API_KEY}`
        },
        body: JSON.stringify({ limit: 100 })
      });
      const json = await res.json();
      setMemories(json.data.result.data || []);
    } catch (e) {
      console.error(e);
    }
    setLoading(false);
  };

  const fetchTranscript = async (conversationId: string) => {
    setTranscriptLoading(true);
    setTranscript([]);
    try {
      const res = await fetch(`${SHERRY_URL}/function/get_conversation`, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "Authorization": `Bearer ${API_KEY}`
        },
        body: JSON.stringify({ conversation_id: conversationId })
      });
      const json = await res.json();
      setTranscript(json.data.result.messages || []);
    } catch (e) {
      console.error(e);
    }
    setTranscriptLoading(false);
  };

  useEffect(() => {
    if (activeTab === "Chat Memory") {
      fetchMemories();
    }
  }, [activeTab]);

  const handleCardClick = (mem: any) => {
    setSelectedMemory(mem);
    if (mem.source.conversationId) {
      fetchTranscript(mem.source.conversationId);
    }
  };

  const filteredMemories = memories.filter(m => {
    if (platformFilter !== "All platforms" && m.source.platform.toLowerCase() !== platformFilter.toLowerCase()) return false;
    // Device and date filters are mocked for UI purposes since API doesn't fully support them yet
    return true;
  });

  return (
    <div className="app-container">
      {/* Sidebar */}
      <aside className="sidebar">
        <div className="logo">Sherry</div>
        
        <nav>
          {[
            { id: "Dashboard", icon: LayoutDashboard },
            { id: "Chat Memory", icon: MessageSquare },
            { id: "Personal Memory", icon: Sparkles },
            { id: "Connected Conversations", icon: GitMerge },
            { id: "Diagnostics", icon: Activity }
          ].map(tab => (
            <div 
              key={tab.id} 
              className={`nav-link ${activeTab === tab.id ? 'active' : ''}`}
              onClick={() => setActiveTab(tab.id)}
            >
              <tab.icon size={18} />
              {tab.id}
            </div>
          ))}
        </nav>

        <div className="sidebar-footer">
          <div className="avatar">M</div>
          <div style={{ flex: 1, fontSize: '14px', fontWeight: 600 }}>Mufaddal</div>
          <Settings size={18} color="var(--text-secondary)" />
        </div>
        <div style={{ padding: '0 12px', fontSize: '12px', color: 'var(--text-secondary)', cursor: 'pointer' }}>
          Sign out
        </div>
      </aside>

      {/* Main Content */}
      <main className="main-content">
        {activeTab === "Chat Memory" ? (
          <>
            <div className="page-header">
              <h1 className="page-title">Chat Memory</h1>
              <p className="page-subtitle">Search within Chat Memory. Filters below only affect this section.</p>
            </div>

            <div className="filters-bar">
              <input type="text" className="search-input" placeholder="Search chats, titles, summaries, and message content..." />
            </div>
            
            <div className="filters-bar" style={{ marginTop: '-16px' }}>
              <select className="filter-dropdown" value={platformFilter} onChange={e => setPlatformFilter(e.target.value)}>
                <option>All platforms</option>
                <option>ChatGPT</option>
                <option>Claude</option>
                <option>Gemini</option>
                <option>Antigravity</option>
                <option>Codex</option>
              </select>
              <select className="filter-dropdown" value={deviceFilter} onChange={e => setDeviceFilter(e.target.value)}>
                <option>All devices</option>
                <option>Browser</option>
                <option>Desktop</option>
                <option>Mobile</option>
              </select>
              <select className="filter-dropdown" value={dateFilter} onChange={e => setDateFilter(e.target.value)}>
                <option>Last 30 days</option>
                <option>Last 7 days</option>
              </select>
            </div>

            {loading ? (
              <div>Loading memories...</div>
            ) : (
              <div className="memory-grid">
                {filteredMemories.map(m => {
                  const titleMatch = m.content.match(/Latest ask:\s*(.*?)\n/);
                  const title = titleMatch ? titleMatch[1].substring(0, 50) + "..." : m.source.label || "Chat Session";
                  return (
                    <div key={m.id} className="memory-card" onClick={() => handleCardClick(m)}>
                      <div className="card-header">
                        <div className="platform-icon">
                          <MessageSquare size={14} color="var(--text-secondary)" />
                        </div>
                        <span style={{ fontSize: '18px', color: 'var(--text-secondary)' }}>→</span>
                      </div>
                      <h3 className="card-title">{title}</h3>
                      <div className="card-preview">{m.content}</div>
                      <div className="card-footer">
                        <span>{m.source.platform}</span>
                        <span>Last active {new Date(m.createdAt).toLocaleDateString()}</span>
                      </div>
                    </div>
                  );
                })}
              </div>
            )}
          </>
        ) : (
          <div className="page-header">
            <h1 className="page-title">{activeTab}</h1>
            <p className="page-subtitle">This page is under construction.</p>
          </div>
        )}
      </main>

      {/* Modal Popup */}
      {selectedMemory && (
        <div className="modal-overlay" onClick={() => setSelectedMemory(null)}>
          <div className="modal-content" onClick={e => e.stopPropagation()}>
            <div className="modal-header">
              <div style={{ position: 'absolute', top: '24px', right: '24px', cursor: 'pointer' }} onClick={() => setSelectedMemory(null)}>
                <X size={20} color="var(--text-secondary)" />
              </div>
              <h2 className="modal-title">{selectedMemory.source.label || "Captured Conversation"}</h2>
              <div className="modal-meta">Last active {new Date(selectedMemory.createdAt).toLocaleString()}</div>
              
              <div className="modal-actions">
                <a href="#" style={{ color: 'var(--accent-blue)', textDecoration: 'underline', fontSize: '14px', marginRight: 'auto', display: 'flex', alignItems: 'center' }}>
                  Open original chat ↗
                </a>
                <button className="btn">Export JSON</button>
                <button className="btn btn-danger">Delete from Sherry</button>
              </div>
            </div>

            <div className="modal-body">
              <div className="transcript-header">
                <span>TRANSCRIPT</span>
                <span>Oldest stored first • source message time where available</span>
              </div>
              
              <h3 style={{ margin: '0 0 16px 0', fontSize: '16px' }}>Messages</h3>
              
              {transcriptLoading ? (
                <div>Loading raw transcript...</div>
              ) : (
                <div>
                  {transcript.map((msg, i) => (
                    <div key={i} className="chat-bubble">
                      <div className="bubble-meta">
                        {msg.role === 'user' ? 'USER' : 'ASSISTANT'} • {new Date(msg.captured_at || Date.now()).toLocaleString()}
                      </div>
                      <div className="bubble-text">
                        {cleanMessageText(msg.text)}
                      </div>
                    </div>
                  ))}
                  {transcript.length === 0 && (
                    <div style={{ color: 'var(--text-secondary)' }}>No transcript messages found for this chat.</div>
                  )}
                </div>
              )}
            </div>
          </div>
        </div>
      )}
    </div>
  );
}
