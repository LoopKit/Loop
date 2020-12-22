
import LoopKitUI
import OmniKit
import OmniKitUI
import MockKit
import MockKitUI
import MinimedKit
import MinimedKitUI
import NightscoutServiceKit
import NightscoutServiceKitUI
import ShareClient
import ShareClientUI

struct Plugins {
    public static var pumpManagers: [PumpManagerUI.Type] = [
        OmnipodPumpManager.self,
        MinimedPumpManager.self,
        MockPumpManager.self,
    ]
    
    public static var cgmManagers: [CGMManagerUI.Type] = [
        ShareClientManager.self,
        MockCGMManager.self,
    ]
    
    public static var services: [ServiceUI.Type] = [
        NightscoutService.self,
    ]

}
