// 
// Copyright 2021 The Matrix.org Foundation C.I.C
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
// http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
//

import Foundation

/// MXThreadingService error
public enum MXThreadingServiceError: Int, Error {
    case sessionNotFound
    case unknown
}

// MARK: - MXThreadingService errors
extension MXThreadingServiceError: CustomNSError {
    public static let errorDomain = "org.matrix.sdk.threadingservice"

    public var errorCode: Int {
        return Int(rawValue)
    }

    public var errorUserInfo: [String: Any] {
        return [:]
    }
}

@objcMembers
/// Threading service class.
public class MXThreadingService: NSObject {
    
    private weak var session: MXSession?
    
    private var threads: [String: MXThread] = [:]
    
    /// Notification to be posted when a new thread is created.
    public static let newThreadCreated: Notification.Name = Notification.Name("MXThreadingService.newThreadCreated")
    
    /// Initializer
    /// - Parameter session: session instance
    public init(withSession session: MXSession) {
        self.session = session
        super.init()
    }
    
    /// Adds event to the related thread instance
    /// - Parameter event: event to be handled
    public func handleEvent(_ event: MXEvent) {
        guard let session = session else {
            //  session closed
            return
        }
        guard let threadIdentifier = event.threadIdentifier else {
            //  event is not in a thread
            return
        }
        
        if let thread = thread(withId: threadIdentifier) {
            //  add event to the thread if found
            thread.addEvent(event)
        } else {
            //  create the thread for the first time
            let thread: MXThread
            //  try to find the root event in the session store
            if let rootEvent = session.store?.event(withEventId: threadIdentifier, inRoom: event.roomId) {
                thread = MXThread(withSession: session, rootEvent: rootEvent)
            } else {
                thread = MXThread(withSession: session, identifier: threadIdentifier, roomId: event.roomId)
            }
            thread.addEvent(event)
            saveThread(thread)
            NotificationCenter.default.post(name: Self.newThreadCreated, object: thread, userInfo: nil)
        }
    }
    
    /// Method to check an event is a thread root or not
    /// - Parameter event: event to be checked
    /// - Returns: true is given event is a thread root
    public func isEventThreadRoot(_ event: MXEvent) -> Bool {
        return thread(withId: event.eventId) != nil
    }
    
    /// Method to get a thread with specific identifier
    /// - Parameter identifier: identifier of a thread
    /// - Returns: thread instance if found, nil otherwise
    public func thread(withId identifier: String) -> MXThread? {
        objc_sync_enter(threads)
        let result = threads[identifier]
        objc_sync_exit(threads)
        return result
    }
    
    private func saveThread(_ thread: MXThread) {
        objc_sync_enter(threads)
        threads[thread.id] = thread
        objc_sync_exit(threads)
    }
    
    /// Method to fetch all threads in a room. Will be used in future.
    /// - Parameters:
    ///   - roomId: room identifier
    ///   - completion: completion block to be called at the end of the process
    public func allThreads(inRoom roomId: String,
                           completion: @escaping (MXResponse<[MXThread]>) -> Void) {
        guard let session = session else {
            completion(.failure(MXThreadingServiceError.sessionNotFound))
            return
        }
        
        let filter = MXRoomEventFilter()
        filter.relationTypes = [MXEventRelationTypeThread]
        
        session.matrixRestClient.messages(forRoom: roomId,
                                          from: "",
                                          direction: .backwards,
                                          limit: nil,
                                          filter: filter) { response in
            switch response {
            case .success(let paginationResponse):
                if let rootEvents = paginationResponse.chunk {
                    let threads = rootEvents.map({ MXThread(withSession: session, rootEvent: $0) })
                    completion(.success(threads))
                } else {
                    completion(.success([]))
                }
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }
    
}
