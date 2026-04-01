-- Magnetar
-- Polyphonic Pulsar Synthesizer

engine.name = 'Magnetar'
local MusicUtil = require("musicutil")

local MAX_VOICES = 6
local active_notes = {}
local note_order = {}
local voices_active = 0
local ui_time = 0

-- UI Navigation State
local current_page = 0 -- 0 = Main Animation Page, 1+ = Full Parameter Menus
local menu_page = 1    -- Tracks which parameter menu page is active in the background
local selected_param = 1
local k1_held = false

-- Animation State
local anim_notes = {}
local stars = {} -- Holds our fixed background starfield positions

local pages = {
  { name = "Oscillator", params = {
      {id="shape",        disp="Wave Shape"},
      {id="pwm",          disp="Pulse Width"},
      {id="formantRatio", disp="Formant Ratio"},
      {id="formantFine",  disp="Formant Fine"},
      {id="overlap",      disp="Wavelet Overlap"},
      {id="phaseOffset",  disp="Phase Offset"},
      {id="fbAmt",        disp="Feedback Amount"},
      {id="fbTime",       disp="Feedback Time"},
      {id="fbDamp",       disp="Feedback Dampen"},
      {id="fbTrackMode",  disp="Feedback Tracking"},
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
      {id="mwLfoGlobal",   disp="ModWheel LFO Depth"},
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
      {id="modVelFbTime",  disp="->Feedback Time"},
      {id="modVelFbDamp",  disp="->Feedback Dampening"},
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

function init_stars()
  -- Helper function to ensure stars don't clump together
  local function get_valid_pos()
    local valid = false
    local rx, ry
    local attempts = 0
    local min_dist = 9 -- Minimum pixels between any two stars

    while not valid and attempts < 100 do
      rx = math.random(50, 127)
      ry = math.random(0, 64)
      valid = true

      -- Check distance against all existing stars
      for _, star in ipairs(stars) do
        local dx = rx - star.x
        local dy = ry - star.y
        local dist = math.sqrt((dx * dx) + (dy * dy))

        if dist < min_dist then
          valid = false
          break
        end
      end
      attempts = attempts + 1
    end
    return rx, ry
  end

  -- Exactly 12 Voice Stars (2 per voice slot)
  for i=1, 12 do
    local sx, sy = get_valid_pos()
    table.insert(stars, {
      x = sx,
      y = sy,
      type = 1,
      v_idx = (i % MAX_VOICES) + 1
    })
  end

  -- Exactly 10 LFO Stars (2 per threshold)
  local thresholds = {-1.0, -0.5, 0.0, 0.5, 1.0}
  for i=1, 10 do
    local sx, sy = get_valid_pos()
    table.insert(stars, {
      x = sx,
      y = sy,
      type = 2,
      lfo_val = thresholds[(i % 5) + 1],
      bright = 0
    })
  end
end

function init()
  build_params()
  init_stars()
  setup_midi()

  clock.run(function()
    while true do
      clock.sleep(1/15)
      ui_time = ui_time + (1/15)

      -- Update visual animation envelopes
      local atk_rate = 1.0 / math.max(0.01, params:get("atk") * 15)
      local rel_rate = 1.0 / math.max(0.01, params:get("rel") * 15)

      for note, data in pairs(anim_notes) do
        if data.state == "on" then
          data.env = math.min(1.0, data.env + atk_rate)
        else
          data.env = math.max(0.0, data.env - rel_rate)
          if data.env <= 0.01 then
            anim_notes[note] = nil -- Clean up dead notes
          end
        end
      end

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
        if anim_notes[oldest_note] then anim_notes[oldest_note].state = "off" end
        voices_active = voices_active - 1
      end

      local hz = MusicUtil.note_num_to_freq(d.note)
      engine.noteOn(d.note, hz, d.vel / 127)

      active_notes[d.note] = true
      table.insert(note_order, d.note)
      voices_active = voices_active + 1

      -- Register note for visual animation
      anim_notes[d.note] = {
        freq = hz,
        vel = d.vel / 127,
        env = 0.0,
        state = "on",
        angle = math.random() * math.pi * 2,
        dist_offset = math.random(-3, 3)
      }

    elseif d.type == "note_off" then
      if active_notes[d.note] then
        engine.noteOff(d.note)
        active_notes[d.note] = nil
        if anim_notes[d.note] then anim_notes[d.note].state = "off" end

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

-- Controls
function key(n, z)
  if n == 1 then k1_held = (z == 1) end

  if n == 3 and z == 1 then
    local target_page = current_page == 0 and menu_page or current_page
    local p_id = pages[target_page].params[selected_param].id
    params:set(p_id, params:get(p_id .. "_default") or params:lookup_param(p_id).default)
  end
end

function enc(n, delta)
  if n == 1 then
    if k1_held then
      -- Toggle Main Page (0) vs Full Menu
      if current_page == 0 then
        current_page = menu_page
      else
        menu_page = current_page
        current_page = 0
      end
    else
      -- E1 Scrolls Pages in BOTH modes now
      if current_page == 0 then
        menu_page = util.clamp(menu_page + delta, 1, #pages)
        selected_param = 1
      else
        current_page = util.clamp(current_page + delta, 1, #pages)
        menu_page = current_page
        selected_param = 1
      end
    end
  elseif n == 2 then
    local target_page = current_page == 0 and menu_page or current_page
    local page_len = #pages[target_page].params
    selected_param = util.clamp(selected_param + delta, 1, page_len)
  elseif n == 3 then
    local target_page = current_page == 0 and menu_page or current_page
    local p_id = pages[target_page].params[selected_param].id

    -- CUSTOM VELOCITY SCALING FOR LFO RATE
    if p_id == "lfoRate" then
      local current = params:get("lfoRate")
      local step = 0

      if math.abs(delta) == 1 then
        if current < 1.0 then step = 0.01 * delta
        elseif current < 10.0 then step = 0.1 * delta
        else step = 1.0 * delta end
      else
        if current < 1.0 then step = 0.1 * delta
        elseif current < 10.0 then step = 1.0 * delta
        else step = 5.0 * delta end
      end

      params:set("lfoRate", util.clamp(current + step, 0.01, 200.0))
    else
      params:delta(p_id, delta)
    end
  end
end

-- Screen Rendering
function redraw()
  screen.clear()

  -- Common Data
  local target_page = current_page == 0 and menu_page or current_page
  local current_p = pages[target_page].params[selected_param]
  local p_id = current_p.id
  local p_val_str = (p_id == "formantRatio") and ratio_labels[params:get(p_id)] or params:string(p_id)
  local full_p_name = params:lookup_param(p_id).name

  if current_page == 0 then
    -- ==========================================
    -- MAIN PAGE: UI LEFT, MAGNETAR RIGHT
    -- ==========================================

    -- 1. Left UI (Full Text Editing)
    screen.level(4)
    screen.move(0, 10)
    screen.text(pages[target_page].name .. " [" .. selected_param .. "/" .. #pages[target_page].params .. "]")

    screen.level(15)
    screen.move(0, 26)
    screen.text(full_p_name)

    screen.move(0, 36)
    screen.text(p_val_str)

    -- 2. Calculate Live LFO
    local lfo_rate = params:get("lfoRate")
    local lfo_shape_idx = params:get("lfoShape")
    local lfo_phase = (ui_time * lfo_rate) % 1.0
    local lfo = 0

    if lfo_shape_idx == 1 then lfo = math.sin(lfo_phase * 2 * math.pi)
    elseif lfo_shape_idx == 2 then lfo = math.abs((lfo_phase * 4) - 2) - 1
    elseif lfo_shape_idx == 3 then lfo = (lfo_phase * 2) - 1
    elseif lfo_shape_idx == 4 then lfo = lfo_phase < 0.5 and 1 or -1
    elseif lfo_shape_idx == 5 then lfo = math.sin(math.floor(ui_time * lfo_rate) * 1337.1)
    elseif lfo_shape_idx == 6 then
      -- Smooth random walk representation
      lfo = math.sin(ui_time * lfo_rate * 2.1) * math.cos(ui_time * lfo_rate * 1.3)
    elseif lfo_shape_idx == 7 then
      -- Pure White Noise (Unfiltered random per frame)
      lfo = (math.random() * 2 - 1)
    end

    lfo = lfo * (1.0 - params:get("mwLfoGlobal"))

    -- Internal Visual Blink LFO for Feedback Representation
    local v_fb_time = util.clamp(params:get("fbTime"), 0.01, 0.5)
    local v_blink_rate = 1.0 / v_fb_time
    local v_blink_phase = (ui_time * v_blink_rate) % 1.0
    local v_blink_lfo = v_blink_phase < 0.5 and 1 or -1

    -- 3. Draw Background Starfield
    for _, star in ipairs(stars) do
      local display_bright = 0

      if star.type == 1 then
        -- Voice Linked Star (The Twinkle)
        local note = note_order[star.v_idx]
        if note and anim_notes[note] then
          local base_env = anim_notes[note].env
          if anim_notes[note].state == "on" and base_env > 0.1 then
            local blink_comp = (v_blink_lfo * params:get("fbAmt"))
            -- Twinkle intensity is increased by fbAmt
            local twinkle = math.random() * (0.2 + (params:get("fbAmt") * 0.3))
            display_bright = math.floor(base_env * (1.0 - twinkle) * 15)
          else
            display_bright = math.floor(base_env * 15)
          end
        end

      elseif star.type == 2 then
        -- LFO Linked Star (The SMOOTH Phosphor Glow)
        local dist = math.abs(lfo - star.lfo_val)
        local target_bright = 0

        -- Widen the detection window slightly to catch fast LFOs
        if dist < 0.3 then
          target_bright = 15 * (1.0 - (dist / 0.3))
        end

        -- Exponential Interpolation for ultra-smooth fading
        if target_bright > star.bright then
          -- Attack: Glides up quickly
          star.bright = star.bright + ((target_bright - star.bright) * 0.6)
        else
          -- Decay: Multiplies by 0.85 every frame for a long, glowing tail
          star.bright = star.bright * 0.85
        end

        if star.bright < 0.1 then star.bright = 0 end
        display_bright = math.floor(star.bright)
      end

      if display_bright > 0 then
        screen.level(util.clamp(display_bright, 0, 15))
        screen.pixel(star.x, star.y)
      end
    end

    -- 4. Draw Magnetar Core & Plumes
    local cx, cy = 94, 32
    local spread = params:get("panSpread")

    local plume_bright = math.max(0, math.floor(spread * 8))
    if plume_bright > 0 then
      screen.level(plume_bright)
      for i=1, 3 do
        local pl = math.random() * 25 * spread
        local spread_offset = math.random(-1, 1)
        screen.move(cx + spread_offset, cy)
        screen.line(cx + spread_offset, cy - 8 - pl)
        screen.stroke()
        screen.move(cx + spread_offset, cy)
        screen.line(cx + spread_offset, cy + 8 + pl)
        screen.stroke()
      end
    end

    -- Core
    screen.level(15)
    screen.circle(cx, cy, 2 + math.floor(voices_active/2))
    screen.fill()

    -- 5. Draw Orbiting Voice Particles
    local orbit_width = 8 + (ratio_values[params:get("formantRatio")] * 2)
    local orbit_height = 2 + (params:get("overlap") * 15)
    local orbit_tilt = params:get("shape") * (math.pi / 2.5)

    for note, data in pairs(anim_notes) do
      local speed = (data.freq / 300) + (lfo * params:get("modLfoFreq"))
      data.angle = data.angle + speed * 0.1

      local radius_x = orbit_width + data.dist_offset
      local radius_y = orbit_height
      local ox = math.cos(data.angle) * radius_x
      local oy = math.sin(data.angle) * radius_y

      local px = cx + (ox * math.cos(orbit_tilt) - oy * math.sin(orbit_tilt))
      local py = cy + (ox * math.sin(orbit_tilt) + oy * math.cos(orbit_tilt))

      local size = math.max(1, math.ceil(data.env * data.vel * 3))
      local bright = math.max(1, math.floor(data.env * 15))

      screen.level(bright)
      screen.rect(math.floor(px), math.floor(py) - math.floor(size/2), size, size)
      screen.fill()
    end

  else
    -- ==========================================
    -- PARAMETER MENUS (FULL PAGE)
    -- ==========================================
    screen.level(15)
    screen.move(0, 10)
    screen.text(pages[current_page].name .. "   [V:" .. voices_active .. "]")
    screen.move(0, 14)
    screen.line(128, 14)
    screen.stroke()

    local start_idx = math.max(1, selected_param - 4)
    local end_idx = math.min(#pages[current_page].params, start_idx + 4)

    if end_idx - start_idx < 4 and #pages[current_page].params >= 5 then
      start_idx = end_idx - 4
    end

    for i = start_idx, end_idx do
      local p = pages[current_page].params[i]
      local y = 26 + (i - start_idx) * 9

      if i == selected_param then
        screen.level(15)
        screen.move(0, y)
        screen.text(">")
      else
        screen.level(4)
      end

      screen.move(8, y)
      screen.text(p.disp)

      local v_str = (p.id == "formantRatio") and ratio_labels[params:get(p.id)] or params:string(p.id)
      screen.move(128, y)
      screen.text_right(v_str)
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
  add_eng_param("overlap", "Overlap (PulWM)", 0.01, 1.6, 0.03)
  add_eng_param("phaseOffset", "Phase Offset", 0.0, 6.28, 0.0)
  add_eng_param("panSpread", "Stereo Spread", 0.0, 1.0, 0.0)

  params:add_group("Waveform Morph", 2)
  add_eng_param("shape", "Shape (Sin-Tri-Sq)", 0.0, 2.0, 0.0)
  add_eng_param("pwm", "Square PWM", 0.0, 1.0, 0.5)

  params:add_group("Granular Feedback", 4)
  add_eng_param("fbAmt", "Feedback Amount", 0.0, 0.9999, 0.0)
  add_eng_param("fbTime", "Feedback Time", 0.0001, 0.5, 0.01)
  add_eng_param("fbDamp", "Feedback Dampen", 0.0, 0.99, 0.5)
  params:add_option("fbTrackMode", "FB Track Mode", {"Free", "Fundamental", "Formant"}, 1)
  params:set_action("fbTrackMode", function(v) engine.setParam("fbTrackMode", v - 1) end)

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
  params:add_option("lfoShape", "LFO Shape", {"Sine", "Tri", "Saw", "Square", "S&H", "Smooth", "White"}, 1)
  params:set_action("lfoShape", function(v) engine.setParam("lfoShape", v - 1) end)
  add_eng_param("lfoRate", "LFO Rate Hz", 0.01, 450.0, 0.8)
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