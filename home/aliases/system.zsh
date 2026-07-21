alias sudo='sudo '
alias hostfile="code /etc/hosts"
alias sshconfig="code ~/.ssh/config"
alias flushdns="sudo dscacheutil -flushcache; sudo killall -HUP mDNSResponder"
alias showfiles='defaults write com.apple.finder AppleShowAllFiles YES; killall Finder'
alias hidefiles='defaults write com.apple.finder AppleShowAllFiles NO; killall Finder'
alias ports='sudo lsof -i -P -n | grep LISTEN | awk "{print \$1, \$2, \$9}"'
alias mysqlroot='mysql -u root -h 127.0.0.1'
