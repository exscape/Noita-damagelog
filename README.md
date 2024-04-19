# FAQ (that nobody has actually asked yet)

## What do I need to use the mod? / I'm getting errors about "ImGui not available"

This mod requires the [NoitaDearImGui](https://github.com/dextercd/Noita-Dear-ImGui/releases) mod to be installed, enabled, and placed **above** this mod in the Noita mod list.  
You can download the latest version of that mod in the link above.  
1) Unpack it into your Noita\mods folder  
2) Start Noita, click Mods, and make sure "Unsafe mods: Allowed" is shown on the right (if not, click "Unsafe mods: Disabled" to enable it)  
3) Make sure NoitaDearImGui is located above this mod in the list by using the "Move up" and "Move down" buttons.

## How do I set this up?

The instructions are basically the same as for NoitaDearImGui above. Download, unzip to Noita\mods, enable in the Mods menu inside Noita.  
When correctly unpacked, you should have the "damagelog" folder inside the "mods" folder.  
After that, start Noita and make sure this mod is **below** NoitaDearImGui in the list with the "Move up" and "Move down" buttons, and that both are enabled.

## The window is not showing up / I don't know the activation hotkey

The default activation hotkey is Ctrl+Q. If that's not it, go to the Noita "Mods" menu, click "Mod Settings", and restore the settings for the mod.  
Once you return to the game, it should show up, and let you set it up the way you want it.  

## Can I change any settings?

Yes! Right-click any row in the damage log, i.e. not the table header or the window titlebar.

One setting (mouse click-through) is only available in the Noita "Mod Settings" menu, since it would be impossible to change back in the standard settings.

## The damage log is very small!

The display size is the same (in pixels) in all resolutions.  
You can change the font size to work around this, however. Right-click on a damage entry (not in the window titlebar or table header) to open the settings window, and select "Noita Pixel 1.4x" or "Noita Pixel 1.8x" to use a larger font.

## Does the mod affect game performance?

From my measurements, not by a lot. With 15 or so rows showing, the performance cost seems close to 0.1 ms per frame for me, i.e. the FPS loss **if any** is typically less than 1%.  
This is on a fairly high-end CPU though (Ryzen 5800X3D); a weaker CPU with 50-60 rows showing might have a noticeable performance impact, but probably only when the GUI is active.

I haven't been able to measure any performance cost at all when the GUI is not showing, so it should be very small.

# Known issues

If the setting to show the log when paused is enabled, it will also show up over the settings menu, over the replay editor, and so on. I don't believe Noita allows a mod to tell if these are active or not. (If anyone has a fix, please contact me!)  
**Workaround** if you use those often: disable the setting to open/close the log on pause/unpause, and and pause + toggle the log manually when you actually want to view it.

Circle of Vigour causes small amounts of healing to show up in the log (about 10 hp), even though it heals far more.  
This is because Noita signals the mod (via the function damage_received, with negative damage values) only for a few particles, while the regeneration effect is what does most of the healing.