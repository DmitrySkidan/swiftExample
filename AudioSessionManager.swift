import Foundation
import AVFoundation
import CocoaLumberjack


protocol AudioSessionManagerDelegate {
    func interruptionBegan() -> Void
    func interruptionEnded() -> Void
}


enum AudioSessionManagerDevice: String {
    case phone = "AudioSessionManagerDevice_Phone"
    case speaker = "AudioSessionManagerDevice_Speaker"
    case headset = "AudioSessionManagerDevice_Headset"
    case bluetooth = "AudioSessionManagerDevice_Bluetooth"
}

class AudioSessionManager {
    static let shared = AudioSessionManager()
    let session = AVAudioSession.sharedInstance()
    
    var mCategory: String!
    var mMode: String!
    
    var delegate: AudioSessionManagerDelegate?
    
    var headsetDeviceAvailable = false
    var bluetoothDeviceAvailable = false
    var speakerDeviceAvailable = true
    var phoneDeviceAvailable = true // TODO: iPod does not have built-in receiver
    
    var audioRoute: String {
        get {
            let currentRoute = AVAudioSession.sharedInstance().currentRoute
            let output = currentRoute.outputs[0].portType
            
            if output == AVAudioSessionPortBuiltInReceiver {
                return AudioSessionManagerDevice.phone.rawValue
            } else if output == AVAudioSessionPortBuiltInSpeaker {
                return AudioSessionManagerDevice.speaker.rawValue
            } else if output == AVAudioSessionPortHeadphones {
                return AudioSessionManagerDevice.headset.rawValue
            } else if isBluetoothDevice(portType: output) {
                return AudioSessionManagerDevice.bluetooth.rawValue
            } else {
                return "Unknown Device"
            }
        }
        
        set(newRoute) {
            if self.audioRoute == newRoute {
                return
            }
            
            _ = self.configureAudioSessionWithDesiredAudioRoute(desiredAudioRoute: newRoute)
        }
    }
    
    var availableAudioDevices: [String] {
        get {
            var availableDevices = [String]()
            
            if headsetDeviceAvailable == true {
                availableDevices.append(AudioSessionManagerDevice.headset.rawValue)
            }
            
            if bluetoothDeviceAvailable == true {
                availableDevices.append(AudioSessionManagerDevice.bluetooth.rawValue)
            }
            
            if speakerDeviceAvailable == true {
                availableDevices.append(AudioSessionManagerDevice.speaker.rawValue)
            }
            
            if phoneDeviceAvailable == true {
                availableDevices.append(AudioSessionManagerDevice.phone.rawValue)
            }
            
            return availableDevices
        }
    }
    
    // MARK: Methods
    
    func start() {
        start(AVAudioSessionCategoryPlayAndRecord, mode: AVAudioSessionModeDefault)
    }
    
    func start(_ category: String, mode: String) {
        self.mCategory = category
        self.mMode = mode
        
       _ = detectAvailableDevices()
        
        do {
            try AVAudioSession.sharedInstance().setMode(mode)
        } catch let error as NSError {
            DDLogDebug("\(error.localizedDescription)")
        }
        
        NotificationCenter.default.addObserver(self, selector: #selector(currentRouteChanged), name: NSNotification.Name.AVAudioSessionRouteChange, object: nil)
        
        NotificationCenter.default.addObserver(self, selector: #selector(interruptionHandler), name: NSNotification.Name.AVAudioSessionInterruption, object: nil)
        
    }
    
    func changeCategory(new category: String) -> Bool {
        mCategory = category
        
        let audioSession = AVAudioSession.sharedInstance()
        if audioSession.category == category {
            return true
        }
        
        return updateCategory()
    }
    
    func refreshAudioSession() {
        _ = updateCategory()
        
        do {
            try AVAudioSession.sharedInstance().setMode(mMode)
        } catch let error as NSError {
            DDLogDebug("\(error.localizedDescription)")
        }
    }
    
    
    // MARK: Private methods
    
    private func detectAvailableDevices() -> Bool {
        // close down our current session...
        do {
            try session.setActive(false)
        } catch let error as NSError {
            DDLogDebug("\(error.localizedDescription)")
        }
        
        // ===== OPEN a new audio session. Without activation, the default route will always be (inputs: null, outputs: Speaker)
        do {
            try session.setActive(true)
        } catch let error as NSError {
            DDLogDebug("\(error.localizedDescription)")
        }
        
        if updateCategory() == false {
            return false
        }
        
        // Check for a wired headset...
        let currentRoute = session.currentRoute
        for output in currentRoute.outputs {
            if output.portType == AVAudioSessionPortHeadphones {
                headsetDeviceAvailable = true
            } else if isBluetoothDevice(portType: output.portType) == true {
                bluetoothDeviceAvailable = true
            }
        }
        
        // In case both headphones and bluetooth are connected, detect bluetooth by inputs
        if let inputs = session.availableInputs {
            for input in inputs {
                if isBluetoothDevice(portType: input.portType) == true {
                    bluetoothDeviceAvailable = true
                    break
                }
            }
        }
        
        // ===== CLOSE session after device checking
        do {
            try session.setActive(false)
        } catch let error as NSError {
            DDLogDebug("\(error.localizedDescription)")
        }
        
        if headsetDeviceAvailable == true {
            DDLogDebug("Found Headset")
        }
        
        if bluetoothDeviceAvailable == true {
            DDLogDebug("Found Bluetooth")
        }
        
        DDLogDebug("AudioSession Category: \(session.category), Mode: \(session.mode), Current Route: \(session.currentRoute)")
        
        return true
    }
    
    private func updateCategory() -> Bool {
        if session.isInputAvailable == true && mCategory == AVAudioSessionCategoryPlayAndRecord {
            do {
                try session.setCategory(AVAudioSessionCategoryPlayAndRecord, with:.allowBluetooth)
            } catch let error as NSError {
                DDLogDebug("\(error.localizedDescription)")
                return false
            }
        } else {
            do {
                try session.setCategory(AVAudioSessionCategoryPlayback, with:.duckOthers)
            } catch let error as NSError {
                DDLogDebug("\(error.localizedDescription)")
                return false
            }
        }
        
        return true
    }
    
    private func isBluetoothDevice(portType: String) -> Bool {
        var isBluetooth = false
        
        if portType == AVAudioSessionPortBluetoothA2DP || portType == AVAudioSessionPortBluetoothHFP {
            isBluetooth = true
        }
        
        return isBluetooth
    }
    
    private func configureAudioSessionWithDesiredAudioRoute(desiredAudioRoute: String) -> Bool {
        // close down our current session...
        do {
            try session.setActive(false)
        } catch let error as NSError {
            DDLogDebug("\(error.localizedDescription)")
        }
        
        if self.mCategory == AVAudioSessionCategoryPlayAndRecord && session.isInputAvailable == false {
            DDLogWarn("device does not support recording")
            return false
        }
        
        /*
         * Need to always use AVAudioSessionCategoryPlayAndRecord to redirect output audio per
         * the "Audio Session Programming Guide", so we only use AVAudioSessionCategoryPlayback when
         * !inputIsAvailable - which should only apply to iPod Touches without external mics.
         */
        if updateCategory() == false {
            return false
        }
        
        /*
         * For now, we can only control output route to default (whichever output with higher priority) or Speaker
         */
        do {
            if desiredAudioRoute == AudioSessionManagerDevice.speaker.rawValue {
                try session.overrideOutputAudioPort(AVAudioSessionPortOverride.speaker)
            } else {
                try session.overrideOutputAudioPort(AVAudioSessionPortOverride.none)
            }
        } catch let error as NSError {
            DDLogWarn("unable to override output: \(error.localizedDescription)")
        }
        
        // Set our session to active...
        do {
            try session.setActive(true)
        } catch let error as NSError {
            DDLogWarn("unable to set audio session active: \(error.localizedDescription)")
            return false
        }
        
        // Display our current route...
        DDLogDebug("current route: \(self.audioRoute)")
        
        return true
    }
    
    // MARK: Observing
    
    @objc func currentRouteChanged(notification: NSNotification) {
        let audioSession = AVAudioSession.sharedInstance()
        
        let changeReason = AVAudioSessionRouteChangeReason(rawValue: UInt(notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as! NSNumber))
        let oldRoute = notification.userInfo?[AVAudioSessionRouteChangePreviousRouteKey] as? AVAudioSessionRouteDescription
        let oldOutput = oldRoute?.outputs[0].portType
        let newRoute = audioSession.currentRoute
        let newOutput = newRoute.outputs[0].portType
        
        switch changeReason! {
        case AVAudioSessionRouteChangeReason.oldDeviceUnavailable:
            if oldOutput == AVAudioSessionPortHeadphones {
                headsetDeviceAvailable = false
                // Special Scenario:
                // when headphones are plugged in before the call and plugged out during the call
                // route will change to {input: MicrophoneBuiltIn, output: Receiver}
                // manually refresh session and support all devices again.
                _ = updateCategory()
                do {
                    try audioSession.setMode(self.mMode)
                    try audioSession.setActive(true)
                } catch let error as NSError {
                    DDLogDebug("\(error.localizedDescription)")
                }
            } else if isBluetoothDevice(portType: oldOutput!) == true {
                var showBluetooth = false
                // Additional checking for iOS7 devices (more accurate)
                // when multiple blutooth devices connected, one is no longer available does not mean no bluetooth available
                if let inputs = audioSession.availableInputs {
                    for input in inputs {
                        if isBluetoothDevice(portType: input.portType) == true {
                            showBluetooth = true
                            break;
                        }
                    }
                }
                
                if showBluetooth == false {
                    bluetoothDeviceAvailable = false
                }
            }
        case AVAudioSessionRouteChangeReason.newDeviceAvailable:
            if isBluetoothDevice(portType: newOutput) == true {
                self.bluetoothDeviceAvailable = true
            } else if newOutput == AVAudioSessionPortHeadphones {
                self.headsetDeviceAvailable = true
            }
        case AVAudioSessionRouteChangeReason.override:
            if isBluetoothDevice(portType: oldOutput!) {
                var showBluetooth = false
                if let inputs = audioSession.availableInputs {
                    for input in inputs {
                        if isBluetoothDevice(portType: input.portType) == true {
                            showBluetooth = true
                            break;
                        }
                    }
                }
                
                if showBluetooth == false {
                    bluetoothDeviceAvailable = false
                }
            }
        default:
            break
        }
    }
    
    @objc func interruptionHandler(notification: NSNotification) {
        let state = notification.userInfo?[AVAudioSessionInterruptionOptionKey] as! AVAudioSessionInterruptionType
        DDLogDebug("===== Interruption State: \(state.rawValue)")
        
        // The InterruptionType name is a bit misleading here
        switch state {
        case AVAudioSessionInterruptionType.began:
            delegate?.interruptionBegan() // this is fired when your app audio session is going to re-start.
        case AVAudioSessionInterruptionType.ended:
            delegate?.interruptionEnded() // this is fired when your app audio session is ended.
        }
    }
}
