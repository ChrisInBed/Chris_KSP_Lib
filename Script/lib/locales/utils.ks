runPath("0:/lib/locales/lang_en.ks").
if (addons:available("AFS")) {
    if (addons:AFS:language = "zh-cn") {
        runPath("0:/lib/locales/lang_zh-cn.ks").
    }
}