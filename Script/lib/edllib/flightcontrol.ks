declare global enable_roll_torque is true.
declare global enable_pitch_torque is true.
declare global enable_yaw_torque is true.
declare global AFS to addons:AFS.
declare global kclcontroller is KCLController_Init().
// Kinetic Control Low attitude controller for high AOA atmospheric flight
// Input target Bank, AOA, Sideslip angles
// Output torque commands (roll, pitch, yaw)
function KCLController_Init {
    return lexicon(
        "RotationRateController", RotationRateController_Init(0.5, 5, 0.05),
        "RollTorqueController", TorqueController_Init(0.4, 0, 0.02, 1, 0),
        "PitchTorqueController", TorqueController_Init(0.8, 0.008, 0.02, 1, 0),
        "YawTorqueController", TorqueController_Init(0.4, 0, 0.02, 1, 0)
    ).
}

// debug
// declare global fc_debug_targetAttitude_x to V(1,0,0).
// declare global fc_debug_targetAttitude_y to V(0,1,0).
// declare global fc_debug_targetAttitude_z to V(0,0,1).
// declare global fc_debug_currentAttitude_x to V(1,0,0).
// declare global fc_debug_currentAttitude_y to V(0,1,0).
// declare global fc_debug_currentAttitude_z to V(0,0,1).
// declare global fc_debug_targetAttitude_x_draw to vecDraw(V(0,0,0), {return fc_debug_targetAttitude_x.}, RGB(255,0,0), "Target X", 1.0, true).
// declare global fc_debug_targetAttitude_y_draw to vecDraw(V(0,0,0), {return fc_debug_targetAttitude_y.}, RGB(0,255,0), "Target Y", 1.0, true).
// declare global fc_debug_targetAttitude_z_draw to vecDraw(V(0,0,0), {return fc_debug_targetAttitude_z.}, RGB(0,0,255), "Target Z", 1.0, true).
// declare global fc_debug_currentAttitude_x_draw to vecDraw(V(0,0,0), {return fc_debug_currentAttitude_x.}, RGB(255,128,128), "Current X", 1.0, true).
// declare global fc_debug_currentAttitude_y_draw to vecDraw(V(0,0,0), {return fc_debug_currentAttitude_y.}, RGB(128,255,128), "Current Y", 1.0, true).
// declare global fc_debug_currentAttitude_z_draw to vecDraw(V(0,0,0), {return fc_debug_currentAttitude_z.}, RGB(128,128,255), "Current Z", 1.0, true).

function KCLController_GetControl {
    parameter this.
    parameter directionCurrent.  // Direction
    parameter directionTarget.  // Direction

    local rateCmd to RotationRateController_GetControll(this["RotationRateController"], directionCurrent, directionTarget).  // In raw frame
    // To ship local frame (before applying rotational offset)
    local _facingInv to ship:facing:inverse.
    set rateCmd to _facingInv * rateCmd.
    local rateCurrent to ship:angularvel * 180/constant:pi.
    set rateCurrent to _facingInv * rateCurrent.
    // Get torque commands
    local pitchTorqueCmd to TorqueController_GetControl(this["PitchTorqueController"], -rateCmd:x, -rateCurrent:x).
    local yawTorqueCmd to TorqueController_GetControl(this["YawTorqueController"], rateCmd:y, rateCurrent:y).
    local rollTorqueCmd to TorqueController_GetControl(this["RollTorqueController"], -rateCmd:z, -rateCurrent:z).
    return V(pitchTorqueCmd, yawTorqueCmd, rollTorqueCmd).
}

function KCLController_ApplyControl {
    parameter this.
    parameter direcctionCurrent.  // Direction
    parameter directionTarget.  // Direction

    // debug
    // set fc_debug_targetAttitude_x to directionTarget:starvector * 50.
    // set fc_debug_targetAttitude_y to directionTarget:upvector * 50.
    // set fc_debug_targetAttitude_z to directionTarget:forevector * 50.
    // set fc_debug_currentAttitude_x to direcctionCurrent:starvector * 50.
    // set fc_debug_currentAttitude_y to direcctionCurrent:upvector * 50.
    // set fc_debug_currentAttitude_z to direcctionCurrent:forevector * 50.

    local torqueCmd to KCLController_GetControl(this, direcctionCurrent, directionTarget).
    // Apply torque commands
    if (enable_pitch_torque) set ship:control:pilotpitchtrim to torqueCmd:x.
    if (enable_yaw_torque) set ship:control:pilotyawtrim to torqueCmd:y.
    if (enable_roll_torque) set ship:control:pilotrolltrim to torqueCmd:z.
}

// Rate controller: input target direction, output angular velocity command
function RotationRateController_Init {
    parameter Kp, Upper, Ep.
    return lexicon(
        "Kp", Kp, "Upper", Upper, "Ep", Ep
    ).
}

function RotationRateController_GetControll {
    parameter this.
    parameter directionCurrent.  // Direction
    parameter directionTarget.  // Direction

    local directionErr to directionTarget * directionCurrent:inverse.
    local angularErr to AFS:DirectionToAngleAxis(directionErr).
    local angleErr to angularErr:mag * 180/constant:pi.
    if (angleErr < max(this["Ep"], 1e-4)) return V(0, 0, 0).
    local angularRateCmd to min(this["Kp"] * angleErr, this["Upper"]).
    local angularVelCmd to angularRateCmd * angularErr:normalized.
    return angularVelCmd.
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

function AeroFrameCmd2Attitude {
    parameter AOA, AOS, Bank.
    // Build target direction from AOA, AOS, Bank angles
    local resDir to lookDirUp(ship:velocity:surface, up:forevector).
    set resDir to resDir * R(0, 0, -Bank) * R(-AOA, 0, 0) * R(0, -AOS, 0).
    return resDir.
}