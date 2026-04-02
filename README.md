# Magnetar

### Polyphonic Pulsar Synthesizer for Norns

## **Overview**

Magnetar is a 12-voice polyphonic pulsar synthesizer built for the monome norns ecosystem. It bridges the gap between classic granular textures, vocal-like formant shifting, and physical modeling. By generating tiny bursts of sound separated by calculated silences, and feeding those bursts through a resonant comb filter, Magnetar can produce everything from tearing sub-bass and crystalline choirs to realistic plucked strings and chaotic, crumbling noise.

The instrument features a rich, OLED-optimized visualizer that renders the synthesizer’s engine as a rotating star core, with orbiting particles that react in real-time to your envelopes, LFOs, and voice allocation.

## **What is Pulsar Synthesis?**

Pulsar synthesis is a specialized technique within the broader family of granular synthesis, originally developed by electronic music pioneer Curtis Roads.

Instead of chopping up an existing audio sample into grains, pulsar synthesis generates its own waveforms from scratch. A "pulsar" consists of two distinct parts that repeat cyclically:

1. **The Pulsaret:** A brief burst of a waveform (like a sine, triangle, or square wave).  
2. **The Silent Interval:** A period of absolute silence that follows the burst.

The magic of pulsar synthesis comes from decoupling the **Fundamental Frequency** from the **Formant Frequency**:

* **Fundamental Frequency:** This dictates how often the entire pulsar (burst \+ silence) repeats. This is what your ear perceives as the actual musical pitch (e.g., the note C3).  
* **Formant Frequency:** This dictates the pitch of the waveform *inside* the burst itself. Changing this alters the timbre or "vowel" sound of the note without changing the fundamental pitch.  
* **Overlap (Duty Cycle):** This determines how much of the cycle is filled with the pulsaret versus the silent interval. An overlap of 1.0 means continuous sound (like a standard oscillator). An overlap of 0.1 means a tiny click followed by a long silence.

By manipulating these three parameters simultaneously, you can create sounds that smoothly morph from rhythmic clicking into pitched tones and complex, vocal-like formants.

## **3\. Controls**

Magnetar utilizes a paged interface to handle its extensive parameter matrix. You can operate the UI in either a full-screen menu mode or a Top Page mode that displays the Magnetar visualizer.

* **E1 (Turn):** Scroll between parameter groups (Oscillator, Envelope, LFO, etc.).  
* **E2 (Turn):** Select a specific parameter within the current group.  
* **E3 (Turn):** Adjust the value of the selected parameter. (Turns are velocity-sensitive for fine/coarse tuning).  
* **K3 (Press):** Reset the currently selected parameter to its default value.  
* **K1 (Hold) \+ E1 (Turn):** Toggle the screen layout between the **Animation Top-Page** and the **Full Parameter Menu**.

## **Voice Design**

Magnetar features a flexible voice architecture designed to maximize the Norns CPU.

### **Voice Modes**

* **Poly:** Standard polyphony. Notes are allocated in a round-robin format up to the defined **Polyphony Cap** (max 12 voices). Older notes are stolen if the cap is exceeded.  
* **Mono Unison:** A massive, stacked monosynth. Pressing a key fires up to 8 voices simultaneously. Playing legato (overlapping key presses) will smoothly glide the pitches to the new note without retriggering the envelopes.  
* **4x3 Unison:** A "Poly-Unison" hybrid. Gives you 4 notes of true polyphony, but each note consists of a thick, 3-voice detuned cluster.

### **Unison Spread**

When using the Mono or 4x3 Unison modes, the **Unison Spread** parameter dictates the detuning of the clustered voices.

* **0.0 to 0.5 (Continuous):** Smoothly detunes the voices from perfect unison up to a maximum spread of a Major 2nd. Perfect for thick, analog-style chorusing.  
* **0.5 to 1.0 (Stepped):** Snaps the outer voices to precise, harmonic musical intervals (Minor 3rd, Major 3rd, Perfect 4th, Perfect 5th, Major 6th, Octave, and Octave \+ 5th). Perfect for instant chord stabs and organs.

### **Comb Filter Feedback**

The output of the pulsar exciter is routed into an optimized Comb Filter. By introducing high amounts of feedback with very short delay times, you introduce a physical modeling effect known as Karplus-Strong synthesis.

* **Tracking Mode:** When set to *Fundamental* or *Formant*, the delay time automatically calculates itself based on the pitch you are playing, turning the feedback loop into a tuned resonating string or tube.

## **5\. Modulation**

Magnetar includes a highly optimized, control-rate modulation matrix. Parameters mapped to modulation sources scale cubically, meaning the center 80% of the parameter acts as a "fine-tune" zone for buttery-smooth modulation sweeps, only reaching extreme values at the absolute limits.

* **Envelope:** A standard ADSR envelope that controls the final VCA, but can also be routed to overlap, formants, phase, and pulse-width.  
* **LFO:** A global, free-running low-frequency oscillator. It features 7 shapes: *Sine, Triangle, Saw, Square, Sample & Hold, Smooth Random,* and *White Noise*. (Routing White Noise to formants or overlaps creates brutal audio-rate chaos).  
* **Velocity:** MIDI note velocity can be routed directly to amplitude, or used to dynamically shift formants and feedback dampening.  
* **Modwheel:** Acts as a direct performance macro, and dictates the **Global LFO Depth**.

## **Best Practices and Patch Recommendations**

**CPU Warning:** 12 voices of active granular synthesis and comb-filtering is the absolute redline limit of the standard Norns hardware. If you experience audio crackling in Poly mode, lower the **Polyphony Cap** or shorten your **Release** times to clear the processor buffer faster.

### **Patch Idea 1: The Karplus Pluck**

* **Voice Mode:** Poly  
* **Overlap:** Very low (0.01 to 0.05). You want a tiny, sharp click.  
* **FB Track Mode:** Fundamental  
* **Feedback Amount:** High (0.95+). This sustains the ringing string.  
* **Feedback Dampen:** 0.6. Muffles the high frequencies over time like a real string.

### **Patch Idea 2: The Formant Choir**

* **Voice Mode:** 4x3 Unison (Spread set to Octave)  
* **Shape:** 1.0 (Triangle)  
* **Formant Ratio:** 3.0 or 4.0  
* **Mod LFO \-\> Formant:** Small amount (0.1) with a slow, smooth Sine LFO to simulate breathing and vocal modulation.  
* **Attack/Release:** High (1.5s+).

### **Patch Idea 3: Crumbling Machinery**

* **LFO Shape:** White Noise  
* **LFO Rate:** (Disabled for White Noise)  
* **Mod LFO \-\> Overlap:** 0.8  
* **Mod LFO \-\> Shape:** 0.5  
* *Result:* The white noise modulation causes the pulsar window to rapidly and randomly open and close at audio rates, turning any clean tone into digital gravel.

## **Resources and Inspiration**

* **Nathan Ho - Pulsar Synthesis:**: [Blog post](https://nathan.ho.name/posts/pulsar-synthesis/) detailing how to create a pulsar synthesis engine using SuperCollider.
* **Microsound (Book):** Written by Curtis Roads, this is the definitive text on granular and pulsar synthesis theory.  
* **SuperCollider & Norns Communities:** The architecture of Magnetar heavily relies on the open-source knowledge shared within the monome/norns and SuperCollider ecosystems.