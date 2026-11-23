import Foundation
import MCP

private let timelineNavigationActions: Set<String> = [
    "beatDetectionGrid", "deselectAll", "enableBeatDetection", "enterFullScreen", "expandSubroles",
    "goToColorBoard", "goToInspector", "goToTimeline", "goToViewer", "nextEdit", "nextKeyframe",
    "nextMarker", "previousEdit", "previousKeyframe", "previousMarker", "selectAll",
    "selectClipAtPlayhead", "selectNextItem", "selectToPlayhead", "selectUpperItem",
    "showAudioAnimation", "showAudioLanes", "showCinematicEditor", "showDuplicateRanges",
    "showKeywordEditor", "showMagneticMaskEditor", "showPrecisionEditor", "showTrackingEditor",
    "showVideoAnimation", "soloAnimation", "timelineHistoryBack", "timelineHistoryForward",
    "timelineScrolling", "toggleAudioSkimming", "toggleClipSkimming", "toggleInspector",
    "toggleInspectorHeight", "togglePrecisionEditor", "toggleSkimming", "toggleSnapping",
    "toggleTimeline", "toggleTimelineIndex", "verticalZoomToFit", "zoomIn", "zoomOut", "zoomToFit",
    "zoomToSamples",
]

private let timelineEditingActions: Set<String> = [
    "addAdjustmentClip", "addBasicLowerThird", "addBasicTitle", "addCaption", "addChannelEQ",
    "addChapterMarker", "addColorAdjustment", "addColorBoard", "addColorCurves", "addColorWheels",
    "addDefaultAudioEffect", "addDefaultVideoEffect", "addEnhanceLightAndColor", "addHueSaturation",
    "addKeyframe", "addKeywordGroup1", "addKeywordGroup2", "addKeywordGroup3", "addKeywordGroup4",
    "addKeywordGroup5", "addKeywordGroup6", "addKeywordGroup7", "addMagneticMask", "addMarker",
    "addToSoloedClips", "addTodoMarker", "addTransition", "addVideoGenerator", "adjustVolumeDown",
    "adjustVolumeUp", "alignAudioToVideo", "analyzeAndFix", "appendEdit", "applyAudioFades",
    "autoReframe", "backgroundTasks", "balanceColor", "changeDuration", "clearRange",
    "connectToPrimaryStoryline", "consolidateEventMedia", "copy", "copyAttributes", "copyTimecode",
    "createAudition", "createCompoundClip", "createMulticamClip", "createStoryline", "detachAudio",
    "disable", "duplicateProject", "editRoles", "enableDisable", "enhanceAudio", "expandAudio",
    "expandAudioComponents", "exportXML", "favorite", "finalizeAudition", "find", "findAndReplaceTitle",
    "insertEdit", "insertGap", "insertPlaceholder", "libraryProperties", "liftFromPrimaryStoryline",
    "makeClipsUnique", "matchAudio", "matchColor", "mergeEvents", "nextAuditionPick", "nextColorEffect",
    "openClip", "paste", "pasteAllAttributes", "pasteAsConnected", "pasteAttributes", "pasteEffects",
    "previousAuditionPick", "previousColorEffect", "projectProperties", "recordVoiceover",
    "referenceNewParentClip", "reject", "removeAttributes", "renameClip", "renderAll", "renderSelection",
    "resetColorBoard", "revealInBrowser", "revealInFinder", "revealProjectInBrowser", "setClipRange",
    "setRangeEnd", "setRangeStart", "shareSelection", "smartConform", "snapshotProject", "solo",
    "synchronizeClips", "toggleAllColorOff", "transcodeMedia", "unrate", "volumeMute",
]

private let timelineDestructiveActions: Set<String> = [
    "appendEditAudio", "appendEditVideo", "avEditModeAudio", "avEditModeBoth", "avEditModeVideo",
    "blade", "bladeAll", "breakApartClipItems", "closeLibrary", "collapseToConnectedStoryline",
    "connectEditAudio", "connectEditBacktimed", "connectEditVideo", "cut", "delete",
    "deleteGeneratedFiles", "deleteKeyframes", "deleteMarker", "deleteMarkersInSelection",
    "extendEditToPlayhead", "freezeFrame", "hideClip", "insertEditAudio", "insertEditVideo", "joinClips",
    "moveToTrash", "nudgeDown", "nudgeLeft", "nudgeRight", "nudgeUp", "overwriteEdit",
    "overwriteEditAudio", "overwriteEditVideo", "overwriteToPrimaryStoryline",
    "removeAllKeyframesFromClip", "removeAllKeywords", "removeAnalysisKeywords", "removeEffects",
    "replaceFromEnd", "replaceFromStart", "replaceWhole", "replaceWithGap", "resolveOverlaps",
    "retimeBladeSpeed", "retimeCustomSpeed", "retimeFast20x", "retimeFast2x", "retimeFast4x",
    "retimeFast8x", "retimeFloorFrame", "retimeFrameBlending", "retimeHold", "retimeInstantReplayHalf",
    "retimeInstantReplayQuarter", "retimeNormal", "retimeOpticalFlow", "retimeReset", "retimeReverse",
    "retimeSlow10", "retimeSlow25", "retimeSlow50", "retimeSpeedRampFromZero", "retimeSpeedRampToZero",
    "splitCaption", "toggleDuplicateDetection", "toggleSelectedEffectsOff", "trimEnd", "trimStart",
    "trimToPlayhead",
]

/// Translate the public MCP arguments into the corresponding editing RPC.
func editingRequest(_ name: String, _ arguments: Arguments) throws -> BridgeRequest? {
    switch name {
    case "bridge_status":
        return BridgeRequest("system.version")
    case "bridge_alive":
        return BridgeRequest("bridge.alive")
    case "bridge_describe":
        var parameters: [String: Value] = [:]
        if arguments["method"].truthy {
            parameters["method"] = arguments["method"]
        }
        if arguments["safety"].truthy {
            parameters["safety"] = arguments["safety"]
        }
        return BridgeRequest("bridge.describe", parameters)
    case "bridge_safety_tags":
        return BridgeRequest("bridge.safetyTags")
    case "events_subscribe":
        return BridgeRequest("events.subscribe", ["patterns": arguments["patterns"].truthy ? arguments["patterns"] : .array([.string("*")])])
    case "events_unsubscribe":
        return BridgeRequest("events.unsubscribe")
    case "events_status":
        return BridgeRequest("events.status")
    case "async_status":
        return BridgeRequest("async.status")
    case "background_render_status":
        return BridgeRequest("backgroundRender.status")
    case "background_render_control":
        let normalized: Value = .string(arguments["action"].text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())
        if !["hold_off", "low_overhead"].contains(normalized.text) {
            throw ToolFailure("action must be 'hold_off' or 'low_overhead'.")
        }
        if arguments["seconds"].number <= 0 {
            throw ToolFailure("seconds must be > 0.")
        }
        return BridgeRequest("backgroundRender.control", ["action": normalized, "seconds": arguments["seconds"]])
    case "timeline_action":
        return BridgeRequest("timeline.action", ["action": arguments["action"], "dry_run": arguments["dry_run"]])
    case "timeline_navigation_action":
        if !timelineNavigationActions.contains(arguments["action"].text) {
            throw ToolFailure("'" + arguments["action"].text + "' is not a supported navigation action. Use timeline_edit_action(), timeline_destructive_action(), history_action(), or legacy timeline_action().")
        }
        return BridgeRequest("timeline.action", ["action": arguments["action"]])
    case "timeline_edit_action":
        if !timelineEditingActions.contains(arguments["action"].text) {
            throw ToolFailure("'" + arguments["action"].text + "' is not a supported non-destructive edit action. Use timeline_navigation_action(), timeline_destructive_action(), history_action(), or legacy timeline_action().")
        }
        return BridgeRequest("timeline.action", ["action": arguments["action"]])
    case "timeline_destructive_action":
        if !timelineDestructiveActions.contains(arguments["action"].text) {
            throw ToolFailure("'" + arguments["action"].text + "' is not a supported destructive action. Use timeline_navigation_action(), timeline_edit_action(), history_action(), or legacy timeline_action().")
        }
        return BridgeRequest("timeline.action", ["action": arguments["action"]])
    case "history_action":
        if !["redo", "undo"].contains(arguments["action"].text) {
            throw ToolFailure("'" + arguments["action"].text + "' is not a supported history action. Valid actions are: undo, redo.")
        }
        return BridgeRequest("timeline.action", ["action": arguments["action"]])
    case "playback_action":
        return BridgeRequest("playback.action", ["action": arguments["action"]])
    case "detect_scene_changes":
        if arguments["action"] != .string("detect") {
            throw ToolFailure("detect_scene_changes() is read-only. Use mark_scene_changes() or blade_scene_changes().")
        }
        return BridgeRequest("scene.detect", ["threshold": arguments["threshold"], "action": arguments["action"], "sampleInterval": arguments["sample_interval"]])
    case "mark_scene_changes":
        return BridgeRequest("scene.detect", ["threshold": arguments["threshold"], "action": .string("markers"), "sampleInterval": arguments["sample_interval"]])
    case "blade_scene_changes":
        return BridgeRequest("scene.detect", ["threshold": arguments["threshold"], "action": .string("blade"), "sampleInterval": arguments["sample_interval"]])
    case "seek_to_time":
        return BridgeRequest("playback.seekToTime", ["seconds": arguments["seconds"]])
    case "get_timeline_clips":
        return BridgeRequest("timeline.getDetailedState", ["limit": arguments["limit"]])
    case "get_selected_clips":
        return BridgeRequest("timeline.getDetailedState")
    case "set_timeline_range":
        return BridgeRequest("timeline.setRange", ["startSeconds": arguments["start_seconds"], "endSeconds": arguments["end_seconds"]])
    case "batch_export":
        var parameters: [String: Value] = ["scope": arguments["scope"]]
        if arguments["folder"].truthy {
            parameters["folder"] = arguments["folder"]
        }
        return BridgeRequest("timeline.batchExport", parameters)
    case "import_fcpxml":
        return BridgeRequest("fcpxml.import", ["xml": arguments["xml"], "internal": arguments["internal"]])
    case "import_url":
        var parameters: [String: Value] = ["url": arguments["url"], "mode": arguments["mode"]]
        if arguments["target_event"].truthy {
            parameters["target_event"] = arguments["target_event"]
        }
        if arguments["title"].truthy {
            parameters["title"] = arguments["title"]
        }
        if arguments["highest_quality"].truthy {
            parameters["highest_quality"] = .bool(true)
        }
        let method: Value = arguments["wait_until_complete"].truthy ? .string("urlImport.import") : .string("urlImport.start")
        return BridgeRequest(method.text, parameters)
    case "import_url_status":
        return BridgeRequest("urlImport.status", ["job_id": arguments["job_id"]])
    case "cancel_import_url":
        return BridgeRequest("urlImport.cancel", ["job_id": arguments["job_id"]])
    case "get_clip_effects":
        var parameters: [String: Value] = [:]
        if arguments["handle"].truthy {
            parameters["handle"] = arguments["handle"]
        }
        return BridgeRequest("effects.getClipEffects", parameters)
    case "analyze_timeline":
        return BridgeRequest("timeline.getDetailedState")
    case "add_markers_at_times":
        let marker_list = try arguments["markers"].decodedJSON()
        return BridgeRequest("timeline.addMarkers", ["markers": marker_list])
    case "blade_at_times":
        let time_list = try arguments["times"].decodedJSON()
        return BridgeRequest("timeline.bladeAtTimes", ["times": time_list])
    case "get_active_libraries":
        return BridgeRequest("system.callMethodWithArgs", ["target": .string("FFLibraryDocument"), "selector": .string("copyActiveLibraries"), "args": .array([]), "classMethod": .bool(true), "returnHandle": .bool(true)])
    case "is_library_updating":
        return BridgeRequest("system.callMethod", ["className": .string("FFLibraryDocument"), "selector": .string("isAnyLibraryUpdating"), "classMethod": .bool(true)])
    case "open_transcript":
        var parameters: [String: Value] = [:]
        if arguments["file_url"].truthy {
            parameters["fileURL"] = arguments["file_url"]
        }
        if arguments["force_retranscribe"].truthy {
            parameters["forceRetranscribe"] = .bool(true)
        }
        return BridgeRequest("transcript.open", parameters)
    case "get_transcript":
        return BridgeRequest("transcript.getState")
    case "delete_transcript_words":
        return BridgeRequest("transcript.deleteWords", ["startIndex": arguments["start_index"], "count": arguments["count"]])
    case "move_transcript_words":
        return BridgeRequest("transcript.moveWords", ["startIndex": arguments["start_index"], "count": arguments["count"], "destIndex": arguments["dest_index"]])
    case "close_transcript":
        return BridgeRequest("transcript.close")
    case "search_transcript":
        return BridgeRequest("transcript.search", ["query": arguments["query"]])
    case "delete_transcript_silences":
        return BridgeRequest("transcript.deleteSilences", ["minDuration": arguments["min_duration"]])
    case "set_transcript_speaker":
        return BridgeRequest("transcript.setSpeaker", ["speaker": arguments["speaker"], "startIndex": arguments["start_index"], "count": arguments["count"]])
    case "set_silence_threshold":
        return BridgeRequest("transcript.setSilenceThreshold", ["threshold": arguments["threshold"]])
    case "list_effects":
        var parameters: [String: Value] = ["type": arguments["type"]]
        if arguments["filter"].truthy {
            parameters["filter"] = arguments["filter"]
        }
        return BridgeRequest("effects.listAvailable", parameters)
    case "apply_effect":
        if (!(arguments["name"].truthy)) && (!(arguments["effectID"].truthy)) {
            throw ToolFailure("provide either name or effectID")
        }
        var parameters: [String: Value] = [:]
        if arguments["effectID"].truthy {
            parameters["effectID"] = arguments["effectID"]
        }
        if arguments["name"].truthy {
            parameters["name"] = arguments["name"]
        }
        return BridgeRequest("effects.apply", parameters)
    case "list_transitions":
        var parameters: [String: Value] = [:]
        if arguments["filter"].truthy {
            parameters["filter"] = arguments["filter"]
        }
        return BridgeRequest("transitions.list", parameters)
    case "apply_transition":
        if (!(arguments["name"].truthy)) && (!(arguments["effectID"].truthy)) {
            throw ToolFailure("provide either name or effectID")
        }
        var parameters: [String: Value] = [:]
        if arguments["effectID"].truthy {
            parameters["effectID"] = arguments["effectID"]
        }
        if arguments["name"].truthy {
            parameters["name"] = arguments["name"]
        }
        if arguments["freeze_extend"].truthy {
            parameters["freezeExtend"] = .bool(true)
        }
        return BridgeRequest("transitions.apply", parameters)
    case "apply_transition_to_all_clips":
        return BridgeRequest("command.execute", ["action": .string("addTransitionToAll"), "type": .string("timeline")])
    case "show_command_palette":
        return BridgeRequest("command.show")
    case "hide_command_palette":
        return BridgeRequest("command.hide")
    case "open_livecam":
        return BridgeRequest("liveCam.show")
    case "close_livecam":
        return BridgeRequest("liveCam.hide")
    case "get_livecam_status":
        return BridgeRequest("liveCam.status")
    case "search_commands":
        return BridgeRequest("command.search", ["query": arguments["query"], "limit": arguments["limit"]])
    case "execute_command":
        return BridgeRequest("command.execute", ["action": arguments["action"], "type": arguments["type"]])
    case "ai_command_gemma":
        return BridgeRequest("command.aiGemma", ["query": arguments["query"], "model": arguments["model"]])
    case "execute_menu_command":
        return BridgeRequest("menu.execute", ["menuPath": arguments["menu_path"], "dry_run": arguments["dry_run"]])
    case "list_menus":
        var parameters: [String: Value] = ["depth": arguments["depth"]]
        if arguments["menu"].truthy {
            parameters["menu"] = arguments["menu"]
        }
        return BridgeRequest("menu.list", parameters)
    case "get_inspector_properties":
        return BridgeRequest("inspector.get", ["property": arguments["property"]])
    case "set_inspector_property":
        return BridgeRequest("inspector.set", ["property": arguments["property"], "value": arguments["value"]])
    case "get_title_text":
        return BridgeRequest("inspector.getTitle")
    case "verify_captions":
        return BridgeRequest("captions.verify")
    case "toggle_panel":
        return BridgeRequest("view.toggle", ["panel": arguments["panel"]])
    case "set_workspace":
        return BridgeRequest("view.workspace", ["workspace": arguments["workspace"]])
    case "select_tool":
        return BridgeRequest("tool.select", ["tool": arguments["tool"]])
    case "assign_role":
        return BridgeRequest("roles.assign", ["type": arguments["type"], "role": arguments["role"]])
    case "mixer_get_state":
        return BridgeRequest("mixer.getState")
    case "mixer_set_volume":
        var parameters: [String: Value] = ["handle": arguments["handle"]]
        if arguments["volume_db"] != .null {
            parameters["volumeDB"] = arguments["volume_db"]
        } else {
            if arguments["volume_linear"] != .null {
                parameters["volumeLinear"] = arguments["volume_linear"]
            } else {
                throw ToolFailure("provide either volume_db or volume_linear")
            }
        }
        return BridgeRequest("mixer.setVolume", parameters)
    case "mixer_set_solo":
        var parameters: [String: Value] = ["mode": arguments["mode"]]
        if arguments["index"].number >= 0 {
            parameters["index"] = arguments["index"]
        }
        if arguments["role"].truthy {
            parameters["role"] = arguments["role"]
        }
        if arguments["solo"] != .null {
            parameters["solo"] = arguments["solo"]
        }
        return BridgeRequest("mixer.setSolo", parameters)
    case "mixer_set_mute":
        var parameters: [String: Value] = ["mode": arguments["mode"]]
        if arguments["index"].number >= 0 {
            parameters["index"] = arguments["index"]
        }
        if arguments["role"].truthy {
            parameters["role"] = arguments["role"]
        }
        if arguments["muted"] != .null {
            parameters["muted"] = arguments["muted"]
        }
        return BridgeRequest("mixer.setMute", parameters)
    case "mixer_apply_bus_effect":
        var parameters: [String: Value] = ["dryRun": arguments["dry_run"], "allowObjectFallback": arguments["allow_object_fallback"]]
        if arguments["effect_id"].truthy {
            parameters["effectID"] = arguments["effect_id"]
        }
        if arguments["name"].truthy {
            parameters["name"] = arguments["name"]
        }
        if arguments["index"].number >= 0 {
            parameters["index"] = arguments["index"]
        }
        if arguments["role"].truthy {
            parameters["role"] = arguments["role"]
        }
        return BridgeRequest("mixer.applyBusEffect", parameters)
    case "mixer_open_bus_effect":
        var parameters: [String: Value] = ["allowObjectFallback": arguments["allow_object_fallback"]]
        if arguments["effect_index"].number >= 0 {
            parameters["effectIndex"] = arguments["effect_index"]
        }
        if arguments["effect_handle"].truthy {
            parameters["effectHandle"] = arguments["effect_handle"]
        }
        if arguments["effect_stack_handle"].truthy {
            parameters["effectStackHandle"] = arguments["effect_stack_handle"]
        }
        if arguments["index"].number >= 0 {
            parameters["index"] = arguments["index"]
        }
        if arguments["role"].truthy {
            parameters["role"] = arguments["role"]
        }
        return BridgeRequest("mixer.openBusEffect", parameters)
    case "mixer_set_bus_effect_enabled":
        var parameters: [String: Value] = ["enabled": arguments["enabled"], "allowObjectFallback": arguments["allow_object_fallback"]]
        if arguments["effect_index"].number >= 0 {
            parameters["effectIndex"] = arguments["effect_index"]
        }
        if arguments["effect_handle"].truthy {
            parameters["effectHandle"] = arguments["effect_handle"]
        }
        if arguments["effect_stack_handle"].truthy {
            parameters["effectStackHandle"] = arguments["effect_stack_handle"]
        }
        if arguments["index"].number >= 0 {
            parameters["index"] = arguments["index"]
        }
        if arguments["role"].truthy {
            parameters["role"] = arguments["role"]
        }
        return BridgeRequest("mixer.setBusEffectEnabled", parameters)
    case "mixer_remove_bus_effect":
        var parameters: [String: Value] = ["allowObjectFallback": arguments["allow_object_fallback"]]
        if arguments["effect_index"].number >= 0 {
            parameters["effectIndex"] = arguments["effect_index"]
        }
        if arguments["effect_handle"].truthy {
            parameters["effectHandle"] = arguments["effect_handle"]
        }
        if arguments["effect_stack_handle"].truthy {
            parameters["effectStackHandle"] = arguments["effect_stack_handle"]
        }
        if arguments["index"].number >= 0 {
            parameters["index"] = arguments["index"]
        }
        if arguments["role"].truthy {
            parameters["role"] = arguments["role"]
        }
        return BridgeRequest("mixer.removeBusEffect", parameters)
    case "mixer_volume_begin":
        return BridgeRequest("mixer.volumeBegin", ["effectStackHandle": arguments["effect_stack_handle"]])
    case "mixer_volume_end":
        return BridgeRequest("mixer.volumeEnd", ["effectStackHandle": arguments["effect_stack_handle"]])
    case "mixer_set_all_volumes":
        return BridgeRequest("mixer.setAllVolumes", ["volumes": arguments["volumes"]])
    case "share_project":
        var parameters: [String: Value] = [:]
        if arguments["destination"].truthy {
            parameters["destination"] = arguments["destination"]
        }
        return BridgeRequest("share.export", parameters)
    case "create_project":
        return BridgeRequest("project.create")
    case "create_event":
        return BridgeRequest("project.createEvent")
    case "create_library":
        return BridgeRequest("project.createLibrary")
    case "open_project":
        var parameters: [String: Value] = ["name": arguments["name"]]
        if arguments["event"].truthy {
            parameters["event"] = arguments["event"]
        }
        return BridgeRequest("project.open", parameters)
    case "dual_timeline_status":
        return BridgeRequest("dualTimeline.status")
    case "dual_timeline_open":
        let parameters = ["source": arguments["source"], "focus": arguments["focus"]]
        return BridgeRequest("dualTimeline.open", parameters)
    case "dual_timeline_sync_root":
        let parameters = ["source": arguments["source"], "focus": arguments["focus"]]
        return BridgeRequest("dualTimeline.syncRoot", parameters)
    case "dual_timeline_open_selected_in_secondary":
        let parameters = ["source": arguments["source"], "focus": arguments["focus"]]
        return BridgeRequest("dualTimeline.openSelectedInSecondary", parameters)
    case "dual_timeline_focus":
        return BridgeRequest("dualTimeline.focus", ["pane": arguments["pane"]])
    case "dual_timeline_close":
        return BridgeRequest("dualTimeline.close", ["focusPrimary": arguments["focus_primary"]])
    case "dual_timeline_toggle_panel":
        return BridgeRequest("dualTimeline.togglePanel", ["pane": arguments["pane"], "panel": arguments["panel"]])
    case "select_clip_in_lane":
        return BridgeRequest("timeline.selectClipInLane", ["lane": arguments["lane"]])
    case "capture_viewer":
        return BridgeRequest("viewer.capture", ["path": arguments["path"]])
    case "capture_timeline":
        return BridgeRequest("timeline.capture", ["path": arguments["path"]])
    case "capture_inspector":
        var parameters: [String: Value] = ["path": arguments["path"]]
        if arguments["class_name"].truthy {
            parameters["class_name"] = arguments["class_name"]
        }
        return BridgeRequest("inspector.capture", parameters)
    case "export_xml":
        return BridgeRequest("fcpxml.export", ["path": arguments["path"]])
    case "get_playhead_position":
        return BridgeRequest("playback.getPosition")
    case "detect_dialog":
        return BridgeRequest("dialog.detect")
    case "click_dialog_button":
        var parameters: [String: Value] = [:]
        if arguments["button"].truthy {
            parameters["button"] = arguments["button"]
        }
        if arguments["index"].number >= 0 {
            parameters["index"] = arguments["index"]
        }
        return BridgeRequest("dialog.click", parameters)
    case "fill_dialog_field":
        return BridgeRequest("dialog.fill", ["value": arguments["value"], "index": arguments["index"]])
    case "toggle_dialog_checkbox":
        var parameters: [String: Value] = ["checkbox": arguments["checkbox"]]
        if arguments["checked"] != .null {
            parameters["checked"] = arguments["checked"]
        }
        return BridgeRequest("dialog.checkbox", parameters)
    case "select_dialog_popup":
        return BridgeRequest("dialog.popup", ["select": arguments["select"], "popupIndex": arguments["popup_index"]])
    case "dismiss_dialog":
        return BridgeRequest("dialog.dismiss", ["action": arguments["action"]])
    case "get_viewer_zoom":
        return BridgeRequest("viewer.getZoom")
    case "set_viewer_zoom":
        return BridgeRequest("viewer.setZoom", ["zoom": arguments["zoom"]])
    case "get_bridge_options":
        return BridgeRequest("options.get")
    case "set_bridge_option":
        return BridgeRequest("options.set", ["option": arguments["option"], "enabled": arguments["enabled"]])
    case "set_bridge_option_value":
        return BridgeRequest("options.set", ["option": arguments["option"], "value": arguments["value"]])
    case "toggle_structure_blocks":
        return BridgeRequest("structure.toggle")
    case "remove_structure_blocks":
        return BridgeRequest("structure.remove")
    case "get_sections":
        return BridgeRequest("sections.get")
    case "hide_sections":
        return BridgeRequest("sections.hide")
    case "flexmusic_list_songs":
        return BridgeRequest("flexmusic.listSongs", ["filter": arguments["filter"]])
    case "flexmusic_get_song":
        return BridgeRequest("flexmusic.getSong", ["songUID": arguments["song_uid"]])
    case "flexmusic_get_timing":
        return BridgeRequest("flexmusic.getTiming", ["songUID": arguments["song_uid"], "durationSeconds": arguments["duration_seconds"]])
    case "flexmusic_render_to_file":
        return BridgeRequest("flexmusic.renderToFile", ["songUID": arguments["song_uid"], "durationSeconds": arguments["duration_seconds"], "outputPath": arguments["output_path"], "format": arguments["format"]])
    case "flexmusic_add_to_timeline":
        return BridgeRequest("flexmusic.addToTimeline", ["songUID": arguments["song_uid"], "durationSeconds": arguments["duration_seconds"]])
    case "montage_analyze_clips":
        return BridgeRequest("montage.analyzeClips", ["eventName": arguments["event_name"]])
    case "montage_plan_edit":
        let beats_arr: Value = try arguments["beats"].decodedJSON()
        let clips_arr: Value = try arguments["clips"].decodedJSON()
        return BridgeRequest("montage.planEdit", ["beats": beats_arr, "clips": clips_arr, "style": arguments["style"], "totalDuration": arguments["total_duration"]])
    case "montage_assemble":
        let plan: Value = try arguments["edit_plan"].decodedJSON()
        return BridgeRequest("montage.assemble", ["editPlan": plan, "projectName": arguments["project_name"], "songFile": arguments["song_file"]])
    case "montage_auto":
        return BridgeRequest("montage.auto", ["songUID": arguments["song_uid"], "eventName": arguments["event_name"], "style": arguments["style"], "projectName": arguments["project_name"]])
    case "debug_get_config":
        return BridgeRequest("debug.getConfig")
    case "debug_reset_config":
        return BridgeRequest("debug.resetConfig", ["scope": arguments["scope"]])
    case "debug_enable_preset":
        return BridgeRequest("debug.enablePreset", ["preset": arguments["preset"]])
    case "debug_start_framerate_monitor":
        return BridgeRequest("debug.startFramerateMonitor", ["interval": arguments["interval"]])
    case "debug_stop_framerate_monitor":
        return BridgeRequest("debug.stopFramerateMonitor")
    case "browser_list_clips":
        var parameters: [String: Value] = [:]
        if arguments["event"].truthy {
            parameters["event"] = arguments["event"]
        }
        return BridgeRequest("browser.listClips", parameters)
    case "browser_append_clip":
        var parameters: [String: Value] = [:]
        if arguments["handle"].truthy {
            parameters["handle"] = arguments["handle"]
        }
        if arguments["index"].number >= 0 {
            parameters["index"] = arguments["index"]
        }
        if arguments["name"].truthy {
            parameters["name"] = arguments["name"]
        }
        return BridgeRequest("browser.appendClip", parameters)
    case "paste_fcpxml":
        var parameters: [String: Value] = [:]
        if arguments["xml"].truthy {
            parameters["xml"] = arguments["xml"]
        }
        return BridgeRequest("fcpxml.pasteImport", parameters)
    case "stabilize_subject":
        return BridgeRequest("stabilize.subject")
    case "insert_title":
        var parameters: [String: Value] = [:]
        if arguments["name"].truthy {
            parameters["name"] = arguments["name"]
        }
        if arguments["effect_id"].truthy {
            parameters["effectID"] = arguments["effect_id"]
        }
        return BridgeRequest("titles.insert", parameters)
    case "set_transcript_engine":
        return BridgeRequest("transcript.setEngine", ["engine": arguments["engine"]])
    case "open_captions":
        var parameters: [String: Value] = [:]
        if arguments["file_url"].truthy {
            parameters["fileURL"] = arguments["file_url"]
        }
        if arguments["style"].truthy {
            parameters["style"] = arguments["style"]
        }
        return BridgeRequest("captions.open", parameters)
    case "close_captions":
        return BridgeRequest("captions.close")
    case "get_caption_state":
        return BridgeRequest("captions.getState")
    case "get_caption_styles":
        return BridgeRequest("captions.getStyles")
    case "set_caption_style":
        var parameters: [String: Value] = [:]
        if arguments["preset_id"].truthy {
            parameters["presetID"] = arguments["preset_id"]
        }
        if arguments["font"].truthy {
            parameters["font"] = arguments["font"]
        }
        if arguments["font_size"].number > 0 {
            parameters["fontSize"] = arguments["font_size"]
        }
        if arguments["text_color"].truthy {
            parameters["textColor"] = arguments["text_color"]
        }
        if arguments["highlight_color"].truthy {
            parameters["highlightColor"] = arguments["highlight_color"]
        }
        if arguments["outline_color"].truthy {
            parameters["outlineColor"] = arguments["outline_color"]
        }
        if arguments["outline_width"].number >= 0 {
            parameters["outlineWidth"] = arguments["outline_width"]
        }
        if arguments["position"].truthy {
            parameters["position"] = arguments["position"]
        }
        if arguments["animation"].truthy {
            parameters["animation"] = arguments["animation"]
        }
        parameters["wordByWordHighlight"] = arguments["word_highlight"]
        parameters["allCaps"] = arguments["all_caps"]
        return BridgeRequest("captions.setStyle", parameters)
    case "set_caption_grouping":
        return BridgeRequest("captions.setGrouping", ["mode": arguments["mode"], "maxWords": arguments["max_words"], "maxChars": arguments["max_chars"], "maxSeconds": arguments["max_seconds"]])
    case "generate_captions":
        var parameters: [String: Value] = [:]
        if arguments["style"].truthy {
            parameters["style"] = arguments["style"]
        }
        parameters["position"] = arguments["position"]
        parameters["animation"] = arguments["animation"]
        parameters["wordByWordHighlight"] = arguments["word_highlight"]
        parameters["maxWords"] = arguments["max_words"]
        parameters["allCaps"] = arguments["all_caps"]
        return BridgeRequest("captions.generate", parameters)
    case "export_captions_srt":
        return BridgeRequest("captions.exportSRT", ["path": arguments["path"]])
    case "export_captions_txt":
        return BridgeRequest("captions.exportTXT", ["path": arguments["path"]])
    case "set_caption_words":
        let word_list = try arguments["words"].decodedJSON()
        return BridgeRequest("captions.setWords", ["words": word_list])
    case "generate_native_captions":
        let parameters = ["grouping": arguments["grouping"], "language": arguments["language"],
                          "maxWords": arguments["max_words"], "maxSeconds": arguments["max_seconds"],
                          "format": arguments["format"]]
        return BridgeRequest("nativeCaptions.generate", parameters)
    case "verify_native_captions":
        return BridgeRequest("nativeCaptions.verify")
    case "lua_reset":
        return BridgeRequest("lua.reset")
    case "lua_state":
        return BridgeRequest("lua.getState")
    case "plugin_list":
        return BridgeRequest("plugin.list")
    case "plugin_list_methods":
        return BridgeRequest("plugin.listMethods")
    case "visionpro_status":
        return BridgeRequest("visionpro.status")
    case "visionpro_open_panel":
        return BridgeRequest("menu.execute", ["menuPath": .array([.string("Splices"), .string("Vision Pro Preview")])])
    case "visionpro_close_panel":
        return BridgeRequest("menu.execute", ["menuPath": .array([.string("Splices"), .string("Vision Pro Preview")])])
    case "visionpro_start":
        return BridgeRequest("visionpro.start", ["displayName": arguments["display_name"]])
    case "visionpro_stop":
        return BridgeRequest("visionpro.stop")
    case "visionpro_list_clients":
        return BridgeRequest("visionpro.listClients")
    case "visionpro_connect":
        var parameters: [String: Value] = [:]
        if arguments["host"].truthy {
            parameters["host"] = arguments["host"]
        }
        if arguments["ip"].truthy {
            parameters["ip"] = arguments["ip"]
        }
        if parameters.isEmpty {
            throw ToolFailure("provide host= or ip=")
        }
        return BridgeRequest("visionpro.addClient", parameters)
    case "visionpro_disconnect":
        var parameters: [String: Value] = [:]
        if arguments["host"].truthy {
            parameters["host"] = arguments["host"]
        }
        if arguments["ip"].truthy {
            parameters["ip"] = arguments["ip"]
        }
        if parameters.isEmpty {
            throw ToolFailure("provide host= or ip=")
        }
        return BridgeRequest("visionpro.removeClient", parameters)
    case "visionpro_load_aime":
        return BridgeRequest("visionpro.loadAime", ["path": arguments["path"]])
    case "visionpro_send_aime":
        let parameters = arguments["path"].truthy ? ["path": arguments["path"]] : [:]
        return BridgeRequest("visionpro.sendAime", parameters)
    case "visionpro_export_aime":
        return BridgeRequest("visionpro.exportAime", ["path": arguments["path"]])
    case "visionpro_set_camera":
        return BridgeRequest("visionpro.setCurrentCamera", ["cameraId": arguments["camera_id"]])
    case "visionpro_set_camera_calibration":
        var parameters: [String: Value] = ["cameraId": arguments["camera_id"]]
        if arguments["usdz_path"].truthy {
            parameters["usdzPath"] = arguments["usdz_path"]
        } else {
            if arguments["ilpd_path"].truthy {
                parameters["ilpdPath"] = arguments["ilpd_path"]
            } else {
                if arguments["json"].truthy {
                    parameters["json"] = arguments["json"]
                } else {
                    throw ToolFailure("provide one of usdz_path / ilpd_path / json")
                }
            }
        }
        return BridgeRequest("visionpro.setCameraCalibration", parameters)
    case "visionpro_remove_camera":
        return BridgeRequest("visionpro.removeCamera", ["cameraId": arguments["camera_id"]])
    case "visionpro_send_mask":
        return BridgeRequest("visionpro.sendMask", ["path": arguments["path"]])
    case "visionpro_set_max_clients":
        return BridgeRequest("visionpro.setMaxClients", ["max": arguments["max"]])
    default:
        return nil
    }
}
