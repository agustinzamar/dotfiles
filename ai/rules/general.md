# General

## Never amend or force-push master
CI deploys production with `git pull --ff-only` over SSH. Amending or force-pushing master rewrites history, diverges the production repo, and the deploy job fails with "Not possible to fast-forward". Recovery (done once): merge the replaced commit back with `git merge <old-sha> -s ours --no-ff` and push normally.
