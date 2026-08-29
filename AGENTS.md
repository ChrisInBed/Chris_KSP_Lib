# Repository instructions

## KerboScript identifiers

When creating or editing `*.ks` files, never use a kOS built-in identifier as a
user-defined variable, parameter, lock, or function name. KerboScript identifiers
are case-insensitive, so `time`, `Time`, and `TIME` are the same identifier.

Do not add `@CLOBBERBUILTINS on.` and do not set `CONFIG:CLOBBERBUILTINS` to true.
Rename the user-defined identifier instead. Prefer descriptive multiword names
such as `sample_time`, `ship_ref`, `body_ref`, `rotation_q`, or `velocity_vec`.

Before introducing an identifier, compare it case-insensitively with the lists
below. These lists were checked against the official kOS 1.6.0.1 release source.

### Built-in functions (reserved as bare identifiers)

```text
ABS ADD ADDALARM ALLWAYPOINTS ANGLEAXIS ANGLEDIFF ARCCOS ARCSIN ARCTAN
ARCTAN2 BODY BODYATMOSPHERE BODYEXISTS BOUNDS BUILDLIST CAREER CD CEILING
CHAR CHDIR CLEARGUIS CLEARSCREEN CLEARVECDRAWS CONSTANT COPY_DEPRECATED
COPYPATH COS CREATE CREATEDIR CREATEORBIT DEBUGDUMP DEBUGFREEZEGAME
DELETE_DEPRECATED DELETEALARM DELETEPATH DROPPRIORITY EDIT EXISTS FLOOR
GETVOICE GUI HEADING HIGHLIGHT HSV HSVA HUDTEXT LATLNG LEX LEXICON LIST
LISTALARMS LN LOAD LOG10 LOGFILE LOOKDIRUP MAKEBUILTINDELEGATE MAX MIN MOD
MOVEPATH NODE NOTE OPEN ORBITAT PATH PIDLOOP POSITIONAT PRINT PRINTAT
PRINTLIST PROCESSOR PROFILERESULT Q QUEUE R RANDOM RANDOMSEED RANGE READJSON
REBOOT REMOVE RENAME_FILE_DEPRECATED RENAME_VOLUME_DEPRECATED RGB RGBA
ROTATEFROMTO ROUND RUN SCRIPTPATH SELECTAUTOPILOTMODE SHUTDOWN SIN SLIDENOTE
SQRT STACK STAGE STOPALLVOICES SWITCH TAN TIME TIMESPAN TIMESTAMP
TOGGLEFLYBYWIRE TRANSFER TRANSFERALL UNCHAR UNIQUESET V VANG VCRS VDOT
VECDRAW VECDRAWARGS VECTORANGLE VECTORCROSSPRODUCT VECTORDOTPRODUCT
VECTOREXCLUDE VELOCITYAT VESSEL VOLUME VXCL WARPTO WAYPOINT WRITEJSON
```

This includes short, collision-prone constructors such as `R`, `Q`, and `V`.

### Bound globals and system locks

```text
ABORT ACTIVESHIP ADDONS AG1 AG2 AG3 AG4 AG5 AG6 AG7 AG8 AG9 AG10 AIRSPEED
ALLNODES ALT ALTITUDE ANGULARMOMENTUM ANGULARVEL ANGULARVELOCITY APOAPSIS
ARCHIVE AVAILABLETHRUST BAYS BLACK BLUE BODY BRAKES CHUTES CHUTESSAFE CONFIG
CONSTANT CONTROLCONNECTION CORE CYAN DEPLOYDRILLS DONOTHING DRILLS ENCOUNTER
ETA FACING FUELCELLS GEAR GEOPOSITION GRAY GREEN GREY GROUNDSPEED HASNODE
HASTARGET HEADING HOMECONNECTION INTAKES ISRU KUNIVERSE LADDERS LATITUDE
LEGS LIGHTS LONGITUDE MAGENTA MAPVIEW MASS MAXTHRUST MISSIONTIME NAVMODE
NEXTNODE NORTH OBT OPCODESLEFT ORBIT PANELS PERIAPSIS PROGRADE PURPLE
RADIATORS RCS RED RETROGRADE SAS SASMODE SENSOR SESSIONTIME SHIP SHIPNAME
SOLARPRIMEVECTOR SRFPROGRADE SRFRETROGRADE STAGE STATUS STEERING
STEERINGMANAGER SURFACESPEED TARGET TERMINAL THROTTLE TIME UP VELOCITY
VERSION VERTICALSPEED WARP WARPMODE WHEELSTEERING WHEELSTEERINGPID
WHEELTHROTTLE WHITE YELLOW
```

Also avoid the legacy/documented aliases `LOADDISTANCE` and `SENSORS` for
compatibility with older kOS versions. `THROTTLE`, `STEERING`,
`WHEELTHROTTLE`, and `WHEELSTEERING` are the special system locks; use them
only for their intended flight-control purpose.

### Dynamic and grammar-reserved names

- Every celestial-body name loaded by KSP becomes a bound global. This includes
  stock `SUN`, `MOHO`, `EVE`, `GILLY`, `KERBIN`, `MUN`, `MINMUS`, `DUNA`,
  `IKE`, `DRES`, `JOOL`, `LAYTHE`, `VALL`, `TYLO`, `BOP`, `POL`, and `EELOO`,
  plus bodies added by planet packs.
- Action Groups Extended binds `AG11` through `AG250` when installed.
- kOS or third-party addons can register additional globals and functions.
  Check the relevant addon's documentation before naming an identifier after
  an addon concept.
- KerboScript keywords, operators, and literals are also unavailable as user
  identifiers. Examples include `SET`, `TO`, `IS`, `LOCAL`, `GLOBAL`,
  `PARAMETER`, `FUNCTION`, `IF`, `ELSE`, `UNTIL`, `FOR`, `FROM`, `RETURN`,
  `LOCK`, `UNLOCK`, `ON`, `OFF`, `TRUE`, `FALSE`, `AND`, `OR`, and `NOT`.
- A suffix used after `:` is not automatically banned as a user identifier.
  The ban applies when the same name is also a built-in function, bound global,
  system lock, dynamic binding, or language keyword.

When reviewing existing code, flag newly introduced collisions. Do not make an
unrequested broad rename of legacy scripts merely because an old identifier is
suspicious; first verify whether it is a standalone user identifier or a valid
built-in/suffix use.

### Authoritative references

- [Clobbering built-in names](https://ksp-kos.github.io/KOS_DOC/language/variables.html#clobbering-built-in-names)
- [Catalog of bound variable names](https://ksp-kos.github.io/KOS_DOC/bindings.html)
- [kOS 1.6.0.1 compiler collision checks](https://github.com/KSP-KOS/KOS/blob/1.6.0.1/src/kOS.Safe/Compilation/KS/Compiler.cs)
- [kOS 1.6.0.1 built-in function registrations](https://github.com/KSP-KOS/KOS/tree/1.6.0.1/src)
- [kOS 1.6.0.1 binding registrations](https://github.com/KSP-KOS/KOS/tree/1.6.0.1/src/kOS/Binding)
