parameter P_MODE is 0.

print "Create a maneuver to circularize at apoapsis or periapsis".
print "MODE 0: apoapsis (default)".
print "MODE 1: periapsis".

function get_velocity {
	parameter _mu, _r, _a.
	return sqrt(_mu * (2/_r - 1/_a)).
}

function create_apoapsis_node {
    local rmax to body:radius + ship:apoapsis.
    local sma to orbit:semimajoraxis.
    local plan_speed to get_velocity(body:mu, rmax, rmax).
    local pred_speed to get_velocity(body:mu, rmax, sma).
    set circ_node to Node(time:seconds+eta:apoapsis, 0, 0, plan_speed-pred_speed).
    add circ_node.
}

function create_periapsis_node {
    local rmin to body:radius + ship:periapsis.
    local sma to orbit:semimajoraxis.
    local plan_speed to get_velocity(body:mu, rmin, rmin).
    local pred_speed to get_velocity(body:mu, rmin, sma).
    set circ_node to Node(time:seconds+eta:periapsis, 0, 0, plan_speed-pred_speed).
    add circ_node.
}

if P_MODE = 0 {
    create_apoapsis_node().
}
else if P_MODE = 1 {
    create_periapsis_node().
}