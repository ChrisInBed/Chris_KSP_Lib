function quadratic_get_burntime {
    parameter qr0.
    parameter qv0.
    parameter qRT.
    parameter qVT.
    parameter qAT.
    parameter qJx.
    parameter qT_seed.
    
    // Use the previous valid solution as the fallback seed.  The velocity-based
    // estimate is undefined when the lateral velocities are equal.
    // The approach controller uses negative time-to-go, which advances toward
    // zero as mission time increases.
    local qT to -max(0.1, abs(qT_seed)).
    local qDeltaV to qVT:x-qv0:x.
    if abs(qDeltaV) > 0.000001 {
        local qTEstimate to 2*(qRT:x-qr0:x)/qDeltaV.
        if qTEstimate < -0.1 set qT to qTEstimate.
    }

    // Bounded Newton iteration: retain the last positive solution if the
    // derivative becomes singular or convergence is not reached.
    from {local qIteration to 0.} until qIteration >= 20 step {set qIteration to qIteration+1.} do {
        local qF to qJx*qT^3 + 6*qAT:x*qT^2 + 6*(qv0:x+3*qVT:x)*qT + 24*(qRT:x-qr0:x).
        local qF1 to 3*qJx*qT^2 + 12*qAT:x*qT + 6*(qv0:x+3*qVT:x).
        if abs(qF1) < 0.000001 break.
        local qStepLimit to abs(qT)/2.
        local qStep to max(-qStepLimit, min(qStepLimit, qF/qF1)).
        local qT_new to min(-0.1, qT-qStep).
        if abs(qT_new - qT) < 0.001 {
            set qT to qT_new.
            break.
        }
        set qT to qT_new.
    }
    return qT.
}

function quadratic_step_control {
    parameter qr0.
    parameter qv0.
    parameter qRT.
    parameter qVT.
    parameter qAT.
    parameter qJx.
    parameter qT.

    set qT to -max(0.1, abs(qT)).
    if (vxcl(V(0,0,1), qRT - qr0):mag > 15) {
        set qT to quadratic_get_burntime(qr0, qv0, qRT, qVT, qAT, qJx, qT).
    }
    local qJ to 24/qT^3*(qr0-qRT) - 6/qT^2*(qv0+3*qVT) - 6/qT*qAT.
    local qS to -72/qT^4*(qr0-qRT) + 24/qT^3*(qv0+2*qVT) + 12/qT^2*qAT.
    return LIST(qT, qJ, qS).
}
