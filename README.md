# CRT Dusha (Soul)
### CRT phosphor decay simulation shader with motion blur reduction and Voodoo2-style color quantization.
![quake](https://github.com/user-attachments/assets/4d4f8b6b-2858-498f-a341-40e03d48a10a)



Hi everyone! I'm a huge fan of classic arena shooters like *Quake* and *Unreal Tournament*. Back in the day, I even competed as a **Quake 2** and **Quake 3** champion. To recapture the feel of the CRT displays from my childhood, I looked for proper CRT effect shaders, but most existing options like various BFI and CRT beam emulators were either simply broken or just didn't deliver the look I was after.

That's why I decided to create my own solution: **CRT Dusha** (Soul in Russian) **ReShade Shader**. The shader simulates the phosphor decay CRTs had, which in my opinion was the soul of the lost tech (hence the shader name, *Dusha*). It's highly flexible and can recreate the look and feel of the monitors from your childhood, including the image produced by **the greatest GPU ever—3dfx Voodoo2!** *RIP, but never forgotten!*

## Main features

- **Realistic Phosphor Decay**: Multi-stage Fibonacci-weighted exponential decay model simulating per-channel phosphor persistence (red, green, blue decay at different rates, matching P22 or custom phosphor characteristics).
- **Advanced Gamma Shaping**: Power-law gamma combined with decay can restore intended luminance curves in retro titles and bring modern games closer to analog display behavior.
- **Single-Frame Processing**: Shader operates on the current frame only, minimizing input lag for the most responsive experience.
- **Motion Blur Reduction**: Extended BFI (Black Frame Insertion) approach through multi-stage phosphor decay increases motion clarity, with richer persistence curves than simple on/off black frame techniques.
- **3dfx Voodoo2 Pipeline**: Optional 16-bit RGB565 color quantization with Bayer ordered dithering (2x2, 4x4, 8x8 matrices) for mid-90s graphics card aesthetic.
- **Split Screen Comparison**: Displays processed and original image side by side for real-time effect comparison.
- **LCD Safe Mode**: Enabled by default, introduces subtle phase flips to prevent image retention on LCD panels.
- **Optimized for Lower-end Hardware**: Tuned for consistent performance on devices like Steam Deck OLED.
- **DX9 Compatible**: Shader Model 3.0 support for older games.

## Requirements
- ReShade 4.0 or higher. 
- Steam Deck: Reshadeck (Reshade Shader Loader for Decky Plugin Loader).
- For desktop and borderless fullscreen apps, ShaderGlass in combination with ReShade can be used.
- Game/app must be compatible with DirectX 9/10/11/12, OpenGL, or Vulkan.

## Frame Synchronization (Important!)
Like all shaders of this type, the effects are frame-based, so you need frame rate synchronization with your display refresh rate:
- High refresh rate displays and high framerate: Use V-Sync.
- Variable refresh rate displays: Use G-Sync/FreeSync with frame capping (standard 3-5 fps below the monitor's max Hz in addition to V-Sync).
- Low refresh rate displays (like 90Hz Steam Deck OLED): Aim for maximum stable fps + V-Sync (with Steam Deck Game Mode you can use Disable Frame Limit and Allow Tearing for better input lag; Gamescope has its own V-Sync always on).

**Simply put**: Sync your monitor refresh rate with your in-game FPS. That's the primary requirement. Otherwise, the shader is plug-and-play.

## Optional Enhancements
High refresh, HDR, and OLED are beneficial (effects might look and feel better) but not required. All development and testing was done on a 4-year-old 165Hz IPS panel and 90Hz Steam Deck OLED.

## What's NOT Included
Besides simple scanlines and Trinitron-like vertical RGB color separation, no CRT masks, halation, or other bells and whistles are included. **CRT Dusha focuses purely on phosphor behavior and motion response**. You can use any mask shader you like, there are many available. I personally prefer simple Trinitron-style masks.

## Usage Tips
- For the most realistic results, apply mask shaders after CRT Dusha in the ReShade chain
- **Steam Deck OLED**: Use 2 frames per decay cycle (basic BFI, 1 bright frame + 1 dark/black frame) to avoid flicker at 90Hz

## Known Limitations

### LCD Image Retention

On LCD panels, prolonged display of high-contrast static patterns can cause ions in the liquid crystal layer to drift, leading to a DC voltage buildup inside the pixel cells. This buildup can temporarily bias the pixels, resulting in image retention (“burn-in”).
This is a physical property of LCDs, not a shader issue, and it primarily appears when alternating bright and dark frames repeat in a perfectly even pattern.

**Examples**:

- Leaving your game paused with static high-contrast menus (e.g., Doom Eternal)
- ReShade overlays left visible for extended periods
- Any UI elements with bright/dark patterns that don't change

**Mitigation**

- Use **odd “Frames Per Effect” values** (3, 5, 7, etc.) - this naturally breaks the repetitive frame polarity pattern.

- Or keep **LCD Safe Mode** enabled - it’s **on by default** and introduces phase flips to prevent DC buildup. You may occasionally notice a very brief, single-frame flick, which is intentional and part of the burn-in protection cycle.

**Note**: This mitigation only applies to shader output — overlays rendered on top of the shader (like ReShade HUDs or GUI overlays) are outside its control and can still contribute to image retention.

**LCD Safe Mode** offers two selectable techniques:

- Phase Jump (default) - slowly accumulates small phase offsets and performs discrete phase jumps at long intervals. By default, the effect provides **mild burn-in mitigation**, but the **Jump Rate** can be increased to make the protection stronger, at the cost of slightly more noticeable phase flips.

- Frame Drop - skips a frame periodically to break the pattern.

These modes only activate when even-frame decay is used (e.g., 2 or 4 frames per effect), where phase repetition could otherwise accumulate charge.

### Frame Time Stability
  
Occasional flicker may occur with unstable frame rates or frame times. This is barely noticeable with proper V-Sync/G-Sync/FreeSync enabled.

## Support and Contact

**Buy me a beer**: [PayPal](https://www.paypal.com/donate/?hosted_button_id=M7ZZ8WVFA5WCS)

[Twitter/X](https://x.com/MaximLapounov)

## License

MIT License - See LICENSE file for details
