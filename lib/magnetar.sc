// Engine_Magnetar.sc
Engine_Magnetar : CroneEngine {
    var <synthGroup;
    var <synths;
    var <globalParams;

    *new { arg context, doneCallback;
        ^super.new(context, doneCallback);
    }

    alloc {
        synthGroup = Group.new(context.server);
        synths = Dictionary.new;
        globalParams = Dictionary.new;

        [
            \amp, 0.5, \atk, 0.01, \dec, 0.2, \sus, 0.5, \rel, 0.5,
            \lfoShape, 0, \lfoRate, 5.0, \panSpread, 0.0, \modWheel, 0.0,
            \formantRatio, 2.0, \formantFine, 1.0, \overlap, 0.5, \phaseOffset, 0.0,
            \shape, 0.0, \pwm, 0.5,
            \modEnvFormant, 0.0, \modEnvOverlap, 0.0, \modEnvShape, 0.0, \modEnvPwm, 0.0,
            \modLfoFreq, 0.0, \modLfoFormant, 0.0, \modLfoOverlap, 0.0, \modLfoShape, 0.0, \modLfoPwm, 0.0, \modLfoAmp, 0.0,
            \modVelFormant, 0.0, \modVelOverlap, 0.0, \modVelShape, 0.0, \velAmp, 1.0,
            \mwFormant, 0.0, \mwOverlap, 0.0, \mwShape, 0.0,
            \mwLfoFormant, 0.0, \mwLfoOverlap, 0.0, \mwLfoShape, 0.0,
            \velLfoFormant, 0.0, \velLfoOverlap, 0.0, \velLfoShape, 0.0
        ].pairsDo { |k, v| globalParams.put(k, v) };

        SynthDef(\pulsarVoice, {
            arg out=0, gate=1, freq=440, vel=0.8, amp=0.5,
                atk=0.01, dec=0.2, sus=0.5, rel=0.5,
                lfoShape=0, lfoRate=5.0, panSpread=0.0, modWheel=0.0,
                formantRatio=2.0, formantFine=1.0, overlap=0.5, phaseOffset=0.0,
                shape=0.0, pwm=0.5,
                modEnvFormant=0.0, modEnvOverlap=0.0, modEnvShape=0.0, modEnvPwm=0.0,
                modLfoFreq=0.0, modLfoFormant=0.0, modLfoOverlap=0.0, modLfoShape=0.0, modLfoPwm=0.0, modLfoAmp=0.0,
                modVelFormant=0.0, modVelOverlap=0.0, modVelShape=0.0, velAmp=1.0,
                mwFormant=0.0, mwOverlap=0.0, mwShape=0.0,
                mwLfoFormant=0.0, mwLfoOverlap=0.0, mwLfoShape=0.0,
                velLfoFormant=0.0, velLfoOverlap=0.0, velLfoShape=0.0;

            var env = EnvGen.ar(Env.adsr(atk, dec, sus, rel), gate, doneAction: 2);

            // --- The Multi-Wave LFO ---
            var lfoSine = SinOsc.kr(lfoRate);
            var lfoTri  = LFTri.kr(lfoRate);
            var lfoSaw  = LFSaw.kr(lfoRate); // Bipolar: -1 to 1
            var lfoSqr  = LFPulse.kr(lfoRate) * 2 - 1; // Converted to bipolar -1 to 1
            var lfoSH   = LFNoise0.kr(lfoRate); // Sample & Hold (Stepped random)
            var lfoNois = LFNoise2.kr(lfoRate); // Quadratic smoothed random noise

            // Select the active LFO based on the parameter index (0 to 5)
            var lfo = Select.kr(lfoShape, [lfoSine, lfoTri, lfoSaw, lfoSqr, lfoSH, lfoNois]);

            var pan = Rand(-1.0, 1.0) * panSpread;

            var effLfoFormant = modLfoFormant + (modWheel * mwLfoFormant) + (vel * velLfoFormant);
            var effLfoOverlap = modLfoOverlap + (modWheel * mwLfoOverlap) + (vel * velLfoOverlap);
            var effLfoShape   = modLfoShape   + (modWheel * mwLfoShape)   + (vel * velLfoShape);

            // --- Core Modulations ---
            // 1. Modulate Fundamental Frequency (Vibrato/FM)
            var modFreq = freq * (1 + (modLfoFreq * lfo));

            // 2. Formant, Overlap, Shape, and PWM Modulations
            var modFormant = modFreq * formantRatio * formantFine * (1 + (modEnvFormant * env) + (effLfoFormant * lfo) + (modVelFormant * vel) + (mwFormant * modWheel));
            var modOverlap = (overlap + (modEnvOverlap * env) + (effLfoOverlap * lfo) + (modVelOverlap * vel) + (mwOverlap * modWheel)).clip(0.001, 1.0);
            var modShape = (shape + (modEnvShape * env) + (effLfoShape * lfo) + (modVelShape * vel) + (mwShape * modWheel)).clip(0.0, 2.0);
            var modPwm = (pwm + (modEnvPwm * env) + (modLfoPwm * lfo)).clip(0.01, 0.99);

            // --- Pulsar Core ---
            // Impulse train now follows modFreq!
            var trig = Impulse.ar(modFreq);
            var timer = Sweep.ar(trig);
            // Window duration dynamically resizes based on the wobbling fundamental freq
            var windowDuration = modOverlap / modFreq;
            var envPhase = timer / windowDuration;
            var window = sin(envPhase * pi) * (envPhase < 1.0);

            var p = (Phasor.ar(trig, modFormant / SampleRate.ir, 0, 1) + (phaseOffset / (2*pi))) % 1.0;

            var wSin = sin(p * 2 * pi);
            var wTri = (4 * ((p + 0.25) % 1.0 - 0.5).abs) - 1;
            var wSqr = (p < modPwm) * 2 - 1;

            var pulsaret = SelectX.ar(modShape, [wSin, wTri, wSqr]);
            var snd = pulsaret * window;

            var dynAmp = 1.0 - velAmp + (vel * velAmp);
            snd = snd * amp * dynAmp * env * (1 + (modLfoAmp * lfo));

            Out.ar(out, Pan2.ar(snd, pan));
        }).add;

        context.server.sync;

        this.addCommand(\noteOn, "iff", { arg msg;
            var id = msg[1]; var hz = msg[2]; var vel = msg[3];
            var args = [\freq, hz, \vel, vel, \out, context.out_b];
            globalParams.keysValuesDo { |key, val| args = args.add(key).add(val) };
            synths[id] = Synth(\pulsarVoice, args, target: synthGroup);
        });

        this.addCommand(\noteOff, "i", { arg msg;
            var id = msg[1];
            if(synths.at(id).notNil) { synths[id].set(\gate, 0); synths.removeAt(id); };
        });

        this.addCommand(\setParam, "sf", { arg msg;
            var param = msg[1].asSymbol; var val = msg[2];
            globalParams.put(param, val); synthGroup.set(param, val);
        });
    }
    free { synthGroup.free; }
}