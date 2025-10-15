# Vercel Deployment Menu Bar

A lightweight macOS menu bar app that monitors your Vercel deployment status in real-time.

![Screenshot](screenshot.png)

## What It Does

This app sits in your macOS menu bar and continuously monitors your Vercel deployments. It provides:

- Real-time deployment status updates
- Visual indicators for deployment states (building, ready, error, etc.)
- Quick access to deployment information
- Configurable API token through preferences

## Installation

### Pre-built Binary (Easiest)

1. Download the latest release from the [Releases](https://github.com/andrewk17/vercel-deployment-menu-bar/releases) page
2. Unzip and move the app to your Applications folder
3. Launch the app
4. Click the menu bar icon and select "Preferences" to configure your Vercel API token

### Build from Source

Requirements:
- macOS 13.0 or later
- Xcode 15.0 or later
- Swift 5.9 or later

```bash
# Clone the repository
git clone https://github.com/andrewk17/vercel-deployment-menu-bar.git
cd vercel-deployment-menu-bar

# Build the app
swift build -c release

# Run the app
.build/release/vercel-deployment-menu-bar
```

## Configuration

### Step 1: Generate a Vercel API Token

1. Go to [Vercel Account Settings → Tokens](https://vercel.com/account/tokens)
2. Click "Create Token"
3. Give your token a name (e.g., "Menu Bar App")
4. Choose the scope:
   - **Personal Account**: Select your personal account scope
   - **Team Account**: Select the specific team you want to monitor
5. Set an expiration date (optional but recommended)
6. Click "Create Token"
7. **Important**: Copy the token immediately - you won't be able to see it again!

### Step 2: Configure the App

1. Launch "Vercel Deployment Menu Bar" from your Applications folder
2. Click the menu bar icon (upside-down triangle)
3. Select "Preferences"
4. Enter your API token in the "Token" field

### Step 3: Configure Team ID (Only if you scoped the token to a team)

If you created a token scoped to a specific team, you **must** also enter your Team ID:

1. In the Preferences window, locate the "Team ID" field
2. To find your Team ID:
   - Go to your [Vercel Dashboard](https://vercel.com/)
   - Select your team from the dropdown
   - Look at the URL - it will be: `https://vercel.com/[TEAM_ID]/~`
   - The `[TEAM_ID]` is what you need (e.g., if the URL is `https://vercel.com/acme-corp/~`, your Team ID is `acme-corp`)
   - Alternatively, go to Team Settings → General and find your Team Slug
3. Enter the Team ID in the preferences
4. Click save

**Note**: If you used a personal account token, you can leave the Team ID field empty.

### Step 4: Start Monitoring

Once configured, the app will automatically start monitoring your deployments. The menu bar icon will update based on your latest deployment status.

## How It Works

The app uses the Vercel API to:
1. Fetch your deployment list periodically
2. Check the status of each deployment
3. Update the menu bar icon based on deployment states
4. Display deployment details in a convenient menu

## Requirements

- macOS 13.0+
- Vercel API token

## License

MIT License - see [LICENSE](LICENSE) file for details

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.
