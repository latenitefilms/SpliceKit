-- Generate social-style captions on the timeline
-- Uses FCP Native transcription, then generates bold_pop captions.

-- Check if transcript already has words (from previous transcription)
local ts = sk.rpc("transcript.getState", {})
local words = ts and ts.words

if not words or #words == 0 then
    -- No words yet — start transcription if not already running
    if not ts or ts.status ~= "transcribing" then
        sk.rpc("transcript.setEngine", {engine = "fcpNative"})
        sk.rpc("transcript.open", {})
    end
    -- Wait up to 15 seconds for short clips
    sk.toast("Transcribing timeline...")
    for i = 1, 15 do
        sk.sleep(1)
        ts = sk.rpc("transcript.getState", {})
        if ts and ts.wordCount and ts.wordCount > 0 then
            words = ts.words
            break
        end
        if ts and ts.status == "error" then
            sk.alert("Captions", "Transcription error:\n" .. (ts.errorMessage or "unknown"))
            return
        end
    end
end

if not words or #words == 0 then
    -- Still transcribing — long clip, tell user to wait
    sk.alert("Captions",
        "Transcription in progress — FCP Native can take several minutes for long clips.\n\n" ..
        "Run this script again once FCP finishes transcribing.\n" ..
        "You can check progress in the Transcript panel (Ctrl+Option+T).")
    return
end

-- Words available — generate captions
sk.toast("Generating captions (" .. #words .. " words)...")
sk.rpc("captions.open", {style = "bold_pop"})
sk.sleep(1)
sk.rpc("captions.setWords", {words = words})
sk.rpc("captions.setStyle", {preset_id = "bold_pop", position = "bottom"})
sk.rpc("captions.setGrouping", {mode = "social"})
sk.rpc("captions.generate", {style = "bold_pop"})

-- Wait for generation
for i = 1, 30 do
    sk.sleep(1)
    local state = sk.rpc("captions.getState", {})
    if state and state.status == "ready" then
        sk.alert("Captions", "Captions generated and placed on timeline")
        return
    end
    if state and state.error then
        local msg = type(state.error) == "table" and state.error.message or tostring(state.error)
        sk.alert("Captions", "Generation failed:\n" .. msg)
        return
    end
end
sk.alert("Captions", "Generation started — check timeline for results")
