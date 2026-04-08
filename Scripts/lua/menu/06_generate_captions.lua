-- Generate social-style captions on the timeline
-- Requires transcription first — opens the caption panel and waits for words.
sk.toast("Transcribing timeline...")
sk.rpc("captions.open", {style = "bold_pop"})

-- Wait for transcription to produce words (up to 120s)
local ready = false
for i = 1, 120 do
    sk.sleep(1)
    local state = sk.rpc("captions.getState", {})
    if not state then break end

    -- Check for hard errors (e.g. missing transcriber)
    if state.error then
        local msg = state.error
        if type(msg) == "table" then msg = msg.message or "unknown error" end
        sk.alert("Captions", "Transcription failed:\n" .. tostring(msg))
        return
    end

    -- Check if we have segments (transcription done)
    if state.segmentCount and state.segmentCount > 0 then
        ready = true
        break
    end

    -- Show progress
    if i % 10 == 0 then
        sk.toast("Still transcribing... (" .. i .. "s)")
    end
end

if not ready then
    sk.alert("Captions", "Timed out waiting for transcription.\nMake sure a transcription engine is available.")
    return
end

-- Configure style and generate
sk.toast("Generating captions...")
sk.rpc("captions.setStyle", {preset_id = "bold_pop", position = "bottom"})
sk.rpc("captions.setGrouping", {mode = "social"})
local r = sk.rpc("captions.generate", {style = "bold_pop"})
if r and r.error then
    local msg = r.error
    if type(msg) == "table" then msg = msg.message or "unknown" end
    sk.alert("Captions", "Generation failed:\n" .. tostring(msg))
else
    sk.alert("Captions", "Captions generated and placed on timeline")
end
