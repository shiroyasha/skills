# skills

Personal Cursor agent skills.

## Install on another machine

Clone this repo into Cursor's personal skills directory:

```bash
git clone git@github.com:shiroyasha/skills.git ~/.cursor/skills
```

If `~/.cursor/skills` already exists, clone elsewhere and copy or symlink each skill folder:

```bash
git clone git@github.com:shiroyasha/skills.git ~/code/skills
ln -s ~/code/skills/shipit ~/.cursor/skills/shipit
ln -s ~/code/skills/superplane ~/.cursor/skills/superplane
```

Restart Cursor (or start a new agent chat) so the skills load.
