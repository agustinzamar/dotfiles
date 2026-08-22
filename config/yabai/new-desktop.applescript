-- Create a new desktop (space) by opening Mission Control and clicking the "+" button.
tell application "Mission Control" to launch
delay 0.4
tell application "System Events"
	tell process "Dock"
		click button 1 of group "Spaces Bar" of group 1 of group "Mission Control"
	end tell
	key code 53 -- esc: close Mission Control
end tell
