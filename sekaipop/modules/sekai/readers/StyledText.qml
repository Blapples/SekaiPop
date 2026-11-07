// Ported from dhrruvsharma/shell (GPL-3.0-or-later), recoloured for SekaiPop.
import QtQuick
import qs.modules.common
import qs.modules.sekai.readers

// Base text element for the shell. The colour is defaulted, and the family
// follows the desktop theme (the default font when none is on); size stays
// whatever Text gives you. Set font.family to opt out.
Text {
    color: Colors.on_surface
    font.family: Theme.fontFamily
}
