# Sherry Manager - Desktop App

This is the frontend desktop application for **Sherry**, built using [Tauri](https://tauri.app/), [React](https://react.dev/), and [Vite](https://vitejs.dev/). It is a native macOS wrapper that reads data from the Jaclang scraper daemon.

## 🚀 Quick Install (For Users & Judges)

If you just want to use the app without touching the code, do not build from source.
1. Go to the [GitHub Releases](https://github.com/mm-25/JacHacks/releases) page.
2. Download the latest `.dmg` file (e.g., `Sherry_0.1.0_aarch64.dmg`).
3. Double-click the file and drag **Sherry** into your Applications folder.

---

## 🛠️ Developer Setup (For Teammates)

If you are contributing to the codebase, follow these steps to run the app in development mode.

### 1. Prerequisites
You must have the following developer tools installed on your Mac:
- **[Node.js](https://nodejs.org/) & [pnpm](https://pnpm.io/installation)** (For the React frontend)
- **[Rust & Cargo](https://rustup.rs/)** (For the Tauri macOS backend)
  ```bash
  curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
  ```

### 2. Install Dependencies
From the root of the repository, install the JavaScript workspace dependencies:
```bash
pnpm install
```

### 3. Run in Development Mode
Navigate to this folder and start the Tauri development server. This will boot up a live-reloading desktop window.
```bash
cd desktop-app
pnpm tauri dev
```

### 4. Build for Production
To compile your own native `.app` and `.dmg` installer files from the source code, run:
```bash
cd desktop-app
pnpm tauri build
```
The compiled binaries will be placed in `desktop-app/src-tauri/target/release/bundle/`.

---

## 🔗 Connecting the Backend

This desktop app expects a `scraped_data.json` file in its `public/` folder to display the AI chat cards. 
To populate this data, you must run the Jaclang background scraper from the root of the repository:
```bash
# From the root of the repo
python3 -m venv venv
source venv/bin/activate
pip install jaclang
npm install -g pm2
./run_scraper.sh
```
