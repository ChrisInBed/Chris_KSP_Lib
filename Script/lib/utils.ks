function arr2str {
    parameter arr.
    parameter rounding to 1.
    local str to "".
    from {local i to 0.} until i = arr:length() step {set i to i+1.} do {
        set str to str + round(arr[i], rounding).
        if (i < arr:length() - 1) {
            set str to str + ", ".
        }
    }
    return str.
}

function str2arr {
    parameter str.
    local strarr to str:split(",").
    local arr to list().
    for _s in strarr {
        arr:add(_s:trim:toNumber(0)).
    }
    return arr.
}