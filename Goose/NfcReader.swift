//
//  NfcReader.swift
//  Goose
//
//  Created by Oz Tamir on 22/08/2024.
//  Modified for Goose.
//

import CoreNFC

class NFCReader: NSObject, ObservableObject, NFCNDEFReaderSessionDelegate {
    var session: NFCNDEFReaderSession?
    var onScanComplete: ((String) -> Void)?
    var onWriteComplete: ((Bool) -> Void)?
    var isWriting = false
    var textToWrite: String?
    
    func scan(completion: @escaping (String) -> Void) {
        self.onScanComplete = completion
        self.isWriting = false
        startSession()
    }
    
    func write(_ text: String, completion: @escaping (Bool) -> Void) {
        self.onWriteComplete = completion
        self.textToWrite = text
        self.isWriting = true
        startSession()
    }
    
    private func startSession() {
        guard NFCNDEFReaderSession.readingAvailable else {
            NSLog("NFC is not available on this device")
            return
        }
        
        session = NFCNDEFReaderSession(delegate: self, queue: nil, invalidateAfterFirstRead: false)
        session?.alertMessage = isWriting ? "Hold your iPhone near an NFC tag to write." : "Hold your iPhone near an NFC tag to read."
        session?.begin()
    }
    
    func readerSession(_ session: NFCNDEFReaderSession, didDetectNDEFs messages: [NFCNDEFMessage]) {
        guard !isWriting, let message = messages.first else { return }
        processMessage(message)
    }
    
    func readerSession(_ session: NFCNDEFReaderSession, didDetect tags: [NFCNDEFTag]) {
        if isWriting {
            handleWriting(session: session, tags: tags)
        } else {
            handleReading(session: session, tags: tags)
        }
    }
    
    private func handleReading(session: NFCNDEFReaderSession, tags: [NFCNDEFTag]) {
        if tags.count > 1 {
            session.alertMessage = "More than 1 tag detected. Please try again with only one tag."
            session.invalidate()
            return
        }
        
        let tag = tags.first!
        session.connect(to: tag) { error in
            if let error = error {
                session.invalidate(errorMessage: "Connection error: \(error.localizedDescription)")
                return
            }
            
            tag.queryNDEFStatus { status, _, error in
                if let error = error {
                    session.invalidate(errorMessage: "Failed to query tag: \(error.localizedDescription)")
                    return
                }
                
                switch status {
                case .notSupported:
                    session.invalidate(errorMessage: "Tag is not NDEF compliant")
                case .readOnly, .readWrite:
                    tag.readNDEF { message, error in
                        if let error = error {
                            session.invalidate(errorMessage: "Read error: \(error.localizedDescription)")
                        } else if let message = message {
                            self.processMessage(message)
                            session.alertMessage = "Tag read successfully!"
                            session.invalidate()
                        } else {
                            session.invalidate(errorMessage: "No NDEF message found on tag")
                        }
                    }
                @unknown default:
                    session.invalidate(errorMessage: "Unknown tag status")
                }
            }
        }
    }
    
    /// Reports only the first readable record: every callback toggles the
    /// block, so a tag with several records must not fire it more than once.
    private func processMessage(_ message: NFCNDEFMessage) {
        guard let text = message.records.lazy.compactMap(Self.payloadText).first else { return }
        DispatchQueue.main.async {
            self.onScanComplete?(text)
        }
    }

    private static func payloadText(_ record: NFCNDEFPayload) -> String? {
        switch record.typeNameFormat {
        case .nfcWellKnown:
            return record.wellKnownTypeTextPayload().0 ?? record.wellKnownTypeURIPayload()?.absoluteString
        case .absoluteURI:
            return String(data: record.payload, encoding: .utf8)
        default:
            return nil
        }
    }
    
    private func handleWriting(session: NFCNDEFReaderSession, tags: [NFCNDEFTag]) {
        guard let tag = tags.first else {
            session.invalidate(errorMessage: "No tag detected")
            return
        }
        
        session.connect(to: tag) { error in
            if let error = error {
                session.invalidate(errorMessage: "Connection error: \(error.localizedDescription)")
                return
            }
            
            tag.queryNDEFStatus { status, capacity, error in
                guard error == nil else {
                    session.invalidate(errorMessage: "Failed to query tag")
                    return
                }
                
                switch status {
                case .notSupported:
                    session.invalidate(errorMessage: "Tag is not NDEF compliant")
                case .readOnly:
                    session.invalidate(errorMessage: "Tag is read-only")
                case .readWrite:
                    guard let textToWrite = self.textToWrite else {
                        session.invalidate(errorMessage: "No text to write")
                        return
                    }
                    
                    let payload = NFCNDEFPayload.wellKnownTypeTextPayload(string: textToWrite, locale: Locale(identifier: "en"))!
                    let message = NFCNDEFMessage(records: [payload])
                    
                    tag.writeNDEF(message) { error in
                        if let error = error {
                            session.invalidate(errorMessage: "Write failed: \(error.localizedDescription)")
                        } else {
                            session.alertMessage = "Write successful!"
                            session.invalidate()
                        }
                        
                        DispatchQueue.main.async {
                            self.onWriteComplete?(error == nil)
                        }
                    }
                @unknown default:
                    session.invalidate(errorMessage: "Unknown tag status")
                }
            }
        }
    }
    
    func readerSession(_ session: NFCNDEFReaderSession, didInvalidateWithError error: Error) {
        if let readerError = error as? NFCReaderError {
            if (readerError.code != .readerSessionInvalidationErrorFirstNDEFTagRead)
                && (readerError.code != .readerSessionInvalidationErrorUserCanceled) {
                NSLog("Session invalidated with error: \(error.localizedDescription)")
            }
        }
        self.session = nil
    }
}
