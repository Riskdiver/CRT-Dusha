//***************************************************************************************//
//
//  MIT License
//
//  Copyright (c) 2025 Maxim Lapounov
//  Twitter/X: @MaximLapounov
//  Patreon: @MaximLapounov
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
//  Version: 1.1
//---------------------------------------------------------------------------------------

// NOTE: This shader intentionally works in gamma-encoded space (not linear) for three reasons:
//
// 1. Provides superior motion blur reduction and more authentic CRT phosphor decay
//    compared to linear-space processing. The perceptually-weighted precision distribution
//    in gamma space creates more realistic trailing/persistence effects.
// 2. Matches authentic Voodoo2 hardware behavior (quantization in gamma space)
// 3. Real CRTs never linearized their signal path. Human vision is nonlinear.
//
// However, we are not modelling CRT as a physical object, we are modelling the effects that CRT tech provided.

//----------------------------------------------------------------------------------------------------------------
// Pipeline:
//
// sRGB(~2.2 encoded source)                // Game image as provided by GPU
//      ↓
// pow(BeamVoltage)                         // Power-law response (beam voltage → phosphor excitation) = CONTRAST
//      ↓
// + MidtoneContrast                        // Nonlinear punch in midtones for analog 'pop' (color-preserving parabola)
//      ↓
// + Dither (+Quantize16Bit optional)       // Ordered noise in gamma space (Voodoo2 / DAC precision simulation)
//                                          // Adds analog-like grain, enhancing texture and masking banding.
//                                          // Interacts with decay: it can slightly reduce motion
//                                          // clarity by introducing fine temporal interference.
//                                          // Effect is strongest in Vertical Raster Sweep, weaker in Uniform
//                                          // Pulse.
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
// ---------------------------------------------------------------------------------------------------------------
// Optional controls:
// Hue & Saturation adjustments - analog color shift & saturation like TV controls
// BlackLevel floor - prevents full black collapse (residual CRT glow)


// === PRESETS ===
uniform int Preset <
    ui_type = "combo";
    ui_label = "Color Preset";
    ui_items = "Manual\0Flat sRGB\0Vibrant\0Quick Phosphor\0";
    ui_tooltip = "Reset to defaults before use. \n\nManual: Use slider settings.\nFlat sRGB: Standart 2.2 Gamma (Contrast 1.0, Brightness 2.0, Black Level 0.500).\nVibrant: High contrast, punchy colors (Contrast 2.0, Brightness 40.0).\nQuick Phosphor: CRT-like phosphor decay speed (Contrast 1.8, Brightness 60.0 Midtone Boost 5.0, Softclip Strength 1.00, Black Level 0.0, Decay Speed 25.0).\n\nNOTE: When a preset is active, slider changes used in preset are ignored by the shader.";
> = 0;

// === CRT TIMING ===
uniform int FramesPerEffect < 
    ui_category="CRT Timing"; 
    ui_type="slider"; 
    ui_min=1; ui_max=12; ui_step=1; 
    ui_label="Frames per Effect"; 
    ui_tooltip="Duration of full decay cycle in frames. Higher values = smoother decay but require higher refresh rates to avoid flicker.\n\nEVEN numbers: Best effect quality.\nODD numbers: Mediocre effect quality. Use when 'parking' the shader with static content to prevent LCD burn-in (breaks up DC voltage buildup).";
> = 4;

uniform int DecayMode < 
    ui_category="CRT Timing"; 
    ui_type="combo"; 
    ui_items="Uniform Pulse\0Raster Continuous Sweep\0"; 
    ui_label="Decay Mode"; 
    ui_tooltip="Decay simulation type:\n\nUniform Pulse: global flash + decay.\nRaster Continuous Sweep: smooth top-to-bottom beam motion.";
> = 1;

uniform float RasterFrequency < 
    ui_category="CRT Timing"; 
    ui_type="slider"; 
    ui_min=0.001; ui_max=10.0; ui_step=0.001; 
    ui_label="Raster Frequency Multiplier"; 
    ui_tooltip="Adjusts the speed/spacing of Raster Sweep mode."; 
> = 0.010;

uniform float DebugSlowFactor < 
    ui_category="CRT Timing"; 
    ui_type="slider"; 
    ui_min=1.0; ui_max=500.0; ui_step=1.0; 
    ui_label="Slow Motion Factor"; 
    ui_tooltip="Slows down the decay/timing simulation for debugging or demonstration."; 
> = 1.0;

// === CRT DISPLAY ===
uniform float BeamVoltage < 
    ui_category="CRT Display"; 
    ui_type="slider"; 
    ui_min=0.01; ui_max=5.0; ui_step=0.01; 
    ui_label="Contrast (Beam Voltage)";
    ui_tooltip="Controls image contrast via gamma curve. Higher values = darker mid-tones, brighter highlights.\n\nHigher values can be compensated with Brightness to create more vivid image.\n\nTechnical: Simulates electron beam accelerating voltage affecting the phosphor's power-law response curve."; 
> = 1.35;

uniform float BeamCurrent < 
    ui_category="CRT Display"; 
    ui_type="slider"; 
    ui_min=0.1; ui_max=1000.0; ui_step=0.01; 
    ui_label="Brightness (Beam Current)"; 
    ui_tooltip="Controls overall image brightness. Higher values = brighter image.\n\nCompensates for the darkening from contrast curve. Adjust together with Contrast for best results, higher contrast needs higher brightness.\n\nTechnical: Simulates electron beam current strength (number of electrons striking the phosphor per frame)."; 
> = 5.0;

uniform float MidtoneContrast < 
    ui_category="CRT Display"; 
    ui_type="slider"; 
    ui_min=0.0; ui_max=50.0; ui_step=0.01; 
    ui_label="Midtone Boost"; 
    ui_tooltip="Boosts contrast in midtones without crushing shadows or blowing highlights too much. Can be used to fine-tune authentic CRT punch."; 
> = 0.0;

uniform float ToneMapStrength < 
    ui_category="CRT Display"; 
    ui_type="slider"; 
    ui_min=0.00; ui_max=1.0; ui_step=0.01; 
    ui_label="Softclip Strength"; 
    ui_tooltip="Controls how aggressively highlights are compressed. Lower = subtle, higher = full Reinhard.\n\n0.0 - 0.3 = Punchy, high midtone contrast - best for 90s games, pixel art, CRT authenticity.\n0.4 - 0.6 = Balanced soft highlights - good for older PC games or mixed content.\n0.7 - 1.0 = Full Reinhard - cinematic or modern SDR/HDR content, preserves skin tones in movies."; 
> = 0.0;

// === COLOR ADJUSTMENT ===
uniform float Saturation < 
    ui_category="CRT Display"; 
    ui_type="slider"; 
    ui_min=0.0; ui_max=2.0; ui_step=0.01; 
    ui_label="Color Saturation"; 
    ui_tooltip="Adjusts color intensity. 0 = grayscale, 1 = normal, >1 = oversaturated.\n\nTypical CRT TV 'Color' control."; 
> = 1.0;

uniform float Hue < 
    ui_category="CRT Display"; 
    ui_type="slider"; 
    ui_min=-180.0; ui_max=180.0; ui_step=0.1; 
    ui_label="Tint (Hue Shift)"; 
    ui_tooltip="Shifts all colors around the color wheel. ±180° range.\n\nTypical CRT TV 'Tint' control."; 
> = 0.0;

uniform float BlackLevel < 
    ui_category="CRT Display"; 
    ui_type="slider"; 
    ui_min=0.0; ui_max=1.0; ui_step=0.001; 
    ui_label="Decay Black Level Floor"; 
    ui_tooltip="Minimum brightness floor. Prevents decay from reaching full black for a more realistic CRT glow."; 
> = 0.005;

// === PHOSPHOR DECAY ===
uniform float DecaySpeed < 
    ui_category="Phosphor Decay"; 
    ui_type="slider"; 
    ui_min=0.01; ui_max=25.0; ui_step=0.01; 
    ui_label="Global Decay Speed"; 
    ui_tooltip="Overall speed of phosphor decay. Higher = quicker fade into black. \n\nFaster decay increases motion clarity but creates stroboscopic 'judder' as the eye loses temporal information between frames."; 
> = 1.0;

uniform float DecayMultR < 
    ui_category="Phosphor Decay"; 
    ui_type="slider"; 
    ui_min=0.01; ui_max=5.0; ui_step=0.01; 
    ui_label="Red Decay Multiplier"; 
    ui_tooltip="Relative decay speed for red phosphors (vs global). Lower = longer persistence, higher = faster fade."; 
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

uniform int DecayLevels < 
    ui_category="Phosphor Decay"; 
    ui_type="slider"; 
    ui_min=1; ui_max=10; ui_step=1; 
    ui_label="Decay Stages"; 
    ui_tooltip="Number of exponential decay stages to blend. More = richer trailing effect but quicker fade into black."; 
> = 5;

// === DITHERING / 3dfx Voodoo2 PIPELINE ===
uniform int DitherSize < 
    ui_category="Dithering / 3dfx Voodoo2"; 
    ui_type="combo"; 
    ui_items="2x2\0""4x4\0""8x8\0"; 
    ui_label="Bayer Dither Size"; 
    ui_tooltip="Matrix size for Bayer ordered dithering:\n\n2x2 = finest grain.\n4x4 = medium structure.\n8x8 = coarse grid (authentic Voodoo2 look)\n\nCan simulate physical phosphor dot/mesh patterns on CRT screens or hide banding.";
> = 0;

uniform float DitherStrength < 
    ui_category="Dithering / 3dfx Voodoo2"; 
    ui_type="slider"; 
    ui_min=0.0; ui_max=10.0; ui_step=0.001; 
    ui_label="Dither Strength"; 
    ui_tooltip="Strength of dithering noise used to reduce banding.\n\n0.0 = maximum motion blur reduction (no dither)\n0.02 = subtle, balanced \nHigher = more visible grain\n\nWorks best with Quantize to 16-bit (5:6:5) for authentic 3dfx Voodoo2 output.";
> = 0.0;

uniform bool Quantize16Bit < 
    ui_category="Dithering / 3dfx Voodoo2"; 
    ui_label="Quantize to 16-bit (5:6:5)"; 
    ui_tooltip="Simulates a 16-bit color framebuffer by quantizing channels (5-bit red, 6-bit green, 5-bit blue).\n\nRecreates the limited color precision of the 3dfx Voodoo2 framebuffer."; 
> = false;

uniform bool TemporalDither < 
    ui_category="Dithering / 3dfx Voodoo2"; 
    ui_label="Enable Temporal Dithering"; 
    ui_tooltip="Animates the dithering pattern over time to reduce visible grid.\n\nNot authentic to CRT hardware or 3dfx Voodoo2 and can reduce motion clarity.\n\nOFF = authentic, maximum motion blur reduction (recommended).\nON = smoother appearance, reduced motion clarity."; 
> = false;

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
    ui_tooltip="Width of the bright scanline.\n\n1-2 = fine (good for 1080p).\n3-4 = medium (good for 1440p).\n5-8 = thick (good for 4K)."; 
> = 2.0;

uniform float ScanlineGapSize < 
    ui_category="Scanlines"; 
    ui_type="slider"; 
    ui_min=0.0; ui_max=4.0; ui_step=1.0; 
    ui_label="Scanline Gap Width (pixels)"; 
    ui_tooltip="Width of the dark gap between bright scanlines.\n\n0 = no gaps (solid).\n1 = subtle (authentic CRT).\n2 = moderate\n3-4 = pronounced."; 
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
    ui_label="Aperture Grille Strength (Trinitron)";
    ui_tooltip="Controls the intensity of vertical RGB color separation in Trinitron mode.\n\n0.0 = no color separation (disabled).\n0.3 = subtle, authentic.\n0.5 = moderate.\n1.0 = maximum separation.";
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
    ui_tooltip="Prevents burn-in/image retention on LCD displays by periodically breaking same frames/phases pattern.\n\nOnly needed for EVEN Frames per Effect on LCD panels. Causes brief phase flip.\n\nNot needed for: ODD Frames per Effect or OLED displays.";
> = true;

uniform int PhaseFlipMethod <
    ui_category="LCD Burn-in Protection / Phase Flip";
    ui_type="combo";
    ui_items="Phase Jump\0Phase Flip\0Frame Drop\0";
    ui_label="Phase Flip Method";
    ui_tooltip="Phase Jump: Jumps phase after accumulating enough offset.\nPhase Flip: Instant flip every interval.\nFrame Drop: Skip frame every interval.";
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
    ui_min=1; ui_max=3600; ui_step=1;
    ui_label="Phase Flip Interval";
    ui_tooltip="Defines how often phase flipping occurs (measured in frames).\n\n600 = balanced.\n1200 = maximum safety, more frequent disruption.\n1800+ frames = minimal disruption, slower protection.";
> = 600;

//--------------------------------------------------------------------------------
// Runtime Parameters (provided by ReShade runtime)
#include "ReShade.fxh"
uniform int FrameCount < source="framecount"; >;

//--------------------------------------------------------------------------------
// Compile-time constants 
#define PHI 1.61803398875 // Golden ratio. The specific rounding/precision of this value can create subtle irregularity in the decay cascade.
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
float4 PS_CRT_Dusha(float4 pos : SV_Position, float2 texcoord : TEXCOORD) : SV_Target
{
    // --- Get preset-overridden values ---
    float beamVoltage = BeamVoltage;
    float beamCurrent = BeamCurrent;
    float blackLevel = BlackLevel;
    float midtoneContrast = MidtoneContrast;
    float toneMapStrength = ToneMapStrength;
    float saturation = Saturation;
    float decaySpeed = DecaySpeed;
    float ditherStrength = DitherStrength;
    bool quantize16Bit = Quantize16Bit;

    switch (Preset)
    {
        case 1: beamVoltage = 1.0; beamCurrent = 2.0; blackLevel = 0.500; break;
        case 2: beamVoltage = 2.0; beamCurrent = 40.0; break;
        case 3: beamVoltage = 1.8; beamCurrent = 60.0; midtoneContrast = 5.0; toneMapStrength = 1.00; blackLevel = 0; decaySpeed = 25.00; break;
        default: break; // 0 Manual -> keep uniforms
    }

    // --- LCD Burn-in Protection ---
    int effectiveFrameCount = FrameCount;
    float phaseOffset = 0.0;

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
           // Method 2: Phase Flip - alternating polarity
            phaseOffset = 0.5 * ((FrameCount / protectionInterval) % 2);
        }
        else if (PhaseFlipMethod == 2)
        {
             // Method 3: Frame Drop - skip frames to shift phase
            effectiveFrameCount -= FrameCount / protectionInterval;
        }
    }

    // --- CRT timing simulation ---
    const float fraction = frac((effectiveFrameCount * rcp(DebugSlowFactor) * rcp(FramesPerEffect)) + phaseOffset);

    // --- Sample source frame (sRGB encoded, ~2.2 gamma) ---
    float3 frameCurr = GetFrame(texcoord);

    // --- Apply CRT power-law curve: simulates phosphor response to electron beam voltage (contrast shaping, nonlinear gamma) ---
    frameCurr = pow(frameCurr, beamVoltage);

    // --- Midtone contrast boost. Parabola peaks at 0.5. ---
    float3 midtone = frameCurr * (1.0 - frameCurr) * 4.0;
    frameCurr += frameCurr * midtone * midtoneContrast;
    
    // --- Compute Bayer dither value ---
    int2 pixelCoord = int2(pos.xy);
    float ditherVal = GetBayerDither(pixelCoord, DitherSize);

    // --- Temporal dithering (pattern shifts each frame, modulo instead of bitwise for dx9 compatability) ---
    if (TemporalDither) {
        ditherVal = frac(ditherVal + (FrameCount % FramesPerEffect) * rcp(FramesPerEffect));
    }

    // --- Apply dithering & optional 16-bit quantization ---
    float3 noise = (ditherVal - 0.5) * ditherStrength;
    
    if (quantize16Bit) {
        frameCurr.r += noise.r * INV_31;
        frameCurr.g += noise.g * INV_63;
        frameCurr.b += noise.b * INV_31;
        
        frameCurr.r = floor(frameCurr.r * 31.0 + 0.5) * INV_31;
        frameCurr.g = floor(frameCurr.g * 63.0 + 0.5) * INV_63;
        frameCurr.b = floor(frameCurr.b * 31.0 + 0.5) * INV_31;
    } else {
        frameCurr += noise;
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
    // Golden-ratio-weighted (φ) exponential stages create perceptually smooth decay,
    // mimicking how CRT phosphors naturally fade across R, G, and B channels.
    //
    // [unroll] generates fixed instruction count regardless of DecayLevels setting,
    // ensuring consistent performance on lower-end devices like Steam Deck.
    // The if() disables unused stages at runtime without branching.
    //
    // Native exp() is NON-NEGOTIABLE: Fibonacci-weighted exponential decay is HIGHLY
    // sensitive to precision - approximations (exp2, fast_exp, etc.) destroy the
    // perceptual effect. Single-exponential and bi-exponential models were tested;
    // multi-stage φ-weighted decay provided superior motion clarity and phosphor realism.
    //
    // Early versions used independent φ multipliers (phiR/G/B) and decay lengths
    // (DecayLengthR/G/B) per channel for ultra-accurate phosphor chemistry (P22-style).
    // This was simplified to a unified φ cascade with per-channel decay multipliers,
    // preserving perceptual accuracy and motion clarity while reducing GPU cost.
    // Each color channel remains independent in timing/brightness, but shares the
    // φ-weighted stage structure.

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

    // --- Prevent full black collapse (raise floor) ---
    decay = max(decay, blackLevel);

    // --- Apply phosphor decay ---
    float3 phosphorEmission = frameCurr * decay;

    // --- Apply static scanlines ---
    if (ScanlineDarkness > 0.0) {
        float scanlineMask = 1.0;
        
        // Only apply scanline pattern if gaps are enabled
        if (ScanlineGapSize > 0.0) {
            // Convert to integers to ensure pixel-perfect, consistent patterns
            int brightWidth = int(ScanlineThickness);  // Width of bright scanline (phosphor glow)
            int gapWidth = int(ScanlineGapSize);       // Width of dark gap between scanlines
            int scanlinePattern = brightWidth + gapWidth;  // Total pattern size in pixels
            
            if (ScanlineDirection == 0) { // Horizontal scanlines
                // Calculate which pixel we're at within the repeating pattern (0 to scanlinePattern-1)
                int pixelInPattern = int(pos.y) % scanlinePattern;
                
                // Gap-first pattern: dark pixels come first (0 to gapWidth-1), then bright pixels
                // This phase alignment:
                // 1. Behaves more naturally with decay, no floaty feel
                // 2. Placing rounding errors in dark regions (less visible)
                // 3. Centering bright scanlines away from pattern boundaries (reduces strobing)
                // 4. Providing stable luminance centroids for eye tracking
                scanlineMask = pixelInPattern < gapWidth ? (1.0 - ScanlineDarkness) : 1.0;
                
            } else if (ScanlineDirection == 1) { // Vertical scanlines
                int pixelInPattern = int(pos.x) % scanlinePattern;
                scanlineMask = pixelInPattern < gapWidth ? (1.0 - ScanlineDarkness) : 1.0;
                
            } else if (ScanlineDirection == 2) { // Trinitron mode (horizontal scanlines + vertical aperture grille)
                // Apply horizontal scanlines (standard raster scanning)
                int pixelInPatternH = int(pos.y) % scanlinePattern;
                float maskH = pixelInPatternH < gapWidth ? (1.0 - ScanlineDarkness) : 1.0;
                
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
                float maskH = pixelInPatternH < gapWidth ? (1.0 - ScanlineDarkness) : 1.0;
                float maskV = pixelInPatternV < gapWidth ? (1.0 - ScanlineDarkness) : 1.0;
                
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
    if (Hue != 0.0) {
        float angle = radians(Hue);
        float s = sin(angle);
        float c = cos(angle);
        
        float3x3 hueMatrix = float3x3(
            0.299 + 0.701*c + 0.168*s,  0.587 - 0.587*c + 0.330*s,  0.114 - 0.114*c - 0.497*s,
            0.299 - 0.299*c - 0.328*s,  0.587 + 0.413*c + 0.035*s,  0.114 - 0.114*c + 0.292*s,
            0.299 - 0.299*c + 1.250*s,  0.587 - 0.587*c - 1.050*s,  0.114 + 0.886*c - 0.203*s
        );
        
        phosphorEmission = mul(hueMatrix, phosphorEmission);
    }

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
    
    // Return as-is, preserves HDR-like bright highlights. Softclip (earlier in pipeline) handles extreme brightness gracefully. 
    // Should not have visual artifacts (negative colors, NaN issues), so no need for saturate()
    return float4(phosphorEmission, 1.0);
}

//--------------------------------------------------------------------------------
// Technique declaration
technique CRT_Dusha {
    pass { VertexShader = PostProcessVS; PixelShader = PS_CRT_Dusha; }
}
