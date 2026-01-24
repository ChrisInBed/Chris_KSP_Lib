runOncePath("0:/lib/edllib/flightcontrol.ks").
runOncePath("0:/lib/edllib/gui_utils.ks").

set gui_kcl to fc_MakeKCLGUI().

declare global _pitch to 0.
declare global _yaw to 0.
declare global _bank to 0.
declare global gui_kcl_pitch_input to gui_kcl:addtextfield("0").
declare global gui_kcl_yaw_input to gui_kcl:addtextfield("0").
declare global gui_kcl_bank_input to gui_kcl:addtextfield("0").
declare global gui_kcl_apply_button to gui_kcl:addbutton("Apply KCL Inputs").
set gui_kcl_apply_button:onClick to {
    set _pitch to gui_kcl_pitch_input:text:tonumber.
    set _yaw to gui_kcl_yaw_input:text:tonumber.
    set _bank to gui_kcl_bank_input:text:tonumber.
}.

until ag1 {
    local dirTarget to prograde * R(-_pitch, _yaw, -_bank).
    KCLController_ApplyControl(kclcontroller, ship:facing, dirTarget).
    wait 0.
}

gui_kcl:hide().