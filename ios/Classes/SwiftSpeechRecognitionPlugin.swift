import Flutter
import UIKit
import Speech

@available(iOS 10.0, *)
public class SwiftSpeechRecognitionPlugin: NSObject, FlutterPlugin, SFSpeechRecognizerDelegate {
  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: "speech_recognition", binaryMessenger: registrar.messenger())
    let instance = SwiftSpeechRecognitionPlugin(channel: channel)
    registrar.addMethodCallDelegate(instance, channel: channel)
  }

  private let speechRecognizerFr = SFSpeechRecognizer(locale: Locale(identifier: "fr_FR"))!
  private let speechRecognizerEn = SFSpeechRecognizer(locale: Locale(identifier: "en_US"))!
  private let speechRecognizerRu = SFSpeechRecognizer(locale: Locale(identifier: "ru_RU"))!
  private let speechRecognizerIt = SFSpeechRecognizer(locale: Locale(identifier: "it_IT"))!

  private var speechChannel: FlutterMethodChannel?

  private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?

  private var recognitionTask: SFSpeechRecognitionTask?
    
  private final  let formatter = DateFormatter()
    
  private let audioEngine = AVAudioEngine()
    private var audioSession: AVAudioSession?

  init(channel:FlutterMethodChannel){
    speechChannel = channel
    formatter.timeZone = TimeZone.current
    formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSSSSS"
    super.init()
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    //result("iOS " + UIDevice.current.systemVersion)
    switch (call.method) {
    case "speech.activate":
      self.activateRecognition(result: result)
    case "speech.listen":
      self.startRecognition(lang: call.arguments as! String, result: result)
    case "speech.cancel":
      self.cancelRecognition(result: result)
    case "speech.stop":
      self.stopRecognition(result: result)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func activateRecognition(result: @escaping FlutterResult) {
    speechRecognizerFr.delegate = self
    speechRecognizerEn.delegate = self
    speechRecognizerRu.delegate = self
    speechRecognizerIt.delegate = self

    SFSpeechRecognizer.requestAuthorization { authStatus in
      OperationQueue.main.addOperation {
        switch authStatus {
        case .authorized:
          result(true)
          self.speechChannel?.invokeMethod("speech.onCurrentLocale", arguments: Locale.preferredLanguages.first)

        case .denied:
          result(false)

        case .restricted:
          result(false)

        case .notDetermined:
          result(false)
        }
        print("SFSpeechRecognizer.requestAuthorization \(authStatus.rawValue)")
      }
    }
  }

  private func startRecognition(lang: String, result: FlutterResult) {
    debugPrint("\(formatter.string(from: Date())) [startRecognition] Initiate")
    if audioEngine.isRunning {
        debugPrint("[startRecognition] Stopping Audio Engine")
      audioEngine.stop()
      recognitionRequest?.endAudio()
      result(false)
    } else {
      try! start(lang: lang)
      result(true)
    }
  }

  private func cancelRecognition(result: FlutterResult?) {
    if let recognitionTask = recognitionTask {
      recognitionTask.cancel()
      self.recognitionTask = nil
      if let r = result {
        r(false)
      }
    }
  }

  private func stopRecognition(result: FlutterResult) {
    debugPrint("\(formatter.string(from: Date())) [stopRecognition] Initiate")
//    if audioEngine.isRunning {
        debugPrint("\(formatter.string(from: Date())) [stopRecognition] Stopping Audio Engine")
        audioEngine.stop()
        recognitionRequest?.endAudio()
        audioEngine.inputNode.removeTap(onBus: 0)
//    }
    result(false)
  }

  private func start(lang: String) throws {
    debugPrint("\(formatter.string(from: Date())) [start] FirstStep")
    cancelRecognition(result: nil)
    
    debugPrint("\(formatter.string(from: Date())) [start] SecondStep")
    if audioSession == nil {
        debugPrint("\(formatter.string(from: Date())) [start] Instantiating AudioSession")
        audioSession = AVAudioSession.sharedInstance()
    }
    try audioSession?.setCategory(AVAudioSessionCategoryPlayAndRecord, with: .mixWithOthers)
    debugPrint("\(formatter.string(from: Date())) [start] ThirdStep")
    try audioSession?.setMode(AVAudioSessionModeDefault)
    debugPrint("\(formatter.string(from: Date())) [start] FourthStep")
    try audioSession?.setActive(true, with: .notifyOthersOnDeactivation)
    debugPrint("\(formatter.string(from: Date())) [start] FifthStep")
    
    debugPrint("\(formatter.string(from: Date())) [start] Creating Recognition Request")
    recognitionRequest = SFSpeechAudioBufferRecognitionRequest()

    let inputNode = audioEngine.inputNode

    guard let recognitionRequest = recognitionRequest else {
      fatalError("[start] Unable to created a SFSpeechAudioBufferRecognitionRequest object")
    }

    recognitionRequest.shouldReportPartialResults = true

    let speechRecognizer = getRecognizer(lang: lang)
    debugPrint("\(formatter.string(from: Date())) [start] Setting up Recognition Request")
    recognitionTask = speechRecognizer.recognitionTask(with: recognitionRequest) { result, error in
      var isFinal = false

      if let result = result {
        debugPrint("\(self.formatter.string(from: Date())) Speech : \(result.bestTranscription.formattedString)")
        self.speechChannel?.invokeMethod("speech.onSpeech", arguments: result.bestTranscription.formattedString)
        isFinal = result.isFinal
        if isFinal {
          self.speechChannel!.invokeMethod(
             "speech.onRecognitionComplete",
             arguments: result.bestTranscription.formattedString
          )
        }
      }

      if error != nil || isFinal {
        if error != nil {
            print("Error in recognition: \(error!.localizedDescription)")
        }
        debugPrint("[start] Stopping Audio Engine")
        self.audioEngine.stop()
        debugPrint("L2. Removed Tap")
        inputNode.removeTap(onBus: 0)
        self.recognitionRequest = nil
        self.recognitionTask = nil
      }
    }

    debugPrint("\(self.formatter.string(from: Date())) [start] Resetting InputNode")
    inputNode.reset()
    let recognitionFormat = inputNode.outputFormat(forBus: 0)
    debugPrint("\(self.formatter.string(from: Date())) [start] Recognition Format: \(recognitionFormat)")
    usleep(10000)
    
    inputNode.removeTap(onBus: 0)
    inputNode.installTap(onBus: 0, bufferSize: 1024, format: recognitionFormat) {
      (buffer: AVAudioPCMBuffer, when: AVAudioTime) in
//        debugPrint("\(self.formatter.string(from: Date())) [start] Appending to Buffer")
      self.recognitionRequest?.append(buffer)
    }
    debugPrint("\(self.formatter.string(from: Date())) [start] Added Tap")
    try audioEngine.start()
    debugPrint("\(formatter.string(from: Date())) [start] Started Engine \(audioEngine.isRunning)")

    speechChannel!.invokeMethod("speech.onRecognitionStarted", arguments: nil)
  }

  private func getRecognizer(lang: String) -> Speech.SFSpeechRecognizer {
    switch (lang) {
    case "fr_FR":
      return speechRecognizerFr
    case "en_US":
      return speechRecognizerEn
    case "ru_RU":
      return speechRecognizerRu
    case "it_IT":
      return speechRecognizerIt
    default:
      return speechRecognizerFr
    }
  }

  public func speechRecognizer(_ speechRecognizer: SFSpeechRecognizer, availabilityDidChange available: Bool) {
    if available {
      speechChannel?.invokeMethod("speech.onSpeechAvailability", arguments: true)
    } else {
      speechChannel?.invokeMethod("speech.onSpeechAvailability", arguments: false)
    }
  }
}