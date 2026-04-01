-- Magnetar
-- Polyphonic Pulsar Synthesizer

engine.name = 'Magnetar'
local MusicUtil = require("musicutil")

local MAX_VOICES = 8
local active_notes = {}
local note_order = {}
local voices_active = 0
local ui_time = 0

local current_page = 1
local selected_param = 1

local pages = {
  { name = "Oscillator", params = {
      -- {id="mode",         disp="Voice Mode"},
      -- {id="voiceSpread",  disp="Voice Spread"},
      -- {id="glide",        disp="Glide"},
      {id="shape",        disp="Wave Shape"},
      {id="pwm",          disp="Pulse Width"},
      {id="formantRatio", disp="Formant Ratio"},
      {id="formantFine",  disp="Formant Fine"},
      {id="overlap",      disp="Wavelet Overlap"},
      {id="phaseOffset",  disp="Phase Offset"},
      {id="fbAmt",        disp="Feedback Amount"},
      {id="fbTime",       disp="Feedback Time"},
      {id="fbDamp",       disp="Feedback Dampen"},
      {id="fbTracking",   disp="Feedback Tracking"},
      {id="panSpread",    disp="Stereo Spread"}
    }
  },
  { name = "Envelope", params = {
      {id="atk",           disp="Attack"},
      {id="dec",           disp="Decay"},
      {id="sus",           disp="Sustain"},
      {id="rel",           disp="Release"},
      {id="modEnvFormant", disp="->Formant"},
      {id="modEnvOverlap", disp="->OverLap"},
      {id="modEnvPhase",   disp="->Phase Offset"},
      {id="modEnvShape",   disp="->OSC Wave Shape"},
      {id="modEnvPwm",     disp="->OSC Pulse Width"}
    }
  },
  { name = "LFO", params = {
      {id="lfoShape",      disp="Wave Shape"},
      {id="lfoRate",       disp="Rate"},
      {id="mwLfoGlobal",   disp="ModWheel LFO Depth"}, -- Global LFO Scale
      {id="modLfoFreq",    disp="->Frequency"},
      {id="modLfoAmp",     disp="->Amplitude"},
      {id="modLfoFormant", disp="->Formant"},
      {id="modLfoOverlap", disp="->Wavelet OverLap"},
      {id="modLfoShape",   disp="->Wave Shape"},
      {id="modLfoPwm",     disp="->Pulse Width"},
      {id="modLfoFbTime",  disp="->Feedback Time"},
      {id="modLfoFbDamp",  disp="->Feedback Dampening"},
    }
  },
  { name = "Velocity", params = {
      {id="velAmp",        disp="->Amplitude"},
      {id="modVelFormant", disp="->Formant"},
      {id="modVelOverlap", disp="->Overlap"},
      {id="modVelShape",   disp="->OSC Wave Shape"},
      {id="velLfoFormant", disp="LFO -> Formant"},
      {id="velLfoOverlap", disp="LFO -> Overlap"},
      {id="velLfoShape",   disp="LFO -> OSC Wave Shape"},
      {id="modVelFbTime", disp="->Feedback Time"},
      {id="modVelFbDamp", disp="->Feedback Dampening"},
    }
  },
  { name = "Modwheel", params = {
      {id="mwFormant",    disp=">Formant"},
      {id="mwOverlap",    disp=">Overlap"},
      {id="mwShape",      disp=">OSC Wave Shape"},
      {id="mwLfoFormant", disp="LFO -> Formant"},
      {id="mwLfoOverlap", disp="LFO -> Overlap"},
      {id="mwLfoShape",   disp="LFO -> OSC Wave Shape"},
      {id="mwFbTime",     disp="->Feedback Time"},
      {id="mwFbDamp",     disp="->Feedback Dampening"}

    }
  }
}

local ratio_values = {0.125, 0.25, 0.5, 1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 7.0, 8.0, 9.0, 10.0, 11.0, 12.0, 13.0, 14.0}
local ratio_labels = {"1/8", "1/4", "1/2", "1", "2", "3", "4", "5", "6", "7", "8", "9", "10", "11", "12", "13", "14"}

function init()
  build_params()
  setup_midi()
  clock.run(function()
    while true do
      clock.sleep(1/15)
      ui_time = ui_time + (1/15)
      redraw()
    end
  end)
end

function setup_midi()
  m = midi.connect()
  m.event = function(data)
    local d = midi.to_msg(data)
    if d.type == "note_on" then
      if active_notes[d.note] then
        engine.noteOff(d.note)
        for i, n in ipairs(note_order) do
          if n == d.note then table.remove(note_order, i); break end
        end
        voices_active = voices_active - 1
      end

      if voices_active >= MAX_VOICES then
        local oldest_note = table.remove(note_order, 1)
        engine.noteOff(oldest_note)
        active_notes[oldest_note] = nil
        voices_active = voices_active - 1
      end

      engine.noteOn(d.note, MusicUtil.note_num_to_freq(d.note), d.vel / 127)
      active_notes[d.note] = true
      table.insert(note_order, d.note)
      voices_active = voices_active + 1

    elseif d.type == "note_off" then
      if active_notes[d.note] then
        engine.noteOff(d.note)
        active_notes[d.note] = nil
        for i, n in ipairs(note_order) do
          if n == d.note then table.remove(note_order, i); break end
        end
        voices_active = voices_active - 1
      end
    elseif d.type == "cc" and d.cc == 1 then
      engine.setParam("modWheel", d.val / 127)
    end
  end
end

function enc(n, delta)
  if n == 1 then
    current_page = util.clamp(current_page + delta, 1, #pages)
    selected_param = 1
  elseif n == 2 then
    local page_len = #pages[current_page].params
    selected_param = util.clamp(selected_param + delta, 1, page_len)
  elseif n == 3 then
    -- Notice the .id added here!
    local p_id = pages[current_page].params[selected_param].id
    params:delta(p_id, delta)
  end
end

function key(n, z)
  if n == 3 and z == 1 then
    -- And the .id added here!
    local p_id = pages[current_page].params[selected_param].id
    params:set(p_id, params:get(p_id .. "_default") or params:lookup_param(p_id).default)
  end
end

local function morph_wave(p, shape, pwm)
  local wSin = math.sin(p * 2 * math.pi)
  local wTri = (4 * math.abs((p + 0.25) % 1.0 - 0.5)) - 1
  local wSqr = (p < pwm) and 1 or -1
  if shape < 1.0 then return wSin * (1.0 - shape) + wTri * shape
  else return wTri * (2.0 - shape) + wSqr * (shape - 1.0) end
end

function redraw()
  screen.clear()

  -- 1. ADVANCED VISUALIZER LFO SIMULATION
  local lfo_rate = params:get("lfoRate")
  local lfo_shape_idx = params:get("lfoShape")
  local lfo_phase = (ui_time * lfo_rate) % 1.0
  local lfo = 0

  if lfo_shape_idx == 1 then     -- Sine
    lfo = math.sin(lfo_phase * 2 * math.pi)
  elseif lfo_shape_idx == 2 then -- Triangle
    lfo = math.abs((lfo_phase * 4) - 2) - 1
  elseif lfo_shape_idx == 3 then -- Saw
    lfo = (lfo_phase * 2) - 1
  elseif lfo_shape_idx == 4 then -- Square
    lfo = lfo_phase < 0.5 and 1 or -1
  elseif lfo_shape_idx == 5 then -- S&H (Stepped)
    local step = math.floor(ui_time * lfo_rate)
    -- Use a sine hash to generate deterministic pseudo-random steps
    lfo = math.sin(step * 1337.1)
  elseif lfo_shape_idx == 6 then -- Noise (Smoothed)
    -- Simple random visual jitter
    lfo = (math.random() * 2 - 1) * 0.8
  end

  -- We don't simulate modFreq visually because drawing changing screen widths
  -- rapidly looks like a glitching screen rather than audio. We apply the rest.
  local ratio_idx = params:get("formantRatio")
  local actual_ratio = ratio_values[ratio_idx]
  local v_formant = actual_ratio * params:get("formantFine") * (1 + (params:get("modLfoFormant") * lfo))
  local v_overlap = util.clamp(params:get("overlap") + (params:get("modLfoOverlap") * lfo), 0.001, 1.0)
  local v_shape   = util.clamp(params:get("shape") + (params:get("modLfoShape") * lfo), 0.0, 2.0)
  local v_pwm     = util.clamp(params:get("pwm") + (params:get("modLfoPwm") * lfo), 0.01, 0.99)
  local v_spread  = params:get("panSpread")

  -- 2. DRAW PARTICLE WAVEFORM
  local center_y = 22
  local amp = 18

  local particles_per_voice = 50
  local num_particles = voices_active * particles_per_voice

  if num_particles > 0 then
    for i = 1, num_particles do
      local x = math.random(0, 127)
      local phase = x / 128

      local window_phase = ((phase - 0.5) / v_overlap) + 0.5
      local window = 0
      if window_phase >= 0.0 and window_phase <= 1.0 then
        window = math.sin(window_phase * math.pi)
      end

      local p = (phase * v_formant) % 1.0
      local pulsaret = morph_wave(p, v_shape, v_pwm)

      local y_val = pulsaret * window * amp
      local scatter = (math.random() * 2 - 1) * v_spread * (amp * 0.8)

      local brightness = math.floor(window * 15)
      brightness = util.clamp(brightness - math.random(0, 3), 1, 15)

      if window > 0.01 then
        screen.level(brightness)
        screen.pixel(x, center_y - y_val - scatter)
      end
    end
  end

  screen.level(voices_active > 0 and 4 or 1)
  screen.move(0, center_y)
  screen.line(128, center_y)
  screen.stroke()

  -- 3. DRAW PAGED UI
  screen.level(0)
  screen.rect(0, 44, 128, 20)
  screen.fill()

  screen.level(15)
  screen.rect(0, 44, 128, 20)
  screen.stroke()

  screen.level(15)
  screen.move(4, 53)
  screen.text(pages[current_page].name)

  screen.move(4, 61)
  screen.level(voices_active > 0 and 15 or 4)
  screen.text("V:" .. voices_active .. "/" .. MAX_VOICES)

  -- Get the current parameter's table data
  local current_p = pages[current_page].params[selected_param]
  local p_id = current_p.id
  local p_name = current_p.disp

  screen.level(15)
  screen.move(40, 53)
  screen.text(">" .. p_name)
  screen.move(124, 53)

  -- If it's the formant ratio, display the label, otherwise display the string
  if p_id == "formantRatio" then
    screen.text_right(ratio_labels[params:get(p_id)])
  else
    screen.text_right(params:string(p_id))
  end

  -- Show next param if available
  if selected_param < #pages[current_page].params then
    local next_p = pages[current_page].params[selected_param + 1]

    screen.level(4)
    screen.move(45, 61)
    screen.text(next_p.disp)
    screen.move(124, 61)

    if next_p.id == "formantRatio" then
      screen.text_right(ratio_labels[params:get(next_p.id)])
    else
      screen.text_right(params:string(next_p.id))
    end
  end

  screen.update()
end

function build_params()
  params:add_separator("PULSAR SYNTHESIS")

  local function add_eng_param(id, name, min, max, default)
    params:add_control(id, name, controlspec.new(min, max, "lin", 0, default, ""))
    params:set_action(id, function(v) engine.setParam(id, v) end)
  end

  params:add_group("Oscillator", 6)
  params:add_option("formantRatio", "Formant Ratio", ratio_labels, 4)
  params:set_action("formantRatio", function(v)
    engine.setParam("formantRatio", ratio_values[v])
  end)
  add_eng_param("formantFine", "Formant Fine", 0.25, 1.75, 1.0)
  add_eng_param("overlap", "Overlap (PulWM)", 0.01, 1.2, 0.0)
  add_eng_param("phaseOffset", "Phase Offset", 0.0, 6.28, 0.0)
  add_eng_param("panSpread", "Stereo Spread", 0.0, 1.0, 0.0)

  params:add_group("Waveform Morph", 2)
  add_eng_param("shape", "Shape (Sin-Tri-Sq)", 0.0, 2.0, 0.0)
  add_eng_param("pwm", "Square PWM", 0.0, 1.0, 0.5)

  params:add_group("Granular Feedback", 4)
  -- Amount can go up to 2.0 because the .tanh saturator will protect us
  add_eng_param("fbAmt", "Feedback Amount", 0.0, 2.0, 0.0)
  -- Delay time: 0.0001 creates high metallic pitches, 0.1 creates distinct grain echoes
  add_eng_param("fbTime", "Feedback Time", 0.0001, 0.1, 0.01)
  -- Dampening: 0.0 is completely bright, 0.99 is very muffled
  add_eng_param("fbDamp", "Feedback Dampen", 0.0, 0.99, 0.5)
  -- Free allows for dynamic setting of Feedback Time
  -- Time will be ignored if Fundamental (following the base pitch of the oscillator)
  -- or Formant (tracking Formant Ration * Fundamental) are selected
  params:add_option("fbTrackMode", "FB Track Mode", {"Free", "Fundamental", "Formant"}, 1)
  params:set_action("fbTrackMode", function(v) engine.setParam("fbTrackMode", v - 1) end)

  -- Add this below your Feedback Base parameters
  params:add_group("Mod: Feedback", 6)
  add_eng_param("modLfoFbTime", "LFO -> FB Time", -1.0, 1.0, 0.0)
  add_eng_param("modLfoFbDamp", "LFO -> FB Damp", -1.0, 1.0, 0.0)
  add_eng_param("modVelFbTime", "Vel -> FB Time", -1.0, 1.0, 0.0)
  add_eng_param("modVelFbDamp", "Vel -> FB Damp", -1.0, 1.0, 0.0)
  add_eng_param("mwFbTime", "MW -> FB Time", -1.0, 1.0, 0.0)
  add_eng_param("mwFbDamp", "MW -> FB Damp", -1.0, 1.0, 0.0)

  params:add_group("Envelope", 4)
  add_eng_param("atk", "Attack", 0.001, 5.0, 0.01)
  add_eng_param("dec", "Decay", 0.001, 5.0, 0.2)
  add_eng_param("sus", "Sustain", 0.0, 1.0, 0.4)
  add_eng_param("rel", "Release", 0.001, 10.0, 0.2)

  params:add_group("LFO Base", 5)
  params:add_option("lfoShape", "LFO Shape", {"Sine", "Tri", "Saw", "Square", "S&H", "Noise"}, 1)
  params:set_action("lfoShape", function(v) engine.setParam("lfoShape", v - 1) end) -- SC uses 0-index
  add_eng_param("lfoRate", "LFO Rate Hz", 0.01, 200.0, 0.8)
  add_eng_param("modLfoFreq", "LFO -> Freq", -1.0, 1.0, 0.0)
  add_eng_param("mwLfoGlobal", "ModWheel -> LFO Scale", 0.0, 1.0, 0.0)

  params:add_group("Mod: LFO", 5)
  add_eng_param("modLfoFormant", "LFO -> Formant", -2.0, 2.0, 0.0)
  add_eng_param("modLfoOverlap", "LFO -> Overlap", -1.0, 1.0, 0.0)
  add_eng_param("modLfoShape", "LFO -> Shape", -2.0, 2.0, 0.0)
  add_eng_param("modLfoPwm", "LFO -> PWM", -1.0, 1.0, 0.0)
  add_eng_param("modLfoAmp", "LFO -> Amp", 0.0, 1.0, 0.0)

  params:add_group("Mod: Envelope", 5)
  add_eng_param("modEnvFormant", "Env -> Formant", -2.0, 2.0, 0.0)
  add_eng_param("modEnvOverlap", "Env -> Overlap", -1.0, 1.0, 0.0)
  add_eng_param("modEnvPhase", "Env -> Phase", -6.28, 6.28, 0.0)
  add_eng_param("modEnvShape", "Env -> Shape", -2.0, 2.0, 0.0)
  add_eng_param("modEnvPwm", "Env -> PWM", -1.0, 1.0, 0.0)

  params:add_group("Mod: Velocity Direct", 4)
  add_eng_param("velAmp", "Vel -> Amp", 0.0, 1.0, 1.0)
  add_eng_param("modVelFormant", "Vel -> Formant", -2.0, 2.0, 0.0)
  add_eng_param("modVelOverlap", "Vel -> Overlap", -1.0, 1.0, 0.0)
  add_eng_param("modVelShape", "Vel -> Shape", -2.0, 2.0, 0.0)

  params:add_group("Mod: Velocity -> LFO", 3)
  add_eng_param("velLfoFormant", "Vel scales Form LFO", -2.0, 2.0, 0.0)
  add_eng_param("velLfoOverlap", "Vel scales OvrLp LFO", -1.0, 1.0, 0.0)
  add_eng_param("velLfoShape", "Vel scales Shape LFO", -2.0, 2.0, 0.0)

  params:add_group("Mod: Mod Wheel Direct", 3)
  add_eng_param("mwFormant", "Wheel -> Formant", -2.0, 2.0, 0.0)
  add_eng_param("mwOverlap", "Wheel -> Overlap", -1.0, 1.0, 0.0)
  add_eng_param("mwShape", "Wheel -> Shape", -2.0, 2.0, 0.0)

  params:add_group("Mod: Mod Wheel -> LFO", 3)
  add_eng_param("mwLfoFormant", "Wheel scales Form LFO", -2.0, 2.0, 0.0)
  add_eng_param("mwLfoOverlap", "Wheel scales OvrLp LFO", -1.0, 1.0, 0.0)
  add_eng_param("mwLfoShape", "Wheel scales Shape LFO", -2.0, 2.0, 0.0)

  params:bang()
end