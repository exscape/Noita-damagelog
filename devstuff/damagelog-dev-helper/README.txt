To make a long story... KIND of short: 
EntityGetName() is supposed to give you the (translated) name of every enemy/creature in the game, but whenever the game uses a slightly modified version of an enemy (such as giving it extra HP in the jungle vs another biome), the name isn't inherited from the base enemy, so the damagelog mod could only show something like "Unknown" for the name, or show the XML filename.

There doesn't seem to be a nice workaround, so this mod creates a lookup table that will perform well.
The lookup can be performed in the mod itself, at runtime, but that could cause stutters on lookup, especially on computers without an SSD.

I compared my early 2024 entity list to one from April 2021, and it turned out that **that list would still have worked**. I.e. if I had created this mod and list three years ago, that mod would still be up-do-date regarding enemy names, and so it's not exactly the case that frequent mod updates would be required.