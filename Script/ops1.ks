@LAZYGLOBAL OFF.


//Launch Settings

GLOBAL target_orbit IS LEXICON (	
								"periapsis",120,
								"apoapsis",200,
								"cutoff alt",120,
								"inclination",52
).


GLOBAL logdata Is true.


RUNPATH("0:/Shuttle_OPS1/src/ops1_main_executive").
