# JacHacks

Welcome to the JacHacks repository! 

## Getting Started

To run this project locally, you will need to set up two parts: the Node.js frontend apps and the Python/Jaclang scraper.

### 1. Prerequisites
- [Node.js](https://nodejs.org/) & [pnpm](https://pnpm.io/)
- Python 3.10+

### 2. Setting up the Apps (Frontend & Extension)
1. Navigate to the project root:
   ```bash
   cd JacHacks
   ```
2. Install the node dependencies:
   ```bash
   pnpm install
   ```

### 3. Setting up the Scraper (Python/Jaclang)
1. Create a Python virtual environment:
   ```bash
   python3 -m venv venv
   ```
2. Activate the virtual environment:
   - On macOS/Linux: `source venv/bin/activate`
   - On Windows: `.\venv\Scripts\activate`
3. Install the required python packages:
   ```bash
   pip install -r requirements.txt
   ```
4. To run the scraper:
   ```bash
   ./run_scraper.sh
   ```
### 4. Running the Native Mac App (Tauri)
This project includes a native macOS desktop application built with Rust and Tauri that manages the background scraper automatically.

**Prerequisites for the Mac App:**
- [Rust & Cargo](https://rustup.rs/) (Required to compile the desktop app)
- PM2 (Required for background task management): `npm install -g pm2`

**To launch the Mac App:**
```bash
cd apps/web
pnpm tauri dev
```

**To build a distributable .app or .dmg for your team:**
```bash
cd apps/web
pnpm tauri build
```
The compiled application will be output to `apps/web/src-tauri/target/release/bundle/macos/JacHacks.app`.

### 5. First-Time Setup for Teammates
Before the Mac App buttons will work on a completely new machine, you must initialize the background daemon once in your terminal from the project root:
```bash
pm2 start run_scraper.sh --name "jachacks-scraper"
pm2 save
```
Once that is done, you can rely entirely on the Mac App to start, stop, and monitor the scraper!
