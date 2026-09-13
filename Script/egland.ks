runOncePath("0:/lib/locales/utils.ks").
parameter P_GUI to true.
parameter P_PREC to "auto".
parameter P_NOWAIT is false.
parameter P_ADJUST is v(0, 0, 0).
parameter P_ENGINE is "current".

run pegland(P_GUI, P_PREC, P_NOWAIT, P_ADJUST, P_ENGINE).