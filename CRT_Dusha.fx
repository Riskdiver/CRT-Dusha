//***************************************************************************************//
//
//  MIT License
//
//  Copyright (c) 2025 Maxim Lapounov
//  Twitter/X: @MaximLapounov
//
//  Permission is hereby granted, free of charge, to any person obtaining a copy
//  of this software and associated documentation files (the "Software"), to deal
//  in the Software without restriction, including without limitation the rights
//  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
//  copies of the Software, and to permit persons to whom the Software is
//  furnished to do so, subject to the following conditions:
//
//  The above copyright notice and this permission notice shall be included in all
//  copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
//  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
//  SOFTWARE.
//
//***************************************************************************************//

//---------------------------------------------------------------------------------------
//  CRT Dusha (Soul) ReShade FX Shader
//  Realistic Multi-stage Fibonacci-weighted Exponential Phosphor Decay
//  License: MIT
//  Version: 1.2
//---------------------------------------------------------------------------------------

// NOTE: This shader works in gamma-encoded space (not linear) for three reasons:
//
// 1. Gamma space better approximates CRT phosphor decay and persistence effects.
//    The perceptually-weighted precision distribution produces more natural trailing.
// 2. Matches Voodoo2 hardware behavior (quantization in gamma space).
// 3. Real CRTs never linearized their signal path, and human vision is nonlinear,
//    so gamma space is a closer fit to how the original hardware actually behaved.
//

//----------------------------------------------------------------------------------------------------------------
// Pipeline:
//
// sRGB(~2.2 encoded source)                // Game image as provided by GPU
//      ↓
// pow(BeamVoltage)                         // Power-law response = CONTRAST (beam voltage → phosphor excitation) 
//      ↓
// + MidtoneContrast                        // Nonlinear punch in midtones for analog 'pop' (color-preserving parabola)
//      ↓
// ± Quantize16Bit + Dither (optional)      // Ordered noise in gamma space (Voodoo2 / DAC precision simulation)
//                                          // Adds analog-like grain, enhancing texture and masking banding.
//      ↓
// × BeamCurrent                            // Linear amplitude scaling = BRIGHTNESS (beam current intensity)
//      ↓
// × Decay(stages, exponential per-color)   // Phosphor persistence (temporal trail / motion blending)
//      ↓
// + Softclip(ToneMapStrength)              // Analog highlight compression (Reinhard-style rolloff)
//      ↓
// monitor(÷2.2)                            // Gamma correction by display (sRGB monitor)
//      ↓
// perceived ≈ gamma 2.4–2.8 (typical CRT)  // Matches analog CRT luminance response
//                                          // Shader power-law can simulate any gamma curve (0 → ∞),
//                                          // though practical visual range is usually 0.5–5.0
// ----------------------------------------------------------------------------------------------------------------

// === PRESETS ===
uniform int Preset <
    ui_type = "combo";
    ui_label = "Color Preset";
    ui_items = "Manual\0Vibrant\0Old TV\0";
    ui_tooltip = "Reset to defaults before use.\n\nManual: Use slider settings.\nVibrant: Punchy colors, artistic effect, no black frames (Contrast 2.0, Brightness 40.0, Softclip 0.9, Decay Speed 1.0).\nOld TV: Warm vintage feel, 288 scanlines at 1440p (Contrast 1.5, Brightness 5.0, Softclip 0.85, Saturation 1.1,\nHue 2.0, Phosphor Tint RGB(255, 242, 217), Scanlines 3px with 2px gaps, Scanline Darkness 0.5, Decay Speed 8.0).\n\nNOTE: When a preset is active, sliders used by that preset are ignored.";
> = 0;

// === CRT TIMING ===
uniform int FramesPerEffect < 
    ui_category="CRT Timing"; 
    ui_type="slider"; 
    ui_min=1; ui_max=12; ui_step=1; 
    ui_label="Frames per Decay Cycle"; 
    ui_tooltip="Duration of full decay cycle in frames. Decay is an extended and more complex version of a display trick technique called BFI (Black Frame Insertion). \nEach cycle consists of one bright frame followed by progressively darker frames as the phosphor decays. \nExample: At 160hz with 4 frames per cycle - 1 bright frame + 3 decay frames = 40 visible bright frames per second. 2 frames per decay - 1 bright + 1 dark/black is simple BFI (50/50). \nHigher number of dark/black frames in cycle improves motion clarity up to a point, but reduces perceived brightness and may cause flicker at lower framerates. \nThis and the options below control the decay cycle behaviour. Fine-tune to get the right balance of bright/dark/black frames for your specific use case.\n\nNOTE: EVEN number of frames per cycle may cause temporary image retention/burn-in on LCD displays. 1 bright + 1 black (pure BFI) will cause it quicker. ODD numbers and OLED are safe.\nMild protection is enabled by default but can be further tuned in the LCD Burn-in Protection section.";
> = 3;

uniform int DecayMode < 
    ui_category="CRT Timing"; 
    ui_type="combo"; 
    ui_items="Uniform Pulse\0Raster Sweep\0"; 
    ui_label="Decay Mode"; 
    ui_tooltip="Decay simulation type:\n\nUniform Pulse: all pixels decay in sync.\nRaster Sweep: decay phase offset increases from top to bottom.";
> = 0;

uniform float RasterFrequency < 
    ui_category="CRT Timing"; 
    ui_type="slider"; 
    ui_min=0.001; ui_max=1.0; ui_step=0.001; 
    ui_label="Raster Frequency Multiplier"; 
    ui_tooltip="Adjusts the speed/spacing of Raster Sweep mode."; 
> = 0.050;

uniform float DebugSlowFactor < 
    ui_category="CRT Timing"; 
    ui_type="slider"; 
    ui_min=1.0; ui_max=500.0; ui_step=1.0; 
    ui_label="Debug: Slow Motion Factor"; 
    ui_tooltip="Slows down the decay/timing simulation for debugging or demonstration."; 
> = 1.0;

uniform bool DebugFrameStep < 
    ui_label = "Debug: Slow Motion Frame Step";
    ui_category="CRT Timing";  
    ui_tooltip="Locks decay cycle to discrete frame steps instead of continuous interpolation. \nUse with Slow Motion Factor to step through each frame of the decay cycle one at a time for debugging or demonstration purposes. \nCurrent frame number is displayed in the top right corner of the screen."; 
>;

// === CRT DISPLAY ===
uniform float BeamVoltage < 
    ui_category="CRT Display"; 
    ui_type="slider"; 
    ui_min=0.01; ui_max=10.0; ui_step=0.01; 
    ui_label="Contrast";
    ui_tooltip="Controls image contrast via gamma curve.\n\nHigher values can be compensated with Brightness to create more vivid image.\n\nTechnical: Simulates electron beam accelerating voltage affecting the phosphor's power-law response curve."; 
> = 1.0;

uniform float BeamCurrent < 
    ui_category="CRT Display"; 
    ui_type="slider"; 
    ui_min=0.1; ui_max=1000.0; ui_step=1.0; 
    ui_label="Brightness"; 
    ui_tooltip="Controls overall image brightness.\n\nCompensates for the darkening from contrast curve. Adjust together with Contrast for best results, higher Contrast needs higher Brightness.\n\nTechnical: Simulates electron beam current strength (number of electrons striking the phosphor per frame)."; 
> = 1.0;

uniform float MidtoneContrast < 
    ui_category="CRT Display"; 
    ui_type="slider"; 
    ui_min=0.0; ui_max=50.0; ui_step=0.01; 
    ui_label="Midtone Boost"; 
    ui_tooltip="Boosts contrast in midtones without crushing shadows or blowing highlights too much. Can be used to fine-tune authentic CRT punch."; 
> = 0.30;

uniform float ToneMapStrength < 
    ui_category="CRT Display"; 
    ui_type="slider"; 
    ui_min=0.00; ui_max=1.0; ui_step=0.01; 
    ui_label="Softclip Strength"; 
    ui_tooltip = "Phosphor saturation compression strength.\n\n0.0 = Disabled (default) - no highlight rolloff. At default Contrast (1.0) and Brightness (1.0) this produces the most accurate CRT-like output with no extra processing applied to highlights.\n\n0.1 - 0.9 = Partial compression - softens highlights progressively. Useful when boosting Contrast and Brightness above defaults.\n\n1.0 = Full Reinhard softclip - strong highlight rolloff. Physically models phosphor saturation at high beam drive levels. Recommended when using high Contrast/Brightness values to prevent harsh clipping.";
> = 0.0;

// === COLOR ADJUSTMENT ===
uniform float Saturation < 
    ui_category="CRT Display"; 
    ui_type="slider"; 
    ui_min=0.0; ui_max=2.0; ui_step=0.01; 
    ui_label="Color Saturation"; 
    ui_tooltip="Adjusts color intensity. 0 = grayscale, 1 = normal, >1 = oversaturated.\n\nTypical CRT TV 'Color' control."; 
> = 1.0;

uniform float3 TintColor <
    ui_category = "CRT Display";
    ui_type = "color";
    ui_label = "Phosphor Tint";
    ui_tooltip = "Tints the image with a color cast. Set Color Saturation to 0 first for true monochrome phosphor effect.\n\nWhite: no tint (default)\nGreen: P31 terminal monitor\nAmber: P3 amber monitor\nCool blue-white: cold phosphor";
> = float3(1.0, 1.0, 1.0);

uniform float Hue < 
    ui_category="CRT Display"; 
    ui_type="slider"; 
    ui_min=-180.0; ui_max=180.0; ui_step=0.1; 
    ui_label="Hue Shift"; 
    ui_tooltip="Shifts all colors around the color wheel. ±180° range.\n\nTypical CRT TV 'Hue' control."; 
> = 0.0;

// === PHOSPHOR DECAY ===
uniform float DecaySpeed < 
    ui_category="Phosphor Decay"; 
    ui_type="slider"; 
    ui_min=0.01; ui_max=50.0; ui_step=0.01; 
    ui_label="Global Decay Speed"; 
    ui_tooltip="Overall speed of phosphor decay. Higher = decay cycle fades to black quicker (more dark/black frames). \n\nFaster decay increases motion clarity but creates stroboscopic 'judder' as the eye loses temporal information between frames."; 
> = 10.0;

uniform int DecayLevels < 
    ui_category="Phosphor Decay"; 
    ui_type="slider"; 
    ui_min=1; ui_max=10; ui_step=1; 
    ui_label="Decay Stages"; 
   ui_tooltip="Number of exponential decay stages. More stages = darker later frames and a richer decay curve shape.";
> = 5;

uniform float DecayMultR < 
    ui_category="Phosphor Decay"; 
    ui_type="slider"; 
    ui_min=0.01; ui_max=5.0; ui_step=0.01; 
    ui_label="Red Decay Multiplier"; 
    ui_tooltip="Relative decay speed for red phosphors (vs global). Lower = longer persistence, higher = faster fade. \nHigher values for RGB phosphors only have noticeable effect at low Global Decay Speed settings."; 
> = 0.50;

uniform float DecayMultG < 
    ui_category="Phosphor Decay"; 
    ui_type="slider"; 
    ui_min=0.01; ui_max=5.0; ui_step=0.01; 
    ui_label="Green Decay Multiplier"; 
    ui_tooltip="Relative decay speed for green phosphors (vs global). Green typically decays faster than red."; 
> = 0.60;

uniform float DecayMultB < 
    ui_category="Phosphor Decay"; 
    ui_type="slider"; 
    ui_min=0.01; ui_max=5.0; ui_step=0.01; 
    ui_label="Blue Decay Multiplier"; 
    ui_tooltip="Relative decay speed for blue phosphors (vs global). Blue phosphors usually have the fastest decay."; 
> = 0.70;

// === 3dfx Voodoo2 PIPELINE ===
uniform bool Quantize16Bit < 
    ui_category="3dfx Voodoo2"; 
    ui_label="Enable Voodoo2 Quantize to 16-bit (5:6:5)"; 
    ui_tooltip="Simulates Voodoo2 16-bit framebuffer color precision by quantizing to 5-bit red, 6-bit green, 5-bit blue (RGB565)."; 
> = false;

uniform int DitherSize < 
    ui_category="3dfx Voodoo2"; 
    ui_type="combo"; 
    ui_items="2x2\0""4x4\0""8x8\0"; 
    ui_label="V2 Bayer Dither Size"; 
    ui_tooltip="Matrix size for Bayer ordered dithering:\n\n2x2 = finest pattern, least visible, fewer unique threshold values.\n4x4 = closest to original Voodoo2 dither pattern, default and recommended.\n8x8 = largest pattern, most visible structure, best banding reduction at higher resolutions.\n\nVoodoo2 used a small ordered dither pattern for RGB565, exact implementation was undocumented.\nTry different sizes at your resolution for best results - larger matrices work better at higher resolutions.";
> = 1;

uniform float DitherStrength < 
    ui_category="3dfx Voodoo2"; 
    ui_type="slider"; 
    ui_min=0.0; ui_max=2.0; ui_step=0.01; 
    ui_label="V2 Dither Strength"; 
    ui_tooltip="Strength of the Bayer dithering pattern.\n\n0.0 = no dithering, banding visible.\n1.0 = default, recommended starting point.\nHigher = more aggressive dithering, pattern becomes visible.";> = 1.0;

// === SCANLINES ===
uniform int ScanlineDirection <
    ui_category="Scanlines";
    ui_type="combo";
    ui_items="Horizontal\0Vertical\0Trinitron\0Crosshatch\0";
    ui_label="Scanline Direction";
    ui_tooltip="Direction of scanline pattern:\n\nHorizontal = typical CRT raster lines.\nVertical = can simulate aperture grille.\nTrinitron = horizontal scanlines + vertical RGB color separation.\nCrosshatch = grid pattern (combined H+V).";
> = 0;

uniform float ScanlineThickness < 
    ui_category="Scanlines"; 
    ui_type="slider"; 
    ui_min=1.0; ui_max=8.0; ui_step=1.0; 
    ui_label="Scanline Width (pixels)"; 
    ui_tooltip="Width of the bright scanline in pixels.\n\n1-2px = fine, good for simulating a CRT monitor at higher resolutions.\n3-4px = medium, good for simulating a TV (e.g. 3px bright + 2px gap = 288 lines at 1440p).\n5-8px = thick, good for 4K or oversized TV effect."; 
> = 2.0;

uniform float ScanlineGapSize < 
    ui_category="Scanlines"; 
    ui_type="slider"; 
    ui_min=0.0; ui_max=4.0; ui_step=1.0; 
    ui_label="Scanline Gap Width (pixels)"; 
    ui_tooltip="Width of the dark gap between bright scanlines in pixels.\n\n0 = disabled, no scanline pattern applied.\n1 = subtle gap.\n2 = moderate.\n3-4 = pronounced.";
> = 0.0;

uniform float ScanlineDarkness < 
    ui_category="Scanlines"; 
    ui_type="slider"; 
    ui_min=0.0; ui_max=1.0; ui_step=0.01; 
    ui_label="Gap Darkness"; 
    ui_tooltip="How dark the gaps between scanlines appear.\n\n0.0 = no darkening (gaps invisible).\n0.3 = subtle gaps.\n0.5 = moderate gaps.\n0.8 = very dark gaps."; 
> = 0.5;

uniform float ApertureGrilleStrength <
    ui_category="Scanlines";
    ui_type="slider";
    ui_min=0.0; ui_max=1.0; ui_step=0.05;
    ui_label="Trinitron Color Separation";
    ui_tooltip="Controls the intensity of vertical RGB color separation in Trinitron mode.\n\n0.0 = no color separation (disabled).\n0.15 = subtle, authentic.\n0.3 = moderate.\n1.0 = maximum separation.\n\nProduces the characteristic Trinitron greenish tint due to the green stripe dominance in the aperture grille.";
> = 0.15;

// === SPLIT SCREEN COMPARISON ===
uniform bool EnableSplitScreen <
    ui_category="Split Screen Comparison";
    ui_label="Enable Split Screen";
    ui_tooltip="Shows shader effect on left half, original image on right half for comparison.";
> = false;

uniform float SplitPosition <
    ui_category="Split Screen Comparison";
    ui_type="slider";
    ui_min=0.0; ui_max=1.0; ui_step=0.01;
    ui_label="Split Position";
    ui_tooltip="Adjusts the vertical dividing line position.\n\n0.0 = all original.\n0.5 = centered split.\n1.0 = all effect.";
> = 0.5;

uniform bool ShowDividerLine <
    ui_category="Split Screen Comparison";
    ui_label="Show Divider Line";
    ui_tooltip="Draws a visible line at the split position.";
> = true;

// === LCD BURN-IN PROTECTION ===
uniform bool LCDSafeMode <
    ui_category="LCD Burn-in Protection";
    ui_label="Enable LCD Safe Mode";
    ui_tooltip="Prevents burn-in/image retention on LCD displays by periodically breaking same frames/phases pattern.\n\nOnly needed for EVEN Frames per Decay on LCD panels. Causes brief phase flip.\n\nNot needed for: ODD Frames per Decay or OLED displays.";
> = true;

uniform int PhaseFlipMethod <
    ui_category="LCD Burn-in Protection / Phase Flip";
    ui_type="combo";
    ui_items="Phase Jump\0Frame Drop\0";
    ui_label="Phase Flip Method";
    ui_tooltip="Phase Jump: Jumps phase after accumulating enough offset.\nFrame Drop: Skip frame every interval.";
> = 0;

uniform float JumpRate <
    ui_category="LCD Burn-in Protection / Phase Flip";
    ui_type="slider";
    ui_min=0.0001; ui_max=0.1; ui_step=0.0001;
    ui_label="Phase Jump Rate";
    ui_tooltip="Controls the rate at which phase offset accumulates when using the Phase Jump method.\n\n0.0001 = very slow, non-intrusive jumps.\n0.001 = slow, subtle.\n0.01 = fast, noticeable.\n0.1 = very fast.";
> = 0.0001;

uniform int FlipRate <
    ui_category="LCD Burn-in Protection / Phase Flip";
    ui_type="slider";
    ui_min=1000; ui_max=100000; ui_step=1;
    ui_label="Frame Drop Interval";
    ui_tooltip="Defines how often phase flipping occurs when using the Frame Drop methods (measured in frames).\n\n1000 = maximum safety, frequent flips.\n5000 = balanced, less frequent flips.\n10000+ frames = minimal disruption, slower protection.";
> = 1000;

//--------------------------------------------------------------------------------
// Runtime Parameters (provided by ReShade runtime)
#include "ReShade.fxh"
uniform int FrameCount < source="framecount"; >;

//--------------------------------------------------------------------------------
// Compile-time constants 
#define PHI 1.61803398875 // Golden ratio
#define MAX_DECAY_LEVELS 10
#define INV_31 0.032258064516129 // 1/31
#define INV_63 0.015873015873016 // 1/63

//--------------------------------------------------------------------------------
// Bayer Dither Matrices (2x2, 4x4, 8x8)
static const int bayer2[4] = {0, 2, 3, 1};
static const int bayer4[16] = {
     0,  8,  2, 10,
    12,  4, 14,  6,
     3, 11,  1,  9,
    15,  7, 13,  5
};
static const int bayer8[64] = {
     0, 32,  8, 40,  2, 34, 10, 42,
    48, 16, 56, 24, 50, 18, 58, 26,
    12, 44,  4, 36, 14, 46,  6, 38,
    60, 28, 52, 20, 62, 30, 54, 22,
     3, 35, 11, 43,  1, 33,  9, 41,
    51, 19, 59, 27, 49, 17, 57, 25,
    15, 47,  7, 39, 13, 45,  5, 37,
    63, 31, 55, 23, 61, 29, 53, 21
};

//--------------------------------------------------------------------------------
// Digit overlay for debug frame counter
// 4-wide x 5-tall bitmap per digit
// Usage: call DrawFrameCounter() at end of shader before return
// digit pixel lookup: digits 0-9, 5 rows, 4 cols packed as bools
static const int digitRows[50] = {
    0xE, 0xA, 0xA, 0xA, 0xE, // 0
    0x4, 0xC, 0x4, 0x4, 0xE, // 1
    0xE, 0x2, 0xE, 0x8, 0xE, // 2
    0xE, 0x2, 0x6, 0x2, 0xE, // 3
    0xA, 0xA, 0xE, 0x2, 0x2, // 4
    0xE, 0x8, 0xE, 0x2, 0xE, // 5
    0xE, 0x8, 0xE, 0xA, 0xE, // 6
    0xE, 0x2, 0x4, 0x4, 0x4, // 7
    0xE, 0xA, 0xE, 0xA, 0xE, // 8
    0xE, 0xA, 0xE, 0x2, 0xE, // 9
};

int DigitPixel(int d, int col, int row) {
    int val = digitRows[d * 5 + row];
    int shift = 3 - col;
    int divided = val;
    for (int i = 0; i < shift; i++)
        divided /= 2;
    return divided % 2;
}

float DrawDigit(int d, int2 pixel, int2 origin, int scale) {
    int2 local = pixel - origin;
    if (local.x < 0 || local.x >= 4 * scale) return 0.0;
    if (local.y < 0 || local.y >= 5 * scale) return 0.0;
    return DigitPixel(d, local.x / scale, local.y / scale) ? 1.0 : 0.0;
}

//--------------------------------------------------------------------------------
// Frame Sampling
float3 GetFrame(float2 uv) {
    return tex2Dlod(ReShade::BackBuffer, float4(uv, 0, 0)).rgb;
}

//--------------------------------------------------------------------------------
// Fetch Bayer Dither Value (normalized to 0..1 range) (modulo instead of bitwise for dx9 compatability)
float GetBayerDither(int2 pixel, int size) {
    if (size == 0) return bayer2[(pixel.y % 2) * 2 + (pixel.x % 2)] * 0.333333333;
    if (size == 1) return bayer4[(pixel.y % 4) * 4 + (pixel.x % 4)] * 0.066666667;
    return bayer8[(pixel.y % 8) * 8 + (pixel.x % 8)] * 0.015873016;
}

//--------------------------------------------------------------------------------
// Main Pixel Shader
float4 PS_Dusha(float4 pos : SV_Position, float2 texcoord : TEXCOORD) : SV_Target
{
    // --- Get preset-overridden values ---
    float beamVoltage = BeamVoltage;
    float beamCurrent = BeamCurrent;
    float midtoneContrast = MidtoneContrast;
    float toneMapStrength = ToneMapStrength;
    float saturation = Saturation;
    float hue = Hue;
    float3 tintColor = TintColor;
    float decaySpeed = DecaySpeed;
    float ditherStrength = DitherStrength;
    bool quantize16Bit = Quantize16Bit;
    float scanlineDarkness = ScanlineDarkness;
    float scanlineThickness = ScanlineThickness;
    float scanlineGapSize = ScanlineGapSize;

    switch (Preset)
    {
        case 1: beamVoltage = 2.0; beamCurrent = 40.0; toneMapStrength = 0.9; decaySpeed = 1.0; break;
        case 2: beamVoltage = 1.5; beamCurrent = 5.0; toneMapStrength = 0.85; saturation = 1.1; hue = 2.0; tintColor = float3(1.0, 0.95, 0.85); decaySpeed = 8.0; scanlineDarkness = 0.5; scanlineThickness = 3.0; scanlineGapSize = 2.0; break;        
        default: break; // Manual: keep uniforms
    }

    // --- LCD Burn-in Protection ---
    int effectiveFrameCount = FrameCount;

    if (LCDSafeMode && (FramesPerEffect % 2 == 0))
    {
        int protectionInterval = FlipRate;

        // Ensure interval doesn't align perfectly with decay cycle
        if ((protectionInterval % FramesPerEffect) == 0)
            protectionInterval += 1;

        if (PhaseFlipMethod == 0)
        {
            // Method 1: Phase Jump - discrete jumps
            effectiveFrameCount += int(FrameCount * JumpRate);
        }
        else if (PhaseFlipMethod == 1)
        {
            // Method 2: Frame Drop - skip frames to shift phase
            effectiveFrameCount -= FrameCount / protectionInterval;
        }
    }

    // --- CRT timing simulation ---
    const float rawFraction = frac((effectiveFrameCount * rcp(DebugSlowFactor) * rcp(FramesPerEffect)));
    const float fraction = DebugFrameStep ? floor(rawFraction * FramesPerEffect) * rcp(FramesPerEffect) : rawFraction;

    // --- Sample source frame (sRGB encoded, ~2.2 gamma) ---
    float3 frameCurr = GetFrame(texcoord);

    // --- Apply CRT power-law curve: simulates phosphor response to electron beam voltage (contrast shaping, nonlinear gamma) ---
    frameCurr = pow(frameCurr, beamVoltage);

    // --- Midtone contrast boost. Parabola peaks at 0.5, multiplicative so blacks are unaffected. ---
    float3 midtone = frameCurr * (1.0 - frameCurr) * 4.0;
    frameCurr += frameCurr * midtone * midtoneContrast;
    
    // --- Compute Bayer dither value ---
    int2 pixelCoord = int2(pos.xy);
    float ditherVal = GetBayerDither(pixelCoord, DitherSize);

    // --- Apply optional Voodoo2 16-bit quantization and dithering ---
    float d = (ditherVal - 0.5) * ditherStrength;

    if (quantize16Bit) {
        frameCurr.r = floor(clamp(frameCurr.r * 31.0 + d, 0.0, 31.0)) * INV_31;
        frameCurr.g = floor(clamp(frameCurr.g * 63.0 + d, 0.0, 63.0)) * INV_63;
        frameCurr.b = floor(clamp(frameCurr.b * 31.0 + d, 0.0, 31.0)) * INV_31;
    }

    // --- Apply electron gun current ---
    frameCurr *= beamCurrent;

    // --- Apply timing ---
    float decayPhase;
    if (DecayMode == 0) {
        // Uniform global pulse
        decayPhase = fraction;
    } else {
        // Vertical raster sweep (top-to-bottom fade)
        decayPhase = frac((1.0 - texcoord.y) * RasterFrequency + fraction);
    }

    // --- Multi-stage Per-Channel Exponential Phosphor Decay ---
    //
    // Each stage contributes a different slope at a different rate, their weighted sum
    // producing a complex multi-slope curve that a single exponential cannot replicate.
    // The decay cycle samples this curve at N points (Frames Per Cycle), repeated
    // at the monitor refresh rate - the richer curve shape reads as more natural phosphor
    // persistence compared to a plain single exponential.
    //
    // Per-channel decay multipliers (DecayMultR/G/B) allow independent timing per
    // color channel, mimicking real phosphor chemistry where R/G/B components
    // decay at different rates (P22-style).
    // Early versions used fully independent φ multipliers and decay lengths per channel
    // (phiR/G/B, DecayLengthR/G/B) for ultra-accurate phosphor chemistry. Simplified
    // to a unified φ cascade with per-channel multipliers, preserving perceptual
    // accuracy while reducing GPU cost.
    //
    // [unroll] generates fixed instruction count regardless of DecayLevels,
    // ensuring consistent performance on lower-end devices like Steam Deck.
    //
    // Native exp() is NON-NEGOTIABLE: φ-weighted exponential decay is sensitive
    // to precision - approximations (exp2, fast_exp etc.) degrade the curve shape.

    const float3 decayMult = float3(DecayMultR, DecayMultG, DecayMultB);
    const float decayBase = -decayPhase * decaySpeed;
    float scale = 1.0;
    float3 decay = 0.0;
    float sum = 0.0;

    [unroll]
    for (int i = 0; i < MAX_DECAY_LEVELS; ++i) {
        if (i < DecayLevels) {
            decay += scale * exp(decayBase * scale * decayMult);
            sum += scale;
            scale *= PHI;
        }
    }

    decay *= rcp(sum);

    // --- Apply phosphor decay ---
    float3 phosphorEmission = frameCurr * decay;

    // --- Apply static scanlines ---
    if (scanlineDarkness > 0.0) {
        float scanlineMask = 1.0;
        
        // Only apply scanline pattern if gaps are enabled
        if (scanlineGapSize > 0.0) {
            // Convert to integers to ensure pixel-perfect, consistent patterns
            int brightWidth = int(scanlineThickness);  // Width of bright scanline (phosphor glow)
            int gapWidth = int(scanlineGapSize);       // Width of dark gap between scanlines
            int scanlinePattern = brightWidth + gapWidth;  // Total pattern size in pixels
            
            if (ScanlineDirection == 0) { // Horizontal scanlines
                // Calculate which pixel we're at within the repeating pattern (0 to scanlinePattern-1)
                int pixelInPattern = int(pos.y) % scanlinePattern;
                
                // Gap-first pattern: dark pixels come first (0 to gapWidth-1), then bright pixels
                scanlineMask = pixelInPattern < gapWidth ? (1.0 - scanlineDarkness) : 1.0;
                
            } else if (ScanlineDirection == 1) { // Vertical scanlines
                int pixelInPattern = int(pos.x) % scanlinePattern;
                scanlineMask = pixelInPattern < gapWidth ? (1.0 - scanlineDarkness) : 1.0;
                
            } else if (ScanlineDirection == 2) { // Trinitron mode (horizontal scanlines + vertical aperture grille)
                // Apply horizontal scanlines
                int pixelInPatternH = int(pos.y) % scanlinePattern;
                float maskH = pixelInPatternH < gapWidth ? (1.0 - scanlineDarkness) : 1.0;
                
                // Apply Trinitron aperture grille (vertical RGB phosphor stripes)
                // Each pixel is divided into R, G, B sub-pixels (3 stripes per pixel)
                int subPixel = int(pos.x * 3.0) % 3;  // 0=R, 1=G, 2=B

                // Calculate dimming for non-active channels
                float dimAmount = 1.0 - ApertureGrilleStrength;
                
                // Isolate color channels based on aperture grille position
                float3 apertureMask = float3(
                    subPixel == 0 ? 1.0 : dimAmount,  // Red stripe
                    subPixel == 1 ? 1.0 : dimAmount,  // Green stripe
                    subPixel == 2 ? 1.0 : dimAmount   // Blue stripe
                );
                
                // Apply both horizontal scanlines and vertical aperture grille
                phosphorEmission.rgb *= apertureMask * maskH;
                // Don't apply scanlineMask at the end for Trinitron mode
                scanlineMask = 1.0; // Set to 1.0 to skip the final multiplication below
                
            } else { // Crosshatch pattern
                // Calculate pattern position for both axes independently
                int pixelInPatternH = int(pos.y) % scanlinePattern;
                int pixelInPatternV = int(pos.x) % scanlinePattern;
                
                // Create separate masks for horizontal and vertical
                float maskH = pixelInPatternH < gapWidth ? (1.0 - scanlineDarkness) : 1.0;
                float maskV = pixelInPatternV < gapWidth ? (1.0 - scanlineDarkness) : 1.0;
                
                // Multiply masks together to create crosshatch grid
                // Dark gaps appear where either horizontal OR vertical gaps exist
                scanlineMask = maskH * maskV;
            }
        }
        
        // Apply the scanline mask to the phosphor emission
        // Bright scanlines remain at full intensity (1.0)
        // Dark gaps are dimmed by ScanlineDarkness amount
        phosphorEmission *= scanlineMask;
    }

    // --- Softclip ---
    float3 softclip = phosphorEmission / (1.0 + phosphorEmission);
    phosphorEmission = lerp(phosphorEmission, softclip, toneMapStrength);

    // --- Saturation adjustment ---
    if (saturation != 1.0) {
        float luma = dot(phosphorEmission, float3(0.299, 0.587, 0.114));
        phosphorEmission = lerp(float3(luma, luma, luma), phosphorEmission, saturation);
    }

    // --- Hue shift ---
    if (hue != 0.0) {  // skip matrix if no shift
        float angle = radians(hue);
        float s = sin(angle);
        float c = cos(angle);
        
        float3x3 hueMatrix = float3x3(
            0.299 + 0.701*c + 0.168*s,  0.587 - 0.587*c + 0.330*s,  0.114 - 0.114*c - 0.497*s,
            0.299 - 0.299*c - 0.328*s,  0.587 + 0.413*c + 0.035*s,  0.114 - 0.114*c + 0.292*s,
            0.299 - 0.299*c + 1.250*s,  0.587 - 0.587*c - 1.050*s,  0.114 + 0.886*c - 0.203*s
        );
        
        phosphorEmission = mul(hueMatrix, phosphorEmission);
    }

    // --- Phosphor Tint ---
    if (any(tintColor != float3(1.0, 1.0, 1.0)))
        phosphorEmission *= tintColor;

    // --- Split Screen Comparison Mode ---
    if (EnableSplitScreen) {
        // Get original unprocessed frame
        float3 original = GetFrame(texcoord);
        
        // Determine which side to show
        if (texcoord.x > SplitPosition) {
            phosphorEmission = original;
        }
        
        // Draw divider line (2-pixel wide vertical line)
        if (ShowDividerLine && abs(texcoord.x - SplitPosition) < 2.0 * BUFFER_RCP_WIDTH) {
            phosphorEmission = float3(1.0, 1.0, 1.0); // White divider line
        }
    }
    
    // --- Debug Frame Number Overlay ---
    if (DebugFrameStep) {
        int frameNum = int(floor(rawFraction * FramesPerEffect)) + 1;

        int2 pixel = int2(pos.xy);
        int scale = 4;
        int margin = 8;

        // How many digits wide is the display?
        int numDigits = FramesPerEffect >= 10 ? 2 : 1;
        int totalWidth = numDigits * 5 * scale; // 5 = 4 wide + 1 gap

        // Anchor to top-right
        int2 origin = int2(BUFFER_WIDTH - totalWidth - margin, margin);

        float ink = 0.0;
        if (FramesPerEffect >= 10)
            ink += DrawDigit(frameNum / 10, pixel, origin, scale);
        ink += DrawDigit(frameNum % 10, pixel, origin + int2((FramesPerEffect >= 10 ? 5 : 0) * scale, 0), scale);

        if (ink > 0.0)
            phosphorEmission = float3(1.0, 1.0, 0.0);
    }

    // Return as-is, preserves HDR-like bright highlights. Softclip (earlier in pipeline) handles extreme brightness gracefully. 
    // Should not have visual artifacts (negative colors, NaN issues), so no need for saturate()
    return float4(phosphorEmission, 1.0);
}

//--------------------------------------------------------------------------------
// Technique declaration
technique Dusha {
    pass { VertexShader = PostProcessVS; PixelShader = PS_Dusha; }
}
