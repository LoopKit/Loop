
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
import G4ShareSpy
import CGMBLEKit
import CGMBLEKitUI

struct Plugins {
    public static var pumpManagers: [PumpManagerUI.Type] = [
        OmnipodPumpManager.self,
        MinimedPumpManager.self,
        MockPumpManager.self,
    ]
    
    public static var cgmManagers: [CGMManagerUI.Type] = [
        G6CGMManager.self,
        G5CGMManager.self,
        G4CGMManager.self,
        ShareClientManager.self,
        MockCGMManager.self,
    ]
    
    public static var services: [ServiceUI.Type] = [
        NightscoutService.self,
    ]

}
