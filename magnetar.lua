--
--           Magnetar
-- Polyphonic Pulsar Synthesizer
--
--   E1 - select parameter group
--   E2 - select parameter
--   E3 - adjust parameter value
--
--   K3 - return to default value
--   K1 + E1 - select between
--        animation and full menu
engine.name = 'Magnetar'
local MusicUtil = require("musicutil")

local MAX_VOICES = 12
local active_notes = {}
local note_order = {}
local voices_active = 0
local ui_time = 0

local show_splash = true
local current_page = 0
local menu_page = 1
local selected_param = 1
local k1_held = false

local anim_notes = {}
local stars = {}

local pages = {
  { name = "Voice", params = {
      {id="voiceMode",    disp="Voice Mode"},
      {id="polyVoices",   disp="Polyphony Cap"},
      {id="voiceSpread",  disp="Unison Spread"},
      {id="glide",        disp="Glide Time"},
      {id="panSpread",    disp="Stereo Spread"}
    }
  },
  { name = "Oscillator", params = {
      {id="shape",        disp="Wave Shape"},
      {id="pwm",          disp="Pulse Width"},
      {id="formantRatio", disp="Formant Ratio"},
      {id="formantFine",  disp="Formant Fine"},
      {id="overlap",      disp="Wavelet Overlap"},
      {id="phaseOffset",  disp="Phase Offset"},
    }
  },
  { name = "Comb Filter", params = {
      {id="fbTrackMode",  disp="Tracking Mode"},
      {id="fbAmt",        disp="Amount"},
      {id="fbTime",       disp="Time"},
      {id="fbDamp",       disp="Dampening"}
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
      {id="modVelFbTime",  disp="->Feedback Time"},
      {id="modVelFbDamp",  disp="->Feedback Dampening"},
    }
  },
  { name = "Modwheel", params = {
      {id="mwFormant",    disp="->Formant"},
      {id="mwOverlap",    disp="->Overlap"},
      {id="mwShape",      disp="->OSC Wave Shape"},
      {id="mwFbTime",     disp="->Feedback Time"},
      {id="mwFbDamp",     disp="->Feedback Dampening"}
    }
  }
}

local ratio_values = {0.125, 0.25, 0.5, 1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 7.0, 8.0, 9.0, 10.0, 11.0, 12.0, 13.0, 14.0}
local ratio_labels = {"0.125", "0.25", "0.5", "1", "2", "3", "4", "5", "6", "7", "8", "9", "10", "11", "12", "13", "14"}

function init_stars()
  local function get_valid_pos()
    local valid = false
    local rx, ry
    local attempts = 0
    local min_dist = 9

    while not valid and attempts < 100 do
      rx = math.random(0, 127)
      ry = math.random(15, 50)
      valid = true

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

  for i=1, 12 do
    local sx, sy = get_valid_pos()
    table.insert(stars, { x = sx, y = sy, type = 1, v_idx = (i % MAX_VOICES) + 1 })
  end

  local thresholds = {-1.0, -0.5, 0.0, 0.5, 1.0}
  for i=1, 10 do
    local sx, sy = get_valid_pos()
    table.insert(stars, { x = sx, y = sy, type = 2, lfo_val = thresholds[(i % 5) + 1], bright = 0 })
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

      local atk_rate = 1.0 / math.max(0.01, params:get("atk") * 15)
      local rel_rate = 1.0 / math.max(0.01, params:get("rel") * 15)

      for note, data in pairs(anim_notes) do
        if data.state == "on" then
          data.env = math.min(1.0, data.env + atk_rate)
        else
          data.env = math.max(0.0, data.env - rel_rate)
          if data.env <= 0.01 then
            anim_notes[note] = nil
          end
        end
      end

      redraw()
    end
  end)
end

-- Abstract Detune Function: Converts 0-1 spread into precise semitone offsets
local function calc_detune_hz(base_hz, voice_index, center_index)
  local spread = params:get("voiceSpread")
  local step_st = 0

  if spread <= 0.5 then
    -- Continuous: 0 to 2 semitones (Major 2nd)
    step_st = (spread * 2) * 2
  else
    -- Stepped: Minor 3rd, Major 3rd, Perfect 4th, Perfect 5th, Major 6th, Octave, Octave+5th
    local snaps = {3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19}
    local idx = math.floor((spread - 0.5001) * 2 * #snaps) + 1
    idx = util.clamp(idx, 1, #snaps)
    step_st = snaps[idx]
  end

  local st_offset = (voice_index - center_index) * step_st
  -- True pitch calculation rather than simple linear multipliers
  return base_hz * (2 ^ (st_offset / 12))
end

function setup_midi()
  m = midi.connect()
  m.event = function(data)
    local d = midi.to_msg(data)
    local v_mode = params:get("voiceMode")

    -- Dismiss splash screen if MIDI is played
    if d.type == "note_on" and show_splash then
      show_splash = false
    end

    if d.type == "note_on" then
      if active_notes[d.note] then
        for i, n in ipairs(note_order) do
          if n == d.note then table.remove(note_order, i); break end
        end
      end

      local hz = MusicUtil.note_num_to_freq(d.note)
      local vel = d.vel / 127

      if v_mode == 1 then
        local active_limit = params:get("polyVoices")
        -- Voice Stealing: Use a WHILE loop in case the user lowered the cap
        -- drastically (e.g. from 12 to 4) while holding notes.
        while #note_order >= active_limit do
          local oldest = table.remove(note_order, 1)
          engine.noteOff(oldest)
          active_notes[oldest] = nil
          if anim_notes[oldest] then anim_notes[oldest].state = "off" end
          voices_active = voices_active - 1
        end

        engine.noteOn(d.note, hz, vel)
        active_notes[d.note] = true
        table.insert(note_order, d.note)
        voices_active = voices_active + 1
        anim_notes[d.note] = { freq = hz, vel = vel, env = 0, state = "on", angle = math.random() * math.pi * 2, dist_offset = math.random(-3,3) }

      elseif v_mode == 2 then
        local mono_voices = 8
        active_notes[d.note] = true
        table.insert(note_order, d.note)

        if voices_active == 0 then
          for i=1, mono_voices do
            local v_hz = calc_detune_hz(hz, i, 4.5)
            engine.noteOn(i, v_hz, vel)
            anim_notes[i] = { freq = v_hz, vel = vel, env = 0, state = "on", angle = math.random() * math.pi * 2, dist_offset = math.random(-3,3) }
          end
          voices_active = mono_voices
        else
          for i=1, mono_voices do
            local v_hz = calc_detune_hz(hz, i, 4.5)
            engine.setVoiceFreq(i, v_hz)
            if anim_notes[i] then anim_notes[i].freq = v_hz end
          end
        end

      elseif v_mode == 3 then
        -- 4x3 calculates its active note cap strictly based on the Polyphony user setting
        local max_cluster_notes = math.max(1, math.floor(params:get("polyVoices") / 3))

        while #note_order >= max_cluster_notes do
          local oldest = table.remove(note_order, 1)
          active_notes[oldest] = nil
          for i=1, 3 do
            local id = oldest * 10 + i
            engine.noteOff(id)
            if anim_notes[id] then anim_notes[id].state = "off" end
          end
          voices_active = voices_active - 3
        end

        active_notes[d.note] = true
        table.insert(note_order, d.note)

        for i=1, 3 do
          local v_hz = calc_detune_hz(hz, i, 2.0)
          local id = d.note * 10 + i
          engine.noteOn(id, v_hz, vel)
          anim_notes[id] = { freq = v_hz, vel = vel, env = 0, state = "on", angle = math.random() * math.pi * 2, dist_offset = math.random(-3,3) }
        end
        voices_active = voices_active + 3
      end

    elseif d.type == "note_off" then
      if not active_notes[d.note] then return end
      active_notes[d.note] = nil

      for i, n in ipairs(note_order) do
        if n == d.note then table.remove(note_order, i); break end
      end

      if v_mode == 1 then
        engine.noteOff(d.note)
        if anim_notes[d.note] then anim_notes[d.note].state = "off" end
        voices_active = voices_active - 1

      elseif v_mode == 2 then
        local mono_voices = 8
        if #note_order > 0 then
          local last_note = note_order[#note_order]
          local hz = MusicUtil.note_num_to_freq(last_note)
          for i=1, mono_voices do
            local v_hz = calc_detune_hz(hz, i, 4.5)
            engine.setVoiceFreq(i, v_hz)
            if anim_notes[i] then anim_notes[i].freq = v_hz end
          end
        else
          for i=1, mono_voices do
            engine.noteOff(i)
            if anim_notes[i] then anim_notes[i].state = "off" end
          end
          voices_active = 0
        end

      elseif v_mode == 3 then
        for i=1, 3 do
          local id = d.note * 10 + i
          engine.noteOff(id)
          if anim_notes[id] then anim_notes[id].state = "off" end
        end
        voices_active = voices_active - 3
      end

    elseif d.type == "cc" and d.cc == 1 then
      engine.setParam("modWheel", d.val / 127)
    end
  end
end

function key(n, z)
  -- Dismiss splash on any key press
  if show_splash and z == 1 then
    show_splash = false
    return
  end

  if n == 1 then k1_held = (z == 1) end
  if n == 3 and z == 1 then
    local target_page = current_page == 0 and menu_page or current_page
    local p_id = pages[target_page].params[selected_param].id
    params:set(p_id, params:get(p_id .. "_default") or params:lookup_param(p_id).default)
  end
end

function enc(n, delta)
  if show_splash then
    show_splash = false
    return
  end

  if n == 1 then
    if k1_held then
      if current_page == 0 then current_page = menu_page else menu_page = current_page; current_page = 0 end
    else
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

local function is_param_disabled(id)
  if id == "fbTime" and params:get("fbTrackMode") ~= 1 then return true end
  if (id == "voiceSpread" or id == "glide") and params:get("voiceMode") == 1 then return true end
  if id == "polyVoices" and params:get("voiceMode") == 2 then return true end
  if id == "lfoRate" and params:get("lfoShape") == 7 then return true end
  return false
end

function redraw()
  screen.clear()

  if show_splash then
    -- Draw randomly twinkling background stars
    for _, star in ipairs(stars) do
      screen.level(math.random(1, 6))
      screen.pixel(star.x, star.y)
    end

    local cx, cy = 64, 26

    -- Stylized Magnetar Plumes
    screen.level(5)
    for i=1, 5 do
      screen.move(cx - 2 + i, cy)
      screen.line(cx - 2 + i, cy - 24 + math.random(-2, 2))
      screen.stroke()
      screen.move(cx - 2 + i, cy)
      screen.line(cx - 2 + i, cy + 24 + math.random(-2, 2))
      screen.stroke()
    end

    -- Rotating Magnetic Field Rings
    screen.level(3)
    for i=1, 4 do
      local r = 8 + (i * 3)
      local phase = ui_time * (1.5 - (i * 0.2))
      screen.arc(cx, cy, r, phase, phase + math.pi/1.5)
      screen.stroke()
      screen.arc(cx, cy, r, phase + math.pi, phase + math.pi + math.pi/1.5)
      screen.stroke()
    end

    -- Pulsing Core
    screen.level(15)
    screen.circle(cx, cy, 5 + math.sin(ui_time * 3) * 1.5)
    screen.fill()

    -- Title Text
    screen.level(15)
    screen.move(64, 52)
    screen.text_center("M A G N E T A R")

    -- Controls Cheat Sheet
    screen.level(4)
    screen.move(64, 62)
    screen.text_center("E1:Group   E2:Param   E3:Val")

    screen.update()
    return
  end

  local target_page = current_page == 0 and menu_page or current_page
  local current_p = pages[target_page].params[selected_param]
  local p_id = current_p.id
  local p_val_str = params:string(p_id)

  if p_id == "formantRatio" then
    p_val_str = ratio_labels[params:get(p_id)]
  elseif p_id == "voiceMode" then
    local vm = params:get(p_id)
    p_val_str = (vm == 1) and "Poly" or ((vm == 2) and "Mono" or "4x3")
  elseif p_id == "voiceSpread" then
    local sp = params:get(p_id)
    if sp <= 0.5 then
      p_val_str = string.format("%.2f st", (sp * 2) * 2)
    else
      local snaps = {3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19}
      local idx = math.floor((sp - 0.5001) * 2 * #snaps) + 1
      idx = util.clamp(idx, 1, #snaps)
      p_val_str = snaps[idx] .. " st"
    end
  elseif p_id == "polyVoices" then
    p_val_str = string.format("%d Voices", params:get(p_id))
  end

  local full_p_name = params:lookup_param(p_id).name
  local is_disabled = is_param_disabled(p_id)

  if current_page == 0 then
    -- ==========================================
    -- MAIN PAGE (CORNERS)
    -- ==========================================
    screen.level(4)
    screen.move(0, 8)
    screen.text(pages[target_page].name .. " [" .. selected_param .. "/" .. #pages[target_page].params .. "]")

    if is_disabled then
      screen.level(1)
      screen.rect(0, 54, 128, 10)
      screen.fill()
    end

    screen.level(is_disabled and 4 or 15)
    screen.move(0, 62)
    screen.text(full_p_name)

    screen.move(128, 62)
    screen.text_right(p_val_str)

    local lfo_rate = params:get("lfoRate")
    local lfo_shape_idx = params:get("lfoShape")
    local lfo_phase = (ui_time * lfo_rate) % 1.0
    local lfo = 0

    if lfo_shape_idx == 1 then lfo = math.sin(lfo_phase * 2 * math.pi)
    elseif lfo_shape_idx == 2 then lfo = math.abs((lfo_phase * 4) - 2) - 1
    elseif lfo_shape_idx == 3 then lfo = (lfo_phase * 2) - 1
    elseif lfo_shape_idx == 4 then lfo = lfo_phase < 0.5 and 1 or -1
    elseif lfo_shape_idx == 5 then lfo = math.sin(math.floor(ui_time * lfo_rate) * 1337.1)
    elseif lfo_shape_idx == 6 then lfo = math.sin(ui_time * lfo_rate * 2.1) * math.cos(ui_time * lfo_rate * 1.3)
    elseif lfo_shape_idx == 7 then lfo = (math.random() * 2 - 1) end

    lfo = lfo * (1.0 - params:get("mwLfoGlobal"))

    local v_fb_time = util.clamp(params:get("fbTime"), 0.01, 0.5)
    local v_blink_rate = 1.0 / v_fb_time
    local v_blink_phase = (ui_time * v_blink_rate) % 1.0
    local v_blink_lfo = v_blink_phase < 0.5 and 1 or -1

    local v_mode = params:get("voiceMode")

    for _, star in ipairs(stars) do
      local display_bright = 0
      if star.type == 1 then
        local target_idx = nil

        if v_mode == 1 then
          target_idx = note_order[star.v_idx]
        elseif v_mode == 2 then
          target_idx = star.v_idx
        elseif v_mode == 3 then
          local note_idx = math.ceil(star.v_idx / 3)
          local base_note = note_order[note_idx]
          if base_note then
            local sub_idx = ((star.v_idx - 1) % 3) + 1
            target_idx = base_note * 10 + sub_idx
          end
        end

        local note = target_idx
        if note and anim_notes[note] then
          local base_env = anim_notes[note].env
          if anim_notes[note].state == "on" and base_env > 0.1 then
            local twinkle = math.random() * (0.2 + (params:get("fbAmt") * 0.3))
            display_bright = math.floor(base_env * (1.0 - twinkle) * 15)
          else
            display_bright = math.floor(base_env * 15)
          end
        end

      elseif star.type == 2 then
        local dist = math.abs(lfo - star.lfo_val)
        local target_bright = 0
        if dist < 0.3 then target_bright = 15 * (1.0 - (dist / 0.3)) end
        if target_bright > star.bright then star.bright = star.bright + ((target_bright - star.bright) * 0.6)
        else star.bright = star.bright * 0.85 end
        if star.bright < 0.1 then star.bright = 0 end
        display_bright = math.floor(star.bright)
      end

      if display_bright > 0 then
        screen.level(util.clamp(display_bright, 0, 15))
        screen.pixel(star.x, star.y)
      end
    end

    local cx, cy = 64, 32
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

    screen.level(15)
    screen.circle(cx, cy, 2 + math.floor(voices_active/2))
    screen.fill()

    local orbit_width = 8 + (ratio_values[params:get("formantRatio")] * 2)
    local orbit_height = 2 + (params:get("overlap") * 15)
    local orbit_tilt = params:get("shape") * (math.pi / 2.5)

    for note, data in pairs(anim_notes) do
      local speed = (data.freq / 300) + (lfo * params:get("modLfoFreq"))
      data.angle = data.angle + speed * 0.1

      local radius_x = orbit_width + data.dist_offset
      local radius_y = orbit_height

      -- Draw Fading Trails
      local trail_length = 6
      for i = 1, trail_length do
        -- Calculate previous angle positions
        local t_angle = data.angle - (speed * 0.1 * i * 1.5)
        local t_ox = math.cos(t_angle) * radius_x
        local t_oy = math.sin(t_angle) * radius_y

        local t_px = cx + (t_ox * math.cos(orbit_tilt) - t_oy * math.sin(orbit_tilt))
        local t_py = cy + (t_ox * math.sin(orbit_tilt) + t_oy * math.cos(orbit_tilt))

        -- Fade brightness progressively backwards
        local t_bright = math.floor((data.env * 15) * (1 - (i / (trail_length + 1))))
        if t_bright > 0 then
          screen.level(t_bright)
          screen.pixel(math.floor(t_px), math.floor(t_py))
        end
      end

      -- Draw Main Head Particle
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
    -- FULL MENU PAGE
    -- ==========================================
    screen.level(15)
    screen.move(0, 10)
    screen.text(pages[current_page].name .. "   [V:" .. voices_active .. "/" .. params:get("polyVoices") .. "]")
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
      local is_list_item_disabled = is_param_disabled(p.id)

      if is_list_item_disabled then
        screen.level(1)
        screen.rect(0, y - 7, 128, 9)
        screen.fill()
      end

      if i == selected_param then
        screen.level(is_list_item_disabled and 4 or 15)
        screen.move(0, y)
        screen.text(">")
      else
        screen.level(is_list_item_disabled and 3 or 4)
      end

      screen.move(8, y)
      screen.text(p.disp)

      local v_str = params:string(p.id)
      if p.id == "formantRatio" then
        v_str = ratio_labels[params:get(p.id)]
      elseif p.id == "voiceMode" then
        local vm = params:get(p.id)
        v_str = (vm == 1) and "Poly" or ((vm == 2) and "Mono" or "4x3")
      elseif p.id == "voiceSpread" then
        local sp = params:get(p.id)
        if sp <= 0.5 then
          v_str = string.format("%.2f st", (sp * 2) * 2)
        else
          local snaps = {3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19}
          local idx = math.floor((sp - 0.5001) * 2 * #snaps) + 1
          idx = util.clamp(idx, 1, #snaps)
          v_str = snaps[idx] .. " st"
        end
      elseif p.id == "polyVoices" then
        v_str = string.format("%d", params:get(p.id))
      end

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

  params:add_group("Voice", 5)

  params:add_option("voiceMode", "Voice Mode", {"Poly", "Mono Unison", "4x3 Unison"}, 1)
  params:set_action("voiceMode", function()
    for i=0, 127 do engine.noteOff(i) end
    for i=1, MAX_VOICES do engine.noteOff(i) end
    for n=0, 127 do
      for i=1, 3 do engine.noteOff(n*10+i) end
    end
    voices_active = 0
    anim_notes = {}
    note_order = {}
  end)
  -- The new Polyphony limiting parameter!
  params:add_number("polyVoices", "Polyphony Cap", 1, 12, 8)
  add_eng_param("voiceSpread", "Unison Spread", 0.0, 1.0, 0.1)
  add_eng_param("glide", "Glide Time", 0.0, 5.0, 0.0)
  add_eng_param("panSpread", "Stereo Spread", 0.0, 1.0, 0.0)

  params:add_group("Oscillator", 6)
  add_eng_param("shape", "Shape (Sin-Tri-Sq)", 0.0, 2.0, 0.0)
  add_eng_param("pwm", "Square PWM", 0.0, 1.0, 0.5)
  params:add_option("formantRatio", "Formant Ratio", ratio_labels, 4)
  params:set_action("formantRatio", function(v) engine.setParam("formantRatio", ratio_values[v]) end)
  add_eng_param("formantFine", "Formant Fine", 0.25, 1.75, 1.0)
  add_eng_param("overlap", "Overlap (PulWM)", 0.01, 1.6, 0.03)
  add_eng_param("phaseOffset", "Phase Offset", 0.0, 6.28, 0.0)

  params:add_group("Comb Filter", 4)
  params:add_option("fbTrackMode", "Tracking Mode", {"Free", "Fundamental", "Formant"}, 1)
  params:set_action("fbTrackMode", function(v) engine.setParam("fbTrackMode", v - 1) end)
  add_eng_param("fbAmt", "Feedback Amount", 0.0, 0.9999, 0.0)
  add_eng_param("fbTime", "Feedback Time", 0.0001, 0.5, 0.01)
  add_eng_param("fbDamp", "Feedback Dampen", 0.0, 0.99, 0.5)

  params:add_group("Envelope", 9)
  add_eng_param("atk", "Attack", 0.001, 5.0, 0.01)
  add_eng_param("dec", "Decay", 0.001, 5.0, 0.2)
  add_eng_param("sus", "Sustain", 0.0, 1.0, 0.4)
  add_eng_param("rel", "Release", 0.001, 10.0, 0.2)
  add_eng_param("modEnvFormant", "Env -> Formant", -2.0, 2.0, 0.0)
  add_eng_param("modEnvOverlap", "Env -> Overlap", -1.0, 1.0, 0.0)
  add_eng_param("modEnvPhase", "Env -> Phase", -6.28, 6.28, 0.0)
  add_eng_param("modEnvShape", "Env -> Shape", -2.0, 2.0, 0.0)
  add_eng_param("modEnvPwm", "Env -> PWM", -1.0, 1.0, 0.0)

  params:add_group("LFO", 11)
  params:add_option("lfoShape", "LFO Shape", {"Sine", "Tri", "Saw", "Square", "S&H", "Smooth", "Noise"}, 1)
  params:set_action("lfoShape", function(v) engine.setParam("lfoShape", v - 1) end)
  add_eng_param("lfoRate", "LFO Rate Hz", 0.01, 200.0, 0.8)
  add_eng_param("mwLfoGlobal", "ModWheel LFO Depth", 0.0, 1.0, 0.0)
  add_eng_param("modLfoFreq", "LFO -> Freq", -1.0, 1.0, 0.0)
  add_eng_param("modLfoAmp", "LFO -> Amp", 0.0, 1.0, 0.0)
  add_eng_param("modLfoFormant", "LFO -> Formant", -2.0, 2.0, 0.0)
  add_eng_param("modLfoOverlap", "LFO -> Overlap", -1.0, 1.0, 0.0)
  add_eng_param("modLfoShape", "LFO -> Shape", -2.0, 2.0, 0.0)
  add_eng_param("modLfoPwm", "LFO -> PWM", -1.0, 1.0, 0.0)
  add_eng_param("modLfoFbTime", "LFO -> FB Time", -1.0, 1.0, 0.0)
  add_eng_param("modLfoFbDamp", "LFO -> FB Damp", -1.0, 1.0, 0.0)

  params:add_group("Velocity", 6)
  add_eng_param("velAmp", "Vel -> Amp", 0.0, 1.0, 1.0)
  add_eng_param("modVelFormant", "Vel -> Formant", -2.0, 2.0, 0.0)
  add_eng_param("modVelOverlap", "Vel -> Overlap", -1.0, 1.0, 0.0)
  add_eng_param("modVelShape", "Vel -> Shape", -2.0, 2.0, 0.0)
  add_eng_param("modVelFbTime", "Vel -> FB Time", -1.0, 1.0, 0.0)
  add_eng_param("modVelFbDamp", "Vel -> FB Damp", -1.0, 1.0, 0.0)

  params:add_group("Modwheel", 5)
  add_eng_param("mwFormant", "Wheel -> Formant", -2.0, 2.0, 0.0)
  add_eng_param("mwOverlap", "Wheel -> Overlap", -1.0, 1.0, 0.0)
  add_eng_param("mwShape", "Wheel -> Shape", -2.0, 2.0, 0.0)
  add_eng_param("mwFbTime", "Wheel -> FB Time", -1.0, 1.0, 0.0)
  add_eng_param("mwFbDamp", "Wheel -> FB Damp", -1.0, 1.0, 0.0)

  params:bang()
end