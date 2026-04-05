// GUI for uentry.ks
runOncePath("0:/lib/locales/utils.ks").
runOncePath("0:/lib/utils.ks").
runOncePath("0:/lib/orbit.ks").
runOncePath("0:/lib/chrismath.ks").

declare global hudtextsize to 15.
declare global hudtextcolor to RGB(22/255, 255/255, 22/255).

declare global _entrygui_preset to "".

declare global AFS to addons:AFS.
function edl_MakeEDLGUI {
    // EDL Main GUI
    // Required global variables:
    // - AFS, entry_vf, entry_hf, entry_dist, entry_bank_i, entry_bank_f
    // - entry_heading_tol, AOAProfile, HProfile
    declare global gui_edlmain to GUI(500, 500).
    set gui_edlmain:style:hstretch to true.

    // Title
    declare global gui_edl_title_box to gui_edlmain:addhbox().
    set gui_edl_title_box:style:height to 40.
    set gui_edl_title_box:style:margin:top to 0.
    declare global gui_edl_title_label to gui_edl_title_box:addlabel("<b><size=20>" + UI_LANG["uentryGui.gui_main_title"] + "</size></b>").
    set gui_edl_title_label:style:align to "center".
    declare global gui_edl_title_exit_button to gui_edl_title_box:addbutton("X").
    set gui_edl_title_exit_button:style:width to 20.
    set gui_edl_title_exit_button:style:align to "right".
    set gui_edl_title_exit_button:onclick to {
        set done to true.
        gui_edlmain:hide().
    }.

    declare global gui_edlmainbox to gui_edlmain:addscrollbox().

    gui_edlmainbox:addspacing(10).

    declare global gui_edl_activate_button to gui_edlmainbox:addcheckbox("<b><size=16>" + UI_LANG["uentryGui.gui_activate"] + "</size></b>").
    set gui_edl_activate_button:ontoggle to {
        parameter newstate.
        set guidance_active to newstate.
    }.
    declare global gui_edl_emergency_button to gui_edlmainbox:addcheckbox("<b><size=16>" + UI_LANG["uentryGui.gui_emergency"] + "</size></b>", false).
    set gui_edl_emergency_button:ontoggle to {
        parameter newstate.
        set config:suppressautopilot to newstate.
    }.
    declare global gui_edl_kcl_button to gui_edlmainbox:addbutton(UI_LANG["uentryGui.gui_open_kcl"]).
    set gui_edl_kcl_button:onclick to {
        fc_MakeKCLGUI().
    }.
    declare global gui_edl_list_presets to {
        local _presetPath to path("0:/entry_presets").
        if (not exists(_presetPath)) {return list().}
        local _presetDir to open(_presetPath).
        if (_presetDir:isfile) {return list().}
        local _presetFiles to list().
        for _file in _presetDir:lexicon:values {
            if (_file:isfile and _file:extension = "json") {
                _presetFiles:add(_file:name:substring(0, _file:name:length - 5)).
            }
        }
        return _presetFiles.
    }.
    declare global gui_edl_save_preset to {
        parameter presetName.
        local _presetPath to path("0:/entry_presets").
        if (not exists(_presetPath)) createDir(_presetPath).
        local _path to path("0:/entry_presets/" + presetName + ".json").
        if (exists(_path)) deletePath(_path).
        local _presetBody to lexicon(
            "vessel", lexicon(
                "mass", AFS:mass,
                "area", AFS:area
            ),
            "kclcontroller", kclcontroller,
            "aeroprofile", lexicon(
                "CtrlSpeedSamples", AFS:CtrlSpeedSamples,
                "CtrlAOASamples", AFS:CtrlAOASamples,
                "AeroSpeedSamples", AFS:AeroSpeedSamples,
                "AeroLogDensitySamples", AFS:AeroLogDensitySamples,
                "AeroCdSamples", AFS:AeroCdSamples,
                "AeroClSamples", AFS:AeroClSamples,
                // "rotation", AFS:rotation,  // disabled because their is a bug in serialization of Direction object
                "rotation_fore", AFS:rotation:forevector,
                "rotation_up", AFS:rotation:upvector,
                "AOAReversal", AFS:AOAReversal
            ),
            "target", lexicon(
                "vf", entry_vf,
                "hf", entry_hf
            ),
            "guidance", lexicon(
                "tracking_gain", entry_tracking_gain,
                "bank_i", entry_bank_i,
                "bank_f", entry_bank_f,
                "bank_max", AFS:bank_max,
                "heading_tol", AFS:heading_tol,
                "Qdot_max", AFS:Qdot_max,
                "acc_max", AFS:acc_max,
                "dynp_max", AFS:dynp_max,
                "L_min", AFS:L_min,
                "k_QEGC", AFS:k_QEGC,
                "k_C", AFS:k_C,
                "t_lag", AFS:t_lag
            )
        ).
        writeJSON(_presetBody, _path).
    }.
    declare global gui_edl_load_preset to {
        parameter presetName.
        local _path to path("0:/entry_presets/" + presetName + ".json").
        if (not exists(_path)) {
            hudtext(UI_LANG["uentryGui.err_preset_not_found"], 4, 2, 12, hudtextcolor, false).
            return.
        }
        set _entrygui_preset to presetName.
        AFS:InitAtmModel().
        local _presetBody to readJSON(_path).
        local _vesselInfo to _presetBody["vessel"].
        set AFS:mass to _vesselInfo["mass"].
        set AFS:area to _vesselInfo["area"].
        set kclcontroller to _presetBody["kclcontroller"].
        local _aeroProfile to _presetBody["aeroprofile"].
        set AFS:CtrlSpeedSamples to _aeroProfile["CtrlSpeedSamples"].
        set AFS:CtrlAOASamples to _aeroProfile["CtrlAOASamples"].
        set AFS:AeroSpeedSamples to _aeroProfile["AeroSpeedSamples"].
        set AFS:AeroLogDensitySamples to _aeroProfile["AeroLogDensitySamples"].
        set AFS:AeroCdSamples to _aeroProfile["AeroCdSamples"].
        set AFS:AeroClSamples to _aeroProfile["AeroClSamples"].
        // set AFS:rotation to _aeroProfile["rotation"].  // disabled because their is a bug in serialization of Direction object
        set AFS:rotation to lookDirUp(_aeroProfile["rotation_fore"], _aeroProfile["rotation_up"]).
        set AFS:AOAReversal to _aeroProfile["AOAReversal"].
        local _target to _presetBody["target"].
        set entry_vf to _target["vf"].
        set entry_hf to _target["hf"].
        set AFS:target_energy to entry_get_spercific_energy(body:radius+entry_hf, entry_vf).
        local _guidance to _presetBody["guidance"].
        if (_guidance:haskey("tracking_gain")) {set entry_tracking_gain to _guidance["tracking_gain"].}
        set entry_bank_i to _guidance["bank_i"].
        set entry_bank_f to _guidance["bank_f"].
        set AFS:bank_max to _guidance["bank_max"].
        set AFS:heading_tol to _guidance["heading_tol"].
        set AFS:Qdot_max to _guidance["Qdot_max"].
        set AFS:acc_max to _guidance["acc_max"].
        set AFS:dynp_max to _guidance["dynp_max"].
        set AFS:L_min to _guidance["L_min"].
        set AFS:k_QEGC to _guidance["k_QEGC"].
        set AFS:k_C to _guidance["k_C"].
        set AFS:t_lag to _guidance["t_lag"].
        // Refresh GUI
        edl_MakeEDLGUI().
    }.
    declare global gui_edl_load_box to gui_edlmainbox:addhbox().
    declare global gui_edl_load_label to gui_edl_load_box:addlabel(UI_LANG["uentryGui.lbl_load_preset"]).
    declare global gui_edl_load_options to gui_edl_load_box:addpopupmenu().
    set gui_edl_load_options:maxvisible to 15.
    set gui_edl_load_options:onclick to {
        set gui_edl_load_options:options to gui_edl_list_presets().
    }.
    declare global gui_edl_load_button to gui_edl_load_box:addbutton(UI_LANG["uentryGui.btn_load"]).
    set gui_edl_load_button:onclick to {
        local _selectedPreset to gui_edl_load_options:value.
        gui_edl_load_preset(_selectedPreset).
    }.
    declare global gui_edl_save_box to gui_edlmainbox:addhbox().
    declare global gui_edl_save_label to gui_edl_save_box:addlabel(UI_LANG["uentryGui.lbl_save_preset"]).
    declare global gui_edl_save_input to gui_edl_save_box:addtextfield("").
    declare global gui_edl_save_button to gui_edl_save_box:addbutton(UI_LANG["uentryGui.btn_save"]).
    if (_entrygui_preset <> "") {
        set gui_edl_load_options:options to gui_edl_list_presets().
        // set gui_edl_load_options:value to _entrygui_preset.  // disabled because of a bug in popupmenu: "value" is a structure type, but preset name is a string
        set gui_edl_save_input:text to _entrygui_preset.  // workaround: show the preset name in the save input field
    }
    set gui_edl_save_button:onclick to {
        local _presetName to gui_edl_save_input:text.
        if (_presetName = "") {
            hudtext(UI_LANG["uentryGui.msg_enter_name"], 4, 2, 12, hudtextcolor, false).
            return.
        }
        gui_edl_save_preset(_presetName).
        hudtext(UI_LANG["uentryGui.msg_preset_saved"] + _presetName, 4, 2, 12, hudtextcolor, false).
    }.
    

    gui_edlmainbox:addspacing(10).

    // State Display
    declare global gui_edl_state_label to gui_edlmainbox:addlabel("<b>" + UI_LANG["uentryGui.lbl_guidance_state"] + "</b>").
    declare global gui_edl_state_box to gui_edlmainbox:addhbox().
    declare global gui_edl_state_box1 to gui_edl_state_box:addvlayout().
    declare global gui_edl_state_box2 to gui_edl_state_box:addvlayout().
    declare global gui_edl_state_status to gui_edl_state_box1:addlabel(UI_LANG["uentryGui.lbl_status"] + guidance_stage).
    on guidance_stage {
        set gui_edl_state_status:text to UI_LANG["uentryGui.lbl_status"] + guidance_stage.
        return not done.
    }
    declare global gui_edl_state_alt to gui_edl_state_box1:addlabel(UI_LANG["uentryMain.lbl_alt"] + "0 km").
    declare global gui_edl_state_speed to gui_edl_state_box1:addlabel(UI_LANG["uentryMain.lbl_speed"] + "0 m/s").
    declare global gui_edl_state_banki to gui_edl_state_box1:addlabel(UI_LANG["uentryMain.lbl_bank_i"] + round(entry_bank_i,1):tostring + " °").
    declare global gui_edl_state_aoa to gui_edl_state_box1:addlabel(UI_LANG["uentryMain.lbl_aoa"] + "0").
    declare global gui_edl_state_bank to gui_edl_state_box1:addlabel(UI_LANG["uentryMain.lbl_bank"] + "0").
    declare global gui_edl_state_pathangle to gui_edl_state_box1:addlabel(UI_LANG["uentryMain.lbl_path_angle"] + "0").
    declare global gui_edl_state_T to gui_edl_state_box2:addlabel(UI_LANG["uentryMain.lbl_time_t"] + "0 s").
    declare global gui_edl_state_EToGo to gui_edl_state_box2:addlabel(UI_LANG["uentryMain.lbl_energy_togo"] + "0 kJ").
    declare global gui_edl_state_rangetogo to gui_edl_state_box2:addlabel(UI_LANG["uentryMain.lbl_range_togo"] + "0 km").
    declare global gui_edl_state_rangeerr to gui_edl_state_box2:addlabel(UI_LANG["uentryMain.lbl_range_err"] + "0 km").
    declare global gui_edl_state_vf to gui_edl_state_box2:addlabel(UI_LANG["uentryMain.lbl_vf"] + "0 m/s").
    declare global gui_edl_state_hf to gui_edl_state_box2:addlabel(UI_LANG["uentryMain.lbl_hf"] + "0 km").

    declare global gui_edl_state_box34 to gui_edlmainbox:addhbox().
    declare global gui_edl_state_box3 to gui_edl_state_box34:addvlayout().
    declare global gui_edl_state_box4 to gui_edl_state_box34:addvlayout().
    declare global gui_edl_state_qdot to gui_edl_state_box3:addlabel(UI_LANG["uentryMain.lbl_heatflux"] + "0 kW").
    declare global gui_edl_state_maxqdot to gui_edl_state_box4:addlabel(UI_LANG["uentryMain.lbl_m_heatflux"] + "0 kW @ 0s").
    declare global gui_edl_state_load to gui_edl_state_box3:addlabel(UI_LANG["uentryMain.lbl_load"] + "0 g").
    declare global gui_edl_state_maxload to gui_edl_state_box4:addlabel(UI_LANG["uentryMain.lbl_m_load"] + "0 g @ 0s").
    declare global gui_edl_state_dynp to gui_edl_state_box3:addlabel(UI_LANG["uentryMain.lbl_dynp"] + "0 kPa").
    declare global gui_edl_state_maxdynp to gui_edl_state_box4:addlabel(UI_LANG["uentryMain.lbl_m_dynp"] + "0 kPa @ 0s").

    declare global gui_edl_state_msg to gui_edlmainbox:addlabel("").

    // Target Parameters
    gui_edlmainbox:addlabel("<b>" + UI_LANG["uentryGui.lbl_target_header"] + "</b>").
    declare global entry_edl_target_mainbox to gui_edlmainbox:addvbox().
    declare global gui_edl_target_button to entry_edl_target_mainbox:addbutton(UI_LANG["uentryGui.btn_update_target"]).
    set gui_edl_target_button:onclick to {
        local target_geo to get_target_geo().
        if (target_geo = 0) {
            hudtext(UI_LANG["uentryGui.err_no_waypoint"], 4, 2, 12, hudtextcolor, false).
            return.
        }
        local entry_vf to gui_edl_entry_vf_input:text:tonumber.
        local entry_hf to gui_edl_entry_hf_input:text:tonumber * 1e3.  // convert to m
        local entry_dist to gui_edl_entry_dist_input:text:tonumber * 1e3.  // convert to m
        local entry_headingf to gui_edl_entry_headingf_input:text:tonumber.
        entry_set_target(entry_hf, entry_vf, entry_dist, entry_headingf, target_geo).
    }.

    declare global gui_edl_target_box1 to entry_edl_target_mainbox:addhbox().  // line 1
    declare global gui_edl_target_box2 to entry_edl_target_mainbox:addhbox().  // line 2

    declare global gui_edl_entry_hf_label to gui_edl_target_box1:addlabel(UI_LANG["uentryGui.lbl_in_height"]).
    set gui_edl_entry_hf_label:style:width to 150.
    declare global gui_edl_entry_hf_input to gui_edl_target_box1:addtextfield(round(entry_hf*1e-3, 1):tostring).
    
    declare global gui_edl_entry_vf_label to gui_edl_target_box1:addlabel(UI_LANG["uentryGui.lbl_in_speed"]).
    set gui_edl_entry_vf_label:style:width to 150.
    declare global gui_edl_entry_vf_input to gui_edl_target_box1:addtextfield(round(entry_vf, 1):tostring).

    local active_geo to get_target_geo().
    if (active_geo = 0) {
        hudtext(UI_LANG["uentryGui.hud_no_waypoint"], 4, 2, 12, hudtextcolor, false).
        set active_geo to body:geopositionlatlng(0, 0).
    }
    local entry_dist to (active_geo:position - entry_target_geo:position):mag.
    declare global gui_edl_entry_dist_label to gui_edl_target_box2:addlabel(UI_LANG["uentryGui.lbl_in_dist"]).
    set gui_edl_entry_dist_label:style:width to 150.
    declare global gui_edl_entry_dist_input to gui_edl_target_box2:addtextfield(round(entry_dist*1e-3, 1):tostring).

    local entry_headingf to mheadingangle(active_geo:lat, active_geo:lng, entry_target_geo:lat, entry_target_geo:lng).
    declare global gui_edl_entry_headingf_label to gui_edl_target_box2:addlabel(UI_LANG["uentryGui.lbl_in_heading"]).
    set gui_edl_entry_headingf_label:style:width to 150.
    declare global gui_edl_entry_headingf_input to gui_edl_target_box2:addtextfield(round(entry_headingf, 1):tostring).

    declare global gui_edl_aero_button to gui_edlmainbox:addbutton(UI_LANG["uentryGui.btn_open_aero"]).
    set gui_edl_aero_button:onclick to {
        edl_MakeAeroGUI().
    }.

    // Guidance Parameters
    gui_edlmainbox:addlabel("<b>" + UI_LANG["uentryGui.lbl_guidance_header"] + "</b>").
    declare global gui_edl_trackgain_box to gui_edlmainbox:addhbox().
    declare global gui_edl_trackgain_label to gui_edl_trackgain_box:addlabel(UI_LANG["uentryGui.lbl_track_gain"]).
    set gui_edl_trackgain_label:style:width to 150.
    declare global gui_edl_trackgain_input to gui_edl_trackgain_box:addtextfield(round(entry_tracking_gain, 2):tostring).
    declare global gui_edl_trackgain_set to gui_edl_trackgain_box:addbutton(UI_LANG["uentryGui.btn_set"]).
    set gui_edl_trackgain_set:style:width to 50.
    set gui_edl_trackgain_set:onclick to {set entry_tracking_gain to gui_edl_trackgain_input:text:tonumber.}.
    declare global gui_edl_entry_bank_i_box to gui_edlmainbox:addhbox().
    declare global gui_edl_entry_bank_i_label to gui_edl_entry_bank_i_box:addlabel(UI_LANG["uentryGui.lbl_bank_i_param"]).
    set gui_edl_entry_bank_i_label:style:width to 150.
    declare global gui_edl_entry_bank_i_input to gui_edl_entry_bank_i_box:addtextfield(entry_bank_i:tostring).
    declare global gui_edl_entry_bank_i_set to gui_edl_entry_bank_i_box:addbutton(UI_LANG["uentryGui.btn_set"]).
    set gui_edl_entry_bank_i_set:style:width to 50.
    set gui_edl_entry_bank_i_set:onclick to {set entry_bank_i to gui_edl_entry_bank_i_input:text:tonumber.}.

    declare global gui_edl_entry_bank_f_box to gui_edlmainbox:addhbox().
    declare global gui_edl_entry_bank_f_label to gui_edl_entry_bank_f_box:addlabel(UI_LANG["uentryGui.lbl_bank_f_param"]).
    set gui_edl_entry_bank_f_label:style:width to 150.
    declare global gui_edl_entry_bank_f_input to gui_edl_entry_bank_f_box:addtextfield(entry_bank_f:tostring).
    declare global gui_edl_entry_bank_f_set to gui_edl_entry_bank_f_box:addbutton(UI_LANG["uentryGui.btn_set"]).
    set gui_edl_entry_bank_f_set:style:width to 50.
    set gui_edl_entry_bank_f_set:onclick to {set entry_bank_f to gui_edl_entry_bank_f_input:text:tonumber.}.

    declare global gui_edl_bank_max_box to gui_edlmainbox:addhbox().
    declare global gui_edl_bank_max_label to gui_edl_bank_max_box:addlabel(UI_LANG["uentryGui.lbl_bank_max"]).
    set gui_edl_bank_max_label:style:width to 150.
    declare global gui_edl_bank_max_input to gui_edl_bank_max_box:addtextfield(AFS:bank_max:tostring).
    declare global gui_edl_bank_max_set to gui_edl_bank_max_box:addbutton(UI_LANG["uentryGui.btn_set"]).
    set gui_edl_bank_max_set:style:width to 50.
    set gui_edl_bank_max_set:onclick to {set AFS:bank_max to gui_edl_bank_max_input:text:tonumber.}.

    declare global gui_edl_heading_tol_box to gui_edlmainbox:addhbox().
    declare global gui_edl_heading_tol_label to gui_edl_heading_tol_box:addlabel(UI_LANG["uentryGui.lbl_head_tol"]).
    set gui_edl_heading_tol_label:style:width to 150.
    declare global gui_edl_heading_tol_input to gui_edl_heading_tol_box:addtextfield(AFS:heading_tol:tostring).
    declare global gui_edl_heading_tol_set to gui_edl_heading_tol_box:addbutton(UI_LANG["uentryGui.btn_set"]).
    set gui_edl_heading_tol_set:style:width to 50.
    set gui_edl_heading_tol_set:onclick to {set AFS:heading_tol to gui_edl_heading_tol_input:text:tonumber.}.
    declare global gui_edl_heading_tol_forceReversal to gui_edl_heading_tol_box:addbutton(UI_LANG["uentryGui.btn_force_reversal"]).
    set gui_edl_heading_tol_forceReversal:style:width to 140.
    set gui_edl_heading_tol_forceReversal:onclick to {
        set AFS:bank_reversal to (not AFS:bank_reversal).
    }.
    
    declare global gui_edl_qdot_max_box to gui_edlmainbox:addhbox().
    declare global gui_edl_qdot_max_label to gui_edl_qdot_max_box:addlabel(UI_LANG["uentryGui.lbl_max_qdot_limit"]).
    set gui_edl_qdot_max_label:style:width to 150.
    declare global gui_edl_qdot_max_input to gui_edl_qdot_max_box:addtextfield(round(AFS:Qdot_max*1e-3):tostring).
    declare global gui_edl_qdot_max_set to gui_edl_qdot_max_box:addbutton(UI_LANG["uentryGui.btn_set"]).
    set gui_edl_qdot_max_set:style:width to 50.
    set gui_edl_qdot_max_set:onclick to {set AFS:Qdot_max to gui_edl_qdot_max_input:text:tonumber * 1e3.}.

    declare global gui_edl_acc_max_box to gui_edlmainbox:addhbox().
    declare global gui_edl_acc_max_label to gui_edl_acc_max_box:addlabel(UI_LANG["uentryGui.lbl_max_acc_limit"]).
    set gui_edl_acc_max_label:style:width to 150.
    declare global gui_edl_acc_max_input to gui_edl_acc_max_box:addtextfield(round(AFS:acc_max/9.81, 1):tostring).
    declare global gui_edl_acc_max_set to gui_edl_acc_max_box:addbutton(UI_LANG["uentryGui.btn_set"]).
    set gui_edl_acc_max_set:style:width to 50.
    set gui_edl_acc_max_set:onclick to {set AFS:acc_max to gui_edl_acc_max_input:text:tonumber * 9.81.}.

    declare global gui_edl_dynp_max_box to gui_edlmainbox:addhbox().
    declare global gui_edl_dynp_max_label to gui_edl_dynp_max_box:addlabel(UI_LANG["uentryGui.lbl_max_dynp_limit"]).
    set gui_edl_dynp_max_label:style:width to 150.
    declare global gui_edl_dynp_max_input to gui_edl_dynp_max_box:addtextfield(round(AFS:dynp_max*1e-3):tostring).
    declare global gui_edl_dynp_max_set to gui_edl_dynp_max_box:addbutton(UI_LANG["uentryGui.btn_set"]).
    set gui_edl_dynp_max_set:style:width to 50.
    set gui_edl_dynp_max_set:onclick to {set AFS:dynp_max to gui_edl_dynp_max_input:text:tonumber * 1e3.}.

    declare global gui_edl_l_min_box to gui_edlmainbox:addhbox().
    declare global gui_edl_l_min_label to gui_edl_l_min_box:addlabel(UI_LANG["uentryGui.lbl_min_lift_limit"]).
    set gui_edl_l_min_label:style:width to 150.
    declare global gui_edl_l_min_input to gui_edl_l_min_box:addtextfield(AFS:L_min:tostring).
    declare global gui_edl_l_min_set to gui_edl_l_min_box:addbutton(UI_LANG["uentryGui.btn_set"]).
    set gui_edl_l_min_set:style:width to 50.
    set gui_edl_l_min_set:onclick to {set AFS:L_min to gui_edl_l_min_input:text:tonumber.}.
    
    declare global gui_edl_k_qegc_box to gui_edlmainbox:addhbox().
    declare global gui_edl_k_qegc_label to gui_edl_k_qegc_box:addlabel(UI_LANG["uentryGui.lbl_qegc_gain"]).
    set gui_edl_k_qegc_label:style:width to 150.
    declare global gui_edl_k_qegc_input to gui_edl_k_qegc_box:addtextfield(AFS:k_QEGC:tostring).
    declare global gui_edl_k_qegc_set to gui_edl_k_qegc_box:addbutton(UI_LANG["uentryGui.btn_set"]).
    set gui_edl_k_qegc_set:style:width to 50.
    set gui_edl_k_qegc_set:onclick to {set AFS:k_QEGC to gui_edl_k_qegc_input:text:tonumber.}.

    declare global gui_edl_k_c_box to gui_edlmainbox:addhbox().
    declare global gui_edl_k_c_label to gui_edl_k_c_box:addlabel(UI_LANG["uentryGui.lbl_constraint_gain"]).
    set gui_edl_k_c_label:style:width to 150.
    declare global gui_edl_k_c_input to gui_edl_k_c_box:addtextfield(AFS:k_C:tostring).
    declare global gui_edl_k_c_set to gui_edl_k_c_box:addbutton(UI_LANG["uentryGui.btn_set"]).
    set gui_edl_k_c_set:style:width to 50.
    set gui_edl_k_c_set:onclick to {set AFS:k_C to gui_edl_k_c_input:text:tonumber.}.

    declare global gui_edl_t_lag_box to gui_edlmainbox:addhbox().
    declare global gui_edl_t_lag_label to gui_edl_t_lag_box:addlabel(UI_LANG["uentryGui.lbl_lag_t"]).
    set gui_edl_t_lag_label:style:width to 150.
    declare global gui_edl_t_lag_input to gui_edl_t_lag_box:addtextfield(AFS:t_lag:tostring).
    declare global gui_edl_t_lag_set to gui_edl_t_lag_box:addbutton(UI_LANG["uentryGui.btn_set"]).
    set gui_edl_t_lag_set:style:width to 50.
    set gui_edl_t_lag_set:onclick to {set AFS:t_lag to gui_edl_t_lag_input:text:tonumber.}.

    declare global gui_edl_planner_box to gui_edlmainbox:addvbox().
    declare global gui_edl_planner_msg to gui_edl_planner_box:addlabel("").
    declare global gui_edl_planner_box1 to gui_edl_planner_box:addhlayout().
    declare global gui_edl_planner_show_button to gui_edl_planner_box1:addcheckbox(UI_LANG["uentryGui.gui_show_prediction"], false).
    set gui_edl_planner_show_button:ontoggle to {
        parameter newstate.
        if (not newstate) {
            if (defined gui_draw_vecRpred_final) set gui_draw_vecRpred_final:show to false.
            if (defined gui_draw_vecTgt) set gui_draw_vecTgt:show to false.
            return.
        }
        if (not (defined gui_vecRpred_final)) {
            declare global gui_vecRpred_final to V(body:radius*1.5, 0, 0).
        }
        declare global gui_draw_vecRpred_final to vecDraw(
            {return body:position.},
            {return gui_vecRpred_final.},
            RGB(0, 255, 0), UI_LANG["uentryGui.vec_final"], 1.0, true
        ).
        declare global gui_draw_vecTgt to vecDraw(
            {return body:position.},
            {return (entry_target_geo:position-body:position):normalized*body:radius*1.5.},
            RGB(255, 0, 0), UI_LANG["uentryGui.vec_target"], 1.0, true
        ).
    }.
    declare global gui_edl_planner_update_button to gui_edl_planner_box1:addbutton(UI_LANG["uentryGui.btn_update_pred"]).
    set gui_edl_planner_update_button:onclick to {
        AFS:InitAtmModel().
        // Propagate to entry
        local tt to 0.
        local vecR to v(0,0,0).
        local vecV to v(0,0,0).
        if (hasNode) {
            set tt to nextNode:time - time:seconds.
            set vecR to positionAt(ship, nextNode:time + 10) - body:position.
            set vecV to velocityAt(ship, nextNode:time + 10):orbit.
        }
        else {
            set tt to 0.
            set vecR to ship:position - body:position.
            set vecV to ship:velocity:orbit.
        }
        local entryInfo to entry_propagate_to_entry(tt, vecR, vecV).
        if (not entryInfo["ok"]) {
            set gui_edl_planner_msg:text to UI_LANG["uentryGui.err_prop_fail"] + "(" + entryInfo["status"] + ") " + entryInfo["msg"].
            return.
        }
        set tt to entryInfo["time_entry"].
        set vecR to entryInfo["vecR"].
        set vecV to entryInfo["vecV"].
        local vecVsrf to vecV - vCrs(body:angularvel, vecR).  // to body-fixed frame
        local gst to lexicon(
            "bank_i", entry_bank_i, "bank_f", entry_bank_f,
            "energy_i", entry_get_spercific_energy(vecR:mag, vecVsrf:mag),
            "energy_f", entry_get_spercific_energy(entry_hf + body:radius, entry_vf)
        ).
        local finalInfo to entry_predictor(tt, vecR, vecV, gst, true).
        if (not finalInfo["ok"]) {
            set gui_edl_planner_msg:text to UI_LANG["uentryGui.err_pred_fail"] + "(" + finalInfo["status"] + ") " + finalInfo["msg"].
            return.
        }
        set gui_vecRpred_final to finalInfo["vecR_final"]:normalized * body:radius * 1.5.
        local gammae to 90 - vAng(vecR, vecV).
        local thetaf to entry_angle_to_target(vecR, vecV, finalInfo["vecR_final"]).
        set gui_edl_planner_msg:text to 
            UI_LANG["uentryGui.lbl_entry_interface"] + "V = " + round(vecVsrf:mag) 
            + " m/s, " + UI_LANG["uentryGui.lbl_path_angle"] + " = " + round(gammae, 2)
            + "°, " + UI_LANG["uentryGui.lbl_pred_time"] + " = " + round(tt + finalInfo["time_final"]) + " s"
            + ", " + UI_LANG["uentryGui.lbl_thetaf"] + " =  " + round(thetaf, 1)
            + ", " + UI_LANG["uentryGui.lbl_pred_range"] + " = " + round(thetaf/180*constant:pi*body:radius*1e-3) + " km"
            + ", " + UI_LANG["uentryGui.lbl_pred_vf"] + " = " + round(finalInfo["vecV_final"]:mag) + " m/s"
            + ", " + UI_LANG["uentryGui.lbl_pred_hf"] + " = " + round((finalInfo["vecR_final"]:mag - body:radius)*1e-3, 1) + " km"
            + ", " + UI_LANG["uentryGui.lbl_max_qdot"] + " = " + round(finalInfo["maxQdot"]*1e-3) + " kW"
            + ", " + UI_LANG["uentryGui.lbl_max_load"] + " = " + round(finalInfo["maxAcc"]/9.81, 2) + " g"
            + ", " + UI_LANG["uentryGui.lbl_max_dynp"] + " = " + round(finalInfo["maxDynP"]*1e-3) + " kPa".
    }.

    gui_edlmain:show().
    return gui_edlmain.
}

function edl_MakeAeroGUI {
    declare global gui_aeromain to GUI(400, 400).
    set gui_aeromain:style:hstretch to true.

    // Title
    declare global gui_aero_title_box to gui_aeromain:addhbox().
    set gui_aero_title_box:style:height to 40.
    set gui_aero_title_box:style:margin:top to 0.
    declare global gui_aero_title_label to gui_aero_title_box:addlabel("<b><size=20>" + UI_LANG["uentryGui.gui_aero_title"] + "</size></b>").
    set gui_aero_title_label:style:align TO "center".
    declare global gui_aero_title_exit_button to gui_aero_title_box:addbutton("X").
    set gui_aero_title_exit_button:style:width to 20.
    set gui_aero_title_exit_button:style:align to "right".
    set gui_aero_title_exit_button:onclick to {
        gui_aeromain:hide().
    }.
    declare global gui_aero_msg_label to gui_aeromain:addlabel("").

    gui_aeromain:addspacing(10).
    declare global gui_aero_attitude_label to gui_aeromain:addlabel("<b>" + UI_LANG["uentryGui.lbl_attitude_offset"] + "</b>").
    declare global gui_attitude_offset_box to gui_aeromain:addhbox().
    declare global gui_attitude_offset_box1 to gui_attitude_offset_box:addvlayout().
    declare global gui_attitude_offset_box2 to gui_attitude_offset_box:addvlayout().
    declare global gui_attitude_offset_set_button to gui_attitude_offset_box1:addbutton(UI_LANG["uentryGui.btn_set_attitude"]).
    set gui_attitude_offset_set_button:onclick to {
        local pitch to gui_attitude_offset_pitch_input:text:tonumber.
        local yaw to gui_attitude_offset_yaw_input:text:tonumber.
        local roll to gui_attitude_offset_roll_input:text:tonumber.
        set AFS:rotation to R(pitch, yaw, roll).
    }.
    declare global gui_attitude_offset_show_button to gui_attitude_offset_box1:addcheckbox(UI_LANG["uentryGui.gui_show_attitude"], false).
    set gui_attitude_offset_show_button:ontoggle to {
        parameter newstate.
        if (not newstate) {
            if (defined gui_draw_attitude_offset_x) set gui_draw_attitude_offset_x:show to false.
            if (defined gui_draw_attitude_offset_y) set gui_draw_attitude_offset_y:show to false.
            if (defined gui_draw_attitude_offset_z) set gui_draw_attitude_offset_z:show to false.
            return.
        }
        set gui_draw_attitude_offset_x to vecDraw(
            V(0,0,0),
            {return (ship:facing*AFS:rotation):starvector * gui_attitude_offset_show_input1:text:tonumber.},
            RGB(255, 0, 0), UI_LANG["uentryGui.vec_right"], 1.0, true
        ).
        set gui_draw_attitude_offset_x:show to true.
        set gui_draw_attitude_offset_y to vecDraw(
            V(0,0,0),
            {return (ship:facing*AFS:rotation):upvector * gui_attitude_offset_show_input1:text:tonumber.},
            RGB(0, 255, 0), UI_LANG["uentryGui.vec_up"], 1.0, true
        ).
        set gui_draw_attitude_offset_y:show to true.
        set gui_draw_attitude_offset_z to vecDraw(
            V(0,0,0),
            {return (ship:facing*AFS:rotation):forevector * gui_attitude_offset_show_input1:text:tonumber.},
            RGB(0, 0, 255), UI_LANG["uentryGui.vec_forward"], 1.0, true
        ).
        set gui_draw_attitude_offset_z:show to true.
    }.
    declare global gui_attitude_offset_show_box1 to gui_attitude_offset_box1:addhbox().
    declare global gui_attitude_offset_show_label1 to gui_attitude_offset_show_box1:addlabel(UI_LANG["uentryGui.lbl_scale"]).
    set gui_attitude_offset_show_label1:style:width to 80.
    declare global gui_attitude_offset_show_input1 to gui_attitude_offset_show_box1:addtextfield("50").
    declare global gui_attitude_offset_pitch_box to gui_attitude_offset_box2:addhbox().
    declare global gui_attitude_offset_pitch_label to gui_attitude_offset_pitch_box:addlabel(UI_LANG["uentryGui.lbl_pitch"]).
    set gui_attitude_offset_pitch_label:style:width to 80.
    declare global gui_attitude_offset_pitch_input to gui_attitude_offset_pitch_box:addtextfield(round(AFS:rotation:pitch):tostring).
    declare global gui_attitude_offset_yaw_box to gui_attitude_offset_box2:addhbox().
    declare global gui_attitude_offset_yaw_label to gui_attitude_offset_yaw_box:addlabel(UI_LANG["uentryGui.lbl_yaw"]).
    set gui_attitude_offset_yaw_label:style:width to 80.
    declare global gui_attitude_offset_yaw_input to gui_attitude_offset_yaw_box:addtextfield(round(AFS:rotation:yaw):tostring).
    declare global gui_attitude_offset_roll_box to gui_attitude_offset_box2:addhbox().
    declare global gui_attitude_offset_roll_label to gui_attitude_offset_roll_box:addlabel(UI_LANG["uentryGui.lbl_roll"]).
    set gui_attitude_offset_roll_label:style:width to 80.
    declare global gui_attitude_offset_roll_input to gui_attitude_offset_roll_box:addtextfield(round(AFS:rotation:roll):tostring).
    declare global gui_attitude_offset_AOAReversal_button to gui_attitude_offset_box2:addcheckbox(UI_LANG["uentryGui.gui_reverse_aoa"], AFS:AOAReversal).
    set gui_attitude_offset_AOAReversal_button:ontoggle to {
        parameter newstate.
        set AFS:AOAReversal to newstate.
    }.

    gui_aeromain:addspacing(10).
    declare global gui_aero_update_button to gui_aeromain:addbutton(UI_LANG["uentryGui.gui_update_aero_profiles"]).
    set gui_aero_update_button:onclick to {
        if (not entry_aeroprofile_process["idle"]) {
            hudtext(UI_LANG["uentryGui.err_process_running"], 4, 2, hudtextsize, hudtextcolor, false).
            return.
        }
        set AFS:mass to gui_aero_mass_input:text:tonumber.
        set AFS:area to AFS:REFAREA.
        AFS:InitAtmModel().
        local CtrlSpeedSamples to str2arr(gui_aero_speedsamples_input:text).
        mscalarmul(CtrlSpeedSamples, 1e3).  // convert to m/s
        local CtrlAOASamples to str2arr(gui_aero_AOAsamples_input:text).
        set AFS:CtrlSpeedSamples to CtrlSpeedSamples.
        set AFS:CtrlAOASamples to CtrlAOASamples.

        local AeroSpeedSamples to list().
        mlinspace(
            gui_aero_speedgrid_vmin_input:text:tonumber * 1e3,  // convert to m/s
            gui_aero_speedgrid_vmax_input:text:tonumber * 1e3,  // convert to m/s
            gui_aero_speedgrid_npoints_input:text:tonumber,
            AeroSpeedSamples
        ).
        local altSamples to list().
        // Reverse order to make log density array in ascending order
        mlinspace(
            gui_aero_altgrid_hmax_input:text:tonumber * 1e3,  // convert to m
            gui_aero_altgrid_hmin_input:text:tonumber * 1e3,  // convert to m
            round(gui_aero_altgrid_npoints_input:text:tonumber, 0),
            altSamples
        ).
        local CdCorrection to gui_aero_cd_input:text:tonumber.
        local ClCorrection to gui_aero_cl_input:text:tonumber.
        local batchsize to round(gui_aero_batchsize_input:text:tonumber(20), 0).
        entry_async_set_aeroprofile(AeroSpeedSamples, altSamples, CdCorrection, ClCorrection, batchsize).
        when (true) then {
            local nV to AeroSpeedSamples:length().
            local nH to altSamples:length().
            local currentIndex to entry_aeroprofile_process["curIndex"].
            set gui_aero_msg_label:text to UI_LANG["uentryGui.msg_generating"] + (round(currentIndex*100/(nV*nH), 1)):tostring + "% complete".
            if (entry_aeroprofile_process["idle"]) {
                set gui_aero_msg_label:text to UI_LANG["uentryGui.msg_gen_complete"].
                return false.
            }
            return true.
        }
    }.

    declare global gui_aero_speedsamples_box to gui_aeromain:addhbox().
    declare global gui_aero_speedsamples_label to gui_aero_speedsamples_box:addlabel(UI_LANG["uentryGui.lbl_speed_profile"]).
    set gui_aero_speedsamples_label:style:width to 150.
    local speedsamples to AFS:CtrlSpeedSamples:copy.
    mscalarmul(speedsamples, 1e-3).  // convert to km/s
    declare global gui_aero_speedsamples_input to gui_aero_speedsamples_box:addtextfield(arr2str(speedsamples, 1)).

    declare global gui_aero_AOAsamples_box to gui_aeromain:addhbox().
    declare global gui_aero_AOAsamples_label to gui_aero_AOAsamples_box:addlabel(UI_LANG["uentryGui.lbl_aoa_profile"]).
    set gui_aero_AOAsamples_label:style:width to 150.
    declare global gui_aero_AOAsamples_input to gui_aero_AOAsamples_box:addtextfield(arr2str(AFS:CtrlAOASamples, 1)).

    // Corrections to ship parameters
    declare global gui_aero_correction_box to gui_aeromain:addhbox().
    declare global gui_aero_mass_label to gui_aero_correction_box:addlabel(UI_LANG["uentryGui.lbl_mass_t"]).
    set gui_aero_mass_label:style:width to 150.
    declare global gui_aero_mass_input to gui_aero_correction_box:addtextfield(round(ship:mass, 3):tostring).
    declare global gui_aero_correction_box1 to gui_aeromain:addhbox().
    declare global gui_aero_cd_label to gui_aero_correction_box1:addlabel(UI_LANG["uentryGui.lbl_cd_corr"]).
    declare global gui_aero_cd_input to gui_aero_correction_box1:addtextfield("1").
    declare global gui_aero_cl_label to gui_aero_correction_box1:addlabel(UI_LANG["uentryGui.lbl_cl_corr"]).
    declare global gui_aero_cl_input to gui_aero_correction_box1:addtextfield("1").

    declare global gui_aero_speedgrid_box to gui_aeromain:addhbox().
    local _vmin to 0.
    local _vmax to 0.
    local _nvpoints to 0.
    if (AFS:AeroSpeedSamples:length() > 1) {
        set _nvpoints to AFS:AeroSpeedSamples:length().
        set _vmin to AFS:AeroSpeedSamples[0].
        set _vmax to AFS:AeroSpeedSamples[_nvpoints-1].
    }
    else {
        set _nvpoints to 64.
        set _vmin to entry_vf.
        set _vmax to max(_vmin, get_orbit_v_at_theta(orbit:semimajoraxis, orbit:eccentricity, 0, body:mu)).
    }
    declare global gui_aero_speedgrid_label to gui_aero_speedgrid_box:addlabel(UI_LANG["uentryGui.lbl_vmin"]).
    declare global gui_aero_speedgrid_vmin_input to gui_aero_speedgrid_box:addtextfield((round(_vmin*1e-3, 2)):tostring).
    declare global gui_aero_speedgrid_label2 to gui_aero_speedgrid_box:addlabel(UI_LANG["uentryGui.lbl_vmax"]).
    declare global gui_aero_speedgrid_vmax_input to gui_aero_speedgrid_box:addtextfield((round(_vmax*1e-3, 2)):tostring).
    declare global gui_aero_speedgrid_npoints_label to gui_aero_speedgrid_box:addlabel(UI_LANG["uentryGui.lbl_points"]).
    declare global gui_aero_speedgrid_npoints_input to gui_aero_speedgrid_box:addtextfield(_nvpoints:tostring).

    declare global gui_aero_altgrid_box to gui_aeromain:addhbox().
    local _hmin to 0.
    local _hmax to 0.
    local _nhpoints to 0.
    if (AFS:AeroLogDensitySamples:length() > 1) {
        set _nhpoints to AFS:AeroLogDensitySamples:length().
        set _hmin to AFS:GetAltEst(exp(AFS:AeroLogDensitySamples[_nhpoints-1])).
        set _hmax to AFS:GetAltEst(exp(AFS:AeroLogDensitySamples[0])).
    }
    else {
        set _nhpoints to 64.
        set _hmin to entry_hf.
        set _hmax to body:atm:height.
    }
    declare global gui_aero_altgrid_label to gui_aero_altgrid_box:addlabel(UI_LANG["uentryGui.lbl_hmin"]).
    declare global gui_aero_altgrid_hmin_input to gui_aero_altgrid_box:addtextfield(round(_hmin*1e-3, 2):tostring).
    declare global gui_aero_altgrid_label2 to gui_aero_altgrid_box:addlabel(UI_LANG["uentryGui.lbl_hmax"]).
    declare global gui_aero_altgrid_hmax_input to gui_aero_altgrid_box:addtextfield((round(_hmax*1e-3, 2)):tostring).
    declare global gui_aero_altgrid_npoints_label to gui_aero_altgrid_box:addlabel(UI_LANG["uentryGui.lbl_points"]).
    declare global gui_aero_altgrid_npoints_input to gui_aero_altgrid_box:addtextfield(_nhpoints:tostring).
    declare global gui_aero_batchsize_box to gui_aeromain:addhbox().
    declare global gui_aero_batchsize_label to gui_aero_batchsize_box:addlabel(UI_LANG["uentryGui.lbl_batch_size"]).
    set gui_aero_batchsize_label:style:width to 150.
    declare global gui_aero_batchsize_input to gui_aero_batchsize_box:addtextfield("20").

    gui_aeromain:show().
    return gui_aeromain.
}

function fc_MakeKCLGUI {
    // KCL controller GUI
    // Required Global variables:
    // - enable_roll_torque, enable_pitch_torque, enable_yaw_torque: automatically initialized to true
    // - kclcontroller: automatically initialized to true
    // Return: global gui_kclmain
    declare global gui_kclmain is GUI(400, 400).
    set gui_kclmain:style:hstretch to true.

    // Title
    declare global gui_kcl_title_box to gui_kclmain:addhbox().
    set gui_kcl_title_box:style:height to 40.
    set gui_kcl_title_box:style:margin:top to 0.
    declare global gui_kcl_title_label to gui_kcl_title_box:addlabel("<b><size=20>" + UI_LANG["uentryGui.gui_kcl_title"] + "</size></b>").
    set gui_kcl_title_label:style:align TO "center".
    declare global gui_kcl_title_exit_button to gui_kcl_title_box:addbutton("X").
    set gui_kcl_title_exit_button:style:width to 20.
    set gui_kcl_title_exit_button:style:align to "right".
    set gui_kcl_title_exit_button:onclick to {
        gui_kclmain:hide().
    }.

    gui_kclmain:addspacing(10).

    declare global gui_kcl_enable_label to gui_kclmain:addlabel("<b>" + UI_LANG["uentryGui.lbl_enable_ctrl"] + "</b>").
    declare global gui_kcl_enable_box to gui_kclmain:addhbox().
    declare global gui_kcl_enable_pitch_button to gui_kcl_enable_box:addcheckbox(UI_LANG["uentryGui.lbl_pitch_ctrl"], enable_pitch_torque).
    set gui_kcl_enable_pitch_button:ontoggle to {
        parameter newval.
        set enable_pitch_torque to newval.
        if (not newval) {
            set ship:control:pilotpitchtrim to 0.
        }
    }.
    declare global gui_kcl_enable_yaw_button to gui_kcl_enable_box:addcheckbox(UI_LANG["uentryGui.lbl_yaw_ctrl"], enable_yaw_torque).
    set gui_kcl_enable_yaw_button:ontoggle to {
        parameter newval.
        set enable_yaw_torque to newval.
        if (not newval) {
            set ship:control:pilotyawtrim to 0.
        }
    }.
    declare global gui_kcl_enable_roll_button to gui_kcl_enable_box:addcheckbox(UI_LANG["uentryGui.lbl_roll_ctrl"], enable_roll_torque).
    set gui_kcl_enable_roll_button:ontoggle to {
        parameter newval.
        set enable_roll_torque to newval.
        if (not newval) {
            set ship:control:pilotrolltrim to 0.
        }
    }.
    declare global gui_kcl_pitch_damper_button to gui_kcl_enable_box:addbutton(UI_LANG["uentryGui.btn_pitch_damper"]).
    set gui_kcl_pitch_damper_button:onclick to {
        set gui_kcl_pitch_kp_input:text to "0".
        set kclcontroller["PitchTorqueController"]["PID"]:kp to 0.
        set gui_kcl_pitch_ki_input:text to "0".
        set kclcontroller["PitchTorqueController"]["PID"]:ki to 0.
        set gui_kcl_pitch_kd_input:text to "0.1".
        set kclcontroller["PitchTorqueController"]["PID"]:kd to 0.1.
    }.
    set gui_kcl_pitch_damper_button:style:width to 150.

    // Rotation Rate Controller Parameters
    gui_kclmain:addlabel("<b>" + UI_LANG["uentryGui.lbl_rot_rate_ctrl"] + "</b>").

    declare global gui_kcl_rotation_rate_box to gui_kclmain:addhbox().
    declare global gui_kcl_kp_label to gui_kcl_rotation_rate_box:addlabel("Kp:").
    declare global gui_kcl_kp_input to gui_kcl_rotation_rate_box:addtextfield(kclcontroller["RotationRateController"]["Kp"]:tostring).
    set gui_kcl_kp_input:onconfirm to {
        parameter newval.
        set kclcontroller["RotationRateController"]["Kp"] to newval:tonumber.
    }.
    declare global gui_kcl_upper_label to gui_kcl_rotation_rate_box:addlabel(UI_LANG["uentryGui.lbl_upper_limit"]).
    declare global gui_kcl_upper_input to gui_kcl_rotation_rate_box:addtextfield(kclcontroller["RotationRateController"]["Upper"]:tostring).
    set gui_kcl_upper_input:onconfirm to {
        parameter newval.
        set kclcontroller["RotationRateController"]["Upper"] to newval:tonumber.
    }.
    declare global gui_kcl_ep_label to gui_kcl_rotation_rate_box:addlabel(UI_LANG["uentryGui.lbl_ep_param"]).
    declare global gui_kcl_ep_input to gui_kcl_rotation_rate_box:addtextfield(kclcontroller["RotationRateController"]["Ep"]:tostring).
    set gui_kcl_ep_input:onconfirm to {
        parameter newval.
        set kclcontroller["RotationRateController"]["Ep"] to newval:tonumber.
    }.

    gui_kclmain:addspacing(10).

    // Torque Controllers
    gui_kclmain:addlabel("<b>" + UI_LANG["uentryGui.lbl_torque_ctrls"] + "</b>").

    // Roll torque controller
    gui_kclmain:addlabel(UI_LANG["uentryGui.lbl_roll_axis"]).
    declare global gui_kcl_roll_box to gui_kclmain:addhbox().
    declare global gui_kcl_roll_kp_label to gui_kcl_roll_box:addlabel("Kp:").
    declare global gui_kcl_roll_kp_input to gui_kcl_roll_box:addtextfield(kclcontroller["RollTorqueController"]["PID"]:kp:tostring).
    set gui_kcl_roll_kp_input:onconfirm to {
        parameter newval.
        set kclcontroller["RollTorqueController"]["PID"]:kp to newval:tonumber.
    }.
    declare global gui_kcl_roll_ki_label to gui_kcl_roll_box:addlabel("Ki:").
    declare global gui_kcl_roll_ki_input to gui_kcl_roll_box:addtextfield(kclcontroller["RollTorqueController"]["PID"]:ki:tostring).
    set gui_kcl_roll_ki_input:onconfirm to {
        parameter newval.
        set kclcontroller["RollTorqueController"]["PID"]:ki to newval:tonumber.
    }.
    declare global gui_kcl_roll_kd_label to gui_kcl_roll_box:addlabel("Kd:").
    declare global gui_kcl_roll_kd_input to gui_kcl_roll_box:addtextfield(kclcontroller["RollTorqueController"]["PID"]:kd:tostring).
    set gui_kcl_roll_kd_input:onconfirm to {
        parameter newval.
        set kclcontroller["RollTorqueController"]["PID"]:kd to newval:tonumber.
    }.

    // Pitch torque controller
    gui_kclmain:addlabel(UI_LANG["uentryGui.lbl_pitch_axis"]).
    declare global gui_kcl_pitch_box to gui_kclmain:addhbox().
    declare global gui_kcl_pitch_kp_label to gui_kcl_pitch_box:addlabel("Kp:").
    declare global gui_kcl_pitch_kp_input to gui_kcl_pitch_box:addtextfield(kclcontroller["PitchTorqueController"]["PID"]:kp:tostring).
    set gui_kcl_pitch_kp_input:onconfirm to {
        parameter newval.
        set kclcontroller["PitchTorqueController"]["PID"]:kp to newval:tonumber.
    }.
    declare global gui_kcl_pitch_ki_label to gui_kcl_pitch_box:addlabel("Ki:").
    declare global gui_kcl_pitch_ki_input to gui_kcl_pitch_box:addtextfield(kclcontroller["PitchTorqueController"]["PID"]:ki:tostring).
    set gui_kcl_pitch_ki_input:onconfirm to {
        parameter newval.
        set kclcontroller["PitchTorqueController"]["PID"]:ki to newval:tonumber.
    }.
    declare global gui_kcl_pitch_kd_label to gui_kcl_pitch_box:addlabel("Kd:").
    declare global gui_kcl_pitch_kd_input to gui_kcl_pitch_box:addtextfield(kclcontroller["PitchTorqueController"]["PID"]:kd:tostring).
    set gui_kcl_pitch_kd_input:onconfirm to {
        parameter newval.
        set kclcontroller["PitchTorqueController"]["PID"]:kd to newval:tonumber.
    }.

    // Yaw torque controller
    gui_kclmain:addlabel(UI_LANG["uentryGui.lbl_yaw_axis"]).
    declare global gui_kcl_yaw_box to gui_kclmain:addhbox().
    declare global gui_kcl_yaw_kp_label to gui_kcl_yaw_box:addlabel("Kp:").
    declare global gui_kcl_yaw_kp_input to gui_kcl_yaw_box:addtextfield(kclcontroller["YawTorqueController"]["PID"]:kp:tostring).
    set gui_kcl_yaw_kp_input:onconfirm to {
        parameter newval.
        set kclcontroller["YawTorqueController"]["PID"]:kp to newval:tonumber.
    }.
    declare global gui_kcl_yaw_ki_label to gui_kcl_yaw_box:addlabel("Ki:").
    declare global gui_kcl_yaw_ki_input to gui_kcl_yaw_box:addtextfield(kclcontroller["YawTorqueController"]["PID"]:ki:tostring).
    set gui_kcl_yaw_ki_input:onconfirm to {
        parameter newval.
        set kclcontroller["YawTorqueController"]["PID"]:ki to newval:tonumber.
    }.
    declare global gui_kcl_yaw_kd_label to gui_kcl_yaw_box:addlabel("Kd:").
    declare global gui_kcl_yaw_kd_input to gui_kcl_yaw_box:addtextfield(kclcontroller["YawTorqueController"]["PID"]:kd:tostring).
    set gui_kcl_yaw_kd_input:onconfirm to {
        parameter newval.
        set kclcontroller["YawTorqueController"]["PID"]:kd to newval:tonumber.
    }.

    gui_kclmain:show().
    return gui_kclmain.
}
