import Toybox.Application;
import Toybox.Lang;
import Toybox.WatchUi;

//! Feasibility probe for Anicca: meditation detection and particle frame rates
class ProbeApp extends Application.AppBase {

    public function initialize() {
        AppBase.initialize();
    }

    public function getInitialView() as [WatchUi.Views] or [WatchUi.Views, WatchUi.InputDelegates] {
        return [new ProbeView()];
    }
}
