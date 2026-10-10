// kOS-ATM smoke check. Terminal output only; no files are recorded.
if not addons:hasaddon("ATM") {
    print "kOS-ATM is unavailable.".
} else {
    local atmosphere_ref to addons:ATM:Snapshot().
    local vessel_lat_deg to ship:geoposition:lat.
    local vessel_lon_deg to ship:geoposition:lng.
    local query_alt_m to ship:altitude.
    local gas_sample to atmosphere_ref:GetAt(lexicon(
        "latitude", vessel_lat_deg, "longitude", vessel_lon_deg,
        "altitude", query_alt_m, "ut", atmosphere_ref:EpochUT
    )).
    print "ATM body: " + atmosphere_ref:BodyName + ", epoch UT: " + atmosphere_ref:EpochUT.
    print "Ambient temperature: model=" + gas_sample["temperature"]
        + " K, vessel=" + addons:ATM:Temperature + " K".
    print "Ambient pressure: model=" + gas_sample["pressure"]
        + " Pa, vessel=" + addons:ATM:Pressure + " Pa".
    print "Ambient density: model=" + gas_sample["density"]
        + " kg/m3, vessel=" + addons:ATM:Density + " kg/m3".
    if addons:ATM:Density > 0.000001 {
        print "Density difference: " + 100 * (gas_sample["density"] / addons:ATM:Density - 1) + " %".
    }
    local future_sample to atmosphere_ref:GetAt(lexicon(
        "latitude", vessel_lat_deg, "longitude", vessel_lon_deg,
        "altitude", query_alt_m, "ut", atmosphere_ref:EpochUT + 600
    )).
    print "Same coordinates at UT+600: temperature=" + future_sample["temperature"]
        + " K, density=" + future_sample["density"] + " kg/m3".
    print "Smoke check complete. No log files were written.".
}
