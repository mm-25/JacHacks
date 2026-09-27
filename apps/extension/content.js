// Basic DOM Observer to detect when the AI finishes a response
let lastScrapedText = "";

function scrapeChat() {
  const isChatGPT = window.location.hostname.includes("chatgpt.com");
  const isClaude = window.location.hostname.includes("claude.ai");

  let latestResponse = "";
  let platform = "unknown";

  if (isChatGPT) {
    platform = "chatgpt";
    // ChatGPT usually uses .markdown blocks for AI responses
    const elements = document.querySelectorAll('.markdown');
    if (elements.length > 0) {
      latestResponse = elements[elements.length - 1].innerText;
    }
  } else if (isClaude) {
    platform = "claude";
    // Claude usually uses .font-claude-message or specific div classes
    const elements = document.querySelectorAll('.font-claude-message');
    if (elements.length > 0) {
      latestResponse = elements[elements.length - 1].innerText;
    }
  }

  // If we found a new response and it's substantial
  if (latestResponse && latestResponse !== lastScrapedText && latestResponse.length > 10) {
    lastScrapedText = latestResponse;
    console.log("[Sherry Scraper] New AI response detected! Sending to local daemon...");
    
    // POST to the local daemon (which we will set up to listen on port 3001)
    fetch("http://localhost:3001/ingest", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        content: latestResponse,
        platform: platform,
        label: `Web Chat: ${platform}`
      })
    }).catch(err => console.log("Sherry daemon not running locally.", err));
  }
}

// Observe the DOM for changes (new chat messages appearing)
const observer = new MutationObserver(() => {
  // Debounce the scrape slightly so we don't spam while the AI is typing
  clearTimeout(window.scrapeTimeout);
  window.scrapeTimeout = setTimeout(scrapeChat, 2000); 
});

observer.observe(document.body, { childList: true, subtree: true });
console.log("[Sherry Web Scraper] Injected and listening for AI messages...");
