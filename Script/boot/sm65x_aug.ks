wait until ship:unpacked.
switch to 0.
runOncePath("0:/lib/engine_utility.ks").

print "Augmentation launch script for SM65X-Atlas".
print "This Script will guide the booster seperation at right moment".

function anyFlameOut {
    parameter engs.
    for _eng in engs {
        if _eng:flameout {
            return true.
        }
    }
    return false.
}

function main {
    local coreEng to search_engine("core")[0].
    wait until coreEng:ignition.
    print "Ignition detected".
    local boosterEngs to search_engine("booster").
    local done to false.
    until done {
        if anyFlameOut(boosterEngs) {
            break.
        }
        wait 0.
    }
    deactivate_engines(boosterEngs).
    stage.
    print "Booster seperated".
}

main().
