@LAZYGLOBAL OFF.


//Launch Settings

//for Vandenberg launches

//FWC SRBs, RS-25A, 11.4 ton payload
GLOBAL target_orbit IS LEXICON (	
								"periapsis",0,
								"apoapsis",195,
								"cutoff alt",112,
								"inclination",-104
).


GLOBAL logdata Is true.


RUNPATH("0:/Shuttle_OPS1/src/ops1_main_executive").
