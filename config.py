import re
from xkeysnail.transform import *

define_modmap({
    Key.CAPSLOCK: Key.LEFT_CTRL,
    Key.LEFT_CTRL: Key.CAPSLOCK,
})

define_conditional_modmap(lambda wm_class: wm_class in ("FocusProxy"), {
    Key.CAPSLOCK: Key.LEFT_CTRL,
    Key.LEFT_CTRL: Key.CAPSLOCK,
    Key.LEFT_ALT: Key.LEFT_META,
    Key.LEFT_META: Key.LEFT_ALT,
})

define_keymap(lambda wm_class: wm_class in ("FocusProxy"), {
    K("Super-q"): K("M-q"),
})

