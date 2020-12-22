
import LoopKitUI
import OmniKit
import OmniKitUI
import MockKit
import MockKitUI
import MinimedKit
import MinimedKitUI
import NightscoutServiceKit
import NightscoutServiceKitUI

struct Plugins {
    public static var pumpManagers: [PumpManagerUI.Type] = [
        MockPumpManager.self,
        OmnipodPumpManager.self,
        MinimedPumpManager.self,
    ]
    
    public static var services: [ServiceUI.Type] = [
        NightscoutService.self,
    ]

}
