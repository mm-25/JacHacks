use std::process::Command;
use tauri::Manager;

#[tauri::command]
fn run_pm2(action: String) -> Result<String, String> {
    let mut cmd = Command::new("sh");
    cmd.arg("-c");
    
    let command_str = match action.as_str() {
        "status" => "pm2 status jachacks-scraper",
        "logs" => "pm2 logs jachacks-scraper --nostream --lines 15",
        "stop" => "pm2 stop jachacks-scraper",
        "start" => "pm2 start jachacks-scraper",
        "restart" => "pm2 restart jachacks-scraper",
        _ => return Err("Invalid action".into()),
    };
    
    cmd.arg(format!("export PATH=$PATH:/usr/local/bin:/opt/homebrew/bin:$HOME/.npm-global/bin; {}", command_str));

    match cmd.output() {
        Ok(output) => {
            let stdout = String::from_utf8_lossy(&output.stdout).to_string();
            let stderr = String::from_utf8_lossy(&output.stderr).to_string();
            if output.status.success() {
                Ok(format!("{}\n{}", stdout, stderr))
            } else {
                Err(format!("Command failed:\n{}", stderr))
            }
        }
        Err(e) => Err(format!("Failed to execute process: {}", e)),
    }
}

#[tauri::command]
fn read_scraped_data() -> Result<String, String> {
    let home = std::env::var("HOME").unwrap_or_default();
    let path = format!("{}/.sherry/scraped_data.json", home);
    match std::fs::read_to_string(&path) {
        Ok(content) => Ok(content),
        Err(e) => Err(format!("Failed to read {}: {}", path, e)),
    }
}

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    tauri::Builder::default()
        .plugin(tauri_plugin_shell::init())
        .invoke_handler(tauri::generate_handler![run_pm2, read_scraped_data])
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}
