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
		{ID: "git", Label: "Git and configuration", Category: "Git", Default: true, Links: []string{"git", "lazygit"}, Commands: []string{"brew install git gh lazygit git-delta", "dot git"}},
		{ID: "hunk", Label: "Hunk", Category: "Git", Default: true, Links: []string{"hunk"}, Commands: []string{"brew install hunk"}, Dependencies: []string{"git"}},
		{ID: "terminal", Label: "Terminal tools", Category: "Terminal", Default: true, Links: []string{"ghostty", "tmux", "yazi"}, Commands: []string{"brew install --cask ghostty", "brew install tmux yazi neovim"}},
		{ID: "php", Label: "PHP, Laravel, Herd and PHPStorm", Category: "PHP", Commands: []string{"brew install php composer laravel Herd", "brew install --cask phpstorm"}},
		{ID: "databases", Label: "Databases and services", Category: "Services", Commands: []string{"brew install mysql postgresql redis sqlite"}},
		{ID: "ai", Label: "AI tools", Category: "AI", Commands: []string{"brew install opencode"}, Links: []string{"claude", "agents"}},
		{ID: "vscode", Label: "VS Code", Category: "Editors", Commands: []string{"brew install --cask visual-studio-code", "dot code"}, Links: []string{"vscode"}},
		{ID: "desktop", Label: "Desktop apps", Category: "Desktop", Commands: []string{"dot install desktop"}},
		{ID: "communication", Label: "Communication apps", Category: "Communication", Commands: []string{"brew install --cask discord slack whatsapp telegram"}},
		{ID: "media", Label: "Media apps", Category: "Media", Commands: []string{"brew install --cask spotify vlc stremio"}},
	}
}

func componentIDs() map[string]bool {
	ids := make(map[string]bool)
	for _, component := range Components() {
		ids[component.ID] = true
	}
	return ids
}
