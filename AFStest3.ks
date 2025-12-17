declare global entry_bank_rate to 20.  // deg/s

function get_bank {
    // calculate current bank angle
    return arcTan2(
        -vDot(ship:facing:starvector, up:forevector),
        vDot(ship:facing:upvector, up:forevector)
    ).
}

function init_attitude_control {
    local ast to lexicon(
        "last_bank", get_bank(),
        "last_time", time:seconds
    ).
    return ast.
}

function step_attitude_control {
    parameter ast.
    set ast["last_bank"] to get_bank().
    set ast["last_time"] to time:seconds.
}

function get_attitude_control {
    parameter _AOA, _Bank.
    parameter ast.
    print "Command AOA = " + round(_AOA) + " deg; Bank = " + round(_Bank) + " deg; " AT(0, 1).
    // calculate bank
    local bank_current to get_bank().
    local time_current to time:seconds.
    if (abs(bank_current - _Bank) < entry_bank_rate) {
        // close enough, jump to the target directly
        set ast["last_bank"] to bank_current.
        set ast["last_time"] to time_current.
        return lexicon("AOA", _AOA, "Bank", _Bank).
    }
    local dt to time:seconds - ast["last_time"].
    local bank_error to ast["last_bank"] - _Bank.
    if (bank_error > 0) {
        set _Bank to ast["last_bank"] - min(entry_bank_rate * dt, bank_error).
    }
    else {
        set _Bank to ast["last_bank"] + min(entry_bank_rate * dt, -bank_error).
    }
    print "Adjusted Bank = " + round(_Bank) + " deg; " AT(0, 2).
    print "Last bank = " + round(ast["last_bank"]) + " deg; dt = " + round(dt, 3) + " s; " AT(0, 3).
    print "Bank error = " + round(bank_error) + " deg; " AT(0, 4).
    return lexicon("AOA", _AOA, "Bank", _Bank).
}

function __attitude_from_AOA_Bank {
    parameter _AOA.
    parameter _Bank.
    // AOS = 0
    local target_attitude to angleAxis(-_Bank, srfprograde:forevector) * srfPrograde.
    set target_attitude to angleAxis(-_AOA, target_attitude:starvector) * target_attitude.
    return target_attitude.
}

clearScreen.
local target_attitude to __attitude_from_AOA_Bank(28, 70).
lock steering to target_attitude.
wait until steeringManager:angleerror < 0.1 and steeringManager:rollerror < 0.1.
wait 5.
local ast to init_attitude_control().
until ag1 {
    local contInfo to get_attitude_control(28, -70, ast).
    set target_attitude to __attitude_from_AOA_Bank(contInfo["AOA"], contInfo["Bank"]).
    wait 0.
}
unlock steering.