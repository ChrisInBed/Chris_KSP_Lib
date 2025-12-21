// flight controller test
declare global FAR to addons:FAR.
set config:IPU to 1000.

// Kinetic Control Low attitude controller for high AOA atmospheric flight
// Input target Bank, AOA, Sideslip angles
// Output torque commands (roll, pitch, yaw)
function KCLController_Init {
    return lexicon(
        "RotationRateController", RotationRateController_Init(
            1, 10, 0.3,    // AOA
            1, 15, 0.3,    // Bank
            1, 10, 0.3     // Sideslip
        ),
        "RollTorqueController", TorqueController_Init(0.2, 0.0005, 0.05, 1, 0),
        "PitchTorqueController", TorqueController_Init(0.2, 0.0005, 0.1, 1, 0),
        "YawTorqueController", TorqueController_Init(0.2, 0.0005, 0.05, 1, 0)
    ).
}

function KCLController_GetControl {
    parameter this.
    parameter angleTarget.  // vector: (Bank, AOA, Sideslip)

    local rateCmd to RotationRateController_GetControll(this["RotationRateController"], angleTarget).
    // Calculate current roll, pitch, yaw rate
    local rateCurrent to ship:angularvel * 180/constant:pi.
    set rateCurrent to ship:facing:inverse * rateCurrent.
    local rollRate to -rateCurrent:z.
    local pitchRate to -rateCurrent:x.
    local yawRate to rateCurrent:y.
    // Get torque commands
    local rollTorqueCmd to TorqueController_GetControl(this["RollTorqueController"], rateCmd:x, rollRate).
    local pitchTorqueCmd to TorqueController_GetControl(this["PitchTorqueController"], rateCmd:y, pitchRate).
    local yawTorqueCmd to TorqueController_GetControl(this["YawTorqueController"], rateCmd:z, yawRate).
    return V(rollTorqueCmd, pitchTorqueCmd, yawTorqueCmd).
}

// Rate controller: input (Bank, AOA, Sideslip), output body rotation rate (roll, pitch, yaw)
function RotationRateController_Init {
    parameter KAOA, UpperAOA, EpAOA.
    parameter KBank, UpperBank, EpBank.
    parameter KSideslip, UpperSideslip, EpSideslip.
    return lexicon(
        "KAOA", KAOA, "UpperAOA", UpperAOA, "EpAOA", EpAOA,
        "KBank", KBank, "UpperBank", UpperBank, "EpBank", EpBank,
        "KSideslip", KSideslip, "UpperSideslip", UpperSideslip, "EpSideslip", EpSideslip
    ).
}

function RotationRateController_GetControll {
    parameter this.
    parameter angleTarget.  // vector: (Bank, AOA, Sideslip)

    // Get current angles
    local _facing to ship:facing.
    local _prog to srfPrograde.
    local _up to up.
    local BankErr to arcTan2(-vDot(_up:forevector, _facing:starvector), vDot(_up:forevector, _facing:upvector)) - angleTarget:x.
    if (abs(BankErr) < this["EpBank"]) set BankErr to 0.
    // local AOACurrent to arcTan2(-vDot(_prog:forevector, _facing:upvector), vDot(_prog:forevector, _facing:forevector)).
    local AOACurrent to FAR:AOA.
    local AOAErr to AOACurrent - angleTarget:y.
    if (abs(AOAErr) < this["EpAOA"]) set AOAErr to 0.
    // local SideslipErr to arcSin(vDot(_prog:forevector, _facing:starvector)) - angleTarget:z.
    local SideslipErr to FAR:AOS - angleTarget:z.
    if (abs(SideslipErr) < this["EpSideslip"]) set SideslipErr to 0.

    // Rotation rates (wind frame)
    local pitchRateCmd to max(-this["UpperAOA"], min(this["UpperAOA"], -AOAErr*this["KAOA"])).
    local bankRateCmd to max(-this["UpperBank"], min(this["UpperBank"], -BankErr*this["KBank"])).
    local sideslipRateCmd to max(-this["UpperSideslip"], min(this["UpperSideslip"], -SideslipErr*this["KSideslip"])).
    print "Rate(airflow): Bank = " + round(bankRateCmd, 2) + " AOA = " + round(pitchRateCmd, 2) + " Side = " + round(sideslipRateCmd, 2) AT(0, 6).

    // transform to body frame
    local cosAOA to cos(AOACurrent).
    local sinAOA to sin(AOACurrent).
    // local rollRateCmd to bankRateCmd * cosAOA + sideslipRateCmd * sinAOA.
    local rollRateCmd to bankRateCmd * cosAOA.
    local yawRateCmd to bankRateCmd * sinAOA - sideslipRateCmd * cosAOA.
    print "Rate(body): Roll = " + round(rollRateCmd, 2) + " Pitch = " + round(pitchRateCmd, 2) + " Yaw = " + round(yawRateCmd, 2) AT(0, 7).

    return V(rollRateCmd, pitchRateCmd, yawRateCmd).
}

// Roll, Pitch, Yaw torque controllers: Input target rotation rate, output torque command
function TorqueController_Init {
    parameter Kp, Ki, Kd, Upper, Ep.
    return lexicon(
        "PID", pidLoop(Kp, Ki, Kd, -Upper, Upper, Ep)
    ).
}

function TorqueController_GetControl {
    parameter this.
    parameter rateTarget, rateCurrent.
    set this["PID"]:setpoint to rateTarget.
    return this["PID"]:update(time:seconds, rateCurrent).
}

function get_bank {
    // calculate current bank angle
    return arcTan2(
        -vDot(ship:facing:starvector, up:forevector),
        vDot(ship:facing:upvector, up:forevector)
    ).
}

function make_gui {
    declare global gui_maingui is GUI(600, 800).
    set gui_maingui:style:hstretch to true.

    // Title
    declare global gui_title_box to gui_maingui:addhbox().
    set gui_title_box:style:height to 40.
    set gui_title_box:style:margin:top to 0.
    declare global gui_title_label to gui_title_box:addlabel("<b><size=20>KCL Flight Controller</size></b>").
    set gui_title_label:style:align TO "center".
    declare global gui_title_exit_button to gui_title_box:addbutton("X").
    set gui_title_exit_button:style:width to 20.
    set gui_title_exit_button:style:align to "right".
    set gui_title_exit_button:onclick to {
        gui_maingui:hide().
        set done to true.
    }.

    // Target angles section
    gui_maingui:addlabel("<b>Target Angles</b>").
    
    // AOA target
    declare global gui_aoa_box to gui_maingui:addhbox().
    declare global gui_aoa_label to gui_aoa_box:addlabel("AOA Target (deg):").
    set gui_aoa_label:style:width to 150.
    declare global gui_aoa_input to gui_aoa_box:addtextfield(AOAtarget:tostring).
    set gui_aoa_input:onconfirm to {
        parameter newval.
        set AOAtarget to newval:tonumber.
    }.

    // Bank target
    declare global gui_bank_box to gui_maingui:addhbox().
    declare global gui_bank_label to gui_bank_box:addlabel("Bank Target (deg):").
    set gui_bank_label:style:width to 150.
    declare global gui_bank_input to gui_bank_box:addtextfield(Banktarget:tostring).
    set gui_bank_input:onconfirm to {
        parameter newval.
        set Banktarget to newval:tonumber.
    }.

    // AOS target
    declare global gui_aos_box to gui_maingui:addhbox().
    declare global gui_aos_label to gui_aos_box:addlabel("AOS Target (deg):").
    set gui_aos_label:style:width to 150.
    declare global gui_aos_input to gui_aos_box:addtextfield(AOStarget:tostring).
    set gui_aos_input:onconfirm to {
        parameter newval.
        set AOStarget to newval:tonumber.
    }.

    gui_maingui:addspacing(10).

    // Rotation Rate Controller Parameters
    gui_maingui:addlabel("<b>Rotation Rate Controller</b>").

    declare global gui_enable_box to gui_maingui:addvbox().
    declare global gui_enable_pitch_button to gui_enable_box:addcheckbox("Enable Pitch Control", true).
    set gui_enable_pitch_button:ontoggle to {
        parameter newval.
        set enable_pitch_torque to newval.
        if (not newval) {
            set ship:control:pilotpitchtrim to 0.
        }
    }.
    declare global gui_enable_yaw_button to gui_enable_box:addcheckbox("Enable Yaw Control", true).
    set gui_enable_yaw_button:ontoggle to {
        parameter newval.
        set enable_yaw_torque to newval.
        if (not newval) {
            set ship:control:pilotyawtrim to 0.
        }
    }.
    declare global gui_enable_roll_button to gui_enable_box:addcheckbox("Enable Roll Control", true).
    set gui_enable_roll_button:ontoggle to {
        parameter newval.
        set enable_roll_torque to newval.
        if (not newval) {
            set ship:control:pilotrolltrim to 0.
        }
    }.
    
    // AOA rate controller
    gui_maingui:addlabel("AOA Rate").
    declare global gui_aoa_rate_box to gui_maingui:addhbox().
    declare global gui_kaoa_label to gui_aoa_rate_box:addlabel("K:").
    declare global gui_kaoa_input to gui_aoa_rate_box:addtextfield(kclcontroller["RotationRateController"]["KAOA"]:tostring).
    set gui_kaoa_input:onconfirm to {
        parameter newval.
        set kclcontroller["RotationRateController"]["KAOA"] to newval:tonumber.
    }.
    declare global gui_upperaoa_label to gui_aoa_rate_box:addlabel("Upper:").
    declare global gui_upperaoa_input to gui_aoa_rate_box:addtextfield(kclcontroller["RotationRateController"]["UpperAOA"]:tostring).
    set gui_upperaoa_input:onconfirm to {
        parameter newval.
        set kclcontroller["RotationRateController"]["UpperAOA"] to newval:tonumber.
    }.
    declare global gui_epaoa_label to gui_aoa_rate_box:addlabel("Ep:").
    declare global gui_epaoa_input to gui_aoa_rate_box:addtextfield(kclcontroller["RotationRateController"]["EpAOA"]:tostring).
    set gui_epaoa_input:onconfirm to {
        parameter newval.
        set kclcontroller["RotationRateController"]["EpAOA"] to newval:tonumber.
    }.

    // Bank rate controller
    gui_maingui:addlabel("Bank Rate").
    declare global gui_bank_rate_box to gui_maingui:addhbox().
    declare global gui_kbank_label to gui_bank_rate_box:addlabel("K:").
    declare global gui_kbank_input to gui_bank_rate_box:addtextfield(kclcontroller["RotationRateController"]["KBank"]:tostring).
    set gui_kbank_input:onconfirm to {
        parameter newval.
        set kclcontroller["RotationRateController"]["KBank"] to newval:tonumber.
    }.
    declare global gui_upperbank_label to gui_bank_rate_box:addlabel("Upper:").
    declare global gui_upperbank_input to gui_bank_rate_box:addtextfield(kclcontroller["RotationRateController"]["UpperBank"]:tostring).
    set gui_upperbank_input:onconfirm to {
        parameter newval.
        set kclcontroller["RotationRateController"]["UpperBank"] to newval:tonumber.
    }.
    declare global gui_epbank_label to gui_bank_rate_box:addlabel("Ep:").
    declare global gui_epbank_input to gui_bank_rate_box:addtextfield(kclcontroller["RotationRateController"]["EpBank"]:tostring).
    set gui_epbank_input:onconfirm to {
        parameter newval.
        set kclcontroller["RotationRateController"]["EpBank"] to newval:tonumber.
    }.

    // Sideslip rate controller
    gui_maingui:addlabel("Sideslip Rate").
    declare global gui_sideslip_rate_box to gui_maingui:addhbox().
    declare global gui_ksideslip_label to gui_sideslip_rate_box:addlabel("K:").
    declare global gui_ksideslip_input to gui_sideslip_rate_box:addtextfield(kclcontroller["RotationRateController"]["KSideslip"]:tostring).
    set gui_ksideslip_input:onconfirm to {
        parameter newval.
        set kclcontroller["RotationRateController"]["KSideslip"] to newval:tonumber.
    }.
    declare global gui_uppersideslip_label to gui_sideslip_rate_box:addlabel("Upper:").
    declare global gui_uppersideslip_input to gui_sideslip_rate_box:addtextfield(kclcontroller["RotationRateController"]["UpperSideslip"]:tostring).
    set gui_uppersideslip_input:onconfirm to {
        parameter newval.
        set kclcontroller["RotationRateController"]["UpperSideslip"] to newval:tonumber.
    }.
    declare global gui_epsideslip_label to gui_sideslip_rate_box:addlabel("Ep:").
    declare global gui_epsideslip_input to gui_sideslip_rate_box:addtextfield(kclcontroller["RotationRateController"]["EpSideslip"]:tostring).
    set gui_epsideslip_input:onconfirm to {
        parameter newval.
        set kclcontroller["RotationRateController"]["EpSideslip"] to newval:tonumber.
    }.

    gui_maingui:addspacing(10).

    // Torque Controllers
    gui_maingui:addlabel("<b>Torque Controllers</b>").

    // Roll torque controller
    gui_maingui:addlabel("Roll").
    declare global gui_roll_box to gui_maingui:addhbox().
    declare global gui_roll_kp_label to gui_roll_box:addlabel("Kp:").
    declare global gui_roll_kp_input to gui_roll_box:addtextfield(kclcontroller["RollTorqueController"]["PID"]:kp:tostring).
    set gui_roll_kp_input:onconfirm to {
        parameter newval.
        set kclcontroller["RollTorqueController"]["PID"]:kp to newval:tonumber.
    }.
    declare global gui_roll_ki_label to gui_roll_box:addlabel("Ki:").
    declare global gui_roll_ki_input to gui_roll_box:addtextfield(kclcontroller["RollTorqueController"]["PID"]:ki:tostring).
    set gui_roll_ki_input:onconfirm to {
        parameter newval.
        set kclcontroller["RollTorqueController"]["PID"]:ki to newval:tonumber.
    }.
    declare global gui_roll_kd_label to gui_roll_box:addlabel("Kd:").
    declare global gui_roll_kd_input to gui_roll_box:addtextfield(kclcontroller["RollTorqueController"]["PID"]:kd:tostring).
    set gui_roll_kd_input:onconfirm to {
        parameter newval.
        set kclcontroller["RollTorqueController"]["PID"]:kd to newval:tonumber.
    }.

    // Pitch torque controller
    gui_maingui:addlabel("Pitch").
    declare global gui_pitch_box to gui_maingui:addhbox().
    declare global gui_pitch_kp_label to gui_pitch_box:addlabel("Kp:").
    declare global gui_pitch_kp_input to gui_pitch_box:addtextfield(kclcontroller["PitchTorqueController"]["PID"]:kp:tostring).
    set gui_pitch_kp_input:onconfirm to {
        parameter newval.
        set kclcontroller["PitchTorqueController"]["PID"]:kp to newval:tonumber.
    }.
    declare global gui_pitch_ki_label to gui_pitch_box:addlabel("Ki:").
    declare global gui_pitch_ki_input to gui_pitch_box:addtextfield(kclcontroller["PitchTorqueController"]["PID"]:ki:tostring).
    set gui_pitch_ki_input:onconfirm to {
        parameter newval.
        set kclcontroller["PitchTorqueController"]["PID"]:ki to newval:tonumber.
    }.
    declare global gui_pitch_kd_label to gui_pitch_box:addlabel("Kd:").
    declare global gui_pitch_kd_input to gui_pitch_box:addtextfield(kclcontroller["PitchTorqueController"]["PID"]:kd:tostring).
    set gui_pitch_kd_input:onconfirm to {
        parameter newval.
        set kclcontroller["PitchTorqueController"]["PID"]:kd to newval:tonumber.
    }.

    // Yaw torque controller
    gui_maingui:addlabel("Yaw").
    declare global gui_yaw_box to gui_maingui:addhbox().
    declare global gui_yaw_kp_label to gui_yaw_box:addlabel("Kp:").
    declare global gui_yaw_kp_input to gui_yaw_box:addtextfield(kclcontroller["YawTorqueController"]["PID"]:kp:tostring).
    set gui_yaw_kp_input:onconfirm to {
        parameter newval.
        set kclcontroller["YawTorqueController"]["PID"]:kp to newval:tonumber.
    }.
    declare global gui_yaw_ki_label to gui_yaw_box:addlabel("Ki:").
    declare global gui_yaw_ki_input to gui_yaw_box:addtextfield(kclcontroller["YawTorqueController"]["PID"]:ki:tostring).
    set gui_yaw_ki_input:onconfirm to {
        parameter newval.
        set kclcontroller["YawTorqueController"]["PID"]:ki to newval:tonumber.
    }.
    declare global gui_yaw_kd_label to gui_yaw_box:addlabel("Kd:").
    declare global gui_yaw_kd_input to gui_yaw_box:addtextfield(kclcontroller["YawTorqueController"]["PID"]:kd:tostring).
    set gui_yaw_kd_input:onconfirm to {
        parameter newval.
        set kclcontroller["YawTorqueController"]["PID"]:kd to newval:tonumber.
    }.

    gui_maingui:show().
}

clearScreen.
declare global AOAtarget to 0.
declare global Banktarget to 0.
declare global AOStarget to 0.
lock steering to srfprograde.
wait until abs(steeringManager:angleerror) < 0.1 and abs(steeringManager:rollerror) < 0.1 and abs(ship:angularvel:mag) < 0.005.
wait 5.
print "Switch to KCL attitude control" AT(0, 1).
declare global kclcontroller to KCLController_Init().
declare done to false.
make_gui().
unlock steering.

declare global enable_pitch_torque to true.
declare global enable_yaw_torque to true.
declare global enable_roll_torque to true.
until done {
    local torqueCmd to KCLController_GetControl(kclcontroller, V(Banktarget, AOAtarget, AOStarget)).
    if (enable_roll_torque) set ship:control:pilotrolltrim to torqueCmd:x.
    if (enable_pitch_torque) set ship:control:pilotpitchtrim to torqueCmd:y.
    if (enable_yaw_torque) set ship:control:pilotyawtrim to torqueCmd:z.
    print "       Target      Current    " AT(0, 2).
    print "Bank  " + round(Banktarget, 1) + "   " + round(get_bank(), 1) + "    " AT(0, 3).
    print "AOA   " + round(AOAtarget, 1) + "   " + round(FAR:AOA, 1) + "    " AT(0, 4).
    print "AOS   " + round(AOStarget, 1) + "   " + round(FAR:AOS, 1) + "    " AT(0, 5).
}

unlock steering.
set ship:control:pilotrolltrim to 0.
set ship:control:pilotpitchtrim to 0.
set ship:control:pilotyawtrim to 0.
set ship:control:neutralize to true.