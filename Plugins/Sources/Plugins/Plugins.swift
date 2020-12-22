
import LoopKitUI
import OmniKit
import OmniKitUI
import MockKit
import MockKitUI

struct Plugins {
    public static var pumpManagers: [PumpManagerUI.Type] = [
        MockPumpManager.self,
        OmnipodPumpManager.self
    ]
}
