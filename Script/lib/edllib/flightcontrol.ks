declare global enable_roll_torque is true.
declare global enable_pitch_torque is true.
declare global enable_yaw_torque is true.
declare global kclcontroller is KCLController_Init().
// Kinetic Control Low attitude controller for high AOA atmospheric flight
// Input target Bank, AOA, Sideslip angles
// Output torque commands (roll, pitch, yaw)
function KCLController_Init {
    return lexicon(
        "RotationRateController", RotationRateController_Init(
            0.5, 5, 0.3,    // AOA
            0.5, 5, 0.3,    // Bank
            0.5, 5, 0.05     // Sideslip
        ),
        "RollTorqueController", TorqueController_Init(0.2, 0, 0.02, 1, 0),
        "PitchTorqueController", TorqueController_Init(0.2, 0.002, 0.05, 1, 0),
        "YawTorqueController", TorqueController_Init(0.8, 0, 0.02, 1, 0)
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

function KCLController_ApplyControl {
    parameter this.
    parameter angleTarget.  // vector: (Bank, AOA, Sideslip)
    local torqueCmd to KCLController_GetControl(this, angleTarget).
    // Apply torque commands
    if (enable_roll_torque) set ship:control:pilotrolltrim to torqueCmd:x.
    if (enable_pitch_torque) set ship:control:pilotpitchtrim to torqueCmd:y.
    if (enable_yaw_torque) set ship:control:pilotyawtrim to torqueCmd:z.
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
    local AOACurrent to AFS:AOA.
    local AOAErr to AOACurrent - angleTarget:y.
    if (abs(AOAErr) < this["EpAOA"]) set AOAErr to 0.
    // local SideslipErr to arcSin(vDot(_prog:forevector, _facing:starvector)) - angleTarget:z.
    local SideslipErr to AFS:AOS - angleTarget:z.
    if (abs(SideslipErr) < this["EpSideslip"]) set SideslipErr to 0.

    // Rotation rates (wind frame)
    local pitchRateCmd to max(-this["UpperAOA"], min(this["UpperAOA"], -AOAErr*this["KAOA"])).
    local bankRateCmd to max(-this["UpperBank"], min(this["UpperBank"], -BankErr*this["KBank"])).
    local sideslipRateCmd to max(-this["UpperSideslip"], min(this["UpperSideslip"], -SideslipErr*this["KSideslip"])).
    // print "Rate(airflow): Bank = " + round(bankRateCmd, 2) + " AOA = " + round(pitchRateCmd, 2) + " Side = " + round(sideslipRateCmd, 2) AT(0, 6).

    // transform to body frame
    local cosAOA to cos(AOACurrent).
    local sinAOA to sin(AOACurrent).
    // local rollRateCmd to bankRateCmd * cosAOA + sideslipRateCmd * sinAOA.
    local rollRateCmd to bankRateCmd * cosAOA.
    local yawRateCmd to bankRateCmd * sinAOA - sideslipRateCmd * cosAOA.
    // print "Rate(body): Roll = " + round(rollRateCmd, 2) + " Pitch = " + round(pitchRateCmd, 2) + " Yaw = " + round(yawRateCmd, 2) AT(0, 7).

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

function fc_DeactiveControl {
    set ship:control:neutralize to true.
    set ship:control:pilotpitchtrim to 0.
    set ship:control:pilotrolltrim to 0.
    set ship:control:pilotyawtrim to 0.
}