// GLOBAL addonEnabled IS FALSE.
FUNCTION forceLiftOff {
  set liftoffTime to TIME + 15.
}

// register a hook
registerHook(forceLiftOff@, "init").  // note the delegate notation: @