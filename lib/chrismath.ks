function exp {
    parameter x.
    return constant:e ^ x.
}

function mzeros {
    parameter n.
    parameter xseq.

    xseq:clear().
    from {local i to 0.} until i = n step {set i to i+1.} do {
        xseq:add(0).
    }
    return xseq.
}

function mlinspace {
    parameter start.
    parameter end.
    parameter n.
    parameter xseq.
    
    xseq:clear().
    local interval to (end - start) / (n - 1).
    from {local i to 0.} until i = n step {set i to i+1.} do {
        xseq:add(start + i * interval).
    }
    return xseq.
}

function marradd {
    parameter xseq.
    parameter yseq.

    local n to xseq:length.
    from {local i to 0.} until i = n step {set i to i+1.} do {
        set xseq[i] to xseq[i] + yseq[i].
    }
}

function marrsub {
    parameter xseq.
    parameter yseq.

    local n to xseq:length.
    from {local i to 0.} until i = n step {set i to i+1.} do {
        set xseq[i] to xseq[i] - yseq[i].
    }
}

function mscalaradd {
    parameter xseq.
    parameter scalar.

    local n to xseq:length.
    from {local i to 0.} until i = n step {set i to i+1.} do {
        set xseq[i] to xseq[i] + scalar.
    }
}

function marrmul {
    parameter xseq.
    parameter yseq.

    local n to xseq:length.
    from {local i to 0.} until i = n step {set i to i+1.} do {
        set xseq[i] to xseq[i] * yseq[i].
    }
}

function mscalarmul {
    parameter xseq.
    parameter scalar.

    local n to xseq:length.
    from {local i to 0.} until i = n step {set i to i+1.} do {
        set xseq[i] to xseq[i] * scalar.
    }
}

function marropt {
    parameter funcobj.
    parameter funcparams.
    parameter outseq.
    // support only up to 3 array parameters
    local n to funcparams[0]:length.
    local nparams to funcparams:length.
    from {local i to 0.} until i = n step {set i to i+1.} do {
        if nparams = 1 {
            set outseq[i] to funcobj(funcparams[0][i]).
        } else if nparams = 2 {
            set outseq[i] to funcobj(funcparams[0][i], funcparams[1][i]).
        } else if nparams = 3 {
            set outseq[i] to funcobj(funcparams[0][i], funcparams[1][i], funcparams[2][i]).
        }
    }
    return outseq.
}

function msafedivision {
    parameter num.
    parameter dzsize is 1e-5.
    if abs(num) > dzsize {return num.}
    if num < 0 {return -dzsize.}
    else {return dzsize.}
}

function mintegral {
    parameter xseq.
    parameter interval.
    // Simpson 1/3 rule for integral
    local n to xseq:length.
    if mod(n, 2) = 0 {
        set n to n - 1.  // Make sure n is odd
    }
    local res to xseq[0] + xseq[n-1].
    from {local i to 1.} until i > n-2 step {set i to i+2.} do {
        set res to res + 4 * xseq[i].
    }
    from {local i to 2.} until i > n-3 step {set i to i+2.} do {
        set res to res + 2 * xseq[i].
    }
    set res to res * (interval / 3).
    return res.
}