function quadratic_get_burntime {
    parameter qr0.
    parameter qv0.
    parameter qRT.
    parameter qVT.
    parameter qAT.
    parameter qJx.
    
    // newton method to find T
    local qT to 2*(qRT:x-qr0:x)/(qVT:x-qv0:x). // initial guess
    until false {
        local qF to qJx*qT^3 + 6*qAT:x*qT^2 + 6*(qv0:x+3*qVT:x)*qT + 24*(qRT:x-qr0:x).
        local qF1 to 3*qJx*qT^2 + 12*qAT:x*qT + 6*(qv0:x+3*qVT:x).
        local qT_new to qT - qF/qF1.
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
    
    if (vxcl(V(0,0,1), qRT - qr0):mag > 15) {
        set qT to quadratic_get_burntime(qr0, qv0, qRT, qVT, qAT, qJx).
    }
    local qJ to 24/qT^3*(qr0-qRT) - 6/qT^2*(qv0+3*qVT) - 6/qT*qAT.
    local qS to -72/qT^4*(qr0-qRT) + 24/qT^3*(qv0+2*qVT) + 12/qT^2*qAT.
    return LIST(qT, qJ, qS).
}