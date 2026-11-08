import Toybox.Application;
import Toybox.Lang;
import Toybox.WatchUi;

//! Anicca watch face application
class AniccaApp extends Application.AppBase {

    public function initialize() {
        AppBase.initialize();
    }

    public function getInitialView() as [WatchUi.Views] or [WatchUi.Views, WatchUi.InputDelegates] {
        return [new AniccaView()];
    }
}
