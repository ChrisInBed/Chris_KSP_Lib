WAIT UNTIL SHIP:UNPACKED.
SWITCH TO 0.

RUNONCEPATH("0:/Falcon9_lib/params.ks").
RUNONCEPATH("0:/Falcon9_lib/f9utility.ks").
RUNONCEPATH("0:/Falcon9_lib/f9launch.ks").

FUNCTION gof9u_main {
    SET CONFIG:IPU TO F9_PARAMS["kOSIPU"].
    IF NOT f9_launch(F9_PARAMS) {
        PRINT "F9 upper executive: launch aborted".
        RETURN FALSE.
    }
    PRINT "F9 upper executive: launch sequence complete".
    RETURN TRUE.
}

gof9u_main().
