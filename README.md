# CRT Dusha (Soul)
### Authentic CRT phosphor decay simulation shader with motion blur reduction and Voodoo2-style color quantization features.
![quake](https://github.com/user-attachments/assets/4d4f8b6b-2858-498f-a341-40e03d48a10a)



Hi everyone! I'm a huge fan of classic arena shooters like *Quake* and *Unreal Tournament*. Back in the day, I even competed as a **Quake 2** and **Quake 3** champion. To recapture the feel of the CRT displays from my childhood, I looked for proper CRT effect shaders, but most existing options like various BFI and CRT beam emulators were either simply broken or just didn't deliver the authentic look I was after.

That's why I decided to create my own solution: **CRT Dusha** (Soul in Russian) **ReShade Shader**. It doesn't rely on fancy algorithms, the codebase is small, using mostly math and physics to simulate the phosphor decay CRTs had, which in my opinion was the soul of the lost tech (hence the shader name, *Dusha*). It's highly flexible and can recreate the look and feel of the monitors from your childhood, including the authentic image produced by **the greatest GPU ever—3dfx Voodoo2!** *RIP, but never forgotten!*

## Main features

- **Realistic Phosphor Decay**: Original multi-stage Fibonacci-weighted exponential decay model simulating per-channel phosphor persistence (red, green, blue decay at different rates, matching P22 or custom phosphor characteristics). This gives the image its soul back through vibrant, organic "breathing" contrast—producing colors exactly as 90s game and movie creators intended, avoiding the flat, washed-out visuals of modern sample-and-hold displays.
- **Advanced Gamma Shaping**: Power-law gamma combined with decay acts as "CRT HDR," restoring intended luminance curves in retro titles and bringing modern games closer to analog display behavior.    
- **Just-in-Time Processing**: Shader operates on the current frame only, minimizing input lag for the most responsive experience.  
- **Motion Blur Reduction**: Stroboscopic effect through rapid phosphor decay reduces sample-and-hold blur for sharper motion clarity.  
- **3dfx Voodoo2 Pipeline**: Optional 16-bit RGB565 color quantization with Bayer ordered dithering (2x2, 4x4, 8x8 matrices) for authentic mid-90s graphics card aesthetic.  
- **Brightness Preservation**: Maintains image brightness through decay-based approach rather than black frame insertion.  
- **Two Decay Modes**: Uniform Pulse: Global flash and decay (original concept, creative CRT effect). Raster Sweep: Vertical scan beam simulation (classic CRT top-to-bottom refresh variation). 
- **Lower-end Device Optimized**: Specifically tuned for Steam Deck OLED performance.  
- **DX9 Compatible**: Shader Model 3.0 support for older games.

## Requirements

- ReShade 4.0 or higher. Reshadeck for Steam Deck OLED.
- Game/app must be compatible with DirectX 9/10/11/12, OpenGL, or Vulkan.
- ShaderGlass works with Reshade.

**Frame Synchronization (Important!)**

Like all shaders of this type, the effects are frame-based, so you need frame-rate synchronization:

- High refresh rate displays and high framerate: Use V-Sync (the shader's motion blur reduction compensates for V-Sync's slight input lag)
- Variable refresh rate displays: Use G-Sync/FreeSync with frame capping (standard 3-5 fps below the monitor's max Hz). 
- Low refresh rate display (like 90Hz SDO): Aim for maximum stable fps + V-Sync (with SDO Game Mode you can use Disable Frame Limit and Allow Tearing for better input lag; Gamescope has its own V-Sync always on, even with fps exceeding the panel's 90Hz refresh rate)

**Simply put**: Sync your monitor refresh rate with your in-game FPS. That's the primary requirement. Otherwise, the shader is plug-and-play.

**Optional Enhancements**

1000Hz+, HDR, and OLED are beneficial (effects will look and feel better) but not required. All development and testing was done on a 4-year-old 165Hz IPS panel and 90Hz Steam Deck OLED.

**What's NOT Included**

Besides simple scanlines and Trinitron-like vertical RGB color separation, no CRT masks, halation, or other bells and whistles are included. **CRT Dusha focuses purely on phosphor behavior and motion response**. You can use any mask shader you like, there are hundreds available. I personally prefer simple Trinitron-style masks.

**Usage Tips**

- For the most realistic results, apply mask shaders after CRT Dusha in the ReShade chain
- **Steam Deck OLED**: Use 2 frames per decay to avoid flicker at 90Hz
- Feel free to experiment with different combinations to find what works best for you

## Known Limitations

#### LCD Image Retention (DC Voltage Buildup)

On LCD panels, repeated transitions between bright and very dark frames can cause ions inside the liquid crystal layer to drift over time. This ion drift creates a DC voltage buildup in the pixel cells, which manifests as temporary image retention ("burn-in"). This is a physical panel behavior, not a shader bug, and it only occurs with high-contrast static images displayed for extended periods.

**Examples**:

- Leaving your game paused with static high-contrast menus (e.g., Doom Eternal)
- ReShade overlays left visible for extended periods
- Any UI elements with bright/dark patterns that don't change

Mitigation: Use odd "Frames Per Effect" values (3, 5, 7, etc.) when displaying static content. This breaks up the repetitive pattern and prevents DC voltage buildup.

**Why no automatic protection?**

After extensive testing of various compensation methods, I chose not to implement automatic protection because:

- No perfect solution exists without compromising the CRT effect
- Most modern LCDs have built-in protection mechanisms (which conflict with shader-based techniques anyway)
- The default 4-frame decay window produces slow falloff, greatly reducing severity, only extreme cases (high contrast + 2-frame decay + static imagery) exhibit noticeable retention
- Retention fades naturally as soon as motion resumes
- For static content, simply switch to odd "Frames Per Effect" values
- OLEDs are getting cheaper and don't have these retention problems

#### Frame Time Stability
  
Occasional flicker may occur with unstable frame rates or frame times. This is barely noticeable with proper V-Sync/G-Sync/FreeSync enabled.

## Support

I have spent several weeks developing and testing this shader. If you find it useful and want to support me:

**Buy me a beer**: [PayPal](https://www.paypal.com/donate/?hosted_button_id=M7ZZ8WVFA5WCS)

**Or a cofee**: [Ko-fi](https://ko-fi.com/maximlapounov)

## Contact

If you are interested in contacting me, you can reach me on: 

[Twitter/X](https://x.com/MaximLapounov)

[Patreon](https://www.patreon.com/cw/MaximLapounov)


## License

MIT License - See LICENSE file for details
