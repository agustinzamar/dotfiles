alias ports='sudo lsof -i -P -n | grep LISTEN | awk "{print \$1, \$2, \$9}"'
