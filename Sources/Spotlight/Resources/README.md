# Spotlight resources

Drop the Inter font files here so the panel renders in Inter instead of falling
back to the system font:

- `Inter-Regular.ttf`
- `Inter-Medium.ttf`

Easiest install:

```bash
brew install --cask font-inter
# then copy the installed TTFs into this directory:
cp ~/Library/Fonts/Inter-Regular.ttf ~/Library/Fonts/Inter-Medium.ttf \
   Sources/Spotlight/Resources/
```

Or download them directly from https://rsms.me/inter/ and place them in this
directory. `FontLoader.registerBundledFonts()` picks up every `.ttf` / `.otf`
here at launch.
