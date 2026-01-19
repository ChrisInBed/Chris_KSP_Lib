// GUI for uentry.ks
runOncePath("0:/lib/utils.ks").
runOncePath("0:/lib/orbit.ks").
runOncePath("0:/lib/chrismath.ks").

declare global AFS to addons:AFS.
function edl_MakeEDLGUI {
    // EDL Main GUI
    // Required global variables:
    // - AFS, entry_vf, entry_hf, entry_dist, entry_bank_i, entry_bank_f
    // - entry_heading_tol, AOAProfile, HProfile
    declare global gui_edlmain to GUI(500, 700).
    set gui_edlmain:style:hstretch to true.

    // Title
    declare global gui_edl_title_box to gui_edlmain:addhbox().
    set gui_edl_title_box:style:height to 40.
    set gui_edl_title_box:style:margin:top to 0.
    declare global gui_edl_title_label to gui_edl_title_box:addlabel("<b><size=20>UEntry Guidance</size></b>").
    set gui_edl_title_label:style:align to "center".
    declare global gui_edl_title_exit_button to gui_edl_title_box:addbutton("X").
    set gui_edl_title_exit_button:style:width to 20.
    set gui_edl_title_exit_button:style:align to "right".
    set gui_edl_title_exit_button:onclick to {
        set done to true.
        gui_edlmain:hide().
    }.

    gui_edlmain:addspacing(10).

    declare global gui_edl_activate_button to gui_edlmain:addbutton("Activate Guidance").
    set gui_edl_activate_button:onclick to {
        set guidance_active to true.
    }.

    // Vessel Parameters
    gui_edlmain:addlabel("<b>Vessel Parameters</b>").
    
    declare global gui_edl_mass_box to gui_edlmain:addhbox().
    declare global gui_edl_mass_label to gui_edl_mass_box:addlabel("Mass (t):").
    set gui_edl_mass_label:style:width to 120.
    declare global gui_edl_mass_input to gui_edl_mass_box:addtextfield(AFS:mass:tostring).
    declare global gui_edl_mass_set to gui_edl_mass_box:addbutton("set").
    set gui_edl_mass_set:style:width to 50.
    set gui_edl_mass_set:onclick to {set AFS:mass to gui_edl_mass_input:text:tonumber.}.

    declare global gui_edl_area_box to gui_edlmain:addhbox().
    declare global gui_edl_area_label to gui_edl_area_box:addlabel("Area (m²):").
    set gui_edl_area_label:style:width to 120.
    declare global gui_edl_area_input to gui_edl_area_box:addtextfield(AFS:area:tostring).
    declare global gui_edl_area_set to gui_edl_area_box:addbutton("set").
    set gui_edl_area_set:style:width to 50.
    set gui_edl_area_set:onclick to {set AFS:area to gui_edl_area_input:text:tonumber.}.

    gui_edlmain:addspacing(10).

    // // Aerodynamic Parameters
    // gui_edlmain:addlabel("<b>Aerodynamic Profile</b>").
    // declare global gui_edl_aeroprofile_box to gui_edlmain:addvbox().
    // declare global gui_edl_aeroprofile_update_button to gui_edl_aeroprofile_box:addbutton("Update Profiles").
    // set gui_edl_aeroprofile_update_button:onclick to {
    //     local speedsamples to str2arr(gui_edl_speedsamples_input:text).
    //     mscalarmul(speedsamples, 1e3).  // convert to m/s
    //     local AOAProfile to str2arr(gui_edl_aoaprofile_input:text).
    //     entry_set_AOAprofile(speedsamples, AOAProfile).
    //     local _HProfile to str2arr(gui_edl_hprofile_input:text).
    //     mscalarmul(_HProfile, 1e3).  // convert to m
    //     entry_set_aeroprofile(AFS:speedsamples, _HProfile, AOAProfile).
    //     set gui_edl_Cdprofile_input:text to arr2str(AFS:Cdsamples, 2).
    //     set gui_edl_Clprofile_input:text to arr2str(AFS:Clsamples, 2).
    // }.

    // declare global gui_edl_speedsamples_box to gui_edl_aeroprofile_box:addhbox().
    // declare global gui_edl_speedsamples_label to gui_edl_speedsamples_box:addlabel("Speed Profile (km/s):").
    // set gui_edl_speedsamples_label:style:width to 150.
    // local speedsamples to AFS:speedsamples:copy.
    // mscalarmul(speedsamples, 1e-3).  // convert to km/s
    // declare global gui_edl_speedsamples_input to gui_edl_speedsamples_box:addtextfield(arr2str(speedsamples, 1)).

    // declare global gui_edl_hprofile_box to gui_edl_aeroprofile_box:addhbox().
    // declare global gui_edl_hprofile_label to gui_edl_hprofile_box:addlabel("(Guess)Alt Profile (km):").
    // set gui_edl_hprofile_label:style:width to 150.
    // local _HProfile to HProfile:copy.
    // mscalarmul(_HProfile, 1e-3).  // convert to km
    // declare global gui_edl_hprofile_input to gui_edl_hprofile_box:addtextfield(arr2str(_HProfile, 1)).

    // declare global gui_edl_aoaprofile_box to gui_edl_aeroprofile_box:addhbox().
    // declare global gui_edl_aoaprofile_label to gui_edl_aoaprofile_box:addlabel("AOA Profile (°):").
    // set gui_edl_aoaprofile_label:style:width to 150.
    // declare global gui_edl_aoaprofile_input to gui_edl_aoaprofile_box:addtextfield(arr2str(AFS:AOAsamples, 1)).

    // declare global gui_edl_Cdprofile_box to gui_edl_aeroprofile_box:addhbox().
    // declare global gui_edl_Cdprofile_label to gui_edl_Cdprofile_box:addlabel("Cd Profile:").
    // set gui_edl_Cdprofile_label:style:width to 150.
    // declare global gui_edl_Cdprofile_input to gui_edl_Cdprofile_box:addtextfield(arr2str(AFS:Cdsamples, 2)).

    // declare global gui_edl_Clprofile_box to gui_edl_aeroprofile_box:addhbox().
    // declare global gui_edl_Clprofile_label to gui_edl_Clprofile_box:addlabel("Cl Profile:").
    // set gui_edl_Clprofile_label:style:width to 150.
    // declare global gui_edl_Clprofile_input to gui_edl_Clprofile_box:addtextfield(arr2str(AFS:Clsamples, 2)).

    // gui_edlmain:addspacing(10).

    // Target Parameters
    gui_edlmain:addlabel("<b>Target</b>").
    declare global gui_edl_target_button to gui_edlmain:addbutton("Update Target").
    set gui_edl_target_button:onclick to {
        local entry_vf to gui_edl_entry_vf_input:text:tonumber.
        local entry_hf to gui_edl_entry_hf_input:text:tonumber * 1e3.  // convert to m
        local entry_dist to gui_edl_entry_dist_input:text:tonumber * 1e3.  // convert to m
        local entry_headingf to gui_edl_entry_headingf_input:text:tonumber.
        entry_set_target(entry_hf, entry_vf, entry_dist, entry_headingf, get_target_geo()).
    }.

    declare global gui_edl_target_box1 to gui_edlmain:addhbox().  // line 1
    declare global gui_edl_target_box2 to gui_edlmain:addhbox().  // line 2

    declare global gui_edl_entry_hf_label to gui_edl_target_box1:addlabel("Height (km):").
    set gui_edl_entry_hf_label:style:width to 150.
    declare global gui_edl_entry_hf_input to gui_edl_target_box1:addtextfield(round(entry_hf*1e-3, 1):tostring).
    
    declare global gui_edl_entry_vf_label to gui_edl_target_box1:addlabel("Speed (m/s):").
    set gui_edl_entry_vf_label:style:width to 150.
    declare global gui_edl_entry_vf_input to gui_edl_target_box1:addtextfield(round(entry_vf, 1):tostring).

    local active_geo to get_target_geo().
    local entry_dist to (active_geo:position - entry_target_geo:position):mag.
    declare global gui_edl_entry_dist_label to gui_edl_target_box2:addlabel("Distance (km):").
    set gui_edl_entry_dist_label:style:width to 150.
    declare global gui_edl_entry_dist_input to gui_edl_target_box2:addtextfield(round(entry_dist*1e-3, 1):tostring).

    local entry_headingf to mheadingangle(active_geo:lat, active_geo:lng, entry_target_geo:lat, entry_target_geo:lng).
    declare global gui_edl_entry_headingf_label to gui_edl_target_box2:addlabel("Heading (°):").
    set gui_edl_entry_headingf_label:style:width to 150.
    declare global gui_edl_entry_headingf_input to gui_edl_target_box2:addtextfield(round(entry_headingf, 1):tostring).

    // Guidance Parameters
    gui_edlmain:addlabel("<b>Guidance Parameters</b>").
    declare global gui_edl_entry_bank_i_box to gui_edlmain:addhbox().
    declare global gui_edl_entry_bank_i_label to gui_edl_entry_bank_i_box:addlabel("Initial Bank (°):").
    set gui_edl_entry_bank_i_label:style:width to 150.
    declare global gui_edl_entry_bank_i_input to gui_edl_entry_bank_i_box:addtextfield(entry_bank_i:tostring).
    declare global gui_edl_entry_bank_i_set to gui_edl_entry_bank_i_box:addbutton("set").
    set gui_edl_entry_bank_i_set:style:width to 50.
    set gui_edl_entry_bank_i_set:onclick to {set entry_bank_i to gui_edl_entry_bank_i_input:text:tonumber.}.

    declare global gui_edl_entry_bank_f_box to gui_edlmain:addhbox().
    declare global gui_edl_entry_bank_f_label to gui_edl_entry_bank_f_box:addlabel("Final Bank (°):").
    set gui_edl_entry_bank_f_label:style:width to 150.
    declare global gui_edl_entry_bank_f_input to gui_edl_entry_bank_f_box:addtextfield(entry_bank_f:tostring).
    declare global gui_edl_entry_bank_f_set to gui_edl_entry_bank_f_box:addbutton("set").
    set gui_edl_entry_bank_f_set:style:width to 50.
    set gui_edl_entry_bank_f_set:onclick to {set entry_bank_f to gui_edl_entry_bank_f_input:text:tonumber.}.

    declare global gui_edl_bank_max_box to gui_edlmain:addhbox().
    declare global gui_edl_bank_max_label to gui_edl_bank_max_box:addlabel("Max Bank (°):").
    set gui_edl_bank_max_label:style:width to 150.
    declare global gui_edl_bank_max_input to gui_edl_bank_max_box:addtextfield(AFS:bank_max:tostring).
    declare global gui_edl_bank_max_set to gui_edl_bank_max_box:addbutton("set").
    set gui_edl_bank_max_set:style:width to 50.
    set gui_edl_bank_max_set:onclick to {set AFS:bank_max to gui_edl_bank_max_input:text:tonumber.}.

    declare global gui_edl_entry_heading_tol_box to gui_edlmain:addhbox().
    declare global gui_edl_entry_heading_tol_label to gui_edl_entry_heading_tol_box:addlabel("Heading Tol (°):").
    set gui_edl_entry_heading_tol_label:style:width to 150.
    declare global gui_edl_entry_heading_tol_input to gui_edl_entry_heading_tol_box:addtextfield(entry_heading_tol:tostring).
    declare global gui_edl_entry_heading_tol_set to gui_edl_entry_heading_tol_box:addbutton("set").
    set gui_edl_entry_heading_tol_set:style:width to 50.
    set gui_edl_entry_heading_tol_set:onclick to {set entry_heading_tol to gui_edl_entry_heading_tol_input:text:tonumber.}.
    
    declare global gui_edl_qdot_max_box to gui_edlmain:addhbox().
    declare global gui_edl_qdot_max_label to gui_edl_qdot_max_box:addlabel("Max Heatflux (kW/m^2):").
    set gui_edl_qdot_max_label:style:width to 150.
    declare global gui_edl_qdot_max_input to gui_edl_qdot_max_box:addtextfield(round(AFS:Qdot_max*1e-3):tostring).
    declare global gui_edl_qdot_max_set to gui_edl_qdot_max_box:addbutton("set").
    set gui_edl_qdot_max_set:style:width to 50.
    set gui_edl_qdot_max_set:onclick to {set AFS:Qdot_max to gui_edl_qdot_max_input:text:tonumber * 1e3.}.

    declare global gui_edl_acc_max_box to gui_edlmain:addhbox().
    declare global gui_edl_acc_max_label to gui_edl_acc_max_box:addlabel("Max Load (g):").
    set gui_edl_acc_max_label:style:width to 150.
    declare global gui_edl_acc_max_input to gui_edl_acc_max_box:addtextfield(round(AFS:acc_max/9.81, 1):tostring).
    declare global gui_edl_acc_max_set to gui_edl_acc_max_box:addbutton("set").
    set gui_edl_acc_max_set:style:width to 50.
    set gui_edl_acc_max_set:onclick to {set AFS:acc_max to gui_edl_acc_max_input:text:tonumber * 9.81.}.

    declare global gui_edl_dynp_max_box to gui_edlmain:addhbox().
    declare global gui_edl_dynp_max_label to gui_edl_dynp_max_box:addlabel("Max Dynp (kPa):").
    set gui_edl_dynp_max_label:style:width to 150.
    declare global gui_edl_dynp_max_input to gui_edl_dynp_max_box:addtextfield(round(AFS:dynp_max*1e-3):tostring).
    declare global gui_edl_dynp_max_set to gui_edl_dynp_max_box:addbutton("set").
    set gui_edl_dynp_max_set:style:width to 50.
    set gui_edl_dynp_max_set:onclick to {set AFS:dynp_max to gui_edl_dynp_max_input:text:tonumber * 1e3.}.

    declare global gui_edl_l_min_box to gui_edlmain:addhbox().
    declare global gui_edl_l_min_label to gui_edl_l_min_box:addlabel("Min Lift (m/s^2):").
    set gui_edl_l_min_label:style:width to 150.
    declare global gui_edl_l_min_input to gui_edl_l_min_box:addtextfield(AFS:L_min:tostring).
    declare global gui_edl_l_min_set to gui_edl_l_min_box:addbutton("set").
    set gui_edl_l_min_set:style:width to 50.
    set gui_edl_l_min_set:onclick to {set AFS:L_min to gui_edl_l_min_input:text:tonumber.}.
    
    declare global gui_edl_k_qegc_box to gui_edlmain:addhbox().
    declare global gui_edl_k_qegc_label to gui_edl_k_qegc_box:addlabel("QEGC Gain:").
    set gui_edl_k_qegc_label:style:width to 150.
    declare global gui_edl_k_qegc_input to gui_edl_k_qegc_box:addtextfield(AFS:k_QEGC:tostring).
    declare global gui_edl_k_qegc_set to gui_edl_k_qegc_box:addbutton("set").
    set gui_edl_k_qegc_set:style:width to 50.
    set gui_edl_k_qegc_set:onclick to {set AFS:k_QEGC to gui_edl_k_qegc_input:text:tonumber.}.

    declare global gui_edl_k_c_box to gui_edlmain:addhbox().
    declare global gui_edl_k_c_label to gui_edl_k_c_box:addlabel("Constraint Gain:").
    set gui_edl_k_c_label:style:width to 150.
    declare global gui_edl_k_c_input to gui_edl_k_c_box:addtextfield(AFS:k_C:tostring).
    declare global gui_edl_k_c_set to gui_edl_k_c_box:addbutton("set").
    set gui_edl_k_c_set:style:width to 50.
    set gui_edl_k_c_set:onclick to {set AFS:k_C to gui_edl_k_c_input:text:tonumber.}.

    declare global gui_edl_t_reg_box to gui_edlmain:addhbox().
    declare global gui_edl_t_reg_label to gui_edl_t_reg_box:addlabel("Lag T (s):").
    set gui_edl_t_reg_label:style:width to 150.
    declare global gui_edl_t_reg_input to gui_edl_t_reg_box:addtextfield(AFS:t_reg:tostring).
    declare global gui_edl_t_reg_set to gui_edl_t_reg_box:addbutton("set").
    set gui_edl_t_reg_set:style:width to 50.
    set gui_edl_t_reg_set:onclick to {set AFS:t_reg to gui_edl_t_reg_input:text:tonumber.}.

    gui_edlmain:addspacing(10).

    // KCL Controller Button
    declare global gui_edl_kcl_button to gui_edlmain:addbutton("Open KCL Controller GUI").
    set gui_edl_kcl_button:onclick to {
        fc_MakeKCLGUI().
    }.

    gui_edlmain:show().
    return gui_edlmain.
}

function fc_MakeKCLGUI {
    // KCL controller GUI
    // Required Global variables:
    // - enable_roll_torque, enable_pitch_torque, enable_yaw_torque: automatically initialized to true
    // - kclcontroller: automatically initialized to true
    // Return: global gui_kclmain
    declare global gui_kclmain is GUI(500, 700).
    set gui_kclmain:style:hstretch to true.

    // Title
    declare global gui_kcl_title_box to gui_kclmain:addhbox().
    set gui_kcl_title_box:style:height to 40.
    set gui_kcl_title_box:style:margin:top to 0.
    declare global gui_kcl_title_label to gui_kcl_title_box:addlabel("<b><size=20>KCL Flight Controller</size></b>").
    set gui_kcl_title_label:style:align TO "center".
    declare global gui_kcl_title_exit_button to gui_kcl_title_box:addbutton("X").
    set gui_kcl_title_exit_button:style:width to 20.
    set gui_kcl_title_exit_button:style:align to "right".
    set gui_kcl_title_exit_button:onclick to {
        gui_kclmain:hide().
    }.

    gui_kclmain:addspacing(10).

    declare global gui_kcl_enable_label to gui_kclmain:addlabel("<b>Enable/Disable Controllers</b>").
    declare global gui_kcl_enable_box to gui_kclmain:addhbox().
    declare global gui_kcl_enable_pitch_button to gui_kcl_enable_box:addcheckbox("Pitch", enable_pitch_torque).
    set gui_kcl_enable_pitch_button:ontoggle to {
        parameter newval.
        set enable_pitch_torque to newval.
        if (not newval) {
            set ship:control:pilotpitchtrim to 0.
        }
    }.
    declare global gui_kcl_enable_yaw_button to gui_kcl_enable_box:addcheckbox("Yaw", enable_yaw_torque).
    set gui_kcl_enable_yaw_button:ontoggle to {
        parameter newval.
        set enable_yaw_torque to newval.
        if (not newval) {
            set ship:control:pilotyawtrim to 0.
        }
    }.
    declare global gui_kcl_enable_roll_button to gui_kcl_enable_box:addcheckbox("Roll", enable_roll_torque).
    set gui_kcl_enable_roll_button:ontoggle to {
        parameter newval.
        set enable_roll_torque to newval.
        if (not newval) {
            set ship:control:pilotrolltrim to 0.
        }
    }.

    // Rotation Rate Controller Parameters
    gui_kclmain:addlabel("<b>Rotation Rate Controller</b>").

    gui_kclmain:addlabel("AOA Rate").
    declare global gui_kcl_aoa_rate_box to gui_kclmain:addhbox().
    declare global gui_kcl_kaoa_label to gui_kcl_aoa_rate_box:addlabel("K:").
    declare global gui_kcl_kaoa_input to gui_kcl_aoa_rate_box:addtextfield(kclcontroller["RotationRateController"]["KAOA"]:tostring).
    set gui_kcl_kaoa_input:onconfirm to {
        parameter newval.
        set kclcontroller["RotationRateController"]["KAOA"] to newval:tonumber.
    }.
    declare global gui_kcl_upperaoa_label to gui_kcl_aoa_rate_box:addlabel("Upper:").
    declare global gui_kcl_upperaoa_input to gui_kcl_aoa_rate_box:addtextfield(kclcontroller["RotationRateController"]["UpperAOA"]:tostring).
    set gui_kcl_upperaoa_input:onconfirm to {
        parameter newval.
        set kclcontroller["RotationRateController"]["UpperAOA"] to newval:tonumber.
    }.
    declare global gui_kcl_epaoa_label to gui_kcl_aoa_rate_box:addlabel("Ep:").
    declare global gui_kcl_epaoa_input to gui_kcl_aoa_rate_box:addtextfield(kclcontroller["RotationRateController"]["EpAOA"]:tostring).
    set gui_kcl_epaoa_input:onconfirm to {
        parameter newval.
        set kclcontroller["RotationRateController"]["EpAOA"] to newval:tonumber.
    }.

    gui_kclmain:addlabel("Bank Rate").
    declare global gui_kcl_bank_rate_box to gui_kclmain:addhbox().
    declare global gui_kcl_kbank_label to gui_kcl_bank_rate_box:addlabel("K:").
    declare global gui_kcl_kbank_input to gui_kcl_bank_rate_box:addtextfield(kclcontroller["RotationRateController"]["KBank"]:tostring).
    set gui_kcl_kbank_input:onconfirm to {
        parameter newval.
        set kclcontroller["RotationRateController"]["KBank"] to newval:tonumber.
    }.
    declare global gui_kcl_upperbank_label to gui_kcl_bank_rate_box:addlabel("Upper:").
    declare global gui_kcl_upperbank_input to gui_kcl_bank_rate_box:addtextfield(kclcontroller["RotationRateController"]["UpperBank"]:tostring).
    set gui_kcl_upperbank_input:onconfirm to {
        parameter newval.
        set kclcontroller["RotationRateController"]["UpperBank"] to newval:tonumber.
    }.
    declare global gui_kcl_epbank_label to gui_kcl_bank_rate_box:addlabel("Ep:").
    declare global gui_kcl_epbank_input to gui_kcl_bank_rate_box:addtextfield(kclcontroller["RotationRateController"]["EpBank"]:tostring).
    set gui_kcl_epbank_input:onconfirm to {
        parameter newval.
        set kclcontroller["RotationRateController"]["EpBank"] to newval:tonumber.
    }.

    gui_kclmain:addlabel("Sideslip Rate").
    declare global gui_kcl_sideslip_rate_box to gui_kclmain:addhbox().
    declare global gui_kcl_ksideslip_label to gui_kcl_sideslip_rate_box:addlabel("K:").
    declare global gui_kcl_ksideslip_input to gui_kcl_sideslip_rate_box:addtextfield(kclcontroller["RotationRateController"]["KSideslip"]:tostring).
    set gui_kcl_ksideslip_input:onconfirm to {
        parameter newval.
        set kclcontroller["RotationRateController"]["KSideslip"] to newval:tonumber.
    }.
    declare global gui_kcl_uppersideslip_label to gui_kcl_sideslip_rate_box:addlabel("Upper:").
    declare global gui_kcl_uppersideslip_input to gui_kcl_sideslip_rate_box:addtextfield(kclcontroller["RotationRateController"]["UpperSideslip"]:tostring).
    set gui_kcl_uppersideslip_input:onconfirm to {
        parameter newval.
        set kclcontroller["RotationRateController"]["UpperSideslip"] to newval:tonumber.
    }.
    declare global gui_kcl_epsideslip_label to gui_kcl_sideslip_rate_box:addlabel("Ep:").
    declare global gui_kcl_epsideslip_input to gui_kcl_sideslip_rate_box:addtextfield(kclcontroller["RotationRateController"]["EpSideslip"]:tostring).
    set gui_kcl_epsideslip_input:onconfirm to {
        parameter newval.
        set kclcontroller["RotationRateController"]["EpSideslip"] to newval:tonumber.
    }.

    gui_kclmain:addspacing(10).

    // Torque Controllers
    gui_kclmain:addlabel("<b>Torque Controllers</b>").

    // Roll torque controller
    gui_kclmain:addlabel("Roll").
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
    gui_kclmain:addlabel("Pitch").
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
    gui_kclmain:addlabel("Yaw").
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