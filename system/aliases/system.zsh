alias sudo='sudo '
alias hostfile="code /etc/hosts"
alias sshconfig="code ~/.ssh/config"
alias mysqlroot='mysql -u root -h 127.0.0.1'

alias flushdns="sudo dscacheutil -flushcache; sudo killall -HUP mDNSResponder"
alias showfiles='defaults write com.apple.finder AppleShowAllFiles YES; killall Finder'
alias hidefiles='defaults write com.apple.finder AppleShowAllFiles NO; killall Finder'
alias ports='sudo lsof -i -P -n | grep LISTEN | awk "{print \$1, \$2, \$9}"'

# Copy pwd to clipboard
alias cpwd="pwd|tr -d '\n'|pbcopy"

# Local IP address
alias ipl="ifconfig | grep 'inet ' | grep -v 127.0.0.1 | awk '{print \$2}' | head -1"

# Exclude macOS metadata from ZIP archives
alias zip="zip -x *.DS_Store -x *__MACOSX* -x *.AppleDouble*"

# Recursively remove Apple metadata files
alias cleanupds="find . -type f -name '*.DS_Store' -ls -delete"
alias cleanupad="find . -type d -name '.AppleD*' -ls -exec /bin/rm -r {} \;"

# Drop duplicates from the "Open With" menu
alias lscleanup="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -kill -r -domain local -domain system -domain user && killall Finder"

# Reload native apps
alias killfinder="killall Finder"
alias killdock="killall Dock"
alias killmenubar="killall SystemUIServer NotificationCenter"
alias killos="killfinder && killdock && killmenubar"

# System information
alias displays="system_profiler SPDisplaysDataType"
alias cpu="sysctl -n machdep.cpu.brand_string"
alias ram="top -l 1 -s 0 | grep PhysMem"
