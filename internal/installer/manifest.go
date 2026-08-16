package installer

type Component struct {
	ID           string   `json:"id"`
	Label        string   `json:"label"`
	Category     string   `json:"category"`
	Default      bool     `json:"default"`
	Required     bool     `json:"required"`
	Dependencies []string `json:"dependencies,omitempty"`
	Links        []string `json:"links,omitempty"`
	Commands     []string `json:"commands,omitempty"`
}

func Components() []Component {
	return []Component{
		{ID: "base", Label: "Base tools", Category: "Base", Default: true, Required: true, Commands: []string{"xcode-select --install", "brew install go"}},
		{ID: "shell", Label: "Zsh and plugins", Category: "Shell", Default: true, Links: []string{"zsh", "p10k"}, Commands: []string{"brew install zsh fzf", "dot zsh"}},
		{ID: "git", Label: "Git, SSH signing, Hunk and GitHub tools", Category: "Git", Default: true, Links: []string{"git", "lazygit", "hunk"}, Commands: []string{"brew install git gh lazygit git-delta hunk", "dot git"}},
		{ID: "terminal", Label: "Terminal tools", Category: "Terminal", Default: true, Links: []string{"ghostty", "tmux", "yazi"}, Commands: []string{"brew install --cask ghostty", "brew install tmux yazi neovim"}},
		{ID: "php", Label: "Composer, Herd and PHPStorm", Category: "PHP", Commands: []string{"brew install composer Herd", "brew install --cask phpstorm"}},
		{ID: "service-mysql", Label: "MySQL", Category: "Services", Commands: []string{"brew install mysql"}},
		{ID: "service-postgresql", Label: "PostgreSQL", Category: "Services", Commands: []string{"brew install postgresql"}},
		{ID: "service-redis", Label: "Redis", Category: "Services", Commands: []string{"brew install redis"}},
		{ID: "service-sqlite", Label: "SQLite", Category: "Services", Commands: []string{"brew install sqlite"}},
		{ID: "ai", Label: "AI tools", Category: "AI", Commands: []string{"brew install opencode"}, Links: []string{"claude", "agents"}},
		{ID: "vscode", Label: "VS Code", Category: "Editors", Commands: []string{"brew install --cask visual-studio-code", "dot code"}, Links: []string{"vscode"}},
		{ID: "desktop-chrome", Label: "Chrome", Category: "Desktop", Commands: []string{"brew install --cask google-chrome"}},
		{ID: "desktop-firefox", Label: "Firefox", Category: "Desktop", Commands: []string{"brew install --cask firefox"}},
		{ID: "desktop-brave", Label: "Brave", Category: "Desktop", Commands: []string{"brew install --cask brave-browser"}},
		{ID: "communication-discord", Label: "Discord", Category: "Communication", Commands: []string{"brew install --cask discord"}},
		{ID: "communication-telegram", Label: "Telegram", Category: "Communication", Commands: []string{"brew install --cask telegram"}},
		{ID: "communication-whatsapp", Label: "WhatsApp", Category: "Communication", Commands: []string{"brew install --cask whatsapp"}},
		{ID: "communication-slack", Label: "Slack", Category: "Communication", Commands: []string{"brew install --cask slack"}},
		{ID: "desktop-raycast", Label: "Raycast", Category: "Desktop", Commands: []string{"brew install --cask raycast"}},
		{ID: "desktop-finetune", Label: "Finetune", Category: "Desktop", Commands: []string{"brew install --cask finetune"}},
		{ID: "desktop-typewhisper", Label: "TypeWhisper", Category: "Desktop", Commands: []string{"brew install --cask typewhisper"}},
		{ID: "desktop-rectangle", Label: "Rectangle", Category: "Desktop", Commands: []string{"brew install --cask rectangle"}},
		{ID: "desktop-aerospace", Label: "Aerospace", Category: "Desktop", Links: []string{"aerospace"}, Commands: []string{"brew install --cask aerospace"}},
		{ID: "desktop-linearmouse", Label: "LinearMouse", Category: "Desktop", Links: []string{"linearmouse"}, Commands: []string{"brew install --cask linearmouse"}},
		{ID: "desktop-localsend", Label: "LocalSend", Category: "Desktop", Commands: []string{"brew install --cask localsend"}},
		{ID: "media-tools", Label: "Media command-line tools", Category: "Media", Commands: []string{"brew install ffmpeg ffmpegthumbnailer unar imagemagick webp"}},
		{ID: "media-spotify", Label: "Spotify", Category: "Media", Commands: []string{"brew install --cask spotify"}},
		{ID: "media-stremio", Label: "Stremio", Category: "Media", Commands: []string{"brew install --cask stremio"}},
		{ID: "media-vlc", Label: "VLC", Category: "Media", Commands: []string{"brew install --cask vlc"}},
		{ID: "media-castor", Label: "Castor", Category: "Media", Commands: []string{"brew install --cask stupside/tap/castor"}},
	}
}

func componentIDs() map[string]bool {
	ids := make(map[string]bool)
	for _, component := range Components() {
		ids[component.ID] = true
	}
	return ids
}
