// Vessel-independent defaults for kOS-GFOLD landing guidance.
// f9_apply_gfold_defaults copies only missing keys into F9_PARAMS, so values
// explicitly supplied by a boot profile always take precedence.
GLOBAL F9_GFOLD_DEFAULTS IS LEXICON(
    "gfold_planningTime", 3,
    "gfold_updateInterval", 1,
    "gfold_thrustMargin", 0.1,
    "gfold_accelerationSmoothing", 0.2,
    "gfold_nodes", 20,
    "gfold_maxSearchEvaluations", 20,
    "gfold_lqrDt", 0.1,
    "gfold_lqrLambda", 0.1,
    "gfold_lqrBeta", 4,
    "gfold_descentMaxSpeed", 450,
    "gfold_descentTilt", 40,
    "gfold_descentGlideSlope", 40,
    "gfold_entryMaxSpeed", 100,
    "gfold_entryTilt", 30,
    "gfold_entryGlideSlope", 0,
    "gfold_terminalTilt", 5,
    "gfold_terminalTiltWindow", 3,
    "landingPhase2Alt", 20
).
